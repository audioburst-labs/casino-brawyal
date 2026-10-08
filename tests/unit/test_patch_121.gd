extends GutTest
## Patch 0.121, the designer's notes: Sharp Edge, Slow Playing's Rage, and the
## content the sheet changed beside the Drunk Patron.

var db: ContentDB


func before_each() -> void:
	db = ContentDB.new()
	assert_true(db.load_all("res://data"), str(db.errors))


func _sim(enemies: Array, abilities: Array, seed_value := 7) -> CombatSim:
	var sim := CombatSim.new(db, {"hero": "ace", "enemies": enemies,
		"abilities": abilities, "seed": seed_value})
	sim.hero.max_hp = 9999
	sim.hero.hp = 9999
	sim.begin_round()
	sim.drain_events()
	return sim


func _fire(sim: CombatSim, index: int, any_as: StringName = &"spade") -> void:
	var state: AbilityState = sim.abilities[index]
	for slot in state.def.cost.size():
		var suit: StringName = state.def.cost[slot]
		if suit == &"any":
			suit = any_as
		sim.tray.add(suit, 1)
		assert_true(sim.assign_chip(suit, index, slot),
			"%s slot %d refused %s" % [state.def.id, slot, suit])


func _count(sim: CombatSim, type: StringName) -> int:
	return sim.drain_events().filter(
		func(e: CombatEvent) -> bool: return e.type == type).size()


# ---- Sharp Edge ----------------------------------------------------------------

## "It shouldn't deal damage when a Mark is applied to a target that's already
## marked." The trigger is the Mark going on, not the act of trying.
func test_sharp_edge_stays_quiet_when_the_target_is_already_marked() -> void:
	var sim := _sim(["bouncer"], ["sharp_edge", "card_sling"])
	_fire(sim, 0)
	sim.drain_events()
	var hp := sim.enemies[0].hp
	_fire(sim, 1)          # Card Sling with a Spade: Mark again
	assert_eq(_count(sim, &"passive_fired"), 0, "already marked: no trigger")
	assert_eq(sim.enemies[0].hp, hp - 6, "only Card Sling's own 6")


func test_sharp_edge_fires_for_every_fresh_mark() -> void:
	var sim := _sim(["bouncer", "bouncer"], ["sharp_edge", "card_sling"])
	_fire(sim, 0)
	for enemy in sim.enemies:
		enemy.statuses.erase(&"mark")
	sim.drain_events()
	_fire(sim, 1)
	assert_eq(_count(sim, &"passive_fired"), 1, "a fresh Mark pays")


## Whatever puts a Mark on an enemy, Sharp Edge has to answer once the enemy
## really did go from unmarked to marked ("the passive doesn't always trigger").
func test_every_marking_ability_trips_sharp_edge() -> void:
	var checked := 0
	for id: StringName in db.all_ability_ids():
		if id == &"sharp_edge":
			continue
		var def := db.get_ability(id)
		if not def.keywords.has(&"mark"):
			continue
		for suit: StringName in [&"spade", &"heart", &"club", &"diamond"]:
			var sim := _sim(["bouncer", "bouncer"], ["sharp_edge", String(id)])
			_fire(sim, 0, suit)
			for enemy in sim.enemies:
				enemy.statuses.erase(&"mark")
			sim.drain_events()
			var before := sim.enemies.filter(
				func(e: CombatActor) -> bool: return e.has_status(&"mark")).size()
			_fire(sim, 1, suit)
			var marked := sim.enemies.filter(
				func(e: CombatActor) -> bool: return e.has_status(&"mark")).size()
			var fired := _count(sim, &"passive_fired")
			if marked > before:
				checked += 1
				assert_gt(fired, 0, "%s with %s marked an enemy but Sharp Edge stayed quiet"
					% [id, suit])
	assert_gt(checked, 0, "at least one marking ability was exercised")


# ---- Slow Playing / Rage ---------------------------------------------------------

func test_the_heros_rage_adds_to_every_hit_of_the_next_attack_then_is_spent() -> void:
	var sim := _sim(["bouncer"], ["card_sling", "pocket_rockets"])
	sim.hero.apply_status(&"rage", 3)
	var enemy := sim.enemies[0]
	var hp := enemy.hp
	_fire(sim, 0)          # Card Sling: 6, plus Rage 3
	assert_eq(enemy.hp, hp - 9, "Rage 3 lands on the hit")
	assert_false(sim.hero.has_status(&"rage"), "and is spent by that attack")
	assert_eq(_count(sim, &"rage_spent"), 1)


