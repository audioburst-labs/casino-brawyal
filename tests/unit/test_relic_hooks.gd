extends GutTest
## Relics fire their effects at combat trigger points.

var _db: ContentDB


func before_all() -> void:
	_db = ContentDB.new()
	assert_true(_db.load_all("res://data"), str(_db.errors))


func _sim(relics: Array) -> CombatSim:
	return CombatSim.new(_db, {
		"hero": "ace",
		"abilities": ["card_flick"],
		"enemies": ["security_goon"],
		"seed": 3,
		"relics": relics,
	})


func test_combat_started_relics_fire_on_first_round_only() -> void:
	var sim := _sim(["lucky_rabbit_foot", "brass_knuckles"])
	sim.begin_round()
	assert_eq(sim.hero.block, 5, "rabbit foot grants 5 block")
	assert_eq(sim.hero.status_stacks(&"strength"), 1, "knuckles grant 1 strength")
	sim.tray.discard_all()
	sim.end_assignment()
	sim.begin_round()
	assert_eq(sim.hero.status_stacks(&"strength"), 1, "combat_started fires once")


func test_spin_resolved_relics_modify_the_tray() -> void:
	var charm_sim := _sim(["spade_charm"])
	charm_sim.begin_round()
	assert_gt(charm_sim.tray.count(&"spade"), 0, "one chip converts to spade")

	var chip_sim := _sim(["house_chip"])
	var base_sim := _sim([])
	chip_sim.begin_round()
	base_sim.begin_round()
	assert_eq(chip_sim.tray.total(), base_sim.tray.total() + 1,
		"house chip mints one bonus chip")


func test_combat_won_relics_queue_run_rewards() -> void:
	var sim := _sim(["gold_tooth"])
	sim.begin_round()
	sim.enemies[0].hp = 1
	sim.tray.discard_all()
	sim.tray.add(&"spade", 1)
	sim.assign_chip(&"spade", 0, 0)
	assert_eq(sim.phase, CombatSim.Phase.ENDED)
	var has_coin_op := false
	for op: Dictionary in sim.pending_rewards:
		if op.get("op") == "gain_coins":
			has_coin_op = true
	assert_true(has_coin_op, "gold tooth queues bonus coins for the run layer")


func test_relic_triggered_event_is_emitted() -> void:
	var sim := _sim(["lucky_rabbit_foot"])
	sim.begin_round()
	var triggered := sim.drain_events().filter(
		func(e: CombatEvent) -> bool: return e.type == &"relic_triggered")
	assert_eq(triggered.size(), 1)
	assert_eq(triggered[0].data.relic, &"lucky_rabbit_foot")
