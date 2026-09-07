extends GutTest
## Patch 0.18: block-aware damage reporting and doc-compliant summon slotting
## (design doc "Behavior -> Unit Positioning").

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


func test_damage_event_reports_how_much_block_absorbed() -> void:
	# The presenter needs the split: Block must visibly eat the hit instead of
	# the HP bar dropping and then springing back up ("block heals you").
	var sim := _sim()
	sim.begin_round()
	sim.hero.gain_block(6)
	var before := sim.hero.hp
	sim.drain_events()
	sim._hit_hero(sim.enemies[0], 10)
	var events := sim.drain_events()
	var damage: CombatEvent = null
	for event in events:
		if event.type == &"damage_dealt":
			damage = event
	assert_not_null(damage)
	assert_eq(int(damage.data.amount), 10, "full incoming damage")
	assert_eq(int(damage.data.blocked), 6, "block absorbed 6")
	assert_eq(int(damage.data.hp_lost), 4, "only the remainder hits HP")
	assert_eq(sim.hero.hp, before - 4)
	assert_eq(sim.hero.block, 0)


func test_blocked_never_exceeds_the_hit() -> void:
	var sim := _sim()
	sim.begin_round()
	sim.hero.gain_block(30)
	sim.drain_events()
	sim._hit_hero(sim.enemies[0], 4)
	var damage: CombatEvent = null
	for event in sim.drain_events():
		if event.type == &"damage_dealt":
			damage = event
	assert_eq(int(damage.data.blocked), 4, "absorbs only what was thrown")
	assert_eq(int(damage.data.hp_lost), 0)


func test_summon_lands_between_the_summoner_and_the_centre() -> void:
	# Doc: "New summons prioritize the nearest empty slot located between the
	# summoner and the center of the field. If no such inner slot exists, the
	# summoner shifts one position further away from the center."
	# Index 0 is the slot nearest the centre of the field.
	var sim := _sim(["manager"], ["card_sling"], 3)
	sim.hero.max_hp = 9999
	sim.hero.hp = 9999
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
	assert_eq(sim.enemies[0].def_id, &"server", "summon takes the inner slot")
	assert_eq(sim.enemies[1].def_id, &"manager", "summoner shifted outward")


func test_summon_reclaims_a_dead_allys_inner_slot() -> void:
	var sim := _sim(["dealer", "manager"], ["card_sling"], 3)
	sim.hero.max_hp = 9999
	sim.hero.hp = 9999
	sim.begin_round()
	sim.enemies[0].hp = 0          # the inner slot is now empty
	sim.drain_events()
	var manager := sim.enemies[1]
	sim._spawn_enemy(&"server", true, manager)
	assert_eq(sim.enemies.size(), 2, "the corpse's slot was reused, not appended")
	assert_eq(sim.enemies[0].def_id, &"server")
	assert_eq(sim.enemies[1], manager, "the summoner did not move")


func test_field_never_holds_more_than_four_slots() -> void:
	var sim := _sim(["dealer", "dealer", "dealer", "manager"], ["card_sling"], 5)
	sim.begin_round()
	sim.enemies[0].hp = 0
	sim.enemies[1].hp = 0
	sim.drain_events()
	sim._spawn_enemy(&"server", true, sim.enemies[3])
	assert_lte(sim.enemies.size(), CombatSim.MAX_ENEMIES)
