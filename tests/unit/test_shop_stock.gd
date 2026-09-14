extends GutTest
## ShopStock: pricing formulas and stock generation.
## Extra reel: 50 + 50 per previously bought reel, cap 8 reels.
## Stickers (one per suit): 10 + 5 x encounter number (doc v0.121).
## Relics x3 priced per their sheet range, abilities x4 @ 30-50, unowned pools.

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
	assert_eq(stock.reel.price, 50)
	run.machine.add_reel()
	run.machine.add_reel()
	stock = ShopStock.generate(_db, run, _rng())
	assert_eq(stock.reel.price, 150)
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
		assert_eq(sticker.price, 10 + 5 * 5)
		suits.append(sticker.suit)
	for suit: StringName in ContentDB.SUITS:
		assert_has(suits, suit)


func test_relic_offers_are_unowned_distinct_and_priced_per_sheet() -> void:
	var run := RunState.new()
	run.relic_ids = [&"bounty_list"]
	var stock := ShopStock.generate(_db, run, _rng())
	assert_eq(stock.relics.size(), 3)
	var seen: Array[StringName] = []
	for offer: Dictionary in stock.relics:
		var def := _db.get_relic(offer.id)
		assert_between(offer.price, def.price_min, def.price_max)
		assert_does_not_have(run.relic_ids, offer.id)
		assert_does_not_have(seen, offer.id)
		seen.append(offer.id)


## v0.19: the shelf stocks anything that can still improve, new or owned, at
## one 30-50 band either way. Starters are in the pool like everything else.
func test_ability_offers_cover_new_and_upgrades_at_one_price() -> void:
	var run := RunState.new()
	run.ability_ids = [&"card_sling", &"quick_maneuvers", &"color_up", &"double_down"]
	var stock := ShopStock.generate(_db, run, _rng())
	assert_between(stock.abilities.size(), 1, 4)
	for offer: Dictionary in stock.abilities:
		assert_between(offer.price, 30, 50)
		assert_true(run.can_upgrade(offer.id), "%s can still improve" % offer.id)
		assert_eq(bool(offer.upgrade), run.ability_ids.has(offer.id),
			"the shelf knows whether it is selling an upgrade")


func test_exhausted_pools_leave_slots_empty() -> void:
	var run := RunState.new()
	for id in _db.all_relic_ids():
		run.relic_ids.append(id)
	for id in _db.all_ability_ids():
		run.ability_ids.append(id)
		run.ability_tiers[id] = ContentDB.MAX_TIER  # nothing left to improve
	var stock := ShopStock.generate(_db, run, _rng())
	assert_eq(stock.relics.size(), 0)
	assert_eq(stock.abilities.size(), 0)
