class_name CasinoGame
extends RefCounted
## The Casino encounter's slot machine, per doc v0.120: the one spin is free
## (the v0.13 entry fee is gone); each of the 3 reels lands a
## percentage-weighted prize; three of a kind grants a free extra spin.

## Doc percentage table (weights out of 100 per reel). Broken Coins is new in
## v0.120 and took half of Coins' and Heart's old shares.
const PRIZES := [
	{"id": &"coins", "weight": 10},          # +5 x encounter coins
	{"id": &"broken_coins", "weight": 10},   # -5 x encounter coins (floor 0)
	{"id": &"empty_sack", "weight": 5},      # -10 x encounter coins (0.114)
	{"id": &"heart", "weight": 10},          # heal 1 x encounter
	{"id": &"broken_heart", "weight": 10},   # lose 1 x encounter (never fatal)
	{"id": &"broken_hearts", "weight": 5},   # lose 2 x encounter (0.114)
	# The four stickers halved from 10 to 5 in the 0.122 doc, which is what
	# made room for the two new losing faces.
	{"id": &"sticker_spade", "weight": 5},
	{"id": &"sticker_heart", "weight": 5},
	{"id": &"sticker_club", "weight": 5},
	{"id": &"sticker_diamond", "weight": 5},
	{"id": &"relic", "weight": 5},
	{"id": &"money_sack", "weight": 4},      # +10 x encounter coins
	{"id": &"extra_reel", "weight": 1},
]


## Resolves one spin: {symbols, relics, lines, free_respin}. Spins cost
## nothing since doc v0.120 — the screen limits the player to one visit's
## spin plus any free re-spins a triple earns.
static func spin(db: ContentDB, run: RunState, rng: RandomNumberGenerator) -> Dictionary:
	var symbols: Array[StringName] = []
	for i in 3:
		symbols.append(_draw(rng))
	var lines: Array[String] = []
	# Which relic each reel actually landed, parallel to `symbols` (&"" where
	# the prize was not a relic). Patch 0.19: the presenter needs this to draw
	# the relic that was won instead of one stand-in chip for all of them.
	var relics: Array[StringName] = []
	for symbol in symbols:
		var before := run.relic_ids.size()
		lines.append(_award(symbol, db, run, rng))
		relics.append(run.relic_ids[-1] if run.relic_ids.size() > before else &"")
	var free_respin := symbols[0] == symbols[1] and symbols[1] == symbols[2]
	if free_respin:
		lines.append("THREE OF A KIND — free spin!")
	return {"symbols": symbols, "relics": relics, "lines": lines,
		"free_respin": free_respin}


## The doc's table adds up to 90, not 100; rolling over the real total keeps
## every listed percentage in proportion instead of handing the gap to Coins.
static func total_weight() -> int:
	var total := 0
	for prize: Dictionary in PRIZES:
		total += int(prize.weight)
	return total


static func _draw(rng: RandomNumberGenerator) -> StringName:
	var roll := rng.randi_range(1, total_weight())
	for prize: Dictionary in PRIZES:
		roll -= int(prize.weight)
		if roll <= 0:
			return prize.id
	return PRIZES[0].id


static func _award(symbol: StringName, db: ContentDB, run: RunState,
		rng: RandomNumberGenerator) -> String:
	var encounter := run.encounter_number()
	match symbol:
		&"coins":
			run.coins += 5 * encounter
			return "+%d coins" % (5 * encounter)
		&"broken_coins":
			var lost: int = mini(5 * encounter, run.coins)
			run.coins -= lost
			return "Broken coins: -%d coins" % lost
		&"empty_sack":
			var emptied: int = mini(10 * encounter, run.coins)
			run.coins -= emptied
			return "Empty money sack: -%d coins" % emptied
		&"money_sack":
			run.coins += 10 * encounter
			return "Money sack: +%d coins!" % (10 * encounter)
		&"heart":
			var roll := 1 * encounter
			var healed: int = mini(roll, run.max_hp - run.hp)
			run.hp += healed
			# Show the roll even when it's capped by missing HP (patch 0.17),
			# instead of a bare "+0 HP" with no explanation.
			if healed < roll:
				return "Heal %d (+%d HP, already near full)" % [roll, healed]
			return "+%d HP" % healed
		&"broken_heart":
			var loss: int = mini(1 * encounter, run.hp - 1)  # never fatal
			run.hp -= loss
			return "Broken heart: -%d HP" % loss
		&"broken_hearts":
			var wounds: int = mini(2 * encounter, run.hp - 1)  # never fatal
			run.hp -= wounds
			return "Broken hearts: -%d HP" % wounds
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
