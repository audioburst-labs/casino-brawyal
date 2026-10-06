extends GutTest
## Patch 0.22: the sheet's enemy passives and keywords — the Dealer's Bust
## count, the Chip Golem's Break and Gift/Absorb, the Loan Shark's Rage and
## Multistrike. The old blackjack raffle the Dealer used to run is retired.

var _db: ContentDB


func before_all() -> void:
	_db = ContentDB.new()
	assert_true(_db.load_all("res://data"), str(_db.errors))


func _sim(enemies: Array, abilities: Array = ["card_sling"],
		seed_value: int = 5) -> CombatSim:
	var sim := CombatSim.new(_db, {
		"hero": "ace",
		"abilities": abilities,
		"enemies": enemies,
		"seed": seed_value,
	})
	sim.hero.max_hp = 9999
	sim.hero.hp = 9999
	return sim


func _types(events: Array) -> Array:
	return events.map(func(e: CombatEvent) -> StringName: return e.type)


# ---- the DSL accepts them, and rejects typos ----

func test_the_shipped_passives_parse() -> void:
	assert_eq(str(_db.get_enemy(&"dealer").passive.type), "bust")
	assert_eq(int(_db.get_enemy(&"dealer").passive.threshold), 21)
	assert_eq(str(_db.get_enemy(&"chip_golem").passive.type), "break")
	assert_eq(int(_db.get_enemy(&"chip_golem").passive.every), 30)
	assert_eq(str(_db.get_enemy(&"loan_shark").passive.type), "loan")
	assert_eq(int(_db.get_enemy(&"loan_shark").passive.every_rounds), 3)
	assert_true(_db.get_enemy(&"bouncer").passive.is_empty(), "plain enemies have none")


func test_an_unknown_passive_or_intent_key_is_an_error() -> void:
	var db := ContentDB.new()
	db._statuses[&"weak"] = Defs.StatusDef.new()
	db._parse_enemy({
		"id": "typo", "name": "Typo", "hp_min": 10, "hp_max": 10,
		"passive": {"type": "explode"},
		"brain": {"type": "sequence", "steps": ["hit"]},
		"moves": {"hit": {"intent": {"instances": 1, "per_hit": 1, "bluff": true}}},
	})
	var joined := " ".join(db.errors)
	assert_string_contains(joined, "unknown passive")
	assert_string_contains(joined, "unknown intent key")


# ---- Bust (the Dealer) ----

func test_the_dealer_busts_at_twenty_one_damage() -> void:
	var sim := _sim(["dealer"])
	var dealer := sim.enemies[0]
	dealer.hp = 500
	dealer.max_hp = 500
	dealer.apply_status(&"strength", 4)
	sim.on_enemy_damaged(dealer, 20)
	assert_false(dealer.has_status(&"stun"), "20 is not 21 yet")
	assert_eq(dealer.status_stacks(&"strength"), 4)
	sim.drain_events()

	sim.on_enemy_damaged(dealer, 1)
	assert_true(dealer.has_status(&"stun"), "stunned at 21")
	assert_eq(dealer.status_stacks(&"strength"), 0, "and its Strength is gone")
	assert_has(_types(sim.drain_events()), &"enemy_busted")

	# The count resets, so the next 21 is a fresh bust.
	sim.on_enemy_damaged(dealer, 20)
	assert_eq(dealer.status_stacks(&"stun"), 1, "no second bust from one hit")


func test_bust_keeps_multistrike_but_zeroes_strength() -> void:
	var sim := _sim(["dealer"])
	var dealer := sim.enemies[0]
	dealer.hp = 500
	dealer.apply_status(&"strength", 3)
	dealer.apply_status(&"multistrike", 2)
	sim.on_enemy_damaged(dealer, 21)
	assert_eq(dealer.status_stacks(&"strength"), 0)
	assert_eq(dealer.status_stacks(&"multistrike"), 2)


func test_the_dealer_snowballs_strength_through_its_rotation() -> void:
	var sim := _sim(["dealer"])
	var dealer := sim.enemies[0]
	dealer.hp = 500
	dealer.max_hp = 500
	sim.begin_round()
	sim.tray.discard_all()
	sim.end_assignment()
	assert_eq(dealer.status_stacks(&"strength"), 1, "Deal 2x2, gain Strength 1")


# ---- Break / Gift / Absorb (the Chip Golem) ----

## Sheet v0.122 moved the threshold from 20 to 30 (patch 0.114).
func test_break_gifts_a_chip_for_every_thirty_health_lost() -> void:
	var sim := _sim(["chip_golem"])
	var golem := sim.enemies[0]
	sim.tray.discard_all()
	sim.on_enemy_damaged(golem, 29)
	assert_eq(sim.tray.total(), 0, "29 is not a break")
	sim.on_enemy_damaged(golem, 1)
	assert_eq(sim.tray.total(), 1, "30 is")
	sim.on_enemy_damaged(golem, 65)
	assert_eq(sim.tray.total(), 3, "65 more crosses two more thresholds")


