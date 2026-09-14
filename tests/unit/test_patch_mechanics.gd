extends GutTest
## Patch 0.1 mechanics: HP ranges, graph brains, Mark/Cash In, per-turn limits,
## effect conditions, replace-bonuses, passives, summons, boss support moves,
## the Dealer's rotation (its blackjack raffle was retired in patch 0.22),
## and the new relic behaviors.

var _db: ContentDB


func before_all() -> void:
	_db = ContentDB.new()
	assert_true(_db.load_all("res://data"), str(_db.errors))


func _sim(enemies: Array = ["bouncer"], abilities: Array = ["card_sling"],
		seed_value: int = 7, relics: Array = []) -> CombatSim:
	return CombatSim.new(_db, {
		"hero": "ace",
		"abilities": abilities,
		"enemies": enemies,
		"seed": seed_value,
		"relics": relics,
	})


## Fills an ability's sockets left-to-right with the given suits (added to tray first).
func _fire(sim: CombatSim, ability_index: int, suits: Array) -> bool:
	for slot in suits.size():
		sim.tray.add(suits[slot], 1)
		if not sim.assign_chip(suits[slot], ability_index, slot):
			return false
	return true


func test_enemy_hp_rolls_within_range() -> void:
	for seed_value in 20:
		var sim := _sim(["bouncer"], ["card_sling"], seed_value)
		assert_between(sim.enemies[0].hp, 50, 60)


func test_pair_then_brain_shuffles_pair_then_plays_tail_in_order() -> void:
	# Designer ruling: "(1 then 2) or (2 then 1), afterwards 3" — looping,
	# with the opening pair re-shuffled every cycle.
	var brain := EnemyBrain.new({
		"type": "pair_then",
		"pair": ["a", "b"],
		"then": ["c", "d"],
	}, {"a": {}, "b": {}, "c": {}, "d": {}})
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for cycle in 10:
		var first := brain.next_move(rng)
		var second := brain.next_move(rng)
		assert_true((first == "a" and second == "b") or (first == "b" and second == "a"),
			"cycle opens with the pair in either order, got %s,%s" % [first, second])
		assert_eq(brain.next_move(rng), "c", "tail plays in order")
		assert_eq(brain.next_move(rng), "d", "tail plays in order")


func test_weighted_no_repeat_last_never_repeats() -> void:
	var brain := EnemyBrain.new({
		"type": "weighted",
		"weights": {"x": 1, "y": 1, "z": 1},
		"no_repeat_last": true,
	}, {"x": {}, "y": {}, "z": {}})
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var previous := brain.next_move(rng)
	for i in 60:
		var next := brain.next_move(rng)
		assert_ne(next, previous, "no_repeat_last repeated '%s'" % next)
		previous = next


func test_spade_card_sling_marks_and_cash_in_pays_bonus() -> void:
	var sim := _sim(["bouncer"], ["card_sling", "double_down"])
	sim.begin_round()
	var enemy := sim.enemies[0]
	var hp_start := enemy.hp
	assert_true(_fire(sim, 0, [&"spade"]))  # card_sling: 6 dmg + Mark (spade bonus)
	assert_eq(enemy.hp, hp_start - 6)
	assert_eq(enemy.status_stacks(&"mark"), 1)
	# double_down: "Deal 10 damage. Cash In: Deal 20 instead." (sheet v0.19)
	assert_true(_fire(sim, 1, [&"club", &"spade"]))
	assert_eq(enemy.hp, hp_start - 6 - 20)
	assert_eq(enemy.status_stacks(&"mark"), 0, "cash in consumes the mark")


func test_cash_in_without_mark_falls_back_to_the_plain_damage() -> void:
	var sim := _sim(["bouncer"], ["double_down"])
	sim.begin_round()
	var enemy := sim.enemies[0]
	var hp_start := enemy.hp
	_fire(sim, 0, [&"club", &"spade"])
	assert_eq(enemy.hp, hp_start - 10)


func test_summon_skips_to_next_move_when_field_is_full() -> void:
	# Patch 0.13: with all 4 enemy slots taken, a summon move is swapped for
	# the enemy's next non-summon move.
	var sim := _sim(["manager", "server", "server", "server"], ["card_sling"], 3)
	sim.hero.max_hp = 9999
	sim.hero.hp = 9999
	for i in 12:
		if sim.phase != CombatSim.Phase.ROUND_START:
			break
		sim.begin_round()
		sim.tray.discard_all()
		sim.end_assignment()
		for event in sim.drain_events():
			assert_ne(event.type, &"enemy_summoned", "no summons on a full field")
	assert_eq(sim.enemies.size(), 4)


