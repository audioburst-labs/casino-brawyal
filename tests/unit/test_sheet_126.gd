extends GutTest
## Sheet 1.26 (designer's edits to Ace's kit, the Act I enemies, the loans and the
## coin bands), plus the path memory: the last two runs' paths are closed.

var _db: ContentDB

## Every number in each ability's three descriptions, transcribed from the sheet's
## "Ace - Abilities" tab. A number that drifts from the sheet fails here.
const SHEET_KIT := {
	"card_sling": [[6], [8], [10]],
	"quick_maneuvers": [[5, 8], [7, 10], [9, 12]],
	"double_down": [[9, 15], [13, 20], [15, 26]],
	"heartsteal": [[8, 1], [8, 2], [8, 3]],
	"color_up": [[], [], []],
	"pocket_rockets": [[7], [9], [11]],
	"slow_playing": [[2, 1], [3, 1], [4, 1]],
	"house_edge": [[], [2], []],
	"bust": [[28], [31], [34]],
	"dazzling_personality": [[1], [2], [3]],
	"face_reader": [[2], [3], [4]],
	"bad_beat": [[10], [13], [16]],
	"on_a_roll": [[10, 1], [12, 1], [14, 1]],
	"pay_line": [[20], [24], [28]],
	"flush": [[25], [30], [35]],
	"chip_tricks": [[2], [3], [4]],
	"hit": [[3], [4], [5]],
	"the_river": [[12, 1], [14, 1], [16, 1]],
	"card_trick": [[5], [7], [9]],
	"fold": [[20], [25], [30]],
	"all_in": [[30], [40], [50]],
	"sharp_edge": [[3], [4], [5]],
	"rainbow": [[7, 10, 2], [8, 12, 3], [9, 14, 4]],
	"bluff_call": [[10, 14], [12, 16], [14, 18]],
	"safe_play": [[9, 12], [11, 14], [13, 16]],
}


func before_all() -> void:
	_db = ContentDB.new()
	assert_true(_db.load_all("res://data"), str(_db.errors))


func _sim(enemies: Array, abilities: Array = ["card_sling"], seed_value: int = 5) -> CombatSim:
	var sim := CombatSim.new(_db, {"hero": "ace", "abilities": abilities,
		"enemies": enemies, "seed": seed_value})
	sim.hero.max_hp = 9999
	sim.hero.hp = 9999
	return sim


func _numbers(text: String) -> Array:
	var out: Array = []
	var digits := RegEx.new()
	digits.compile("\\d+")
	for found in digits.search_all(text):
		out.append(int(found.get_string()))
	return out


# ---- the kit, number for number ----

func test_every_ace_ability_carries_the_sheets_numbers_at_every_tier() -> void:
	assert_eq(SHEET_KIT.size(), 25, "all of Ace's abilities are on the sheet")
	for id: String in SHEET_KIT:
		for tier in 3:
			var def := _db.get_ability(StringName(id), tier)
			assert_eq(_numbers(def.description), SHEET_KIT[id][tier], "%s tier %d" % [id, tier])


func test_heartsteal_and_dazzling_personality_cost_one_chip_each() -> void:
	var heartsteal := _db.get_ability(&"heartsteal")
	assert_eq(heartsteal.cost.size(), 1)
	assert_eq(str(heartsteal.cost[0]), "heart")
	var dazzling := _db.get_ability(&"dazzling_personality")
	assert_eq(dazzling.cost.size(), 1)
	assert_eq(str(dazzling.cost[0]), "club")
	assert_false(heartsteal.is_mighty())
	assert_false(dazzling.is_mighty())


func test_heartsteal_gains_eight_block_at_every_tier_and_weak_scales() -> void:
	for tier in 3:
		var sim := CombatSim.new(_db, {"hero": "ace", "abilities": ["heartsteal"],
			"ability_tiers": {"heartsteal": tier}, "enemies": ["bouncer", "server"], "seed": 3})
		sim.begin_round()
		sim.tray.add(&"heart", 1)
		assert_true(sim.assign_chip(&"heart", 0, 0))
		assert_eq(sim.hero.block, 8, "tier %d" % tier)
		for enemy in sim.enemies:
			assert_eq(enemy.status_stacks(&"weak"), tier + 1, "Weak %d at tier %d" % [tier + 1, tier])


