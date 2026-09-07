class_name ShopStock
extends RefCounted
## Generates one shop visit's stock and prices, per the design doc's economy
## (per-lineup gold rewards, relic prices from the capabilities sheet):
##   Extra Reel: 50 + 50 per previously purchased reel, machine cap 8
##   Symbol Stickers x4 (one per suit): 20 + 5 x encounter number
##   Relics x3 priced per their sheet range, Abilities x4 @ 30-50 (new or an
##   upgrade of one already owned, same price either way);
##   slots stay empty when a pool runs out.

const REEL_BASE_PRICE := 50
const REEL_PRICE_STEP := 50


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

	var sticker_price := 20 + 5 * run.encounter_number()
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

	# Same pool as the reward screen (doc v0.19: "4 abilities from the available
	# pool", not "4 unowned"), and the same 30-50 band whether the slot is a new
	# ability or an upgrade of one already owned.
	var ability_pool := Rewards.upgradeable_pool(db, run)
	for i in mini(4, ability_pool.size()):
		var index := rng.randi_range(0, ability_pool.size() - 1)
		var id: StringName = ability_pool[index]
		stock.abilities.append({
			"id": id,
			"price": rng.randi_range(30, 50),
			"upgrade": run.ability_ids.has(id),
			"tier": run.ability_tier(id),
		})
		ability_pool.remove_at(index)

	return stock
