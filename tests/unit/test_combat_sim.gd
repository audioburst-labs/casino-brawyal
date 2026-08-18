extends GutTest
## CombatSim: the full combat round loop —
## begin_round (intents + spin) -> chip assignment (abilities auto-fire)
## -> end_assignment (discard tray, enemy phase) -> next round.

var _db: ContentDB


func before_all() -> void:
	_db = ContentDB.new()
	assert_true(_db.load_all("res://data"))


func _sim(enemies: Array = ["security_goon"], seed_value: int = 7) -> CombatSim:
	return CombatSim.new(_db, {
		"hero": "ace",
		"abilities": ["card_flick", "dagger_throw", "card_guard"],
		"enemies": enemies,
		"seed": seed_value,
	})


func _types(events: Array) -> Array:
	return events.map(func(e: CombatEvent) -> StringName: return e.type)


func test_begin_round_shows_intents_spins_and_generates_chips() -> void:
	var sim := _sim()
	sim.begin_round()
	var types := _types(sim.drain_events())
	assert_has(types, &"intents_shown")
	assert_has(types, &"spin_resolved")
	assert_gt(sim.tray.total(), 0)
	assert_eq(sim.phase, CombatSim.Phase.ASSIGNMENT)


func test_assign_is_rejected_outside_assignment_phase() -> void:
	var sim := _sim()
	assert_false(sim.assign_chip(&"spade", 0, 0))


func test_full_ability_auto_fires_with_suit_bonus() -> void:
	var sim := _sim()
	sim.begin_round()
	sim.tray.add(&"spade", 1)
	var enemy := sim.enemies[0]
	var hp_before := enemy.hp
	assert_true(sim.assign_chip(&"spade", 0, 0))  # card_flick: 4 dmg, spade bonus +2
	assert_eq(enemy.hp, hp_before - 6)
	assert_has(_types(sim.drain_events()), &"ability_fired")


func test_off_suit_chip_skips_the_bonus() -> void:
	var sim := _sim()
	sim.begin_round()
	sim.tray.add(&"heart", 1)
	var enemy := sim.enemies[0]
	var hp_before := enemy.hp
	sim.assign_chip(&"heart", 0, 0)  # card_flick without spade bonus
	assert_eq(enemy.hp, hp_before - 4)


func test_assign_requires_matching_suit_and_available_chip() -> void:
	var sim := _sim()
	sim.begin_round()
	sim.tray.discard_all()
	assert_false(sim.assign_chip(&"spade", 0, 0), "no chip in tray")
	sim.tray.add(&"heart", 1)
	assert_false(sim.assign_chip(&"heart", 1, 0), "dagger_throw slot 0 needs spade")


func test_partial_fill_persists_across_rounds_but_tray_discards() -> void:
	var sim := _sim()
	sim.begin_round()
	sim.tray.add(&"spade", 1)
	sim.assign_chip(&"spade", 1, 0)  # dagger_throw slot 1 of 2
	sim.end_assignment()
	assert_eq(sim.tray.total(), 0, "unassigned chips discard at end of assignment")
	sim.begin_round()
	assert_eq(sim.abilities[1].filled[0], &"spade", "socketed chip persists")


func test_enemy_phase_executes_intent_on_hero() -> void:
	var sim := _sim()
	sim.begin_round()
	sim.tray.discard_all()
	sim.end_assignment()  # security_goon round 1: jab = 2x3
	assert_eq(sim.hero.hp, 70 - 6)


func test_block_absorbs_per_hit() -> void:
	var sim := _sim()
	sim.begin_round()
	sim.hero.gain_block(4)
	sim.tray.discard_all()
	sim.end_assignment()  # jab 2x3 vs 4 block -> 2 hp lost
	assert_eq(sim.hero.hp, 70 - 2)


func test_weak_enemy_deals_less() -> void:
	var sim := _sim()
	sim.begin_round()
	sim.enemies[0].apply_status(&"weak", 1)
	sim.tray.discard_all()
	sim.end_assignment()  # jab per hit floor(3*0.75)=2 -> 4 total
	assert_eq(sim.hero.hp, 70 - 4)


func test_stunned_enemy_skips_its_move() -> void:
	var sim := _sim()
	sim.begin_round()
	sim.enemies[0].apply_status(&"stun", 1)
	sim.tray.discard_all()
	sim.end_assignment()
	assert_eq(sim.hero.hp, 70)


func test_killing_all_enemies_wins_the_combat() -> void:
	var sim := _sim()
	sim.begin_round()
	sim.enemies[0].hp = 4
	sim.tray.add(&"spade", 1)
	sim.assign_chip(&"spade", 0, 0)  # 6 damage kills
	var types := _types(sim.drain_events())
	assert_has(types, &"actor_died")
	assert_has(types, &"combat_won")
	assert_eq(sim.phase, CombatSim.Phase.ENDED)


func test_hero_death_loses_the_combat() -> void:
	var sim := _sim()
	sim.begin_round()
	sim.hero.hp = 3
	sim.tray.discard_all()
	sim.end_assignment()
	assert_has(_types(sim.drain_events()), &"combat_lost")
	assert_eq(sim.phase, CombatSim.Phase.ENDED)


func test_ability_hits_the_selected_target() -> void:
	var sim := _sim(["security_goon", "card_shark"])
	sim.begin_round()
	sim.set_target(&"enemy_0")
	sim.tray.add(&"spade", 1)
	sim.assign_chip(&"spade", 0, 0)
	assert_eq(sim.enemies[0].hp, 22 - 6)
	assert_eq(sim.enemies[1].hp, 16)


func test_enemy_self_status_move_buffs_the_enemy() -> void:
	# Bouncer's first move is Velvet Wall: no damage, gains Taunt on itself.
	var sim := _sim(["bouncer"])
	sim.begin_round()
	sim.tray.discard_all()
	sim.end_assignment()
	assert_eq(sim.hero.hp, 70, "velvet wall deals no damage")
	assert_true(sim.enemies[0].has_status(&"taunt"))


func test_enemy_debuff_is_applied_to_hero() -> void:
	var sim := _sim()
	# Round 1 and 2 are jabs; round 3 is haymaker (1x8 + weak 1).
	for i in 3:
		sim.begin_round()
		sim.tray.discard_all()
		sim.end_assignment()
	assert_eq(sim.hero.hp, 70 - 6 - 6 - 8)
	# Weak was applied on round 3 and ticks at round end, so it is gone now;
	# check it was recorded via events instead.
	var had_status := false
	for event: CombatEvent in sim.drain_events():
		if event.type == &"status_applied" and event.data.get("status") == &"weak":
			had_status = true
	assert_true(had_status)
