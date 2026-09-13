extends GutTest
## Integration: the Game autoload routes a run through its screens.
## Uses a dummy screen root so no window interaction is needed.

var _root: Control


func before_each() -> void:
	_root = Control.new()
	add_child_autofree(_root)
	Game.register_screen_root(_root)


func after_each() -> void:
	Game.run = null


func _current_screen() -> Node:
	# queue_free'd old screens may still linger this frame; take the newest.
	return _root.get_child(_root.get_child_count() - 1)


func test_new_run_starts_encounter_one_combat() -> void:
	Game.new_run(123)
	await wait_physics_frames(2)
	var screen := _current_screen()
	assert_eq(screen.name, "CombatScreen")
	assert_true(screen.run_mode)
	assert_eq(Game.run.history, [&"combat"] as Array[StringName])
	assert_eq(screen.sim.hero.hp, Game.run.max_hp)


func test_combat_victory_leads_to_rewards_then_map() -> void:
	Game.new_run(456)
	await wait_physics_frames(2)
	Game.combat_finished(true, 42, [])
	await wait_physics_frames(2)
	assert_eq(_current_screen().name, "RewardScreen")
	assert_eq(Game.run.hp, 42)
	assert_gt(Game.run.coins, 0, "reward screen auto-claims coins")
	Game.encounter_finished()
	await wait_physics_frames(2)
	assert_eq(_current_screen().name, "MapScreen")


func test_combat_defeat_leads_to_game_over() -> void:
	Game.new_run(789)
	await wait_physics_frames(2)
	Game.combat_finished(false, 0, [])
	await wait_physics_frames(2)
	assert_eq(_current_screen().name, "GameOverScreen")


func test_non_combat_encounters_route_to_their_screens() -> void:
	Game.new_run(999)
	await wait_physics_frames(2)
	Game.combat_finished(true, 60, [])
	await wait_physics_frames(2)
	for pair in [
		[{"type": &"story"}, "StoryScreen"],
		[{"type": &"rest"}, "RestScreen"],
		[{"type": &"treasure"}, "TreasureScreen"],
		[{"type": &"casino"}, "CasinoScreen"],
		[{"type": &"shop"}, "ShopScreen"],
	]:
		Game.choose_encounter(pair[0])
		await wait_physics_frames(2)
		assert_eq(_current_screen().name, pair[1])
	Game.show_loadout()
	await wait_physics_frames(2)
	assert_eq(_current_screen().name, "LoadoutScreen")


func test_map_options_are_cached_per_encounter() -> void:
	Game.new_run(321)
	await wait_physics_frames(2)
	Game.combat_finished(true, 60, [])
	await wait_physics_frames(2)
	var first := Game.map_options()
	var second := Game.map_options()  # e.g. after visiting the Abilities screen
	assert_eq(first, second, "detours must not re-roll the offered pair")


func test_boss_victory_leads_to_victory_screen() -> void:
	Game.new_run(111)
	await wait_physics_frames(2)
	for i in 8:
		Game.run.record_visit(&"combat")
	Game.choose_encounter({"type": &"boss"})
	await wait_physics_frames(2)
	var screen := _current_screen()
	assert_eq(screen.name, "CombatScreen")
	assert_eq(screen.sim.enemies[0].def_id, &"mr_moneybags")
	Game.combat_finished(true, 30, [])
	await wait_physics_frames(2)
	assert_eq(_current_screen().name, "VictoryScreen")


# ---- Exiting to the main menu mid-encounter resumes it, not skips it (0.0.111) ----

func test_the_chosen_encounter_is_remembered_until_it_is_finished() -> void:
	Game.new_run(555)
	await wait_physics_frames(2)
	assert_eq(str(Game.run.pending_encounter.get("type", "")), "combat",
		"encounter one is pending while it is being fought")
	assert_true(Game.run.pending_encounter.has("lineup"))
	Game.combat_finished(true, 60, [])
	await wait_physics_frames(2)
	assert_true(Game.run.pending_encounter.is_empty(), "the reward screen is not an encounter")
	Game.choose_encounter({"type": &"shop"})
	await wait_physics_frames(2)
	assert_eq(str(Game.run.pending_encounter.type), "shop")
	Game.encounter_finished()
	await wait_physics_frames(2)
	assert_true(Game.run.pending_encounter.is_empty())


func test_continuing_a_save_reopens_the_pending_encounter() -> void:
	Game.new_run(556)
	await wait_physics_frames(2)
	Game.combat_finished(true, 60, [])
	await wait_physics_frames(2)
	Game.choose_encounter({"type": &"casino"})
	await wait_physics_frames(2)
	var history_before := Game.run.history.duplicate()
	var saved := Game.run.to_dict()
	Game.run = RunState.from_dict(saved)
	Game.resume_run()
	await wait_physics_frames(2)
	assert_eq(_current_screen().name, "CasinoScreen", "back to the start of the casino, not the map")
	assert_eq(Game.run.history, history_before, "the visit is not recorded twice")


func test_continuing_a_save_with_a_pending_combat_refights_the_same_lineup() -> void:
	Game.new_run(557)
	await wait_physics_frames(2)
	var pending := Game.run.pending_encounter.duplicate()
	var first_enemies: Array = _current_screen().sim.enemies.map(
		func(e: CombatActor) -> StringName: return e.def_id)
	Game.run = RunState.from_dict(Game.run.to_dict())
	Game.resume_run()
	await wait_physics_frames(2)
	assert_eq(_current_screen().name, "CombatScreen")
	assert_eq(str(Game.run.pending_encounter.lineup), str(pending.lineup))
	var again: Array = _current_screen().sim.enemies.map(
		func(e: CombatActor) -> StringName: return e.def_id)
	assert_eq(again, first_enemies, "same lineup, from the beginning")


func test_a_committed_encounter_resumes_at_the_map() -> void:
	Game.new_run(558)
	await wait_physics_frames(2)
	Game.combat_finished(true, 60, [])
	await wait_physics_frames(2)
	Game.choose_encounter({"type": &"casino"})
	await wait_physics_frames(2)
	Game.commit_encounter()   # the spin has been played; its winnings are banked
	Game.run = RunState.from_dict(Game.run.to_dict())
	Game.resume_run()
	await wait_physics_frames(2)
	assert_eq(_current_screen().name, "MapScreen", "nothing left to replay")
