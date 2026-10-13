extends GutTest
## Sharp Edge's passive must answer EVERY Mark that goes onto an unmarked enemy,
## whichever ability put it there and whatever the turn (designer, 1.23: "still
## does not work when applying a mark from other abilities"). Plays random
## kits for several rounds and checks the invariant after every single chip.

var db: ContentDB


func before_each() -> void:
	db = ContentDB.new()
	assert_true(db.load_all("res://data"), str(db.errors))


func _marked(sim: CombatSim) -> Array:
	return sim.enemies.map(func(e: CombatActor) -> bool: return e.has_status(&"mark"))


func test_every_fresh_mark_trips_an_active_sharp_edge() -> void:
	var ids: Array = db.all_ability_ids().filter(
		func(id: StringName) -> bool: return id != &"sharp_edge")
	var rng := RandomNumberGenerator.new()
	var checked := 0
	var misses: Array[String] = []
	for seed_value in 60:
		rng.seed = seed_value
		var kit: Array = ["sharp_edge"]
		var pool := ids.duplicate()
		for i in 5:
			kit.append(String(pool.pop_at(rng.randi_range(0, pool.size() - 1))))
		var tiers := {}
		for id in kit:
			tiers[StringName(id)] = rng.randi_range(0, 2)
		var sim := CombatSim.new(db, {"hero": "ace", "enemies": ["bouncer", "server", "dealer"],
			"abilities": kit, "ability_tiers": tiers, "seed": seed_value})
		sim.hero.max_hp = 99999
		sim.hero.hp = 99999
		for round_index in 4:
			if sim.phase == CombatSim.Phase.ENDED:
				break
			sim.begin_round()
			sim.drain_events()
			for step in 14:
				if sim.phase != CombatSim.Phase.ASSIGNMENT:
					break
				var index := rng.randi_range(0, kit.size() - 1)
				var state: AbilityState = sim.abilities[index]
				var slot := -1
				for s in state.def.cost.size():
					if state.filled[s] == &"":
						slot = s
						break
				if slot < 0:
					continue
				var suit: StringName = state.def.cost[slot]
				if suit == &"any":
					suit = ContentDB.SUITS[rng.randi_range(0, 3)]
				var armed := sim.passives.any(
					func(d: Defs.AbilityDef) -> bool: return d.id == &"sharp_edge")
				var before := _marked(sim)
				var alive_before := sim.enemies.map(func(e: CombatActor) -> bool: return e.is_alive())
				sim.tray.add(suit, 1)
				if not sim.assign_chip(suit, index, slot):
					continue
				var fired := sim.drain_events().filter(
					func(e: CombatEvent) -> bool:
						return e.type == &"passive_fired" and e.data.ability == &"sharp_edge").size()
				var after := _marked(sim)
				var fresh := 0
				for i in before.size():
					if not before[i] and after[i] and alive_before[i]:
						fresh += 1
				if armed and fresh > 0:
					checked += 1
					if fired == 0:
						misses.append("seed %d kit %s: fresh mark via %s, no Sharp Edge" % [
							seed_value, kit, state.def.id])
			sim.tray.discard_all()
			sim.end_assignment()
	assert_gt(checked, 10, "the fuzz actually exercised fresh marks")
	assert_eq(misses.size(), 0, "\n".join(misses.slice(0, 8)))


## House Edge marks at the START of a turn, outside any chip placement, which
## the loop above never reaches.
func test_a_round_start_mark_from_house_edge_trips_sharp_edge() -> void:
	for tier in [0, 1, 2]:
		var sim := CombatSim.new(db, {"hero": "ace", "enemies": ["bouncer", "server"],
			"abilities": ["sharp_edge", "house_edge"], "ability_tiers": {&"house_edge": tier},
			"seed": 3})
		sim.hero.max_hp = 99999
		sim.hero.hp = 99999
		sim.begin_round()
		for index in [0, 1]:
			var state: AbilityState = sim.abilities[index]
			for slot in state.def.cost.size():
				var suit: StringName = state.def.cost[slot]
				if suit == &"any":
					suit = &"spade"
				sim.tray.add(suit, 1)
				sim.assign_chip(suit, index, slot)
		for enemy in sim.enemies:
			enemy.statuses.erase(&"mark")
		sim.tray.discard_all()
		sim.end_assignment()
		sim.drain_events()
		sim.begin_round()
		var events := sim.drain_events()
		var marks := events.filter(func(e: CombatEvent) -> bool:
			return e.type == &"status_applied" and e.data.status == &"mark").size()
		var fired := events.filter(func(e: CombatEvent) -> bool:
			return e.type == &"passive_fired" and e.data.ability == &"sharp_edge").size()
		assert_gt(marks, 0, "tier %d: House Edge marked someone" % tier)
		assert_eq(fired, marks, "tier %d: one Sharp Edge answer per fresh Mark" % tier)


## The designer's own scenario (1.23): Sharp Edge was played, then Card Sling
## with a Spade marks an enemy that had no Mark. It must hit for 6 and then 3.
func test_card_sling_marking_a_fresh_enemy_after_sharp_edge_was_played_earlier() -> void:
	for same_round in [true, false]:
		var sim := CombatSim.new(db, {"hero": "ace", "enemies": ["bouncer", "bouncer"],
			"abilities": ["sharp_edge", "card_sling"], "seed": 5})
		sim.hero.max_hp = 99999
		sim.hero.hp = 99999
		sim.begin_round()
		sim.tray.add(&"spade", 1)
		assert_true(sim.assign_chip(&"spade", 0, 0))            # Sharp Edge, played
		if not same_round:
			sim.tray.discard_all()
			sim.end_assignment()
			sim.begin_round()
		var fresh := sim.enemies[1]
		fresh.statuses.erase(&"mark")
		sim.set_target(fresh.id)
		var hp := fresh.hp
		sim.tray.add(&"spade", 1)
		assert_true(sim.assign_chip(&"spade", 1, 0))            # Card Sling + Spade
		assert_true(fresh.has_status(&"mark"), "Card Sling marked it")
		assert_eq(fresh.hp, hp - 9, "6 from Card Sling and 3 from Sharp Edge (same round: %s)" % same_round)


## Equipped is enough (designer, 1.23): Sharp Edge answers a Mark from the first
## round of the fight without ever being played.
func test_an_unplayed_sharp_edge_still_answers_a_mark() -> void:
	var sim := CombatSim.new(db, {"hero": "ace", "enemies": ["bouncer", "bouncer"],
		"abilities": ["sharp_edge", "card_sling"], "seed": 5})
	sim.hero.max_hp = 99999
	sim.hero.hp = 99999
	sim.begin_round()
	var hp := sim.enemies[0].hp
	sim.set_target(sim.enemies[0].id)
	sim.tray.add(&"spade", 1)
	assert_true(sim.assign_chip(&"spade", 1, 0))
	assert_eq(sim.enemies[0].hp, hp - 9, "Card Sling 6 plus Sharp Edge 3, never played")