func test_go_again_win_does_not_spin_after_combat_ends() -> void:
	# Patch 0.13 crash fix: winning with Pay Line must not respin the machine.
	var sim := _sim(["bouncer"], ["pay_line"], 5)
	sim.begin_round()
	sim.enemies[0].hp = 5
	var tray_events := 0
	assert_true(_fire(sim, 0, [&"spade", &"diamond", &"heart", &"club"]))
	assert_eq(sim.phase, CombatSim.Phase.ENDED)
	for event in sim.drain_events():
		if event.type == &"spin_resolved":
			tray_events += 1
	assert_eq(tray_events, 1, "only the round-start spin; no go-again after victory")


func test_intro_loop_brain_plays_intro_once_then_loops() -> void:
	var brain := EnemyBrain.new({
		"type": "intro_loop",
		"intro": ["a", "b", "c"],
		"loop": ["b", "c"],
	}, {"a": {}, "b": {}, "c": {}})
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var picks: Array[String] = []
	for i in 7:
		picks.append(brain.next_move(rng))
	assert_eq(picks, ["a", "b", "c", "b", "c", "b", "c"] as Array[String])


func test_intent_display_updates_after_weak_is_applied() -> void:
	var sim := _sim(["bouncer"], ["card_sling"], 7)
	sim.begin_round()
	var before: Dictionary = sim.intent_display(&"enemy_0")
	sim.enemies[0].apply_status(&"weak", 1)
	var after: Dictionary = sim.intent_display(&"enemy_0")
	assert_lt(int(after.display_per_hit), int(before.display_per_hit),
		"shown damage drops once the enemy is Weak")


func test_per_turn_limit_blocks_reuse_until_next_round() -> void:
	var sim := _sim(["bouncer"], ["color_up"])
	sim.begin_round()
	var spades_before := sim.tray.count(&"spade")
	assert_true(_fire(sim, 0, [&"heart"]))
	assert_eq(sim.tray.count(&"spade"), spades_before + 1, "color up minted a spade")
	sim.tray.add(&"heart", 1)
	assert_false(sim.assign_chip(&"heart", 0, 0), "second use this round is blocked")
	sim.tray.discard_all()
	sim.end_assignment()
	sim.begin_round()
	assert_true(_fire(sim, 0, [&"heart"]), "usable again next round")


func test_replace_bonus_swaps_effects() -> void:
	var sim := _sim(["bouncer"], ["quick_maneuvers"])
	sim.begin_round()
	_fire(sim, 0, [&"diamond"])
	assert_eq(sim.hero.block, 8, "diamond replaces 5 block with 8, not 13")


func test_passive_fires_at_round_start_after_activation() -> void:
	var sim := _sim(["bouncer", "server"], ["face_reader"])
	sim.begin_round()
	_fire(sim, 0, [&"club", &"diamond"])
	assert_eq(sim.hero.block, 0, "passive does not fire on activation")
	sim.tray.discard_all()
	sim.end_assignment()
	sim.begin_round()
	assert_eq(sim.hero.block, 4, "2 block per living enemy at round start")


func test_summon_adds_a_new_enemy() -> void:
	var sim := _sim(["manager"], ["card_sling"], 3)
	sim.hero.max_hp = 9999
	sim.hero.hp = 9999  # survive long enough to see the manager's summon
	var summoned := false
	for i in 16:
		if sim.phase != CombatSim.Phase.ROUND_START:
			break
		sim.begin_round()
		sim.tray.discard_all()
		sim.end_assignment()
		for event in sim.drain_events():
			if event.type == &"enemy_summoned":
				summoned = true
		if summoned:
			break
	assert_true(summoned, "manager eventually calls staff")
	assert_gt(sim.enemies.size(), 1)
	# Patch 0.18 (doc "Unit Positioning"): with no empty slot between the
	# Manager and the centre, the summon takes the Manager's slot and the
	# Manager shifts one position outward.
	assert_eq(sim.enemies[0].def_id, &"server")
	assert_eq(sim.enemies[1].def_id, &"manager")


