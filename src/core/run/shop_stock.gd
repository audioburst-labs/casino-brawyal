class_name ShopStock
extends RefCounted
## Generates one shop visit's stock and prices (design doc):
##   Extra Reel: 100 + 50 per previously purchased reel, machine cap 8
##   Symbol Stickers x4 (one per suit): 20 + 5 x encounter number
##   Relics x3 @ 150-200, Abilities x4 @ 50-100 — random unowned;
##   slots stay empty when a pool runs out.


static func generate(db: ContentDB, run: RunState, rng: RandomNumberGenerator) -> Dictionary:
	var reels_bought := run.machine.reels.size() - SlotMachine.START_REELS
	var stock := {
		"reel": {
			"price": 100 + 50 * reels_bought,
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
		stock.relics.append({"id": relic_pool[index], "price": rng.randi_range(150, 200)})
		relic_pool.remove_at(index)

	var ability_pool: Array[StringName] = []
	for id: StringName in db.all_ability_ids():
		if not run.ability_ids.has(id) and db.get_ability(id).pool != "starter":
			ability_pool.append(id)
	for i in mini(4, ability_pool.size()):
		var index := rng.randi_range(0, ability_pool.size() - 1)
		stock.abilities.append({"id": ability_pool[index], "price": rng.randi_range(50, 100)})
		ability_pool.remove_at(index)

	return stock
