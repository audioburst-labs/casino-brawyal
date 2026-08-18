extends GutTest
## RunState serialization and the checkpoint save file.

const TEST_PATH := "user://test_run_save.json"


func after_each() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)


func _mutated_run() -> RunState:
	var run := RunState.new()
	run.hp = 41
	run.max_hp = 75
	run.coins = 137
	run.seed_value = 987
	run.ability_ids = [&"card_flick", &"shuffle"]
	run.relic_ids = [&"gold_tooth"]
	run.sticker_inventory = [&"spade"]
	run.seen_events = [&"high_roller"]
	run.record_visit(&"combat")
	run.record_visit(&"shop")
	run.machine.add_reel()
	run.machine.apply_sticker(1, 2, &"spade")
	return run


func test_roundtrip_preserves_everything() -> void:
	var run := _mutated_run()
	var restored := RunState.from_dict(run.to_dict())
	assert_eq(restored.hp, 41)
	assert_eq(restored.max_hp, 75)
	assert_eq(restored.coins, 137)
	assert_eq(restored.seed_value, 987)
	assert_eq(restored.ability_ids, run.ability_ids)
	assert_eq(restored.relic_ids, run.relic_ids)
	assert_eq(restored.sticker_inventory, run.sticker_inventory)
	assert_eq(restored.seen_events, run.seen_events)
	assert_eq(restored.history, run.history)
	assert_eq(restored.machine.reels.size(), 4)
	assert_eq(restored.machine.reels[1].symbols[2], &"spade")


func test_save_load_and_clear_file() -> void:
	var run := _mutated_run()
	RunSave.save_run(run, TEST_PATH)
	assert_true(RunSave.has_save(TEST_PATH))
	var loaded := RunSave.load_run(TEST_PATH)
	assert_not_null(loaded)
	assert_eq(loaded.coins, 137)
	RunSave.clear(TEST_PATH)
	assert_false(RunSave.has_save(TEST_PATH))
	assert_null(RunSave.load_run(TEST_PATH))
