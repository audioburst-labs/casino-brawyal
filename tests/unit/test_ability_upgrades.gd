extends GutTest
## Patch 0.19 pass 2 — ability upgrade tiers (doc "Ability Upgrades"):
## base -> silver -> gold, duplicates upgrade instead of stacking, and a gold
## ability leaves the offer pool until it is trashed.

var _db: ContentDB


func before_all() -> void:
	_db = ContentDB.new()
	assert_true(_db.load_all("res://data"), str(_db.errors))


func _run() -> RunState:
	var run := RunState.new()
	run.hero_id = &"ace"
	return run


func _rng(seed_value: int = 3) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


# ---- the content side: three resolved definitions per ability ----

func test_every_ability_resolves_three_tiers() -> void:
	for id: StringName in _db.all_ability_ids():
		for tier in ContentDB.MAX_TIER + 1:
			var def := _db.get_ability(id, tier)
			assert_not_null(def, "%s tier %d" % [id, tier])
			assert_eq(def.tier, tier)
			assert_false(def.description.is_empty(), "%s tier %d has text" % [id, tier])


func test_tiers_scale_the_sheets_numbers() -> void:
	# Card Sling: 6 / 8 / 10 (sheet v0.121)
	var amounts: Array[int] = []
	for tier in 3:
		amounts.append(int(_db.get_ability(&"card_sling", tier).effects[0].amount))
	assert_eq(amounts, [6, 8, 10] as Array[int])
	# Flush: 30 / 35 / 40, all enemies at every tier (sheet v0.121)
	for tier in 3:
		var flush := _db.get_ability(&"flush", tier)
		assert_eq(str(flush.effects[0].target), "all_enemies")
	assert_eq(int(_db.get_ability(&"flush", 2).effects[0].amount), 40)


func test_a_tier_can_override_a_limit_not_just_a_number() -> void:
	# Color Up's upgrades change how often it is usable, not what it does.
	assert_eq(_db.get_ability(&"color_up", 0).per_turn, 1)
	assert_eq(_db.get_ability(&"color_up", 1).per_turn, 2)
	assert_eq(_db.get_ability(&"color_up", 2).per_turn, 0, "0 = unlimited")


func test_tier_definitions_are_separate_objects() -> void:
	# AbilityState holds a reference to the shared def, so a tier must never be
	# the same object as its base or an upgrade would leak across runs.
	var base := _db.get_ability(&"card_sling", 0)
	var gold := _db.get_ability(&"card_sling", 2)
	assert_ne(base, gold)
	assert_ne(base.effects[0], gold.effects[0])
	assert_eq(int(base.effects[0].amount), 6, "base is untouched by the gold tier")


func test_unknown_tier_clamps_to_a_real_one() -> void:
	assert_eq(_db.get_ability(&"card_sling", 99).tier, ContentDB.MAX_TIER)
	assert_eq(_db.get_ability(&"card_sling", -1).tier, 0)


# ---- the run side: owning and upgrading ----

func test_acquiring_a_duplicate_upgrades_it() -> void:
	var run := _run()
	run.acquire_ability(&"bust")
	assert_eq(run.ability_tier(&"bust"), 0)
	assert_eq(run.ability_ids.size(), 1)

	run.acquire_ability(&"bust")
	assert_eq(run.ability_tier(&"bust"), 1, "silver")
	assert_eq(run.ability_ids.size(), 1, "still one copy, not two")

	run.acquire_ability(&"bust")
	assert_eq(run.ability_tier(&"bust"), 2, "gold")
	assert_eq(run.ability_ids.size(), 1)


func test_gold_is_the_ceiling() -> void:
	var run := _run()
	for i in 6:
		run.acquire_ability(&"bust")
	assert_eq(run.ability_tier(&"bust"), ContentDB.MAX_TIER)


