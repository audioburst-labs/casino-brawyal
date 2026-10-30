extends GutTest
## Relics fire their effects at combat trigger points (patch 0.1 relic set).

var _db: ContentDB


func before_all() -> void:
	_db = ContentDB.new()
	assert_true(_db.load_all("res://data"), str(_db.errors))


func _sim(relics: Array) -> CombatSim:
	return CombatSim.new(_db, {
		"hero": "ace",
		"abilities": ["card_sling"],
		"enemies": ["bouncer"],
		"seed": 3,
		"relics": relics,
	})


func test_collectors_satchel_queues_gold_per_kill() -> void:
	var sim := _sim(["collectors_satchel"])
	sim.begin_round()
	sim.enemies[0].hp = 5
	sim.tray.add(&"spade", 1)
	sim.assign_chip(&"spade", 0, 0)
	assert_eq(sim.phase, CombatSim.Phase.ENDED)
	var kill_gold := sim.pending_rewards.filter(
		func(op: Dictionary) -> bool: return op.get("op") == "gain_coins" and int(op.get("amount", 0)) == 7)
	assert_eq(kill_gold.size(), 1, "7 gold queued for the kill")


func test_croupiers_vest_grants_starting_block() -> void:
	var sim := _sim(["croupiers_vest"])
	sim.begin_round()
	assert_eq(sim.hero.block, 10, "Croupier's Vest starts combat with 10 Block")


func test_suit_protection_grants_block_per_gem() -> void:
	var sim := _sim(["spade_buckler"])
	sim.begin_round()
	var spades: int = sim.last_payout.get(&"spade", 0)
	assert_eq(sim.hero.block, spades * 2)


func test_relic_triggered_event_is_emitted() -> void:
	var sim := _sim(["spade_buckler"])
	sim.begin_round()
	var triggered := sim.drain_events().filter(
		func(e: CombatEvent) -> bool: return e.type == &"relic_triggered")
	assert_eq(triggered.size(), 1)
	assert_eq(triggered[0].data.relic, &"spade_buckler")


# ---- the sheet's relic list, patch 0.125 --------------------------------------------

func _fight(relics: Array, enemies := ["bouncer"], seed_value := 3) -> CombatSim:
	return CombatSim.new(_db, {"hero": "ace", "abilities": ["card_sling"], "enemies": enemies,
		"seed": seed_value, "relics": relics})


func test_every_sheet_relic_exists_with_the_sheets_text() -> void:
	var sheet := {
		&"croupiers_vest": "Start combat: Gain 10 Block.",
		&"cold_stare_shades": "At the start of combat, apply Weak 2 to all enemies.",
		&"lucky_sevens_revolver": "When you roll 3 of the same type, deal 10 to a random enemy.",
		&"jade_knucklers": "Attacks that require a Spade or a Club deal 20% more damage.",
		&"ruby_knuckles": "Attacks that require a Heart or a Diamond deal 20% more damage.",
		&"rabbits_foot_keychain": "When attacked, there's a 5% chance the damage is reduced to 0.",
		&"sleeve_garter": "Start combat: Earn a random chip.",
		&"barkeeps_mallet": "Start combat: Gain Strength 1.",
		&"cursed_coin": "Start combat: Apply Vulnerable 1 to all enemies.",
		&"hip_flask": "After each fight: Heal 6.",
		&"vip_comp_card": "Shop prices are 10% lower.",
		&"signed_policy": "Once per run: When you would die, survive with 20 HP instead.",
	}
	assert_eq(_db.all_relic_ids().size(), 20)
	for id: StringName in sheet:
		assert_eq(_db.get_relic(id).description, sheet[id], str(id))


func test_every_relic_has_art() -> void:
	for id: StringName in _db.all_relic_ids():
		assert_true(ResourceLoader.exists("res://assets/icons/relic_%s.png" % id), "%s needs its icon" % id)


func test_sleeve_garter_earns_a_chip_at_the_start_of_combat() -> void:
	var sim := _fight(["sleeve_garter"])
	sim.begin_round()
	var baseline := _fight([])
	baseline.begin_round()
	assert_eq(sim.tray.total(), baseline.tray.total() + 1)


