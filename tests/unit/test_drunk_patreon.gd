extends GutTest
## The Drunk Patreon (sheet v0.121) and the numbers the same sheet changed
## beside it: the Chip Golem's Bash and Crush and the boss's second summon.

var _db: ContentDB


func before_all() -> void:
	_db = ContentDB.new()
	assert_true(_db.load_all("res://data"), str(_db.errors))


func _sim(enemies: Array) -> CombatSim:
	var sim := CombatSim.new(_db, {
		"hero": "ace", "abilities": ["card_sling"], "enemies": enemies, "seed": 5,
	})
	sim.hero.max_hp = 9999
	sim.hero.hp = 9999
	return sim


func test_the_patreon_is_a_small_fragile_drinker() -> void:
	var def := _db.get_enemy(&"drunk_patreon")
	assert_eq(def.name, "Drunk Patreon")
	assert_eq([def.hp_min, def.hp_max], [12, 15])
	assert_true(def.passive.is_empty(), "no passive on the sheet")


func test_it_swings_for_4_then_gains_strength_and_heals_4_forever() -> void:
	var sim := _sim(["drunk_patreon"])
	var patreon := sim.enemies[0]
	patreon.hp = 5
	sim.begin_round()
	assert_eq(int(sim.intent_display(patreon.id).display_per_hit), 4, "attack 1: Deal 4")
	sim.tray.discard_all()
	sim.end_assignment()
	assert_eq(sim.hero.hp, 9999 - 4)
	sim.begin_round()
	sim.tray.discard_all()
	sim.end_assignment()
	assert_eq(patreon.status_stacks(&"strength"), 4, "attack 2: Gain Strength 4")
	assert_eq(patreon.hp, 9, "attack 2: Heal 4")
	sim.begin_round()
	sim.tray.discard_all()
	sim.end_assignment()
	assert_eq(sim.hero.hp, 9999 - 4 - 8, "1,2 then 1 again: Deal 4 plus 4 Strength")


func test_the_patreon_art_is_found_under_its_id() -> void:
	assert_not_null(SuitAssets.character_texture(&"drunk_patreon", false))


func test_the_sheets_other_changes_are_in() -> void:
	var golem := _db.get_enemy(&"chip_golem")
	assert_eq(int(golem.moves["bash"].intent.per_hit), 20, "Deal 20")
	assert_eq(int(golem.moves["crush"].intent.instances), 3)
	assert_eq(int(golem.moves["crush"].intent.per_hit), 6, "Deal 3X6")
	var boss := _db.get_enemy(&"mr_moneybags")
	assert_eq(int(boss.moves["call_server"].intent.summon.count), 2, "Summon 2 Servers")
	assert_eq(int(boss.moves["call_bouncers"].intent.summon.count), 1, "Summon a Bouncer")
