extends GutTest
## Build 1.29 (designer's notes): Bad Beat glows while an enemy is marked, and Face
## Reader procs only at the start of a turn.

var _db: ContentDB


func before_all() -> void:
	_db = ContentDB.new()
	assert_true(_db.load_all("res://data"), str(_db.errors))


func _sim(enemies: Array, abilities: Array, seed_value: int = 4) -> CombatSim:
	var sim := CombatSim.new(_db, {"hero": "ace", "abilities": abilities,
		"enemies": enemies, "seed": seed_value})
	sim.hero.max_hp = 9999
	sim.hero.hp = 9999
	return sim


func _fire_face_reader(sim: CombatSim) -> void:
	sim.tray.add(&"club", 1)
	sim.tray.add(&"diamond", 1)
	assert_true(sim.assign_chip(&"club", 0, 0))
	assert_true(sim.assign_chip(&"diamond", 0, 1))


# ---- the glow ----

func test_bad_beat_glows_while_an_enemy_is_marked_and_not_before() -> void:
	var sim := _sim(["bouncer", "server"], ["bad_beat"])
	sim.begin_round()
	var def := _db.get_ability(&"bad_beat")
	assert_false(AbilityCard.wants_glow(def, sim), "no Mark, no glow")
	sim.enemies[1].apply_status(&"mark", 1)
	assert_true(AbilityCard.wants_glow(def, sim), "any marked enemy lights it, not only the target")
	sim.enemies[1].statuses.erase(&"mark")
	assert_false(AbilityCard.wants_glow(def, sim), "and it goes out when the Mark is cashed")


func test_bad_beat_glows_at_every_tier() -> void:
	var sim := _sim(["bouncer"], ["bad_beat"])
	sim.enemies[0].apply_status(&"mark", 1)
	for tier in 3:
		assert_true(AbilityCard.wants_glow(_db.get_ability(&"bad_beat", tier), sim), "tier %d" % tier)


func test_the_other_glowing_cards_still_glow_as_before() -> void:
	var sim := _sim(["bouncer"], ["double_down", "bluff_call", "card_sling"])
	var double_down := _db.get_ability(&"double_down")
	var bluff := _db.get_ability(&"bluff_call")
	var sling := _db.get_ability(&"card_sling")
	assert_false(AbilityCard.wants_glow(double_down, sim))
	assert_false(AbilityCard.wants_glow(bluff, sim))
	sim.enemies[0].apply_status(&"mark", 1)
	assert_true(AbilityCard.wants_glow(double_down, sim), "a Cash In still lights on a Mark")
	assert_false(AbilityCard.wants_glow(sling, sim), "a card that does not read Marks stays dark")
	sim.enemies[0].apply_status(&"weak", 1)
	assert_true(AbilityCard.wants_glow(bluff, sim), "and a Weak-synergy card on a Weak enemy")


# ---- Face Reader ----

func test_face_reader_pays_nothing_the_turn_it_is_played() -> void:
	var sim := _sim(["dealer"], ["face_reader"])
	sim.begin_round()
	sim.hero.block = 0
	_fire_face_reader(sim)
	assert_eq(sim.hero.block, 0)
	assert_gt(sim.incoming_hit_count(), 0, "hits were announced, and it still did not pay")


func test_face_reader_then_pays_at_the_start_of_every_turn() -> void:
	var sim := _sim(["bouncer", "bouncer"], ["face_reader"])
	sim.begin_round()
	_fire_face_reader(sim)
	var paid_some_turn := false
	for round_index in 4:
		sim.tray.discard_all()
		sim.end_assignment()
		if sim.phase == CombatSim.Phase.ENDED:
			break
		sim.begin_round()
		# A turn where nobody announces an attack has no hits to pay for.
		assert_eq(sim.hero.block, 2 * sim.incoming_hit_count(), "turn %d" % (round_index + 2))
		paid_some_turn = paid_some_turn or sim.hero.block > 0
	assert_true(paid_some_turn, "it paid on at least one of them")


func test_it_is_still_usable_once_per_fight_and_is_a_passive() -> void:
	var def := _db.get_ability(&"face_reader")
	assert_true(def.passive)
	assert_eq(def.per_combat, 1)
	assert_false(def.proc_on_play)
	for tier in 3:
		assert_false(_db.get_ability(&"face_reader", tier).proc_on_play, "tier %d" % tier)


func test_only_face_reader_and_house_edge_wait_for_the_next_turn() -> void:
	# Face Reader in 1.29, House Edge in 1.30 (designer: "should only mark on turn
	# start, and not also when used").
	var waiting: Array[String] = []
	for id: StringName in _db.all_ability_ids():
		var def := _db.get_ability(id)
		if def.passive and def.passive_trigger == "" and not def.proc_on_play:
			waiting.append(String(id))
	waiting.sort()
	assert_eq(waiting, ["face_reader", "house_edge"] as Array[String])


func test_house_edge_no_longer_marks_the_turn_it_is_played() -> void:
	var sim := _sim(["bouncer"], ["house_edge"])
	sim.begin_round()
	sim.tray.add(&"spade", 1)
	assert_true(sim.assign_chip(&"spade", 0, 0))
	assert_false(sim.enemies[0].has_status(&"mark"), "playing it only switches it on (1.30)")


# ---- the images ----

func test_the_risky_dealings_picture_is_still_the_story_size() -> void:
	var picture: Texture2D = load("res://assets/story/story_risky_dealings.png")
	assert_not_null(picture)
	assert_eq(picture.get_size(), Vector2(1536, 1024))