func test_barkeeps_mallet_gives_strength_one() -> void:
	var sim := _fight(["barkeeps_mallet"])
	sim.begin_round()
	assert_eq(sim.hero.status_stacks(&"strength"), 1)


func test_cursed_coin_makes_every_enemy_vulnerable() -> void:
	var sim := _fight(["cursed_coin"], ["bouncer", "server"])
	sim.begin_round()
	for enemy in sim.enemies:
		assert_eq(enemy.status_stacks(&"vulnerable"), 1)


func test_hip_flask_heals_six_after_the_fight_and_before_the_banner() -> void:
	var sim := _fight(["hip_flask"])
	sim.begin_round()
	sim.hero.hp = 40
	sim.enemies[0].hp = 5
	sim.tray.add(&"spade", 1)
	sim.assign_chip(&"spade", 0, 0)
	assert_eq(sim.phase, CombatSim.Phase.ENDED)
	assert_eq(sim.hero.hp, 46)
	var types: Array[StringName] = []
	for e in sim.drain_events():
		types.append(e.type)
	assert_lt(types.find(&"healed"), types.find(&"combat_won"), "the heal is on screen before the win")


func test_hip_flask_does_not_heal_a_lost_fight() -> void:
	var sim := _fight(["hip_flask"])
	sim.begin_round()
	assert_ne(sim.phase, CombatSim.Phase.ENDED)
	assert_eq(sim.hero.hp, sim.hero.max_hp - 0)


func test_signed_policy_saves_the_hero_once() -> void:
	var sim := _fight(["signed_policy"])
	sim.begin_round()
	sim.hero.hp = 0
	sim._check_hero_death()
	assert_true(sim.hero.is_alive(), "survives")
	assert_eq(sim.hero.hp, 20)
	assert_ne(sim.phase, CombatSim.Phase.ENDED)
	assert_eq(sim.relics_spent, [&"signed_policy"] as Array[StringName])
	# the second time it is gone
	sim.hero.hp = 0
	sim._check_hero_death()
	assert_eq(sim.phase, CombatSim.Phase.ENDED)


func test_a_spent_policy_does_nothing_in_a_later_fight() -> void:
	var sim := CombatSim.new(_db, {"hero": "ace", "abilities": ["card_sling"], "enemies": ["bouncer"],
		"seed": 3, "relics": ["signed_policy"], "spent_relics": ["signed_policy"]})
	sim.begin_round()
	sim.hero.hp = 0
	sim._check_hero_death()
	assert_eq(sim.phase, CombatSim.Phase.ENDED)


func test_the_policy_is_spent_for_the_run_and_survives_a_save() -> void:
	var run := RunState.new()
	run.spent_relics = [&"signed_policy"]
	var back := RunState.from_dict(run.to_dict())
	assert_eq(back.spent_relics, [&"signed_policy"] as Array[StringName])
	assert_eq(EncounterFactory.combat_config(_db, back, RandomNumberGenerator.new(), {"type": &"combat"}).spent_relics,
		[&"signed_policy"] as Array[StringName])


func test_vip_comp_card_takes_ten_percent_off_everything() -> void:
	var run := RunState.new()
	assert_eq(ShopPricing.price(run, 100), 100)
	run.relic_ids = [&"vip_comp_card"]
	assert_eq(ShopPricing.price(run, 100), 90)
	assert_eq(ShopPricing.price(run, 35), 32, "31.5 rounds half up")
	assert_eq(ShopPricing.price(run, 1), 1, "never free")


func test_the_knuckles_give_twenty_percent_and_the_keychain_five() -> void:
	assert_eq(CombatSim.EMBLEM_MULTIPLIER, 1.2)
	assert_eq(CombatSim.LUCKY_FOOT_CHANCE, 0.05)


func test_old_relic_ids_in_a_save_become_the_new_ones() -> void:
	var back := RunState.from_dict({"relic_ids": ["gamblers_confidence", "lucky_foot", "high_roller"]})
	assert_eq(back.relic_ids, [&"croupiers_vest", &"rabbits_foot_keychain", &"lucky_sevens_revolver"] as Array[StringName])


