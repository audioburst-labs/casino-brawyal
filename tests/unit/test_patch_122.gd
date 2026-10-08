extends GutTest
## Build 1.22 (patch 0.122), the designer's notes that a test can pin.

var db: ContentDB


func before_each() -> void:
	db = ContentDB.new()
	assert_true(db.load_all("res://data"), str(db.errors))


# ---- Chip generation (doc "Reel Pools") -------------------------------------------

## "Once a pool is completely depleted, it immediately resets, refilling with
## three fresh copies of each symbol": the first pool holds two copies, the
## refill three.
func test_the_refill_is_three_copies_after_a_first_pool_of_two() -> void:
	var reel := Reel.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var first := {}
	for i in reel.symbols.size() * Reel.POOL_COPIES:
		var symbol := reel.spin(rng)
		first[symbol] = int(first.get(symbol, 0)) + 1
	for suit: StringName in reel.symbols:
		assert_eq(first.get(suit, 0), 2, "first pool: two of %s" % suit)
	var second := {}
	for i in reel.symbols.size() * Reel.REFILL_COPIES:
		var symbol := reel.spin(rng)
		second[symbol] = int(second.get(symbol, 0)) + 1
	for suit: StringName in reel.symbols:
		assert_eq(second.get(suit, 0), 3, "refill: three of %s" % suit)


func test_a_sticker_starts_a_fresh_two_copy_pool() -> void:
	var reel := Reel.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for i in reel.symbols.size() * (Reel.POOL_COPIES + 1):
		reel.spin(rng)                      # into the refilled pool
	reel.set_symbol(0, &"heart")
	var counts := {}
	for i in reel.symbols.size() * Reel.POOL_COPIES:
		var symbol := reel.spin(rng)
		counts[symbol] = int(counts.get(symbol, 0)) + 1
	assert_eq(counts.get(&"heart", 0), 4, "two hearts on the face, two copies each")
	assert_eq(counts.get(&"spade", 0), 0, "the replaced face is gone")


# ---- Tutorial: any chip completes a step -------------------------------------------

func test_the_tutorial_accepts_any_chip_on_the_card_being_taught() -> void:
	var flow := TutorialFlow.new()
	flow.step = TutorialFlow.Step.SLING
	for suit in [&"spade", &"club", &"heart", &"diamond"]:
		assert_true(flow.allows_drop(&"card_sling", suit), "any %s on Card Sling" % suit)
	assert_false(flow.allows_drop(&"quick_maneuvers", &"club"), "but not on another card")
	flow.step = TutorialFlow.Step.QUICK
	for suit in [&"spade", &"club", &"heart", &"diamond"]:
		assert_true(flow.allows_drop(&"quick_maneuvers", suit))
	assert_false(flow.allows_drop(&"card_sling", &"diamond"))
	flow.step = TutorialFlow.Step.NICE
	assert_false(flow.allows_drop(&"card_sling", &"club"), "the pause between steps is a pause")
	flow.free()


# ---- Drunk Patron -----------------------------------------------------------------

func test_the_patron_has_a_punch_animation_like_everyone_else() -> void:
	assert_not_null(db.get_enemy(&"drunk_patron"))
	for pose in ["windup", "strike", "follow"]:
		var path := "res://assets/characters/drunk_patron_punch_%s.png" % pose
		assert_true(ResourceLoader.exists(path), path)


func test_the_patrons_heal_is_part_of_what_its_second_move_announces() -> void:
	var sim := CombatSim.new(db, {"hero": "ace", "enemies": ["drunk_patron"],
		"abilities": ["card_sling"], "seed": 4})
	sim.begin_round()
	sim.tray.discard_all()
	sim.end_assignment()
	sim.begin_round()
	var entry := sim.intent_display(sim.enemies[0].id)
	assert_eq(int(entry.intent.self_heal), 4, "the intent carries the heal it will do")
	assert_eq(int(entry.intent.self_status[0].stacks), 4)


# ---- Ace's kit against the sheet --------------------------------------------------

func test_on_a_roll_reads_as_the_sheet_does() -> void:
	var base := db.get_ability(&"on_a_roll", 0)
	assert_eq(base.description, "Deal 10 to all enemies. Cash In: Repeat 1.")
	assert_eq(db.get_ability(&"on_a_roll", 1).description,
		"Deal 12 to all enemies. Cash In: Repeat 1.")
	assert_eq(db.get_ability(&"on_a_roll", 2).description,
		"Deal 14 to all enemies. Cash In: Repeat 1.")
	assert_eq(base.cost, [&"any", &"spade", &"club"] as Array[StringName])


func test_the_river_reads_as_the_sheet_does() -> void:
	assert_eq(db.get_ability(&"the_river", 0).description,
		"Deal 10. For each expended ability, Repeat 1.")
