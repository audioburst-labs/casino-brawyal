extends GutTest
## Ability loadout (doc v0.11): max 6 equipped, 6 stored, 1 trash slot.
## New abilities funnel Equipped -> Stored -> Trash without displacing others;
## whatever sits in the trash is deleted when the next combat begins.


func _run_with(count: int) -> RunState:
	var run := RunState.new()
	for i in count:
		run.acquire_ability(StringName("ability_%d" % i))
	return run


func test_acquisitions_fill_equipped_first() -> void:
	var run := _run_with(4)
	assert_eq(run.equipped_ids.size(), 4)
	assert_eq(run.stored_ids().size(), 0)
	assert_eq(run.trash_id, &"")


func test_overflow_goes_to_storage_then_trash() -> void:
	var run := _run_with(13)  # 6 equipped + 6 stored + 1 trash
	assert_eq(run.equipped_ids.size(), 6)
	assert_eq(run.stored_ids().size(), 6)
	assert_eq(run.trash_id, &"ability_12")
	assert_true(run.needs_loadout, "overflow flags the loadout screen")


func test_trash_replacement_deletes_the_old_occupant() -> void:
	var run := _run_with(13)
	run.acquire_ability(&"newcomer")
	assert_eq(run.trash_id, &"newcomer")
	assert_false(run.ability_ids.has(&"ability_12"), "old trash is gone")


func test_trash_is_emptied_when_combat_begins() -> void:
	var run := _run_with(13)
	run.process_trash()
	assert_eq(run.trash_id, &"")
	assert_false(run.ability_ids.has(&"ability_12"))
	assert_eq(run.ability_ids.size(), 12)


func test_equip_and_unequip_moves() -> void:
	var run := _run_with(8)  # 6 equipped, 2 stored
	var stored: StringName = run.stored_ids()[0]
	var equipped: StringName = run.equipped_ids[0]
	assert_false(run.equip(stored), "equipped is full")
	assert_true(run.unequip(equipped))
	assert_true(run.equip(stored))
	assert_has(run.equipped_ids, stored)
	assert_has(run.stored_ids(), equipped)


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
	var run := _run_with(13)
	var restored := RunState.from_dict(run.to_dict())
	assert_eq(restored.equipped_ids, run.equipped_ids)
	assert_eq(restored.trash_id, run.trash_id)
	assert_eq(restored.stored_ids(), run.stored_ids())
