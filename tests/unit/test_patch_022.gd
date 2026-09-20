extends GutTest
## Patch 0.22 (build 0.0.112): the ability cards' live BLOCK numbers, the
## header's fixed number columns, and the doc/sheet sync of this pull.

var _db: ContentDB


func before_all() -> void:
	_db = ContentDB.new()
	assert_true(_db.load_all("res://data"), str(_db.errors))


func _sim(abilities: Array = ["quick_maneuvers"]) -> CombatSim:
	return CombatSim.new(_db, {
		"hero": "ace",
		"abilities": abilities,
		"enemies": ["bouncer"],
		"seed": 7,
	})


const CardScript := preload("res://src/ui/combat/ability_card.gd")


# ---- "Block numbers on abilities should be affected by buffs/debuffs" ----

func test_block_figures_are_collected_like_damage_figures() -> void:
	# Quick Maneuvers keeps its Diamond value in bonus_effects...
	var quick := CardScript.block_amounts(_db.get_ability(&"quick_maneuvers"))
	assert_has(quick, 5)
	assert_has(quick, 8)
	# ...Bad Beat keeps its whole payoff nested inside a Cash In...
	assert_eq(CardScript.block_amounts(_db.get_ability(&"bad_beat")), [10] as Array[int])
	# ...Face Reader prints a per-enemy figure...
	assert_eq(CardScript.block_amounts(_db.get_ability(&"face_reader")), [2] as Array[int])
	# ...and Fold is the plain case (Slow Playing stopped granting Block in
	# sheet v0.122 - it applies Weak and converts it to Rage instead).
	assert_eq(CardScript.block_amounts(_db.get_ability(&"fold")), [30] as Array[int])
	# A pure damage ability has none.
	assert_eq(CardScript.block_amounts(_db.get_ability(&"card_sling")), [] as Array[int])


func test_frail_lowers_every_previewed_block_figure() -> void:
	var sim := _sim()
	sim.hero.apply_status(&"frail", 2)
	assert_eq(sim.preview_block(5), 4, "Quick Maneuvers base")
	assert_eq(sim.preview_block(8), 6, "its Diamond bonus")
	assert_eq(sim.preview_block(10), 8, "Bad Beat, nested in a Cash In")
	assert_eq(sim.preview_block(20), 15, "Slow Playing")


func test_block_preview_is_unchanged_without_frail() -> void:
	var sim := _sim()
	for base in [5, 8, 10, 20]:
		assert_eq(sim.preview_block(base), base)


func test_gold_tier_block_figures_are_previewed_too() -> void:
	# Gold Quick Maneuvers is 9 -> 12 in the 0.121 sheet (patch 0.113).
	var gold := _db.get_ability(&"quick_maneuvers", 2)
	var amounts := CardScript.block_amounts(gold)
	assert_has(amounts, 9)
	assert_has(amounts, 12)


# ---- doc/sheet sync of the 2026-09-14 pull ----

func test_relic_prices_match_the_sheet() -> void:
	var expected := {
		&"gamblers_confidence": [22, 28], &"bounty_list": [22, 28],
		&"spade_protection": [27, 33], &"heart_protection": [27, 33],
		&"club_protection": [27, 33], &"diamond_protection": [27, 33],
		&"winners_aura": [22, 28], &"high_roller": [32, 38],
		&"dark_emblem": [37, 43], &"red_emblems": [37, 43],
		&"lucky_foot": [27, 33],
	}
	for id: StringName in expected:
		var relic := _db.get_relic(id)
		assert_not_null(relic, str(id))
		assert_eq([relic.price_min, relic.price_max], expected[id], str(id))


func test_sticker_price_is_ten_plus_five_per_encounter() -> void:
	var run := RunState.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	assert_eq(int(ShopStock.generate(_db, run, rng).stickers[0].price), 15,
		"encounter 1: 10 + 5")
	run.record_visit(&"combat")
	run.record_visit(&"combat")
	assert_eq(int(ShopStock.generate(_db, run, rng).stickers[0].price), 25,
		"encounter 3: 10 + 15")


func test_server_glass_barrage_hits_twice() -> void:
	var server := _db.get_enemy(&"server")
	assert_eq(int(server.moves["glass_barrage"].intent.instances), 2)
	assert_eq(int(server.moves["glass_barrage"].intent.per_hit), 3)


