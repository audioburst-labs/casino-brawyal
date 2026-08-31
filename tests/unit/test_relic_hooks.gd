extends GutTest
## Relics fire their effects at combat trigger points (patch 0.1 relic set).

var _db: ContentDB


func before_all() -> void:
	_db = ContentDB.new()
	assert_true(_db.load_all("res://data"), str(_db.errors))


func _sim(relics: Array) -> CombatSim:
	return CombatSim.new(_db, {
		"hero": "ace",
		"abilities": ["card_sling"],
		"enemies": ["bouncer"],
		"seed": 3,
		"relics": relics,
	})


func test_bounty_list_queues_gold_per_kill() -> void:
	var sim := _sim(["bounty_list"])
	sim.begin_round()
	sim.enemies[0].hp = 5
	sim.tray.add(&"spade", 1)
	sim.assign_chip(&"spade", 0, 0)
	assert_eq(sim.phase, CombatSim.Phase.ENDED)
	var kill_gold := sim.pending_rewards.filter(
		func(op: Dictionary) -> bool: return op.get("op") == "gain_coins" and int(op.get("amount", 0)) == 7)
	assert_eq(kill_gold.size(), 1, "7 gold queued for the kill")


func test_gamblers_confidence_grants_starting_block() -> void:
	var sim := _sim(["gamblers_confidence"])
	sim.begin_round()
	assert_eq(sim.hero.block, 20, "Gambler's Confidence starts combat with 20 Block")


func test_suit_protection_grants_block_per_gem() -> void:
	var sim := _sim(["spade_protection"])
	sim.begin_round()
	var spades: int = sim.last_payout.get(&"spade", 0)
	assert_eq(sim.hero.block, spades * 2)


func test_relic_triggered_event_is_emitted() -> void:
	var sim := _sim(["spade_protection"])
	sim.begin_round()
	var triggered := sim.drain_events().filter(
		func(e: CombatEvent) -> bool: return e.type == &"relic_triggered")
	assert_eq(triggered.size(), 1)
	assert_eq(triggered[0].data.relic, &"spade_protection")
