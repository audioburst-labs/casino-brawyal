extends GutTest
## Build 1.30: the redesigned reward screen (tags and the full-hand note).


func test_upgrade_tag_names_the_step() -> void:
	assert_eq(RewardScreen.upgrade_tag(1), "UPGRADE  COPPER TO SILVER")
	assert_eq(RewardScreen.upgrade_tag(2), "UPGRADE  SILVER TO GOLD")


func test_full_hand_note_only_for_new_abilities_with_six_equipped() -> void:
	var run := RunState.new()
	for id in ["card_sling", "quick_maneuvers", "color_up", "double_down", "heartsteal", "pocket_rockets"]:
		run.acquire_ability(StringName(id))
	assert_eq(run.equipped_ids.size(), RunState.EQUIP_CAP)
	assert_true(RewardScreen.hand_full_warning(run, [&"card_sling", &"bust"]), "a new one is on offer")
	assert_false(RewardScreen.hand_full_warning(run, [&"card_sling", &"color_up"]), "upgrades only")
	var roomy := RunState.new()
	roomy.acquire_ability(&"card_sling")
	assert_false(RewardScreen.hand_full_warning(roomy, [&"bust"]), "room in the hand")