func test_trashing_a_gold_ability_forgets_its_tier() -> void:
	# Doc: a gold ability returns to the pool if the player trashes it.
	var run := _run()
	run.acquire_ability(&"bust")
	run.acquire_ability(&"bust")
	run.move_to_trash(&"bust")
	run.process_trash()
	assert_false(run.ability_ids.has(&"bust"))
	assert_eq(run.ability_tier(&"bust"), 0, "reacquiring starts from base again")


func test_tiers_survive_a_save_round_trip() -> void:
	var run := _run()
	run.acquire_ability(&"bust")
	run.acquire_ability(&"bust")
	run.acquire_ability(&"flush")
	var restored := RunState.from_dict(run.to_dict())
	assert_eq(restored.ability_tier(&"bust"), 1)
	assert_eq(restored.ability_tier(&"flush"), 0)


func test_an_old_save_without_tiers_still_loads() -> void:
	var run := _run()
	run.acquire_ability(&"bust")
	var data := run.to_dict()
	data.erase("ability_tiers")
	var restored := RunState.from_dict(data)
	assert_eq(restored.ability_tier(&"bust"), 0, "missing tiers default to base")


# ---- the offer pools ----

func test_rewards_offer_three_and_include_upgrades() -> void:
	var run := _run()
	var choices := Rewards.ability_choices(_db, run, _rng())
	assert_eq(choices.size(), 3, "1 of 3 (doc v0.19)")

	# Own one at base: it should still be offerable, as an upgrade.
	run.acquire_ability(&"bust")
	var seen_owned := false
	for seed_value in 40:
		if Rewards.ability_choices(_db, run, _rng(seed_value)).has(&"bust"):
			seen_owned = true
			break
	assert_true(seen_owned, "an upgradeable ability can be offered again")


func test_gold_abilities_leave_the_pool() -> void:
	var run := _run()
	for i in 3:
		run.acquire_ability(&"bust")
	assert_eq(run.ability_tier(&"bust"), ContentDB.MAX_TIER)
	for seed_value in 40:
		assert_false(Rewards.ability_choices(_db, run, _rng(seed_value)).has(&"bust"),
			"a gold ability is never offered again")


func test_shop_can_stock_an_upgrade() -> void:
	var run := _run()
	run.coins = 500
	# Owned outright — going through acquire_ability would overflow the
	# equipped/storage/trash caps and quietly drop the overflow.
	for id: StringName in _db.all_ability_ids():
		run.ability_ids.append(id)
	# Everything is owned at base, so any shop ability slot must be an upgrade.
	var stock := ShopStock.generate(_db, run, _rng())
	assert_gt(stock.abilities.size(), 0, "the pool is not empty just because we own them")
	for offer: Dictionary in stock.abilities:
		assert_true(run.ability_ids.has(offer.id))
		assert_true(bool(offer.upgrade), "flagged as an upgrade for the shop UI")


func test_shop_skips_gold_abilities() -> void:
	var run := _run()
	run.coins = 500
	for id: StringName in _db.all_ability_ids():
		run.ability_ids.append(id)
		run.ability_tiers[id] = ContentDB.MAX_TIER
	var stock := ShopStock.generate(_db, run, _rng())
	assert_eq(stock.abilities.size(), 0, "nothing left to sell once everything is gold")


# ---- combat reads the run's tier ----

func test_combat_uses_the_owned_tier() -> void:
	var run := _run()
	run.acquire_ability(&"card_sling")
	run.acquire_ability(&"card_sling")   # silver: 9 damage
	var sim := CombatSim.new(_db, {
		"hero": "ace",
		"abilities": [&"card_sling"],
		"ability_tiers": run.ability_tiers,
		"enemies": ["bouncer"],
		"seed": 4,
	})
	sim.begin_round()
	var enemy := sim.enemies[0]
	var hp_start := enemy.hp
	sim.tray.add(&"club", 1)
	assert_true(sim.assign_chip(&"club", 0, 0))
	assert_eq(enemy.hp, hp_start - 8, "the silver copy hits for 8, not 6")
