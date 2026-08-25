extends GutTest
## Casino minigame per doc v0.13: one paid spin costs 5 x encounter number;
## each of the 3 reels lands a percentage-weighted prize (including the
## Broken Heart penalty and a 1% Extra Reel); three of a kind = free spin.

var _db: ContentDB


func before_all() -> void:
	_db = ContentDB.new()
	assert_true(_db.load_all("res://data"), str(_db.errors))


func _rng(seed_value: int = 8) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func test_spin_costs_five_per_encounter_number() -> void:
	var run := RunState.new()
	run.record_visit(&"combat")
	run.record_visit(&"casino")  # encounter number = 3
	assert_eq(CasinoGame.spin_cost(run), 15, "5 x encounter 3")
	run.coins = 15
	var result := CasinoGame.spin(_db, run, _rng())
	assert_false(result.is_empty(), "exactly the cost is affordable")
	assert_eq(int(result.cost), 15)


func test_spin_refused_without_coins() -> void:
	var run := RunState.new()
	run.coins = 4  # encounter 1 costs 5
	var result := CasinoGame.spin(_db, run, _rng())
	assert_true(result.is_empty(), "cannot afford a spin")
	assert_eq(run.coins, 4)


func test_three_of_a_kind_grants_free_respin_flag() -> void:
	var run := RunState.new()
	run.coins = 100000
	var saw_triple := false
	for seed_value in 400:
		var result := CasinoGame.spin(_db, run, _rng(seed_value))
		if result.symbols[0] == result.symbols[1] and result.symbols[1] == result.symbols[2]:
			assert_true(result.free_respin, "triple grants a free spin")
			saw_triple = true
	assert_true(saw_triple)


func test_all_prize_kinds_apply_over_many_spins() -> void:
	var run := RunState.new()
	run.coins = 100000
	run.max_hp = 80
	run.hp = 40
	var reels_before := run.machine.reels.size()
	var lost_hp := false
	var healed := false
	var got_sticker := false
	var got_relic := false
	for seed_value in 400:
		var hp_before := run.hp
		CasinoGame.spin(_db, run, _rng(seed_value))
		lost_hp = lost_hp or run.hp < hp_before
		healed = healed or run.hp > hp_before
		got_sticker = got_sticker or not run.sticker_inventory.is_empty()
		got_relic = got_relic or not run.relic_ids.is_empty()
	assert_true(healed, "heart prize heals")
	assert_true(lost_hp, "broken heart costs health")
	assert_true(got_sticker, "suit sticker prizes land in inventory")
	assert_true(got_relic, "relic prize grants a relic")
	assert_gt(run.machine.reels.size(), reels_before, "1% extra reel hits across 400 spins")


func test_broken_heart_never_kills() -> void:
	var run := RunState.new()
	run.coins = 100000
	run.hp = 1
	for seed_value in 100:
		CasinoGame.spin(_db, run, _rng(seed_value))
		assert_gte(run.hp, 1, "casino misfortune leaves at least 1 HP")