# ---- Slow Playing: Strength, not Rage ----

func test_slow_playing_no_longer_mentions_rage_anywhere() -> void:
	for tier in 3:
		var def := _db.get_ability(&"slow_playing", tier)
		assert_false(def.description.contains("Rage"), "tier %d" % tier)
		for effect: Dictionary in def.effects:
			assert_ne(str(effect.op), "rage_per_weak")
	assert_false((_db.get_ability(&"slow_playing").keywords as Array).has("rage"))
	assert_true((_db.get_ability(&"slow_playing").keywords as Array).has("strength"))


# ---- Face Reader: per incoming hit ----

func test_face_reader_counts_every_announced_hit_multistrike_included() -> void:
	var sim := _sim(["dealer", "dealer"], ["face_reader"])
	sim.begin_round()
	# Two Dealers open with Deal 2X2: four hits between them.
	assert_eq(sim.incoming_hit_count(), 4)
	sim.enemies[0].apply_status(&"multistrike", 1)
	assert_eq(sim.incoming_hit_count(), 5, "Multistrike adds a hit")


func test_a_stunned_enemy_and_a_move_that_does_not_attack_add_no_hits() -> void:
	var sim := _sim(["dealer", "manager"], ["face_reader"])
	sim.begin_round()
	# The Manager opens by calling staff: no attack at all. The Dealer: 2 hits.
	assert_eq(sim.incoming_hit_count(), 2)
	sim.enemies[0].apply_status(&"stun", 1)
	assert_eq(sim.incoming_hit_count(), 0, "a stunned Dealer loses its action")


func test_face_reader_pays_two_block_per_hit_when_it_is_played() -> void:
	var sim := _sim(["dealer"], ["face_reader"])
	sim.begin_round()
	sim.hero.block = 0
	sim.tray.add(&"club", 1)
	sim.tray.add(&"diamond", 1)
	assert_true(sim.assign_chip(&"club", 0, 0))
	assert_true(sim.assign_chip(&"diamond", 0, 1))
	assert_eq(sim.hero.block, 4, "2 hits, 2 Block each")


func test_the_round_start_passive_sees_the_intents_it_is_paying_for() -> void:
	# Passives used to fire before the enemies chose a move, which would have made
	# a "per incoming hit" passive pay nothing at the start of every round.
	var sim := _sim(["dealer"], ["face_reader"])
	sim.begin_round()
	sim.drain_events()
	sim.tray.add(&"club", 1)
	sim.tray.add(&"diamond", 1)
	sim.assign_chip(&"club", 0, 0)
	sim.assign_chip(&"diamond", 0, 1)
	sim.tray.discard_all()
	sim.end_assignment()
	sim.begin_round()
	assert_eq(sim.hero.block, 2 * sim.incoming_hit_count(), "paid on the announced hits")
	assert_gt(sim.hero.block, 0)


# ---- Sturdy ----

func test_sturdy_adds_flat_block_before_frail_takes_its_quarter() -> void:
	var sim := _sim(["bouncer"])
	assert_eq(StatusRules.block_gained(8, sim.hero), 8)
	sim.hero.apply_status(&"sturdy", 2)
	assert_eq(StatusRules.block_gained(8, sim.hero), 10, "Sturdy 2")
	sim.hero.apply_status(&"frail", 1)
	assert_eq(StatusRules.block_gained(8, sim.hero), 8, "(8 + 2) less 25%, half-up: 7.5 is 8")
	assert_eq(StatusRules.block_gained(0, sim.hero), 0, "Sturdy never makes Block from nothing")


func test_sturdy_is_a_buff_the_game_knows_about() -> void:
	var def := _db.get_status(&"sturdy")
	assert_not_null(def)
	assert_eq(def.kind, "buff")
	var keyword := _db.get_keyword(&"sturdy")
	assert_not_null(keyword)
	assert_eq(keyword.text, "Increase Block gain by X.")


func test_an_ability_that_gains_block_gains_the_sturdy_bonus() -> void:
	var sim := _sim(["bouncer"], ["fold"])
	sim.begin_round()
	sim.hero.apply_status(&"sturdy", 3)
	sim.tray.add(&"club", 1)
	assert_true(sim.assign_chip(&"club", 0, 0))
	assert_eq(sim.hero.block, 23, "Fold's 20 plus Sturdy 3")


