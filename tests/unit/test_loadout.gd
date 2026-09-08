extends GutTest
## Ability loadout (doc "Ability Choosing Screen"): max 6 equipped plus a
## single trash slot — no storage tier since v0.20. New abilities funnel
## Equipped -> Trash without displacing others; whatever sits in the trash is
## deleted when the next combat begins.


func _run_with(count: int) -> RunState:
	var run := RunState.new()
	for i in count:
		run.acquire_ability(StringName("ability_%d" % i))
	return run


func test_acquisitions_fill_equipped_first() -> void:
	var run := _run_with(4)
	assert_eq(run.equipped_ids.size(), 4)
	assert_eq(run.trash_id, &"")


func test_overflow_goes_straight_to_the_trash() -> void:
	var run := _run_with(7)  # 6 equipped + 1 trash
	assert_eq(run.equipped_ids.size(), 6)
	assert_eq(run.ability_ids.size(), 7)
	assert_eq(run.trash_id, &"ability_6")
	assert_true(run.needs_loadout, "overflow flags the loadout screen")


func test_trash_replacement_deletes_the_old_occupant() -> void:
	var run := _run_with(7)
	run.acquire_ability(&"newcomer")
	assert_eq(run.trash_id, &"newcomer")
	assert_false(run.ability_ids.has(&"ability_6"), "old trash is gone")


func test_trash_is_emptied_when_combat_begins() -> void:
	var run := _run_with(7)
	run.process_trash()
	assert_eq(run.trash_id, &"")
	assert_false(run.ability_ids.has(&"ability_6"))
	assert_eq(run.ability_ids.size(), 6)


func test_the_trash_is_the_only_way_out_of_the_battle_line() -> void:
	var run := _run_with(7)          # 6 equipped, 1 in the trash
	var waiting: StringName = run.trash_id
	assert_false(run.equip(waiting), "equipped is full")
	assert_true(run.move_to_trash(run.equipped_ids[0]),
		"trashing the incumbent is what frees the slot")
	assert_false(run.ability_ids.has(waiting), "the old trash occupant is gone")
	assert_eq(run.equipped_ids.size(), 5)


func test_trash_move_and_restore() -> void:
	var run := _run_with(3)
	var victim: StringName = run.equipped_ids[0]
	assert_true(run.move_to_trash(victim))
	assert_eq(run.trash_id, victim)
	assert_false(run.equipped_ids.has(victim))
	assert_true(run.restore_from_trash())
	assert_eq(run.trash_id, &"")
	assert_has(run.equipped_ids, victim)


func test_save_roundtrip_preserves_loadout() -> void:
	var run := _run_with(7)
	var restored := RunState.from_dict(run.to_dict())
	assert_eq(restored.equipped_ids, run.equipped_ids)
	assert_eq(restored.ability_ids, run.ability_ids)
	assert_eq(restored.trash_id, run.trash_id)
