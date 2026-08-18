extends GutTest
## Patch 0.1 mechanics: HP ranges, graph brains, Mark/Cash In, per-turn limits,
## effect conditions, replace-bonuses, passives, summons, boss support moves,
## the Dealer's blackjack raffle, and the new relic behaviors.

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
		assert_between(sim.enemies[0].hp, 95, 105)


func test_graph_brain_follows_edges() -> void:
	var brain := EnemyBrain.new({
		"type": "graph",
		"start": "a",
		"edges": {"a": ["b"], "b": ["a", "c"], "c": ["a"]},
	}, {"a": {}, "b": {}, "c": {}})
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var previous := brain.next_move(rng)
	assert_eq(previous, "a", "graph starts at its start node")
	var edges := {"a": ["b"], "b": ["a", "c"], "c": ["a"]}
	for i in 30:
		var next := brain.next_move(rng)
		assert_has(edges[previous], next, "%s -> %s is not an edge" % [previous, next])
		previous = next


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
	assert_true(_fire(sim, 0, [&"spade"]))  # card_sling: 10 dmg + Mark (spade bonus)
	assert_eq(enemy.hp, hp_start - 10)
	assert_eq(enemy.status_stacks(&"mark"), 1)
	assert_true(_fire(sim, 1, [&"club", &"spade"]))  # double_down: 20 dmg + Cash In (10)
	assert_eq(enemy.hp, hp_start - 10 - 20 - 10)
	assert_eq(enemy.status_stacks(&"mark"), 0, "cash in consumes the mark")


func test_cash_in_without_mark_deals_no_bonus() -> void:
	var sim := _sim(["bouncer"], ["double_down"])
	sim.begin_round()
	var enemy := sim.enemies[0]
	var hp_start := enemy.hp
	_fire(sim, 0, [&"club", &"spade"])
	assert_eq(enemy.hp, hp_start - 20)


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


func test_solo_ability_condition() -> void:
	var solo := _sim(["bouncer"], ["slow_playing", "card_sling"])
	solo.begin_round()
	_fire(solo, 0, [&"heart", &"diamond"])
	assert_eq(solo.hero.block, 30, "alone this round -> 30 block")

	var crowded := _sim(["bouncer"], ["slow_playing", "card_sling"])
	crowded.begin_round()
	_fire(crowded, 1, [&"club"])
	crowded.hero.block = 0
	_fire(crowded, 0, [&"heart", &"diamond"])
	assert_eq(crowded.hero.block, 0, "not the only ability -> no block")


func test_no_enemy_marked_condition() -> void:
	var sim := _sim(["bouncer"], ["bad_beat"])
	sim.begin_round()
	_fire(sim, 0, [&"club", &"diamond"])
	assert_eq(sim.hero.block, 15)
	sim.enemies[0].apply_status(&"mark", 1)
	sim.tray.discard_all()
	sim.end_assignment()
	sim.begin_round()
	sim.hero.block = 0
	_fire(sim, 0, [&"club", &"diamond"])
	assert_eq(sim.hero.block, 0, "a marked enemy voids the condition")


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
	sim.hero.hp = 9999  # survive long enough for the graph to reach call_staff
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
	assert_eq(sim.enemies[1].def_id, &"server")


func test_blackjack_dealer_intent_and_damage() -> void:
	for seed_value in 12:
		var sim := _sim(["dealer"], ["card_sling"], seed_value)
		sim.begin_round()
		var shown: Dictionary = {}
		for event in sim.drain_events():
			if event.type == &"intents_shown":
				shown = event.data.intents[0]
		var total := int(shown.get("blackjack_total", -1))
		assert_between(total, 3, 30, "dealer draws three cards of 1-10")
		var hp_before := sim.hero.hp
		sim.tray.discard_all()
		sim.end_assignment()
		if total > 21:
			assert_eq(sim.hero.hp, hp_before, "bust negates the attack")
		else:
			assert_eq(sim.hero.hp, hp_before - total, "hit for the raffled total")


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


func test_high_stakes_relic_raises_weak_to_half() -> void:
	var sim := _sim(["bouncer"], ["card_sling"], 7, ["high_stakes"])
	sim.hero.apply_status(&"weak", 1)
	sim.begin_round()
	var enemy := sim.enemies[0]
	var hp_start := enemy.hp
	_fire(sim, 0, [&"heart"])
	assert_eq(enemy.hp, hp_start - 5, "10 * 0.5 = 5 under high stakes")


func test_dark_emblem_boosts_spade_club_abilities() -> void:
	var sim := _sim(["bouncer"], ["double_down"], 7, ["dark_emblem"])
	sim.begin_round()
	var enemy := sim.enemies[0]
	var hp_start := enemy.hp
	_fire(sim, 0, [&"heart", &"spade"])
	assert_eq(enemy.hp, hp_start - 26, "20 * 1.3 = 26")


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
	_fire(sim, 0, [&"spade", &"spade", &"spade", &"spade", &"spade"])
	assert_eq(sim.enemies[0].hp, hp_a - 50)
	assert_eq(sim.enemies[1].hp, maxi(0, hp_b - 50))


func test_damage_missing_pct() -> void:
	var sim := _sim(["bouncer"], ["bust"])
	sim.begin_round()
	var enemy := sim.enemies[0]
	enemy.hp = enemy.max_hp - 40
	_fire(sim, 0, [&"spade", &"club"])
	assert_eq(enemy.hp, enemy.max_hp - 40 - 12, "30% of 40 missing = 12")