func test_negative_strength_cuts_a_hit_but_never_below_nothing() -> void:
	var sim := _sim(["bouncer"])
	sim.hero.apply_status(&"strength", -4)
	assert_eq(StatusRules.attack_damage(6, sim.hero), 2)
	assert_eq(StatusRules.attack_damage(3, sim.hero), 0)
	sim.hero.apply_status(&"weak", 1)
	assert_eq(StatusRules.attack_damage(3, sim.hero), 0, "Weak cannot lift a nothing back to 1")


# ---- the Act I enemies ----

func test_the_golems_moves_were_reshuffled() -> void:
	var golem := _db.get_enemy(&"chip_golem")
	var bash: Dictionary = golem.moves["bash"].intent
	assert_eq([int(bash.instances), int(bash.per_hit)], [1, 14])
	assert_true(bool(bash.get("absorb", false)), "Bash takes the chips off the abilities")
	assert_false(bash.has("gift_chips"))
	var harden: Dictionary = golem.moves["harden"].intent
	assert_eq(int(harden.self_block), 15)
	assert_eq(int(harden.gift_chips), 1, "Harden is the one that gives a chip")
	assert_false(harden.has("absorb"))


func test_an_enemy_with_sturdy_raises_its_own_block() -> void:
	var sim := _sim(["chip_golem"])
	var golem := sim.enemies[0]
	golem.apply_status(&"sturdy", 5)
	sim._intents[golem.id] = {"intent": {"instances": 0, "per_hit": 0, "debuffs": [], "self_block": 15}}
	sim._execute_move(golem, false)
	assert_eq(golem.block, 20, "15 plus Sturdy 5")


func test_the_dealer_is_two_hits_of_two() -> void:
	var dealer := _db.get_enemy(&"dealer")
	assert_eq([dealer.hp_min, dealer.hp_max], [43, 49])
	for move_id: String in dealer.moves:
		var intent: Dictionary = dealer.moves[move_id].intent
		assert_eq([int(intent.instances), int(intent.per_hit)], [2, 2], move_id)


func test_the_manager_and_the_server_follow_the_sheet() -> void:
	assert_eq([_db.get_enemy(&"manager").hp_min, _db.get_enemy(&"manager").hp_max], [39, 45])
	assert_eq([_db.get_enemy(&"server").hp_min, _db.get_enemy(&"server").hp_max], [25, 31])
	assert_eq([_db.get_enemy(&"bouncer").hp_min, _db.get_enemy(&"bouncer").hp_max], [53, 59])


# ---- Gift: immediate ----

func test_a_gift_on_the_players_own_turn_lands_in_the_tray_at_once() -> void:
	# A Golem's gift normally comes on ITS turn. The chip is the same kind of chip,
	# and wherever it lands it goes into the tray the next round starts from.
	var sim := _sim(["chip_golem"])
	sim.begin_round()
	sim.tray.discard_all()
	sim._intents[sim.enemies[0].id] = {"intent": {"instances": 0, "per_hit": 0,
		"debuffs": [], "gift_chips": 2}}
	sim.drain_events()
	sim._execute_move(sim.enemies[0], false)
	assert_eq(sim.tray.total(), 2, "both chips are in the tray immediately")
	var gifts := sim.drain_events().filter(func(e: CombatEvent) -> bool:
		return e.type == &"chips_generated" and str(e.data.source) == "gift")
	assert_eq(gifts.size(), 2)


# ---- the path memory ----

func test_the_picker_never_offers_a_path_that_is_closed() -> void:
	var ids := ["path_1", "path_2", "path_3", "path_4", "path_5", "path_6"]
	var rng := RandomNumberGenerator.new()
	for seed_value in 60:
		rng.seed = seed_value
		var recent := ["path_2", "path_5"]
		var picked := PathPicker.pick(ids, recent, rng)
		assert_false(recent.has(String(picked)), "seed %d" % seed_value)


func test_a_path_stays_closed_for_exactly_the_next_two_runs() -> void:
	var ids := ["path_1", "path_2", "path_3", "path_4", "path_5", "path_6"]
	var rng := RandomNumberGenerator.new()
	for seed_value in 40:
		rng.seed = seed_value
		var recent: Array[String] = []
		var history: Array[String] = []
		for run_index in 12:
			var picked := PathPicker.pick(ids, recent, rng)
			history.append(String(picked))
			recent = PathPicker.remember(recent, picked)
		for i in history.size():
			for gap in [1, 2]:
				if i + gap < history.size():
					assert_ne(history[i + gap], history[i],
						"seed %d: run %d repeated run %d" % [seed_value, i + gap, i])


