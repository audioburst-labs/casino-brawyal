extends GutTest
## CombatSim: the full combat round loop —
## begin_round (intents + spin) -> chip assignment (abilities auto-fire)
## -> end_assignment (discard tray, enemy phase) -> next round.
## Uses Bouncer (graph: slam -> double_jab -> ...) and Manager
## (graph: clipboard_strike -> performance_review -> ...) for determinism.

var _db: ContentDB


func before_all() -> void:
	_db = ContentDB.new()
	assert_true(_db.load_all("res://data"), str(_db.errors))


func _sim(enemies: Array = ["bouncer"], seed_value: int = 7) -> CombatSim:
	return CombatSim.new(_db, {
		"hero": "ace",
		"abilities": ["card_sling", "quick_maneuvers", "double_down"],
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
	assert_true(sim.assign_chip(&"spade", 0, 0))  # card_sling: 10 dmg, spade -> Mark
	assert_eq(enemy.hp, hp_before - 10)
	assert_true(enemy.has_status(&"mark"))
	assert_has(_types(sim.drain_events()), &"ability_fired")


func test_off_suit_chip_skips_the_bonus() -> void:
	var sim := _sim()
	sim.begin_round()
	sim.tray.add(&"heart", 1)
	var enemy := sim.enemies[0]
	var hp_before := enemy.hp
	sim.assign_chip(&"heart", 0, 0)  # card_sling without the spade bonus
	assert_eq(enemy.hp, hp_before - 10)
	assert_false(enemy.has_status(&"mark"))


func test_assign_requires_matching_suit_and_available_chip() -> void:
	var sim := _sim()
	sim.begin_round()
	sim.tray.discard_all()
	assert_false(sim.assign_chip(&"spade", 0, 0), "no chip in tray")
	sim.tray.add(&"heart", 1)
	assert_false(sim.assign_chip(&"heart", 2, 1), "double_down slot 1 needs spade")


func test_partial_fill_persists_across_rounds_but_tray_discards() -> void:
	var sim := _sim()
	sim.begin_round()
	sim.tray.add(&"club", 1)
	sim.assign_chip(&"club", 2, 0)  # double_down slot 0 of 2 (any)
	sim.end_assignment()
	assert_eq(sim.tray.total(), 0, "unassigned chips discard at end of assignment")
	sim.begin_round()
	assert_eq(sim.abilities[2].filled[0], &"club", "socketed chip persists")


func test_enemy_phase_executes_intent_on_hero() -> void:
	var sim := _sim()
	sim.begin_round()
	sim.tray.discard_all()
	sim.end_assignment()  # bouncer round 1: door check = 1x8 (+ self taunt)
	assert_eq(sim.hero.hp, sim.hero.max_hp - 8)
	assert_true(sim.enemies[0].has_status(&"taunt"))


func test_block_absorbs_damage() -> void:
	var sim := _sim()
	sim.begin_round()
	sim.hero.gain_block(6)
	sim.tray.discard_all()
	sim.end_assignment()  # 8 vs 6 block -> 2 hp lost
	assert_eq(sim.hero.hp, sim.hero.max_hp - 2)


func test_weak_enemy_deals_less() -> void:
	var sim := _sim()
	sim.begin_round()
	sim.enemies[0].apply_status(&"weak", 1)
	sim.tray.discard_all()
	sim.end_assignment()  # 8 * 0.75 = 6 (half-up)
	assert_eq(sim.hero.hp, sim.hero.max_hp - 6)


func test_stunned_enemy_skips_its_move() -> void:
	var sim := _sim()
	sim.begin_round()
	sim.enemies[0].apply_status(&"stun", 1)
	sim.tray.discard_all()
	sim.end_assignment()
	assert_eq(sim.hero.hp, sim.hero.max_hp)


func test_killing_all_enemies_wins_the_combat() -> void:
	var sim := _sim()
	sim.begin_round()
	sim.enemies[0].hp = 5
	sim.tray.add(&"spade", 1)
	sim.assign_chip(&"spade", 0, 0)  # 10 damage kills
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
	var sim := _sim(["bouncer", "server"])
	sim.begin_round()
	sim.set_target(&"enemy_0")
	var hp_a := sim.enemies[0].hp
	var hp_b := sim.enemies[1].hp
	sim.tray.add(&"spade", 1)
	sim.assign_chip(&"spade", 0, 0)
	assert_eq(sim.enemies[0].hp, hp_a - 10)
	assert_eq(sim.enemies[1].hp, hp_b)


func test_enemy_debuff_is_applied_to_hero() -> void:
	# Manager: clipboard_strike (1x20), then performance_review (Vulnerable 3).
	var sim := _sim(["manager"])
	for i in 2:
		sim.begin_round()
		sim.tray.discard_all()
		sim.end_assignment()
	assert_eq(sim.hero.hp, sim.hero.max_hp - 20)
	assert_eq(sim.hero.status_stacks(&"vulnerable"), 2,
		"vulnerable 3 applied on round 2, ticked once at round end")
	var had_status := false
	for event: CombatEvent in sim.drain_events():
		if event.type == &"status_applied" and event.data.get("status") == &"vulnerable":
			had_status = true
	assert_true(had_status)
