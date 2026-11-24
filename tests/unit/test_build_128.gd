extends GutTest
## Build 1.28 (designer's notes): Slow Playing's Strength stops snowballing, loan
## offers carry the keywords they use, and screen titles wrap rather than push the
## screen off-centre.

var _db: ContentDB


func before_all() -> void:
	_db = ContentDB.new()
	assert_true(_db.load_all("res://data"), str(_db.errors))


func _sim(enemies: Array, abilities: Array, seed_value: int = 4, tiers: Dictionary = {}) -> CombatSim:
	var sim := CombatSim.new(_db, {"hero": "ace", "abilities": abilities,
		"ability_tiers": tiers, "enemies": enemies, "seed": seed_value})
	sim.hero.max_hp = 9999
	sim.hero.hp = 9999
	return sim


func _play_slow_playing(sim: CombatSim) -> void:
	sim.begin_round()
	sim.tray.add(&"heart", 3)
	assert_true(sim.assign_chip(&"heart", 0, 0))


# ---- Slow Playing ----

func test_slow_playing_gives_strength_for_the_weak_it_applies_each_time() -> void:
	var sim := _sim(["bouncer"], ["slow_playing"])
	var seen: Array[int] = []
	for turn in 5:
		_play_slow_playing(sim)
		seen.append(sim.hero.status_stacks(&"strength"))
		sim.tray.discard_all()
		sim.end_assignment()
	# Weak 2 each use: a steady +2 a turn. It used to read 2, 5, 9, 14, 20, because
	# every Weak stack already piled on the enemy was counted again.
	assert_eq(seen, [2, 4, 6, 8, 10] as Array[int])


func test_the_tiers_scale_the_strength_with_the_weak() -> void:
	for tier in 3:
		var sim := _sim(["bouncer"], ["slow_playing"], 4, {"slow_playing": tier})
		_play_slow_playing(sim)
		assert_eq(sim.hero.status_stacks(&"strength"), 2 + tier, "tier %d: Weak %d" % [tier, 2 + tier])


func test_weak_already_on_the_field_is_not_counted() -> void:
	var sim := _sim(["bouncer", "server"], ["slow_playing"])
	sim.begin_round()
	sim.enemies[0].apply_status(&"weak", 5)      # Cold Stare Shades, HeartSteal, an earlier turn...
	sim.enemies[1].apply_status(&"weak", 3)
	sim.tray.add(&"heart", 1)
	assert_true(sim.assign_chip(&"heart", 0, 0))
	assert_eq(sim.hero.status_stacks(&"strength"), 2, "only the Weak 2 the card applied")


func test_the_count_starts_over_for_every_ability() -> void:
	var sim := _sim(["bouncer"], ["heartsteal", "slow_playing"])
	sim.begin_round()
	sim.tray.add(&"heart", 2)
	assert_true(sim.assign_chip(&"heart", 0, 0))       # HeartSteal puts Weak 1 on everyone
	assert_eq(sim.hero.status_stacks(&"strength"), 0, "HeartSteal grants no Strength")
	assert_true(sim.assign_chip(&"heart", 1, 0))       # Slow Playing: Weak 2 of its own
	assert_eq(sim.hero.status_stacks(&"strength"), 2, "not 2 plus HeartSteal's 1")


# ---- loan keywords ----

func test_the_strength_and_sturdy_loans_name_their_keywords() -> void:
	assert_eq(_db.get_loan(&"muscle_loan").keywords, [&"strength"] as Array[StringName])
	assert_eq(_db.get_loan(&"plating_loan").keywords, [&"sturdy"] as Array[StringName])
	assert_eq(_db.get_loan(&"pocket_change").keywords.size(), 0, "a chip loan needs no explaining")
	for id: StringName in _db.all_loan_ids():
		for keyword: StringName in _db.get_loan(id).keywords:
			assert_not_null(_db.get_keyword(keyword), "%s uses a real keyword" % id)


func test_an_unknown_loan_keyword_fails_the_content_lint() -> void:
	var db := ContentDB.new()
	db._parse_loan({"id": "typo", "title": "Typo", "turns": 3, "reward_text": "x",
		"penalty_text": "y", "keywords": ["strenth"],
		"reward": [{"op": "heal", "amount": 1}], "penalty": [{"op": "lose_hp", "amount": 1}]})
	assert_string_contains(" ".join(db.errors), "unknown keyword")


func test_an_offer_carries_the_keywords_of_its_loan() -> void:
	var seen := {}
	for seed_value in 40:
		var sim := _sim(["loan_shark"], ["card_sling"], seed_value)
		sim.begin_round()
		for option: Dictionary in sim.pending_choice().options:
			assert_true(option.has("keywords"), "every offer lists its keywords (maybe none)")
			seen[str(option.id)] = option.keywords
	assert_eq(seen.get("muscle_loan"), ["strength"])
	assert_eq(seen.get("plating_loan"), ["sturdy"])
	assert_eq(seen.get("pocket_change"), [])


# ---- the screen title ----

func test_a_screen_title_wraps_instead_of_widening_the_screen() -> void:
	var screen := ScreenBase.new()
	add_child_autofree(screen)
	screen.build_screen("MR. MONEYBAGS DEFEATED!", "res://assets/backgrounds/bg_main_menu.png")
	assert_eq(screen._title_label.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART)
