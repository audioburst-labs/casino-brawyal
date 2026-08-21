extends GutTest
## Casino encounter minigame (doc v0.11): a rewards slot machine.
## Pay 10 coins per spin; receive every landed prize; three of a kind
## grants a free extra spin.

var _db: ContentDB


func before_all() -> void:
	_db = ContentDB.new()
	assert_true(_db.load_all("res://data"), str(_db.errors))


func _rng(seed_value: int = 8) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func test_spin_costs_ten_coins_and_pays_prizes() -> void:
	var run := RunState.new()
	run.coins = 50
	var result := CasinoGame.spin(_db, run, _rng())
	assert_eq(result.symbols.size(), 3)
	assert_gte(run.coins, 40 - 25, "spent 10, may have won coins back")
	assert_gt(result.lines.size(), 0, "every prize reports a summary line")


func test_spin_refused_without_coins() -> void:
	var run := RunState.new()
	run.coins = 9
	var result := CasinoGame.spin(_db, run, _rng())
	assert_true(result.is_empty(), "cannot afford a spin")
	assert_eq(run.coins, 9)


func test_three_of_a_kind_grants_free_respin_flag() -> void:
	var run := RunState.new()
	run.coins = 10000
	var saw_triple := false
	for seed_value in 200:
		var result := CasinoGame.spin(_db, run, _rng(seed_value))
		if result.symbols[0] == result.symbols[1] and result.symbols[1] == result.symbols[2]:
			assert_true(result.free_respin, "triple grants a free spin")
			saw_triple = true
	assert_true(saw_triple, "200 seeds should roll at least one triple")


func test_prizes_actually_apply() -> void:
	var run := RunState.new()
	run.coins = 10000
	run.hp = 10
	run.max_hp = 80
	var got_heal := false
	var got_sticker := false
	var got_relic := false
	for seed_value in 300:
		CasinoGame.spin(_db, run, _rng(seed_value))
		got_heal = got_heal or run.hp > 10
		got_sticker = got_sticker or not run.sticker_inventory.is_empty()
		got_relic = got_relic or not run.relic_ids.is_empty()
	assert_true(got_heal, "heal prize applies HP")
	assert_true(got_sticker, "sticker prize lands in inventory")
	assert_true(got_relic, "relic prize grants a relic")