# ---- "the animation should be exactly the same, but downwards" ----

func test_the_reels_scroll_downward() -> void:
	var strip := ReelStrip.new()
	strip.framed = false
	add_child_autofree(strip)
	strip.set_reel_count(3)
	var clip := Control.new()
	clip.custom_minimum_size = Vector2(102, 122)
	add_child_autofree(clip)
	var spin: Dictionary = strip._populate(clip, &"spade")
	# Position INCREASES from start to landing, and in Godot +y is down, so
	# the faces walk down past the glass.
	assert_lt(float(spin.start_y), float(spin.land_y),
		"the strip starts above its landing offset")
	# The landing cell sits near the TOP of the strip, so the cells that roll
	# past before it are the ones below it.
	assert_eq(int(spin.landing_index), ReelStrip.LANDING_INDEX)
	assert_eq(ReelStrip.LANDING_INDEX, 1)
	# ...and there is a cell above it to cover the downward overshoot.
	assert_gt(ReelStrip.LANDING_INDEX, 0)


func test_the_landed_face_ends_centred_in_its_window() -> void:
	var strip := ReelStrip.new()
	strip.framed = false
	add_child_autofree(strip)
	var clip := Control.new()
	clip.custom_minimum_size = Vector2(102, 122)
	add_child_autofree(clip)
	var spin: Dictionary = strip._populate(clip, &"heart")
	# cell k sits at k * FACE inside the strip; at land_y the landing cell's
	# centre is the window's centre.
	var centre: float = float(spin.land_y) + ReelStrip.FACE * ReelStrip.LANDING_INDEX \
		+ ReelStrip.FACE * 0.5
	assert_almost_eq(centre, 122.0 * 0.5, 0.51)


func test_six_reels_still_fit_the_machine_area() -> void:
	for count in range(1, 7):
		var scale := ReelStrip.scale_for(count)
		var row := ReelStrip.WINDOW.x * scale * count + ReelStrip.SEPARATION * (count - 1)
		assert_lte(row, ReelStrip.MAX_ROW_WIDTH + 0.5, "%d reels fit" % count)
		assert_lte(scale, 1.0)
	assert_eq(ReelStrip.scale_for(4), 1.0, "up to four reels draw full size")
	assert_lt(ReelStrip.scale_for(6), 1.0, "six shrink to fit")


# ---- Elite replaces Hard Combat ----

func test_elites_replace_hard_combat_end_to_end() -> void:
	var run := RunState.new()
	for i in 4:
		run.record_visit(&"combat")
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var config := EncounterFactory.combat_config(_db, run, rng, {"type": &"elite"})
	assert_eq(config.hp_mult, 1.0, "no buffed variant any more")
	assert_eq((config.enemies as Array).size(), 1)
	assert_has([&"chip_golem", &"loan_shark"], config.enemies[0])


func test_an_old_save_migrates_hard_combat_to_elite() -> void:
	var run := RunState.new()
	run.record_visit(&"combat")
	var saved := run.to_dict()
	saved.history = ["combat", "hard_combat", "shop"]
	saved.pending_encounter = {"type": "hard_combat", "variant": "buffed"}
	var restored := RunState.from_dict(saved)
	assert_eq(restored.history[1], &"elite")
	assert_eq(str(restored.pending_encounter.type), "elite")
	assert_false(restored.pending_encounter.has("variant"))
	assert_eq(restored.count_visited(&"elite"), 1)


## Patch 0.114: the gap is a property of the six authored Paths now, not a
## predicate on the generator. Same rule, asserted against the shipped data.
func test_the_elite_placement_rule_needs_a_two_encounter_gap() -> void:
	for path: Dictionary in _db.all_paths():
		var at: Array[int] = []
		for index in path.encounters.size():
			if (path.encounters[index] as Array).has(&"elite"):
				at.append(index + 1)
		assert_eq(at.size(), 2, "%s offers exactly two Elites" % path.id)
		assert_gt(at[0], 3, "%s: the first Elite is after encounter 3" % path.id)
		assert_gt(at[1] - at[0], 2, "%s: two encounters between them" % path.id)