# ---- Mighty and its three relics (patch 0.128) ----------------------------------------

func _mighty_fight(relics: Array) -> CombatSim:
	var sim := CombatSim.new(_db, {"hero": "ace", "abilities": ["double_down", "card_sling"],
		"enemies": ["bouncer"], "seed": 3, "relics": relics})
	sim.begin_round()
	sim.tray.discard_all()
	return sim


func _pay(sim: CombatSim, index: int, suits: Array) -> void:
	for slot in suits.size():
		sim.tray.add(suits[slot], 1)
		sim.assign_chip(suits[slot], index, slot)


func test_mighty_is_an_ability_that_costs_two_or_more_chips() -> void:
	assert_true(_db.get_ability(&"double_down").is_mighty(), "two sockets")
	assert_false(_db.get_ability(&"card_sling").is_mighty(), "one socket")
	assert_not_null(_db.get_keyword(&"mighty"))
	assert_eq(_db.get_keyword(&"mighty").text, "An ability that costs 2 or more chips.")


func test_the_three_new_relics_say_what_the_designer_wrote() -> void:
	assert_eq(_db.get_relic(&"heavy_hitters_ring").description,
		"The first Mighty ability you use each combat earns you one of the used chips.")
	assert_eq(_db.get_relic(&"strongmans_belt").description,
		"When you use a Mighty ability, gain 3 Block.")
	assert_eq(_db.get_relic(&"kaleidoscope_loupe").description,
		"When you roll 3 or more different symbols, deal 2 to a random enemy.")


func test_strongmans_belt_blocks_three_per_mighty_ability_and_ignores_small_ones() -> void:
	var sim := _mighty_fight(["strongmans_belt"])
	sim.hero.block = 0
	_pay(sim, 1, [&"spade"])
	assert_eq(sim.hero.block, 0, "Card Sling is not Mighty")
	_pay(sim, 0, [&"heart", &"spade"])
	assert_eq(sim.hero.block, 3, "Double Down is")


func test_heavy_hitters_ring_returns_a_used_chip_for_the_first_mighty_only() -> void:
	var sim := _mighty_fight(["heavy_hitters_ring"])
	_pay(sim, 0, [&"heart", &"spade"])
	assert_eq(sim.tray.total(), 1, "one of the two paid chips came back")
	sim.tray.discard_all()
	_pay(sim, 0, [&"heart", &"spade"])
	assert_eq(sim.tray.total(), 0, "the second Mighty this combat earns nothing")


func test_heavy_hitters_ring_ignores_a_cheap_ability_and_waits_for_a_mighty_one() -> void:
	var sim := _mighty_fight(["heavy_hitters_ring"])
	_pay(sim, 1, [&"spade"])
	assert_eq(sim.tray.total(), 0)
	_pay(sim, 0, [&"heart", &"spade"])
	assert_eq(sim.tray.total(), 1, "the first MIGHTY one still counts")


func test_kaleidoscope_loupe_needs_three_different_symbols() -> void:
	var sim := _mighty_fight(["kaleidoscope_loupe"])
	var before := sim.enemies[0].hp
	sim.last_symbols = [&"spade", &"spade", &"heart"] as Array[StringName]
	sim._fire_relics(&"spin_resolved")
	assert_eq(sim.enemies[0].hp, before, "two kinds is not enough")
	sim.last_symbols = [&"spade", &"club", &"heart"] as Array[StringName]
	sim._fire_relics(&"spin_resolved")
	assert_eq(sim.enemies[0].hp, before - 2)


func test_kaleidoscope_loupe_counts_kinds_not_reels() -> void:
	var sim := _mighty_fight(["kaleidoscope_loupe"])
	var before := sim.enemies[0].hp
	sim.last_symbols = [&"spade", &"spade", &"heart", &"heart"] as Array[StringName]
	sim._fire_relics(&"spin_resolved")
	assert_eq(sim.enemies[0].hp, before, "four reels, two kinds")
	sim.last_symbols = [&"spade", &"spade", &"heart", &"club"] as Array[StringName]
	sim._fire_relics(&"spin_resolved")
	assert_eq(sim.enemies[0].hp, before - 2)