func test_rage_lands_on_every_hit_of_a_multi_hit_attack() -> void:
	var sim := _sim(["bouncer"], ["pocket_rockets"])
	sim.hero.apply_status(&"rage", 2)
	var enemy := sim.enemies[0]
	var hp := enemy.hp
	_fire(sim, 0)          # Pocket Rockets: 6 twice, +2 each
	assert_eq(enemy.hp, hp - 16)
	assert_false(sim.hero.has_status(&"rage"))


func test_slow_playing_then_an_attack_pays_out() -> void:
	var sim := _sim(["bouncer"], ["slow_playing", "card_sling"])
	_fire(sim, 0, &"heart")
	var rage := sim.hero.status_stacks(&"rage")
	assert_gt(rage, 0, "Slow Playing gave Rage for the Weak it applied")
	var enemy := sim.enemies[0]
	var hp := enemy.hp
	_fire(sim, 1)
	assert_lt(enemy.hp, hp - 6, "Card Sling hit harder than its printed 6")
	assert_false(sim.hero.has_status(&"rage"))


func test_the_card_preview_includes_rage() -> void:
	var sim := _sim(["bouncer"], ["card_sling"])
	var plain := sim.preview_damage(6, sim.abilities[0])
	sim.hero.apply_status(&"rage", 4)
	assert_eq(sim.preview_damage(6, sim.abilities[0]), plain + 4)


# ---- Story encounters -------------------------------------------------------------

func test_a_coin_story_prints_the_final_figure_not_the_formula() -> void:
	var run := RunState.new()
	run.history = [&"combat", &"combat", &"story"]   # encounter 4
	var event := db.get_story_event(&"lost_soul")
	var bucket: Dictionary = event.choices[1]
	assert_eq(RunEffects.summary_text(bucket, run),
		"Gain %d coins" % (5 * run.encounter_number()))
	for id: StringName in db.all_story_event_ids():
		for choice: Dictionary in db.get_story_event(id).choices:
			var text := RunEffects.summary_text(choice, run)
			assert_false(text.contains("{"), "%s: %s" % [id, text])
			assert_false(text.contains("per encounter"), "%s: %s" % [id, text])


func test_the_risky_dealings_line_shows_both_final_figures() -> void:
	var run := RunState.new()
	run.history = [&"combat", &"story"]              # encounter 3
	var hand: Dictionary = db.get_story_event(&"risky_dealings").choices[1]
	assert_eq(RunEffects.summary_text(hand, run), "Lose 9 HP, gain 21 coins")


