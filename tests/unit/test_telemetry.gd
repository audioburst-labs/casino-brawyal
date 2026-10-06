extends GutTest
## The pure half of telemetry: the spool, the event classification, the batch
## envelope and the retry policy. No network, no Node, no autoload.
##
## Disk tests follow `test_run_save.gd`: a distinct `user://test_*` path,
## cleaned in `after_each` so a failed run never poisons the next one.

const SPOOL_PATH := "user://test_telemetry_spool.ndjson"
const INSTALL_PATH := "user://test_telemetry_install.json"
const SETTINGS_PATH := "user://test_telemetry_settings.json"

var _db: ContentDB


func before_all() -> void:
	_db = ContentDB.new()
	assert_true(_db.load_all("res://data"), str(_db.errors))


func after_each() -> void:
	for path in [SPOOL_PATH, SPOOL_PATH + ".tmp", INSTALL_PATH, SETTINGS_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _spool() -> TelemetrySpool:
	return TelemetrySpool.new(SPOOL_PATH)


# ---- ids ---------------------------------------------------------------

func test_uuid4_is_well_formed_and_never_repeats() -> void:
	var seen := {}
	for i in 5000:
		var id := TelemetryIds.uuid4()
		assert_eq(id.length(), 36, id)
		assert_eq(id[14], "4", "version nibble: %s" % id)
		assert_true("89ab".contains(id[19].to_lower()), "variant nibble: %s" % id)
		seen[id] = true
	assert_eq(seen.size(), 5000, "5000 draws, 5000 distinct ids")


func test_the_install_id_is_minted_once_and_kept() -> void:
	var first := TelemetryIds.load_or_create_install(INSTALL_PATH)
	assert_eq(first.length(), 36)
	assert_eq(TelemetryIds.load_or_create_install(INSTALL_PATH), first,
		"the same install keeps its id across launches")
	TelemetryIds.forget_install(INSTALL_PATH)
	var after := TelemetryIds.load_or_create_install(INSTALL_PATH)
	assert_ne(after, first, "opting out and back in is a NEW identity")


func test_a_corrupt_install_file_mints_a_fresh_id_instead_of_throwing() -> void:
	var file := FileAccess.open(INSTALL_PATH, FileAccess.WRITE)
	file.store_string("{ this is not json")
	file = null
	assert_eq(TelemetryIds.load_or_create_install(INSTALL_PATH).length(), 36)


# ---- the spool ---------------------------------------------------------

func test_append_and_read_round_trips_in_order() -> void:
	var spool := _spool()
	for i in 20:
		assert_true(spool.append({"t": "move", "seq": i}))
	spool.close()
	var lines := spool.read_lines()
	assert_eq(lines.size(), 20)
	assert_eq(int(lines[0].seq), 0)
	assert_eq(int(lines[19].seq), 19)


## The reason for NDJSON: a crash mid-write can only damage the last line.
func test_a_torn_final_line_is_dropped_not_fatal() -> void:
	var spool := _spool()
	for i in 3:
		spool.append({"t": "move", "seq": i})
	spool.close()
	var file := FileAccess.open(SPOOL_PATH, FileAccess.READ_WRITE)
	file.seek_end()
	file.store_string('{"t":"move","seq":3')      # no closing brace, no newline
	file = null
	var lines := spool.read_lines()
	assert_eq(lines.size(), 3, "the three good lines survive")
	assert_eq(spool.malformed_lines, 1, "and the torn one is counted")


func test_truncate_head_drops_exactly_what_was_sent() -> void:
	var spool := _spool()
	for i in 10:
		spool.append({"t": "move", "seq": i})
	assert_true(spool.truncate_head(4))
	var lines := spool.read_lines()
	assert_eq(lines.size(), 6)
	assert_eq(int(lines[0].seq), 4, "the oldest four are gone")


func test_clear_removes_the_file() -> void:
	var spool := _spool()
	spool.append({"t": "move", "seq": 1})
	spool.clear()
	assert_false(FileAccess.file_exists(SPOOL_PATH))
	assert_eq(spool.read_lines().size(), 0)


## Over cap it drops the OLDEST half, so a permanently offline machine is not
## pinned to its first session for ever, and leaves a marker so the gap shows.
func test_the_cap_evicts_oldest_first_and_says_so() -> void:
	var spool := _spool()
	var filler := "x".repeat(600)
	var wrote := 0
	while spool.size_bytes() <= TelemetrySpool.MAX_BYTES and wrote < 9000:
		spool.append({"t": "move", "seq": wrote, "d": {"pad": filler}})
		wrote += 1
	# The cap is checked every CHECK_EVERY writes, not every write - so push
	# past the next boundary rather than assuming the very next append trips it.
	for i in TelemetrySpool.CHECK_EVERY + 5:
		spool.append({"t": "move", "seq": wrote + i, "d": {"pad": filler}})
	assert_lt(spool.size_bytes(), TelemetrySpool.MAX_BYTES + 1_000_000,
		"the spool cannot grow without bound")
	var lines := spool.read_lines()
	assert_gt(lines.size(), 0)
	var kinds: Array = []
	for line in lines:
		kinds.append(str(line.get("t", "")))
	assert_true(kinds.has("spool_truncated"), "the gap is marked, not hidden")
	assert_gt(spool.dropped_lines, 0)


func test_an_unwritable_spool_degrades_quietly() -> void:
	# A directory where the file should be: open() fails without throwing.
	DirAccess.make_dir_recursive_absolute(SPOOL_PATH)
	var spool := _spool()
	assert_false(spool.open(), "cannot open")
	assert_true(spool.degraded)
	assert_false(spool.append({"t": "move"}), "and appending is a silent no-op")
	DirAccess.remove_absolute(SPOOL_PATH)


# ---- classification ----------------------------------------------------

## The important one. Drive a REAL combat and assert every type it emits has
## been given a decision — so a 35th event cannot appear without somebody
## choosing whether it is a row, a total, or noise.
func test_every_event_a_real_combat_emits_is_classified() -> void:
	# Driven by hand rather than through GreedyBot: the bot drains and discards,
	# so anything it swallowed would never be classified.
	var seen := {}
	for seed_value in 8:
		var sim := CombatSim.new(_db, {
			"hero": "ace",
			"abilities": ["card_sling", "quick_maneuvers", "double_down",
				"heartsteal", "color_up", "flush"],
			"enemies": ["dealer", "server"],
			"seed": seed_value,
		})
		var guard := 0
		while sim.phase != CombatSim.Phase.ENDED and guard < 60:
			guard += 1
			if sim.phase == CombatSim.Phase.ROUND_START:
				sim.begin_round()
			if sim.phase == CombatSim.Phase.CHOICE:
				sim.choose(0)
			for event: CombatEvent in sim.drain_events():
				seen[event.type] = true
			if sim.phase == CombatSim.Phase.ASSIGNMENT:
				for suit: StringName in ContentDB.SUITS:
					sim.tray.add(suit, 2)
				for index in sim.abilities.size():
					var state: AbilityState = sim.abilities[index]
					for slot in state.def.cost.size():
						var suit: StringName = state.def.cost[slot]
						sim.assign_chip(&"spade" if suit == &"any" else suit, index, slot)
				for event: CombatEvent in sim.drain_events():
					seen[event.type] = true
				sim.tray.discard_all()
				sim.end_assignment()
				for event: CombatEvent in sim.drain_events():
					seen[event.type] = true
	assert_gt(seen.size(), 10, "the fight actually happened")
	for type: StringName in seen:
		assert_true(TelemetryFilter.is_classified(type),
			"%s is a new event type nobody has classified" % type)


func test_the_high_volume_types_are_totals_not_rows() -> void:
	# damage_dealt alone is multistrike x instances x enemies x rounds.
	for type: StringName in [&"damage_dealt", &"block_gained", &"status_applied"]:
		assert_false(TelemetryFilter.keeps(type), "%s must not be a row" % type)
		assert_true(TelemetryFilter.AGGREGATE.has(type))


func test_a_projected_row_carries_only_what_it_should() -> void:
	var row := TelemetryFilter.project(&"chip_assigned",
		{"ability": &"bust", "slot": 1, "suit": &"spade", "noise": 99},
		&"hero", {})
	assert_eq(row.keys().size(), 3, "no stray fields: %s" % [row.keys()])
	assert_eq(str(row.ability), "bust")
	assert_eq(str(row.suit), "spade")


## Runtime actor ids are minted per combat (`enemy_0`), so a row that stored
## one would be meaningless across runs.
func test_rows_store_the_def_id_not_the_runtime_id() -> void:
	var row := TelemetryFilter.project(&"enemy_busted", {"actor": &"enemy_2"},
		&"hero", {&"enemy_2": "dealer"})
	assert_eq(str(row.actor), "dealer")
	var hero_row := TelemetryFilter.project(&"actor_died", {"actor": &"hero"},
		&"hero", {})
	assert_eq(str(hero_row.actor), "hero")
	assert_true(bool(hero_row.hero))


# ---- the summary -------------------------------------------------------

## The piece that does arithmetic, so the piece that needs pinning: play a
## real fight and reconcile the totals against the enemies' starting health.
func test_the_combat_summary_reconciles_against_a_real_fight() -> void:
	var sim := CombatSim.new(_db, {
		"hero": "ace",
		"abilities": ["card_sling", "quick_maneuvers", "double_down",
			"heartsteal", "color_up", "flush"],
		"enemies": ["server"],
		"seed": 11,
	})
	var starting_hp := 0
	for enemy in sim.enemies:
		starting_hp += enemy.max_hp
	var summary := CombatSummary.new("c", "r")
	summary.hp_before = sim.hero.hp
	var hero_id := sim.hero.id
	var guard := 0
	while sim.phase != CombatSim.Phase.ENDED and guard < 60:
		guard += 1
		if sim.phase == CombatSim.Phase.ROUND_START:
			sim.begin_round()
		if sim.phase == CombatSim.Phase.CHOICE:
			sim.choose(0)
		for event: CombatEvent in sim.drain_events():
			summary.feed(event.type, event.data, hero_id)
		if sim.phase == CombatSim.Phase.ASSIGNMENT:
			sim.tray.discard_all()
			sim.end_assignment()
			for event: CombatEvent in sim.drain_events():
				summary.feed(event.type, event.data, hero_id)
	assert_true(summary.finished, "the fight reached an ending")
	assert_gt(summary.rounds, 0, "rounds were counted")
	if summary.won:
		assert_between(summary.damage_dealt, starting_hp - 40, starting_hp + 40,
			"damage dealt is in the neighbourhood of the enemies' health")
	assert_gte(summary.damage_taken, 0)
	var closing := summary.closing("won" if summary.won else "lost")
	assert_eq(int(closing.rounds), summary.rounds)
	assert_true(closing.has("duration_sec"))


# ---- batching and retry ------------------------------------------------

func test_the_batch_envelope_carries_the_events_and_a_fresh_id() -> void:
	var lines: Array[Dictionary] = []
	for i in 12:
		lines.append({"t": "move", "seq": i})
	var built := TelemetryBatch.build(lines, {"install_id": "abc", "app_version": "0.0.115"})
	assert_eq(int(built.count), 12)
	var body: Dictionary = built.batch
	assert_eq(body.events.size(), 12)
	assert_eq(str(body.inst), "abc")
	assert_eq(str(body.batch).length(), 36, "a uuid per batch, for dedup")
	var second := TelemetryBatch.build(lines, {"install_id": "abc"})
	assert_ne(str(second.batch.batch), str(body.batch),
		"a new batch id every time - resends reuse the body, not build()")


func test_a_batch_is_capped_by_count_and_by_bytes() -> void:
	var many: Array[Dictionary] = []
	for i in TelemetryBatch.MAX_EVENTS + 250:
		many.append({"t": "move", "seq": i})
	assert_eq(int(TelemetryBatch.build(many, {}).count), TelemetryBatch.MAX_EVENTS)

	var fat: Array[Dictionary] = []
	for i in 400:
		fat.append({"t": "move", "seq": i, "d": {"pad": "y".repeat(2000)}})
	var built := TelemetryBatch.build(fat, {})
	assert_lt(int(built.count), 400, "the byte cap bites before the count cap")
	assert_gt(int(built.count), 0, "but it always sends something")


func test_an_empty_spool_builds_nothing() -> void:
	assert_true(TelemetryBatch.build([] as Array[Dictionary], {}).is_empty())


## Pinned, because getting these wrong means either losing data or hammering a
## server that has already said no.
func test_the_retry_verdicts() -> void:
	var ok := HTTPRequest.RESULT_SUCCESS
	assert_eq(TelemetryBatch.classify(ok, 200), TelemetryBatch.Verdict.OK)
	assert_eq(TelemetryBatch.classify(ok, 202), TelemetryBatch.Verdict.OK)
	assert_eq(TelemetryBatch.classify(ok, 400), TelemetryBatch.Verdict.DROP,
		"the server refused these exact bytes; resending fails for ever")
	assert_eq(TelemetryBatch.classify(ok, 413), TelemetryBatch.Verdict.DROP)
	assert_eq(TelemetryBatch.classify(ok, 401), TelemetryBatch.Verdict.STOP,
		"a bad key will not fix itself")
	assert_eq(TelemetryBatch.classify(ok, 403), TelemetryBatch.Verdict.STOP)
	assert_eq(TelemetryBatch.classify(ok, 429), TelemetryBatch.Verdict.RETRY)
	assert_eq(TelemetryBatch.classify(ok, 503), TelemetryBatch.Verdict.RETRY)
	assert_eq(TelemetryBatch.classify(HTTPRequest.RESULT_CANT_CONNECT, 0),
		TelemetryBatch.Verdict.RETRY, "offline is the case the spool exists for")


func test_backoff_climbs_jitters_and_is_capped() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var first := TelemetryBatch.next_delay(0, rng)
	assert_between(first, TelemetryBatch.BASE_DELAY * 0.5, TelemetryBatch.BASE_DELAY)
	for failures in [1, 3, 8, 30, 64]:
		var delay := TelemetryBatch.next_delay(failures, rng)
		assert_gt(delay, 0.0, "no zero-delay hammering at %d" % failures)
		assert_lte(delay, TelemetryBatch.MAX_DELAY,
			"capped at half an hour, even at %d failures" % failures)


# ---- settings ----------------------------------------------------------

func test_settings_default_to_on_and_unseen() -> void:
	var settings := AppSettings.load_settings(SETTINGS_PATH)
	assert_true(settings.telemetry_enabled)
	assert_false(settings.telemetry_notice_seen)


func test_settings_round_trip() -> void:
	var settings := AppSettings.load_settings(SETTINGS_PATH)
	settings.telemetry_enabled = false
	settings.telemetry_notice_seen = true
	settings.volume_pct = 42.0
	assert_true(settings.save(SETTINGS_PATH))
	var reloaded := AppSettings.load_settings(SETTINGS_PATH)
	assert_false(reloaded.telemetry_enabled)
	assert_true(reloaded.telemetry_notice_seen)
	assert_eq(reloaded.volume_pct, 42.0)


func test_music_and_sfx_levels_round_trip() -> void:
	var settings := AppSettings.new()
	assert_eq(settings.music_pct, 80.0, "music defaults a notch under the effects")
	assert_eq(settings.sfx_pct, 100.0)
	settings.music_pct = 35.0
	settings.sfx_pct = 70.0
	assert_true(settings.save(SETTINGS_PATH))
	var reloaded := AppSettings.load_settings(SETTINGS_PATH)
	assert_eq(reloaded.music_pct, 35.0)
	assert_eq(reloaded.sfx_pct, 70.0)


func test_the_tutorial_flags_round_trip() -> void:
	var settings := AppSettings.new()
	assert_false(settings.tutorial_completed, "a fresh install gets the tutorial")
	assert_false(settings.play_tutorial, "the title toggle starts off")
	settings.tutorial_completed = true
	settings.play_tutorial = true
	assert_true(settings.save(SETTINGS_PATH))
	var reloaded := AppSettings.load_settings(SETTINGS_PATH)
	assert_true(reloaded.tutorial_completed)
	assert_true(reloaded.play_tutorial)


func test_combat_speed_round_trips_and_snaps_to_an_allowed_value() -> void:
	var settings := AppSettings.new()
	assert_eq(settings.combat_speed, 1.0, "normal speed by default")
	settings.combat_speed = 2.0
	assert_true(settings.save(SETTINGS_PATH))
	assert_eq(AppSettings.load_settings(SETTINGS_PATH).combat_speed, 2.0)
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	file.store_string('{"v":1,"gameplay":{"combat_speed":7}}')
	file = null
	assert_eq(AppSettings.load_settings(SETTINGS_PATH).combat_speed, 2.0, "snapped to the top")


func test_music_and_sfx_levels_are_clamped_on_load() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	file.store_string('{"v":1,"audio":{"music_pct":250,"sfx_pct":-9}}')
	file = null
	var settings := AppSettings.load_settings(SETTINGS_PATH)
	assert_eq(settings.music_pct, 100.0)
	assert_eq(settings.sfx_pct, 0.0)


func test_a_corrupt_settings_file_loads_defaults_instead_of_throwing() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	file.store_string("not json at all")
	file = null
	var settings := AppSettings.load_settings(SETTINGS_PATH)
	assert_true(settings.telemetry_enabled, "defaults, not a crash")


## A newer build's settings must survive a downgrade.
func test_unknown_settings_keys_survive_a_round_trip() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	file.store_string('{"v":1,"from_the_future":{"nice":true}}')
	file = null
	var settings := AppSettings.load_settings(SETTINGS_PATH)
	assert_true(settings.save(SETTINGS_PATH))
	var raw := FileAccess.get_file_as_string(SETTINGS_PATH)
	assert_true(raw.contains("from_the_future"), "we did not eat someone else's key")
