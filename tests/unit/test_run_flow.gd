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
		[{"type": &"shop"}, "ShopScreen"],
	]:
		Game.choose_encounter(pair[0])
		await wait_physics_frames(2)
		assert_eq(_current_screen().name, pair[1])


func test_boss_victory_leads_to_victory_screen() -> void:
	Game.new_run(111)
	await wait_physics_frames(2)
	for i in 8:
		Game.run.record_visit(&"combat")
	Game.choose_encounter({"type": &"boss"})
	await wait_physics_frames(2)
	var screen := _current_screen()
	assert_eq(screen.name, "CombatScreen")
	assert_eq(screen.sim.enemies[0].def_id, &"mr_moneyman")
	Game.combat_finished(true, 30, [])
	await wait_physics_frames(2)
	assert_eq(_current_screen().name, "VictoryScreen")