func test_gift_chips_arrive_after_the_next_spin() -> void:
	var sim := _sim(["chip_golem"])
	sim.begin_round()
	sim.tray.discard_all()
	sim.end_assignment()          # round 1: Bash, Deal 20 + Gift 1
	sim.begin_round()
	var types := _types(sim.drain_events())
	var spin := types.find(&"spin_resolved")
	var chips := -1
	for i in range(types.size() - 1, -1, -1):
		if types[i] == &"chips_generated":
			chips = i
	assert_gt(spin, -1, "the machine spun")
	assert_gt(chips, spin, "the gifted chip lands after the payout, not before")


func test_absorb_takes_every_chip_off_the_abilities() -> void:
	var sim := _sim(["chip_golem"], ["card_sling", "double_down"])
	sim.begin_round()
	sim.tray.add(&"spade", 2)
	sim.abilities[1].fill(0, &"spade")   # a half-filled Double Down
	var before := sim.abilities[1].filled[0]
	assert_eq(before, &"spade")
	sim.drain_events()
	sim._intents[sim.enemies[0].id] = {"intent": {"instances": 0, "per_hit": 0,
		"debuffs": [], "absorb": true}}
	sim._execute_move(sim.enemies[0], false)
	assert_eq(sim.abilities[1].filled[0], &"", "the socket is emptied")
	var absorbed := false
	for event: CombatEvent in sim.drain_events():
		if event.type == &"chips_absorbed":
			absorbed = true
			assert_eq(int(event.data.count), 1)
	assert_true(absorbed, "and the presenter is told")


# ---- Multistrike and Rage ----

func test_multistrike_adds_instances_and_shows_in_the_intent() -> void:
	var sim := _sim(["bouncer"])
	sim.begin_round()
	var bouncer := sim.enemies[0]
	var before := sim.intent_display(bouncer.id)
	bouncer.apply_status(&"multistrike", 2)
	var after := sim.intent_display(bouncer.id)
	assert_eq(int(after.display_instances), int(before.display_instances) + 2)


func test_multistrike_does_not_invent_hits_for_a_non_damaging_move() -> void:
	var sim := _sim(["manager"])
	sim.begin_round()
	var manager := sim.enemies[0]
	manager.apply_status(&"multistrike", 3)
	var intent := {"instances": 0, "per_hit": 0, "debuffs": []}
	assert_eq(sim._move_instances(manager, intent), 0)


func test_rage_adds_to_every_hit_and_is_spent_by_that_attack() -> void:
	var sim := _sim(["bouncer"])
	sim.begin_round()
	var bouncer := sim.enemies[0]
	bouncer.apply_status(&"rage", 10)
	# A 2x0 move: Rage 10 on every hit is 2 x 10.
	sim._intents[bouncer.id] = {"intent": {"instances": 2, "per_hit": 0, "debuffs": []}}
	var hp_before := sim.hero.hp
	sim._execute_move(bouncer, false)
	assert_eq(hp_before - sim.hero.hp, 20, "both hits carry the bonus")
	assert_false(bouncer.has_status(&"rage"), "and the Rage is used up")


func test_rage_survives_a_move_that_does_not_attack() -> void:
	var sim := _sim(["bouncer"])
	sim.begin_round()
	var bouncer := sim.enemies[0]
	bouncer.apply_status(&"rage", 10)
	sim._intents[bouncer.id] = {"intent": {"instances": 0, "per_hit": 0, "debuffs": [],
		"self_status": [{"status": "strength", "stacks": 1}]}}
	sim._execute_move(bouncer, false)
	assert_eq(bouncer.status_stacks(&"rage"), 10, "it is waiting for an attack")


func test_self_block_shields_the_enemy() -> void:
	var sim := _sim(["chip_golem"])
	var golem := sim.enemies[0]
	sim.begin_round()
	sim._intents[golem.id] = {"intent": {"instances": 0, "per_hit": 0, "debuffs": [],
		"self_block": 20}}
	sim._execute_move(golem, false)
	assert_eq(golem.block, 20)


# ---- the retired mechanic ----

func test_the_dealer_no_longer_raffles_blackjack() -> void:
	var dealer := _db.get_enemy(&"dealer")
	assert_eq(dealer.hp_min, 51)
	assert_eq(dealer.hp_max, 55)
	# Sheet v0.122: the first two moves are 2x3, the third is 2x3 too (sheet v0.121 corrected it from 2x2), with
	# Multistrike (patch 0.114).
	for move_id: String in dealer.moves:
		var intent: Dictionary = dealer.moves[move_id].intent
		assert_false(intent.has("blackjack"), "%s still raffles" % move_id)
		assert_eq(int(intent.instances), 2, "%s is a two-hitter" % move_id)
		assert_between(int(intent.per_hit), 2, 3, move_id)
