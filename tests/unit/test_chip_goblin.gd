extends GutTest
## The Chip Goblin (sheet v0.123, the old Slot Gremlin art): 19 to 22 HP, Claw
## Flurry (Deal 1X4, Apply Weak 1) then Sharpen (Gain 1 Strength), and a Break
## passive that fires on its DEATH instead of per 30 health lost.

var _db: ContentDB


func before_all() -> void:
	_db = ContentDB.new()
	assert_true(_db.load_all("res://data"), str(_db.errors))


func _sim(enemies: Array) -> CombatSim:
	var sim := CombatSim.new(_db, {"hero": "ace", "abilities": ["card_sling"],
		"enemies": enemies, "seed": 6})
	sim.hero.max_hp = 999
	sim.hero.hp = 999
	return sim


func test_the_goblin_matches_the_sheet() -> void:
	var def := _db.get_enemy(&"chip_goblin")
	assert_eq(def.name, "Chip Goblin")
	assert_eq([def.hp_min, def.hp_max], [19, 22])
	var flurry: Dictionary = def.moves["claw_flurry"].intent
	assert_eq([int(flurry.instances), int(flurry.per_hit)], [4, 1], "Deal 1X4")
	assert_eq(int(flurry.debuffs[0].stacks), 1, "Apply Weak 1")
	assert_eq(int(def.moves["sharpen"].intent.self_status[0].stacks), 1, "Gain 1 Strength")
	assert_not_null(SuitAssets.character_texture(&"chip_goblin", false))
	for pose in ["windup", "strike", "follow"]:
		assert_true(ResourceLoader.exists("res://assets/characters/chip_goblin_punch_%s.png" % pose))


func test_it_flurries_then_sharpens_and_the_next_flurry_hits_harder() -> void:
	var sim := _sim(["chip_goblin"])
	var goblin := sim.enemies[0]
	sim.begin_round()
	var before := sim.hero.hp
	sim.tray.discard_all()
	sim.end_assignment()
	assert_eq(before - sim.hero.hp, 4, "four hits of 1")
	assert_eq(sim.hero.status_stacks(&"weak"), 1)
	sim.begin_round()
	sim.tray.discard_all()
	sim.end_assignment()
	assert_eq(goblin.status_stacks(&"strength"), 1)
	sim.begin_round()
	before = sim.hero.hp
	sim.tray.discard_all()
	sim.end_assignment()
	assert_eq(before - sim.hero.hp, 8, "four hits of 1 plus 1 Strength")


func test_a_dying_goblin_hands_over_a_chip_once() -> void:
	var sim := _sim(["chip_goblin", "chip_goblin"])
	sim.begin_round()
	sim.drain_events()
	var goblin := sim.enemies[0]
	var chips_before := 0
	for suit in ContentDB.SUITS:
		chips_before += sim.tray.count(suit)
	goblin.hp = 1
	sim.set_target(goblin.id)
	sim.tray.add(&"club", 1)
	assert_true(sim.assign_chip(&"club", 0, 0))      # Card Sling kills it
	var gifts := sim.drain_events().filter(func(e: CombatEvent) -> bool:
		return e.type == &"chips_generated" and str(e.data.source) == "break")
	assert_eq(gifts.size(), 1, "one chip when it dies")
	assert_eq(str(gifts[0].data.actor), String(goblin.id), "the presenter knows who shed it")
	var chips_after := 0
	for suit in ContentDB.SUITS:
		chips_after += sim.tray.count(suit)
	assert_eq(chips_after, chips_before + 1, "the club went in, the goblin's chip came out")
	sim.check_death(goblin)                          # a second call pays nothing more
	assert_eq(sim.drain_events().filter(func(e: CombatEvent) -> bool:
		return e.type == &"chips_generated").size(), 0)


func test_a_wounded_goblin_sheds_nothing_until_it_dies() -> void:
	var sim := _sim(["chip_goblin"])
	sim.begin_round()
	sim.drain_events()
	var goblin := sim.enemies[0]
	goblin.hp = 10
	sim.on_enemy_damaged(goblin, 9)
	assert_eq(sim.drain_events().filter(func(e: CombatEvent) -> bool:
		return e.type == &"chips_generated").size(), 0)