func test_a_path_comes_back_on_the_third_run_after() -> void:
	# Closed for two runs does not mean closed for good.
	var ids := ["path_1", "path_2", "path_3"]
	var rng := RandomNumberGenerator.new()
	for seed_value in 60:
		rng.seed = seed_value
		var first := PathPicker.pick(ids, [], rng)
		var recent := PathPicker.remember([], first)
		var second := PathPicker.pick(ids, recent, rng)
		recent = PathPicker.remember(recent, second)
		var third := PathPicker.pick(ids, recent, rng)
		assert_false([first, second].has(third), "seed %d: the third run gets the one path left" % seed_value)
		recent = PathPicker.remember(recent, third)
		# Closed for two runs, so the FIRST path is open again for the fourth.
		assert_eq(PathPicker.pick(ids, recent, rng), first, "seed %d" % seed_value)


func test_remember_keeps_the_newest_two_oldest_first() -> void:
	var recent := PathPicker.remember([], &"path_1")
	assert_eq(recent, ["path_1"] as Array[String])
	recent = PathPicker.remember(recent, &"path_4")
	assert_eq(recent, ["path_1", "path_4"] as Array[String])
	recent = PathPicker.remember(recent, &"path_3")
	assert_eq(recent, ["path_4", "path_3"] as Array[String], "path_1 is open again")


func test_a_picker_with_everything_closed_still_starts_a_run() -> void:
	var rng := RandomNumberGenerator.new()
	assert_ne(PathPicker.pick(["path_1"], ["path_1"], rng), &"")
	assert_eq(PathPicker.pick([], [], rng), &"")


func test_the_map_generator_rolls_around_the_closed_paths() -> void:
	for seed_value in 40:
		var run := RunState.new()
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		MapGenerator.next_options(_db, run, rng, ["path_1", "path_3"])
		assert_false(["path_1", "path_3"].has(String(run.path_id)), "seed %d" % seed_value)
		assert_ne(run.path_id, &"")


func test_the_bots_still_draw_from_all_six_paths() -> void:
	var seen := {}
	for seed_value in 120:
		var run := RunState.new()
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		MapGenerator.next_options(_db, run, rng)
		seen[run.path_id] = true
	assert_eq(seen.size(), 6, "no memory, no restriction")


func test_a_run_that_already_has_a_path_keeps_it_whatever_is_closed() -> void:
	var run := RunState.new()
	run.path_id = &"path_2"
	var options := MapGenerator.next_options(_db, run, RandomNumberGenerator.new(), ["path_2", "path_3"])
	assert_eq(run.path_id, &"path_2", "an in-flight save is never re-rolled")
	assert_false(options.is_empty())


func test_the_recent_paths_survive_a_restart() -> void:
	var path := "user://test_sheet_126_settings.json"
	var settings := AppSettings.new()
	assert_eq(settings.recent_paths, [] as Array[String], "a fresh install has none")
	settings.recent_paths = ["path_4", "path_6"] as Array[String]
	assert_true(settings.save(path))
	assert_eq(AppSettings.load_settings(path).recent_paths, ["path_4", "path_6"] as Array[String])
	DirAccess.remove_absolute(path)


# ---- the coin bands ----

func test_combat_coin_bands_follow_the_new_sheet() -> void:
	var bands := {1: [36, 44], 2: [45, 55], 3: [54, 66], 4: [63, 77], 5: [72, 88]}
	for stage: int in bands:
		for lineup: Dictionary in _db.lineups_for_stage(stage):
			assert_eq([int(lineup.gold_min), int(lineup.gold_max)], bands[stage], String(lineup.id))
	for lineup: Dictionary in _db.elite_lineups():
		assert_eq([int(lineup.gold_min), int(lineup.gold_max)], [90, 110], String(lineup.id))


func test_the_boss_still_pays_nothing_until_act_two() -> void:
	for lineup: Dictionary in _db.lineups_for_stage(ContentDB.BOSS_STAGE):
		assert_eq([int(lineup.gold_min), int(lineup.gold_max)], [0, 0])
