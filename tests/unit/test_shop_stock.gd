extends GutTest
## ShopStock: pricing formulas and stock generation.
## Extra reel: 100 + 50 per previously bought reel, cap 8 reels.
## Stickers (one per suit): 20 + 5 x encounter number.
## Relics x3 @ 150-200, abilities x4 @ 50-100, from unowned pools.

var _db: ContentDB


func before_all() -> void:
	_db = ContentDB.new()
	assert_true(_db.load_all("res://data"), str(_db.errors))


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	return rng


func test_reel_price_scales_with_previous_purchases() -> void:
	var run := RunState.new()
	var stock := ShopStock.generate(_db, run, _rng())
	assert_eq(stock.reel.price, 100)
	run.machine.add_reel()
	run.machine.add_reel()
	stock = ShopStock.generate(_db, run, _rng())
	assert_eq(stock.reel.price, 200)
	assert_true(stock.reel.available)


func test_reel_unavailable_at_max() -> void:
	var run := RunState.new()
	while run.machine.add_reel():
		pass
	var stock := ShopStock.generate(_db, run, _rng())
	assert_false(stock.reel.available)


func test_sticker_prices_scale_with_encounter_and_cover_all_suits() -> void:
	var run := RunState.new()
	for i in 4:
		run.record_visit(&"combat")  # next encounter = 5
	var stock := ShopStock.generate(_db, run, _rng())
	assert_eq(stock.stickers.size(), 4)
	var suits: Array[StringName] = []
	for sticker: Dictionary in stock.stickers:
		assert_eq(sticker.price, 20 + 5 * 5)
		suits.append(sticker.suit)
	for suit: StringName in ContentDB.SUITS:
		assert_has(suits, suit)


func test_relic_offers_are_unowned_distinct_and_priced() -> void:
	var run := RunState.new()
	run.relic_ids = [&"gold_tooth"]
	var stock := ShopStock.generate(_db, run, _rng())
	assert_eq(stock.relics.size(), 3)
	var seen: Array[StringName] = []
	for offer: Dictionary in stock.relics:
		assert_between(offer.price, 150, 200)
		assert_does_not_have(run.relic_ids, offer.id)
		assert_does_not_have(seen, offer.id)
		seen.append(offer.id)


func test_ability_offers_exclude_owned_and_starters() -> void:
	var run := RunState.new()
	run.ability_ids = [&"card_flick", &"dagger_throw", &"card_guard", &"shuffle"]
	var stock := ShopStock.generate(_db, run, _rng())
	assert_between(stock.abilities.size(), 1, 4)
	for offer: Dictionary in stock.abilities:
		assert_between(offer.price, 50, 100)
		assert_does_not_have(run.ability_ids, offer.id)
		assert_ne(_db.get_ability(offer.id).pool, "starter")


func test_exhausted_pools_leave_slots_empty() -> void:
	var run := RunState.new()
	for id in _db.all_relic_ids():
		run.relic_ids.append(id)
	for id in _db.all_ability_ids():
		run.ability_ids.append(id)
	var stock := ShopStock.generate(_db, run, _rng())
	assert_eq(stock.relics.size(), 0)
	assert_eq(stock.abilities.size(), 0)
