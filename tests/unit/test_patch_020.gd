extends GutTest
## Patch 0.20 pass 1: the targeting drift on a summon, the loadout losing its
## storage tier, and the live ability numbers that never saw a nested Cash In.

var _db: ContentDB


func before_all() -> void:
	_db = ContentDB.new()
	assert_true(_db.load_all("res://data"), str(_db.errors))


func _sim(enemies: Array = ["manager"], abilities: Array = ["card_sling"],
		seed_value: int = 7) -> CombatSim:
	return CombatSim.new(_db, {
		"hero": "ace",
		"abilities": abilities,
		"enemies": enemies,
		"seed": seed_value,
	})


# ---- targeting must not drift when the field changes ----

func test_a_summon_does_not_steal_the_target() -> void:
	# A lone enemy was never recorded as the target, so the first summon fell
	# through to the lowest-HP fallback and took the marker with it.
	var sim := _sim(["manager"], ["card_sling"], 3)
	var manager := sim.enemies[0]
	assert_eq(sim.targeting.effective_target(sim.enemies), manager)

	sim._spawn_enemy(&"server", true, manager)
	var summon: CombatActor = sim.enemies[0] if sim.enemies[0] != manager else sim.enemies[1]
	summon.hp = 1   # the juiciest target by every heuristic
	assert_eq(sim.targeting.effective_target(sim.enemies), manager,
		"the target stays where the player left it")


func test_a_summon_does_not_steal_a_manually_chosen_target() -> void:
	var sim := _sim(["dealer", "manager"], ["card_sling"], 5)
	var manager: CombatActor = sim.enemies[1]
	sim.set_target(manager.id)
	sim._spawn_enemy(&"server", true, manager)
	for enemy in sim.enemies:
		if enemy != manager:
			enemy.hp = 1
	assert_eq(sim.targeting.effective_target(sim.enemies), manager)


func test_the_target_still_moves_on_when_it_dies() -> void:
	var sim := _sim(["dealer", "manager"], ["card_sling"], 5)
	# Whoever the resolver settled on: killing them hands the marker to the
	# other one. (Which of the two starts as the target depends on their HP
	# rolls, and the Dealer's range moved in patch 0.22.)
	var first: CombatActor = sim.targeting.effective_target(sim.enemies)
	var other: CombatActor = sim.enemies[0] if sim.enemies[1] == first else sim.enemies[1]
	first.hp = 0
	sim.check_death(first)
	assert_eq(sim.targeting.effective_target(sim.enemies), other)


# ---- the loadout loses its middle tier ----

func test_a_seventh_ability_goes_straight_to_the_trash() -> void:
	# Doc "Ability Choosing Screen": two zones only, filling Equipped then
	# Trash. There is no Unequipped tier any more (v0.20).
	var run := RunState.new()
	var ids: Array[StringName] = [&"card_sling", &"quick_maneuvers", &"color_up",
		&"double_down", &"heartsteal", &"pocket_rockets"]
	for id in ids:
		run.acquire_ability(id)
	assert_eq(run.equipped_ids.size(), RunState.EQUIP_CAP)
	assert_eq(run.trash_id, &"")

	run.acquire_ability(&"flush")
	assert_eq(run.trash_id, &"flush", "the 7th lands in the trash, not a store")
	assert_true(run.needs_loadout)


func test_nothing_can_be_owned_outside_equipped_or_trash() -> void:
	var run := RunState.new()
	for id in [&"card_sling", &"quick_maneuvers", &"color_up", &"double_down",
			&"heartsteal", &"pocket_rockets", &"flush", &"bust"]:
		run.acquire_ability(id)
	for id: StringName in run.ability_ids:
		assert_true(run.equipped_ids.has(id) or id == run.trash_id,
			"%s is either equipped or awaiting the bin" % id)


func test_trashing_frees_a_slot_to_equip_into() -> void:
	var run := RunState.new()
	for id in [&"card_sling", &"quick_maneuvers", &"color_up", &"double_down",
			&"heartsteal", &"pocket_rockets"]:
		run.acquire_ability(id)
	assert_true(run.move_to_trash(&"card_sling"))
	assert_eq(run.equipped_ids.size(), RunState.EQUIP_CAP - 1)
	assert_true(run.restore_from_trash())
	assert_eq(run.equipped_ids.size(), RunState.EQUIP_CAP)
	assert_eq(run.trash_id, &"")


# ---- Bad Beat's new cost ----

func test_bad_beat_costs_one_wildcard_once_per_turn() -> void:
	var bad_beat := _db.get_ability(&"bad_beat")
	assert_eq(bad_beat.cost, [&"any"] as Array[StringName])
	assert_eq(bad_beat.per_turn, 1)
	for tier in ContentDB.MAX_TIER + 1:
		var tiered := _db.get_ability(&"bad_beat", tier)
		assert_eq(tiered.cost, [&"any"] as Array[StringName],
			"tier %d inherits the cost" % tier)
		assert_eq(tiered.per_turn, 1, "tier %d inherits the limit" % tier)


func test_bad_beat_fires_off_a_single_chip() -> void:
	var sim := _sim(["bouncer"], ["bad_beat"])
	sim.begin_round()
	sim.enemies[0].apply_status(&"mark", 1)
	sim.tray.add(&"heart", 1)
	assert_true(sim.assign_chip(&"heart", 0, 0), "any suit pays for it")
	assert_eq(sim.hero.block, 10)
	sim.tray.add(&"heart", 1)
	assert_false(sim.assign_chip(&"heart", 0, 0), "once per turn")


# ---- live numbers reach nested Cash In damage ----

func test_buffed_numbers_reach_damage_nested_in_cash_in() -> void:
	# Double Down keeps both its figures inside the cash_in op, so the card
	# never previewed them (v0.19 rework, fixed in 0.20).
	var sim := _sim(["bouncer"], ["double_down"])
	sim.begin_round()
	sim.hero.apply_status(&"strength", 5)
	var state: AbilityState = sim.abilities[0]
	var amounts := AbilityCard.damage_amounts(state.def)
	assert_has(amounts, 11, "the unmarked fallback")
	assert_has(amounts, 18, "the cash-in payoff")
	for base: int in amounts:
		assert_eq(sim.preview_damage(base, state), base + 5,
			"Strength lifts every figure on the card")


func test_damage_amounts_covers_bonus_effects_too() -> void:
	var pocket := _db.get_ability(&"pocket_rockets")
	assert_eq(AbilityCard.damage_amounts(pocket), [12] as Array[int],
		"one damage figure; the Spade bonus Earns rather than repeating")
	var bust := _db.get_ability(&"bust")
	assert_eq(AbilityCard.damage_amounts(bust), [24] as Array[int],
		"cash-in only, no fallback")
	var card_sling := _db.get_ability(&"card_sling")
	assert_eq(AbilityCard.damage_amounts(card_sling), [6] as Array[int])
