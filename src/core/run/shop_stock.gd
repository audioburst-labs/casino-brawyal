class_name ShopStock
extends RefCounted
## Generates one shop visit's stock and prices, scaled to the patch 0.1
## economy (per-lineup gold rewards, relic prices from the capabilities sheet):
##   Extra Reel: 60 + 30 per previously purchased reel, machine cap 8
##   Symbol Stickers x4 (one per suit): 10 + 2 x encounter number
##   Relics x3 priced per their sheet range, Abilities x4 @ 20-40;
##   slots stay empty when a pool runs out.

const REEL_BASE_PRICE := 60
const REEL_PRICE_STEP := 30


static func generate(db: ContentDB, run: RunState, rng: RandomNumberGenerator) -> Dictionary:
	var reels_bought := run.machine.reels.size() - SlotMachine.START_REELS
	var stock := {
		"reel": {
			"price": REEL_BASE_PRICE + REEL_PRICE_STEP * reels_bought,
			"available": run.machine.reels.size() < SlotMachine.MAX_REELS,
		},
		"stickers": [],
		"relics": [],
		"abilities": [],
	}

	var sticker_price := 10 + 2 * run.encounter_number()
	for suit: StringName in ContentDB.SUITS:
		stock.stickers.append({"suit": suit, "price": sticker_price})

	var relic_pool: Array[StringName] = []
	for id: StringName in db.all_relic_ids():
		if not run.relic_ids.has(id):
			relic_pool.append(id)
	for i in mini(3, relic_pool.size()):
		var index := rng.randi_range(0, relic_pool.size() - 1)
		var relic := db.get_relic(relic_pool[index])
		stock.relics.append({
			"id": relic.id,
			"price": rng.randi_range(relic.price_min, relic.price_max),
		})
		relic_pool.remove_at(index)

	var ability_pool: Array[StringName] = []
	for id: StringName in db.all_ability_ids():
		if not run.ability_ids.has(id) and db.get_ability(id).pool != "starter":
			ability_pool.append(id)
	for i in mini(4, ability_pool.size()):
		var index := rng.randi_range(0, ability_pool.size() - 1)
		stock.abilities.append({"id": ability_pool[index], "price": rng.randi_range(20, 40)})
		ability_pool.remove_at(index)

	return stock
