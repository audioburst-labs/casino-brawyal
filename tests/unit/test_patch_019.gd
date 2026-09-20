extends GutTest
## Patch 0.19 mechanics: the reworked Cash In (a per-ability payoff instead of
## a flat bonus), per-combat activation limits, the inverted Bad Beat
## condition, and the hero's own death event.

var _db: ContentDB


func before_all() -> void:
	_db = ContentDB.new()
	assert_true(_db.load_all("res://data"), str(_db.errors))


func _sim(enemies: Array = ["bouncer"], abilities: Array = ["card_sling"],
		seed_value: int = 7) -> CombatSim:
	return CombatSim.new(_db, {
		"hero": "ace",
		"abilities": abilities,
		"enemies": enemies,
		"seed": seed_value,
	})


func _fire(sim: CombatSim, ability_index: int, suits: Array) -> bool:
	for slot in suits.size():
		sim.tray.add(suits[slot], 1)
		if not sim.assign_chip(suits[slot], ability_index, slot):
			return false
	return true


# ---- Cash In: each ability names its own payoff (sheet v0.19) ----

func test_cash_in_replaces_the_base_damage() -> void:
	# Double Down: "Deal 10 damage. Cash In: Deal 20 instead."
	var sim := _sim(["bouncer"], ["card_sling", "double_down"])
	sim.begin_round()
	var enemy := sim.enemies[0]
	var hp_start := enemy.hp
	assert_true(_fire(sim, 0, [&"spade"]))          # 6 damage + Mark
	assert_eq(enemy.hp, hp_start - 6)
	assert_true(_fire(sim, 1, [&"club", &"spade"]))
	assert_eq(enemy.hp, hp_start - 6 - 20, "20 instead of 10, not 10 plus 20")
	assert_eq(enemy.status_stacks(&"mark"), 0, "cash in consumes the mark")


func test_cash_in_falls_back_to_the_base_damage_unmarked() -> void:
	var sim := _sim(["bouncer"], ["double_down"])
	sim.begin_round()
	var enemy := sim.enemies[0]
	var hp_start := enemy.hp
	_fire(sim, 0, [&"club", &"spade"])
	assert_eq(enemy.hp, hp_start - 10, "no mark -> the plain 10")


func test_bust_does_nothing_without_a_mark() -> void:
	# Bust is cash-in-only now: "Cash In: Deal 30 damage."
	var sim := _sim(["bouncer"], ["bust"])
	sim.begin_round()
	var enemy := sim.enemies[0]
	var hp_start := enemy.hp
	assert_true(_fire(sim, 0, [&"club", &"spade"]))
	assert_eq(enemy.hp, hp_start, "no mark, no damage")


func test_bust_pays_thirty_on_a_marked_enemy() -> void:
	var sim := _sim(["bouncer"], ["bust"])
	sim.begin_round()
	var enemy := sim.enemies[0]
	enemy.apply_status(&"mark", 1)
	var hp_start := enemy.hp
	assert_true(_fire(sim, 0, [&"club", &"spade"]))
	assert_eq(enemy.hp, hp_start - 30)
	assert_eq(enemy.status_stacks(&"mark"), 0)


func test_on_a_roll_cashes_in_then_re_marks() -> void:
	# "Deal 20. Cash In: Deal 40 instead. Mark."
	var sim := _sim(["bouncer"], ["on_a_roll"])
	sim.begin_round()
	var enemy := sim.enemies[0]
	enemy.apply_status(&"mark", 1)
	var hp_start := enemy.hp
	assert_true(_fire(sim, 0, [&"heart", &"spade", &"club"]))
	assert_eq(enemy.hp, hp_start - 40)
	assert_eq(enemy.status_stacks(&"mark"), 1, "the trailing Mark re-applies")


# ---- conditions and limits ----

func test_bad_beat_now_wants_a_marked_enemy() -> void:
	var sim := _sim(["bouncer"], ["bad_beat"])
	sim.begin_round()
	_fire(sim, 0, [&"club", &"diamond"])
	assert_eq(sim.hero.block, 0, "nothing marked -> no block")
	sim.enemies[0].apply_status(&"mark", 1)
	sim.tray.discard_all()
	sim.end_assignment()
	sim.begin_round()
	sim.hero.block = 0
	_fire(sim, 0, [&"club", &"diamond"])
	assert_eq(sim.hero.block, 10, "a marked enemy pays out")


func test_per_combat_limit_survives_the_round_reset() -> void:
	# House Edge is once per combat now, not once per turn.
	var sim := _sim(["bouncer"], ["house_edge"])
	sim.begin_round()
	assert_true(_fire(sim, 0, [&"spade"]))
	sim.tray.discard_all()
	sim.end_assignment()
	sim.begin_round()
	sim.tray.add(&"spade", 1)
	assert_false(sim.assign_chip(&"spade", 0, 0),
		"a per-combat ability stays spent after the round rolls over")


func test_slow_playing_no_longer_locks_the_turn() -> void:
	var sim := _sim(["bouncer"], ["slow_playing", "card_sling"])
	sim.begin_round()
	assert_true(_fire(sim, 0, [&"heart", &"diamond"]))
	assert_eq(sim.hero.block, 20, "20 block, unconditionally")
	sim.tray.add(&"spade", 1)
	assert_true(sim.assign_chip(&"spade", 1, 0),
		"other abilities stay usable")


# ---- the hero dies like anyone else ----

func test_hero_death_emits_actor_died_before_combat_lost() -> void:
	var sim := _sim(["bouncer"], ["card_sling"])
	sim.begin_round()
	sim.hero.hp = 1
	sim.drain_events()
	sim._hit_hero(sim.enemies[0], 50)
	sim._check_hero_death()
	var order: Array[StringName] = []
	for event in sim.drain_events():
		if event.type in [&"damage_dealt", &"actor_died", &"combat_lost"]:
			order.append(event.type)
	assert_eq(order, [&"damage_dealt", &"actor_died", &"combat_lost"] as Array[StringName],
		"the death animation has an event to hang on, and it lands after the hit")


func test_enemy_death_still_reports_actor_died() -> void:
	var sim := _sim(["bouncer"], ["card_sling"])
	sim.begin_round()
	sim.drain_events()
	sim.enemies[0].hp = 0
	sim.check_death(sim.enemies[0])
	var types: Array[StringName] = []
	for event in sim.drain_events():
		types.append(event.type)
	assert_has(types, &"actor_died")
	assert_has(types, &"combat_won")


# ---- HP is raffled per enemy, not per enemy type ----

func test_same_type_enemies_roll_their_own_hp() -> void:
	# Reported as a bug in patch 0.19; it already worked. This pins it.
	var spreads := 0
	for seed_value in 25:
		var sim := _sim(["dealer", "dealer", "dealer", "dealer"], ["card_sling"], seed_value)
		var rolls := sim.enemies.map(func(e: CombatActor) -> int: return e.max_hp)
		for hp: int in rolls:
			assert_between(hp, 51, 55)   # the Dealer's sheet range (patch 0.114)
		if rolls.any(func(hp: int) -> bool: return hp != rolls[0]):
			spreads += 1
	assert_gt(spreads, 20, "four Dealers should almost never share one HP roll")
