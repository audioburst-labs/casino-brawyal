class_name CasinoGame
extends RefCounted
## The Casino encounter's slot machine (doc v0.11): pay SPIN_COST per spin,
## receive every landed prize; three of a kind grants a free extra spin.

const SPIN_COST := 10

## Prize symbols with weights. Textures are resolved by the casino screen.
const PRIZES := [
	{"id": &"coin_small", "weight": 4},
	{"id": &"heal", "weight": 3},
	{"id": &"coin_big", "weight": 2},
	{"id": &"sticker", "weight": 2},
	{"id": &"relic", "weight": 1},
]


## Pays for and resolves one spin. Returns {} when the run can't afford it,
## else {symbols: Array[StringName], lines: Array[String], free_respin: bool}.
## A free spin (earned by three of a kind) skips the cost.
static func spin(db: ContentDB, run: RunState, rng: RandomNumberGenerator,
		free := false) -> Dictionary:
	if not free and not run.spend(SPIN_COST):
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
	return {"symbols": symbols, "lines": lines, "free_respin": free_respin}


static func _draw(rng: RandomNumberGenerator) -> StringName:
	var total := 0
	for prize: Dictionary in PRIZES:
		total += int(prize.weight)
	var roll := rng.randi_range(1, total)
	for prize: Dictionary in PRIZES:
		roll -= int(prize.weight)
		if roll <= 0:
			return prize.id
	return &"coin_small"


static func _award(symbol: StringName, db: ContentDB, run: RunState,
		rng: RandomNumberGenerator) -> String:
	match symbol:
		&"coin_small":
			run.coins += 10
			return "+10 coins"
		&"coin_big":
			run.coins += 25
			return "+25 coins"
		&"heal":
			var healed: int = mini(10, run.max_hp - run.hp)
			run.hp += healed
			return "+%d HP" % healed
		&"sticker":
			var suit: StringName = ContentDB.SUITS[rng.randi_range(0, ContentDB.SUITS.size() - 1)]
			run.sticker_inventory.append(suit)
			return "%s sticker!" % String(suit).capitalize()
		&"relic":
			var relic := Rewards.random_unowned_relic(db, run, rng)
			if relic == &"":
				run.coins += 15
				return "+15 coins (no relics left)"
			run.relic_ids.append(relic)
			return "Relic: %s!" % db.get_relic(relic).name
	return ""
