class_name ShopStock
extends RefCounted
## Generates one shop visit's stock and prices, per the design doc's economy
## (per-lineup gold rewards, relic prices from the capabilities sheet):
##   Extra Reel: 75 + 75 per previously purchased reel (doc v0.121), cap 6
##   Symbol Stickers x4 (one per suit): 20 + 5 x encounter number
##   Relics x3 priced per their sheet range, Abilities x4 @ 30-50 (new or an
##   upgrade of one already owned, same price either way);
##   slots stay empty when a pool runs out.

const REEL_BASE_PRICE := 75
const REEL_PRICE_STEP := 75


## The Extra Reel's current price and availability, on its own — buying one
## re-prices the reel without disturbing the rest of the shelf (patch 0.20).
static func reel_offer(run: RunState) -> Dictionary:
	var reels_bought := run.machine.reels.size() - SlotMachine.START_REELS
	return {
		"price": REEL_BASE_PRICE + REEL_PRICE_STEP * reels_bought,
		"available": run.machine.reels.size() < SlotMachine.MAX_REELS,
	}


static func generate(db: ContentDB, run: RunState, rng: RandomNumberGenerator) -> Dictionary:
	var stock := {
		"reel": reel_offer(run),
		"stickers": [],
		"relics": [],
		"abilities": [],
	}

	# Doc v0.121: "Price: 10 Coins (+5 Coins x Encounter Number)" (was 20).
	var sticker_price := 10 + 5 * run.encounter_number()
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


## The stock as plain JSON (String keys and values), so a shop visit can ride
## in the run's `pending_encounter` and come back identical after an exit to
## the main menu — regenerating it would re-roll the shelf (0.0.111).
static func to_json(stock: Dictionary) -> Dictionary:
	return {
		"reel": {"price": int(stock.reel.price), "available": bool(stock.reel.available)},
		"stickers": stock.stickers.map(func(o: Dictionary) -> Dictionary:
			return {"suit": String(o.suit), "price": int(o.price)}),
		"relics": stock.relics.map(func(o: Dictionary) -> Dictionary:
			return {"id": String(o.id), "price": int(o.price)}),
		"abilities": stock.abilities.map(func(o: Dictionary) -> Dictionary:
			return {"id": String(o.id), "price": int(o.price),
				"upgrade": bool(o.upgrade), "tier": int(o.tier)}),
	}


static func from_json(data: Dictionary) -> Dictionary:
	var reel: Dictionary = data.get("reel", {})
	return {
		"reel": {"price": int(reel.get("price", 0)), "available": bool(reel.get("available", false))},
		"stickers": Array(data.get("stickers", [])).map(func(o: Dictionary) -> Dictionary:
			return {"suit": StringName(str(o.suit)), "price": int(o.price)}),
		"relics": Array(data.get("relics", [])).map(func(o: Dictionary) -> Dictionary:
			return {"id": StringName(str(o.id)), "price": int(o.price)}),
		"abilities": Array(data.get("abilities", [])).map(func(o: Dictionary) -> Dictionary:
			return {"id": StringName(str(o.id)), "price": int(o.price),
				"upgrade": bool(o.get("upgrade", false)), "tier": int(o.get("tier", 0))}),
	}