func test_bouncer_self_taunt_forces_targeting() -> void:
	# Bouncer's Door Check (one of its opening pair): Deal 8 + self Taunt 2.
	var sim := _sim(["server", "bouncer"], ["card_sling"], 6)
	sim.hero.max_hp = 9999
	sim.hero.hp = 9999
	sim.set_target(&"enemy_0")
	for i in 2:  # the pair is shuffled; Door Check lands within two rounds
		sim.begin_round()
		sim.tray.discard_all()
		sim.end_assignment()
		if sim.enemies[1].has_status(&"taunt"):
			break
	sim.begin_round()
	assert_true(sim.enemies[1].has_status(&"taunt"))
	assert_eq(sim.targeting.effective_target(sim.enemies).id, &"enemy_1",
		"taunt overrides the manual target")


func test_pocket_rockets_repeats_when_both_chips_are_spades() -> void:
	var sim := _sim(["bouncer"], ["pocket_rockets"], 7)
	sim.begin_round()
	var enemy := sim.enemies[0]
	var hp_start := enemy.hp
	assert_true(_fire(sim, 0, [&"spade", &"spade"]))
	assert_eq(enemy.hp, hp_start - 30, "15 damage, repeated once for double spades")
	sim.tray.discard_all()
	sim.end_assignment()
	sim.begin_round()
	var hp_mid := enemy.hp
	_fire(sim, 0, [&"spade", &"heart"])
	assert_eq(enemy.hp, hp_mid - 15, "mixed chips deal the base 15 only")


func test_intent_display_includes_strength_buff() -> void:
	var sim := _sim(["bouncer"], ["card_sling"])
	sim.enemies[0].apply_status(&"strength", 3)
	sim.begin_round()
	var shown: Dictionary = {}
	for event in sim.drain_events():
		if event.type == &"intents_shown":
			shown = event.data.intents[0]
	var intent: Dictionary = shown.intent
	assert_eq(int(shown.display_per_hit), int(intent.per_hit) + 3,
		"displayed damage includes strength")


func test_winners_aura_relic_weakens_enemies_at_combat_start() -> void:
	var sim := _sim(["bouncer"], ["card_sling"], 7, ["winners_aura"])
	sim.begin_round()
	assert_eq(sim.enemies[0].status_stacks(&"weak"), 2,
		"Winner's Aura applies Weak 2 to all enemies at combat start")


func test_gamblers_confidence_relic_grants_starting_block() -> void:
	var sim := _sim(["bouncer"], ["card_sling"], 7, ["gamblers_confidence"])
	sim.begin_round()
	assert_eq(sim.hero.block, 20, "Gambler's Confidence starts combat with 20 Block")


func test_high_roller_relic_hits_a_random_enemy_on_triple() -> void:
	var sim := _sim(["bouncer"], ["card_sling"], 7, ["high_roller"])
	sim.begin_round()
	var hp_before := sim.enemies[0].hp
	sim.last_payout = {&"spade": 3}
	sim._fire_relics(&"spin_resolved")
	assert_eq(sim.enemies[0].hp, hp_before - 20, "High Roller deals 20 on a forced triple")


func test_dark_emblem_boosts_spade_club_abilities() -> void:
	var sim := _sim(["bouncer"], ["double_down"], 7, ["dark_emblem"])
	sim.begin_round()
	var enemy := sim.enemies[0]
	var hp_start := enemy.hp
	_fire(sim, 0, [&"heart", &"spade"])
	assert_eq(enemy.hp, hp_start - 13, "10 * 1.3 = 13")


func test_block_per_chip_relic() -> void:
	var sim := _sim(["bouncer"], ["card_sling"], 7, ["spade_protection"])
	sim.begin_round()
	var spades: int = sim.last_payout.get(&"spade", 0)
	assert_eq(sim.hero.block, spades * 2, "2 block per spade gem")


func test_flush_hits_all_enemies() -> void:
	var sim := _sim(["bouncer", "server"], ["flush"])
	sim.begin_round()
	var hp_a := sim.enemies[0].hp
	var hp_b := sim.enemies[1].hp
	_fire(sim, 0, [&"spade", &"spade", &"spade", &"spade"])
	assert_eq(sim.enemies[0].hp, hp_a - 30)
	assert_eq(sim.enemies[1].hp, maxi(0, hp_b - 30))


func test_bust_is_cash_in_only() -> void:
	# Sheet v0.19: "Cash In: Deal 30 damage." — no base damage of its own.
	var sim := _sim(["bouncer"], ["bust"])
	sim.begin_round()
	var enemy := sim.enemies[0]
	var hp_start := enemy.hp
	enemy.apply_status(&"mark", 1)
	_fire(sim, 0, [&"spade", &"club"])
	assert_eq(enemy.hp, hp_start - 30)
	assert_eq(enemy.status_stacks(&"mark"), 0, "cash in consumes the mark")
