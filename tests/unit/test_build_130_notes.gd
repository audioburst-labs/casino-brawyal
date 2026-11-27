extends GutTest
## Build 1.30 designer's notes: House Edge marks only at turn start, and an enemy's
## Strength stays on the enemy that gained it.

var _db: ContentDB


func before_all() -> void:
	_db = ContentDB.new()
	assert_true(_db.load_all("res://data"), str(_db.errors))


func _sim(enemies: Array, abilities: Array, seed_value: int = 7) -> CombatSim:
	var sim := CombatSim.new(_db, {"hero": "ace", "abilities": abilities,
		"enemies": enemies, "seed": seed_value})
	sim.hero.max_hp = 9999
	sim.hero.hp = 9999
	return sim


func test_house_edge_waits_at_every_tier() -> void:
	for tier in 3:
		assert_false(_db.get_ability(&"house_edge", tier).proc_on_play, "tier %d" % tier)


func test_house_edge_marks_at_the_next_turn_start_not_when_played() -> void:
	var sim := _sim(["bouncer", "server"], ["house_edge"])
	sim.begin_round()
	sim.tray.add(&"spade", 1)
	assert_true(sim.assign_chip(&"spade", 0, 0))
	for enemy in sim.enemies:
		assert_false(enemy.has_status(&"mark"), "nothing the turn it is played")
	sim.tray.discard_all()
	sim.end_assignment()
	sim.begin_round()
	var marked := sim.enemies.filter(func(e: CombatActor) -> bool: return e.has_status(&"mark"))
	assert_eq(marked.size(), 1, "one Mark when the next turn starts")


## The designer saw a Server hit harder after Drunk Patrons drank. The Patrons'
## Strength is theirs alone: the Server's own Strength stays 0 and its damage
## only moves with the HERO's Vulnerable, which its own Hot Plate applies.
func test_a_patrons_strength_never_reaches_the_server() -> void:
	var sim := _sim(["server", "drunk_patron", "drunk_patron"], ["card_sling"])
	var strengthened := false
	for round_index in 6:
		sim.begin_round()
		sim.tray.discard_all()
		sim.end_assignment()
		for enemy in sim.enemies:
			if enemy.def_id == &"drunk_patron" and enemy.status_stacks(&"strength") > 0:
				strengthened = true
			if enemy.def_id == &"server":
				assert_eq(enemy.status_stacks(&"strength"), 0, "round %d" % round_index)
	assert_true(strengthened, "the Patrons did gain Strength, so the check is real")
