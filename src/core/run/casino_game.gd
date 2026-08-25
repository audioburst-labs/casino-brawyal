class_name CasinoGame
extends RefCounted
## The Casino encounter's slot machine, per doc v0.13:
## one paid spin costs [5 x encounter number]; each of the 3 reels lands a
## percentage-weighted prize; three of a kind grants a free extra spin.

const COST_PER_ENCOUNTER := 5

## Doc percentage table (weights out of 100 per reel).
const PRIZES := [
	{"id": &"coins", "weight": 20},          # +5 x encounter coins
	{"id": &"heart", "weight": 20},          # heal 1 x encounter
	{"id": &"broken_heart", "weight": 10},   # lose 1 x encounter (never fatal)
	{"id": &"sticker_spade", "weight": 10},
	{"id": &"sticker_heart", "weight": 10},
	{"id": &"sticker_club", "weight": 10},
	{"id": &"sticker_diamond", "weight": 10},
	{"id": &"relic", "weight": 5},
	{"id": &"money_sack", "weight": 4},      # +10 x encounter coins
	{"id": &"extra_reel", "weight": 1},
]


static func spin_cost(run: RunState) -> int:
	return COST_PER_ENCOUNTER * run.encounter_number()


## Pays for and resolves one spin. Returns {} when the run can't afford it,
## else {symbols, lines, free_respin, cost}. A free spin skips the cost.
static func spin(db: ContentDB, run: RunState, rng: RandomNumberGenerator,
		free := false) -> Dictionary:
	var cost := spin_cost(run)
	if not free and not run.spend(cost):
		return {}
	var symbols: Array[StringName] = []
	for i in 3:
		symbols.append(_draw(rng))
	var lines: Array[String] = []
	for symbol in symbols:
		lines.append(_award(symbol, db, run, rng))
	var free_respin := symbols[0] == symbols[1] and symbols[1] == symbols[2]
	if free_respin:
		lines.append("THREE OF A KIND — free spin!")
	return {"symbols": symbols, "lines": lines, "free_respin": free_respin, "cost": cost}


static func _draw(rng: RandomNumberGenerator) -> StringName:
	var roll := rng.randi_range(1, 100)
	for prize: Dictionary in PRIZES:
		roll -= int(prize.weight)
		if roll <= 0:
			return prize.id
	return &"coins"


static func _award(symbol: StringName, db: ContentDB, run: RunState,
		rng: RandomNumberGenerator) -> String:
	var encounter := run.encounter_number()
	match symbol:
		&"coins":
			run.coins += 5 * encounter
			return "+%d coins" % (5 * encounter)
		&"money_sack":
			run.coins += 10 * encounter
			return "Money sack: +%d coins!" % (10 * encounter)
		&"heart":
			var healed: int = mini(1 * encounter, run.max_hp - run.hp)
			run.hp += healed
			return "+%d HP" % healed
		&"broken_heart":
			var loss: int = mini(1 * encounter, run.hp - 1)  # never fatal
			run.hp -= loss
			return "Broken heart: -%d HP" % loss
		&"sticker_spade", &"sticker_heart", &"sticker_club", &"sticker_diamond":
			var suit := StringName(String(symbol).trim_prefix("sticker_"))
			run.sticker_inventory.append(suit)
			return "%s sticker!" % String(suit).capitalize()
		&"relic":
			var relic := Rewards.random_unowned_relic(db, run, rng)
			if relic == &"":
				run.coins += 5 * encounter
				return "+%d coins (no relics left)" % (5 * encounter)
			run.relic_ids.append(relic)
			return "Relic: %s!" % db.get_relic(relic).name
		&"extra_reel":
			if run.machine.add_reel():
				return "EXTRA REEL! Your machine grows!"
			run.coins += 10 * encounter
			return "+%d coins (machine is maxed)" % (10 * encounter)
	return ""