func test_the_story_picker_prefers_stories_never_seen() -> void:
	var all_ids := [&"a", &"b", &"c", &"d", &"e"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 50:
		var picked := StoryPicker.pick(all_ids, [&"a"], ["b", "c"], rng)
		assert_true(picked in [&"d", &"e"], "unseen in the run and on the machine")
	for i in 50:
		var picked := StoryPicker.pick(all_ids, [&"a"], ["a", "b", "c", "d", "e"], rng)
		assert_ne(picked, &"a", "every story seen on the machine: still not this run's")
	assert_eq(StoryPicker.pick(all_ids, all_ids, all_ids.map(str), rng) in all_ids, true)


func test_the_machine_wide_list_starts_over_when_everything_has_been_seen() -> void:
	var all_ids := [&"a", &"b", &"c"]
	assert_eq(StoryPicker.remember(all_ids, ["a"], &"b"), ["a", "b"] as Array[String])
	assert_eq(StoryPicker.remember(all_ids, ["a", "b"], &"c"), ["c"] as Array[String])


func test_pickers_choose_varied_stories_across_runs() -> void:
	var firsts := {}
	for seed_value in 30:
		var rng := GameRng.new(seed_value * 977 + 3)
		var picked := StoryPicker.pick(db.all_story_event_ids(), [], [], rng.stream(&"map"))
		firsts[picked] = true
	assert_gt(firsts.size(), 2, "the first story is not the same one every run")


# ---- Scripted fights (the tutorial) -----------------------------------------------

func _scripted(spins: Array, first_moves: Dictionary = {}) -> CombatSim:
	var sim := CombatSim.new(db, {"hero": "ace", "enemies": ["bouncer"],
		"abilities": ["card_sling", "quick_maneuvers", "double_down"], "seed": 3,
		"scripted_spins": spins, "first_moves": first_moves})
	sim.hero.max_hp = 9999
	sim.hero.hp = 9999
	return sim


func test_scripted_spins_land_exactly_where_told_then_the_dice_take_over() -> void:
	var sim := _scripted([[&"club", &"club", &"diamond"], [&"spade", &"spade", &"club"],
		[&"heart", &"heart", &"heart"]])
	sim.begin_round()
	assert_eq(sim.last_symbols, [&"club", &"club", &"diamond"] as Array[StringName])
	assert_eq(sim.tray.count(&"club"), 2)
	assert_eq(sim.tray.count(&"diamond"), 1)
	sim.tray.discard_all()
	sim.end_assignment()
	sim.begin_round()
	assert_eq(sim.tray.count(&"spade"), 2)
	assert_eq(sim.tray.count(&"club"), 1)
	sim.tray.discard_all()
	sim.end_assignment()
	sim.begin_round()
	assert_eq(sim.tray.count(&"heart"), 4, "three hearts pay 3 and a bonus 1")
	sim.tray.discard_all()
	sim.end_assignment()
	sim.begin_round()
	assert_eq(sim.last_symbols.size(), 3, "past the script it is a normal spin")


func test_a_script_does_not_disturb_the_dice_of_an_unscripted_fight() -> void:
	var plain := CombatSim.new(db, {"hero": "ace", "enemies": ["bouncer"],
		"abilities": ["card_sling"], "seed": 3})
	plain.begin_round()
	var scripted := _scripted([])
	scripted.begin_round()
	assert_eq(scripted.last_symbols, plain.last_symbols)


func test_the_bouncer_can_be_told_to_open_with_either_move() -> void:
	for first in ["door_check", "double_jab"]:
		var sim := _scripted([], {"bouncer": first})
		sim.begin_round()
		assert_eq(str(sim.intent_display(sim.enemies[0].id).move), first)
		# The tail is untouched: the other opening move, then Pump Up, looping.
		sim.tray.discard_all()
		sim.end_assignment()
		sim.begin_round()
		var second := "double_jab" if first == "door_check" else "door_check"
		assert_eq(str(sim.intent_display(sim.enemies[0].id).move), second)
		sim.tray.discard_all()
		sim.end_assignment()
		sim.begin_round()
		assert_eq(str(sim.intent_display(sim.enemies[0].id).move), "pump_up")


func test_the_tutorial_replaces_only_the_first_encounter_with_the_taught_kit() -> void:
	var kit := [&"card_sling", &"quick_maneuvers", &"double_down"]
	assert_true(TutorialScript.applies(1, kit))
	assert_false(TutorialScript.applies(2, kit))
	assert_false(TutorialScript.applies(1, [&"card_sling", &"double_down"]),
		"it teaches Quick Maneuvers, so the kit must have it")
	var found := db.all_lineups().filter(func(l: Dictionary) -> bool:
		return StringName(str(l.id)) == TutorialScript.LINEUP)
	assert_eq(found.size(), 1, "the Bouncer fight exists")
	assert_eq(found[0].enemies, [&"bouncer"] as Array[StringName])


func test_the_whole_walkthrough_plays_as_the_doc_describes() -> void:
	var config := TutorialScript.apply({"hero": "ace", "enemies": ["bouncer"],
		"abilities": ["card_sling", "quick_maneuvers", "double_down"], "seed": 9})
	assert_true(config.tutorial)
	var sim := CombatSim.new(db, config)
	sim.begin_round()
	assert_eq(str(sim.intent_display(sim.enemies[0].id).move), "double_jab",
		"he starts with Attack #2")
	assert_eq([sim.tray.count(&"club"), sim.tray.count(&"diamond")], [2, 1])
	var bouncer := sim.enemies[0]
	var hp := bouncer.hp
	sim.assign_chip(&"club", 0, 0)                    # Card Sling
	assert_eq(bouncer.hp, hp - 6, "Card Sling hits for 6")
	sim.assign_chip(&"diamond", 1, 0)                 # Quick Maneuvers
	assert_eq(sim.hero.block, 8, "a Diamond makes it 8 Block")
	assert_eq(sim.tray.count(&"club"), 1, "one chip left to place")
	var start_hp := sim.hero.hp
	sim.tray.discard_all()
	sim.end_assignment()
	assert_eq(sim.hero.hp, start_hp, "2 x 3 against 8 Block costs nothing")


func test_run_state_remembers_the_tutorial_was_won() -> void:
	var run := RunState.new()
	run.tutorial_won = true
	assert_true(RunState.from_dict(run.to_dict()).tutorial_won)
