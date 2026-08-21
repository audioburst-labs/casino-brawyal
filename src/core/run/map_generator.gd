class_name MapGenerator
extends RefCounted
## Generates the next encounter choice lazily from the run history.
## Placement rules (design doc + patch 0.1 "Ori fixes"):
##   #1 always Combat (auto-start) - #10 always Boss
##   Rest offered only at #4 and #9 - the final Shop option appears at #9
##   Shop: max 3 visits, never right after a visited shop, never at #2,
##   and at least 2 shop OFFERS per run (forced late if needed)
##   Treasure: max 2 visits, only after #2, never right after a treasure
##   Hard Combat: only after #3 - the two options always differ in type


static func next_options(run: RunState, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var encounter := run.encounter_number()
	if encounter == 1:
		return [{"type": &"combat"}]
	if encounter == 10:
		return [{"type": &"boss"}]
	if encounter == 4 or encounter == 9:
		# Rest slots. #9 pairs Rest with the guaranteed final Shop when allowed.
		var partner: Dictionary
		if encounter == 9 and _shop_allowed(run):
			partner = {"type": &"shop"}
			run.shop_offers += 1
		else:
			partner = _roll_option(run, rng, [&"rest"])
		return [partner, {"type": &"rest"}]

	# At least 2 shop offers per run: if only #9's guaranteed shop is left,
	# force one now (encounters 6-8 qualify).
	if encounter >= 6 and encounter <= 8 and run.shop_offers < 1 and _shop_allowed(run):
		run.shop_offers += 1
		return [{"type": &"shop"}, _roll_option(run, rng, [&"shop"])]

	var first := _roll_option(run, rng, [])
	var second := _roll_option(run, rng, [first.type])
	for option in [first, second]:
		if option.type == &"shop":
			run.shop_offers += 1
	return [first, second]


static func _shop_allowed(run: RunState) -> bool:
	return run.encounter_number() != 2 \
		and run.count_visited(&"shop") < 3 \
		and run.last_visited() != &"shop"


static func _treasure_allowed(run: RunState) -> bool:
	return run.encounter_number() > 2 \
		and run.count_visited(&"treasure") < 2 \
		and run.last_visited() != &"treasure"


static func _casino_allowed(run: RunState) -> bool:
	return run.encounter_number() > 1 \
		and run.count_visited(&"casino") < 2 \
		and run.last_visited() != &"casino"


## Rolls one weighted option whose type is not in `exclude`.
static func _roll_option(run: RunState, rng: RandomNumberGenerator,
		exclude: Array[StringName]) -> Dictionary:
	var pool: Array[Dictionary] = []  # {type, weight}
	pool.append({"type": &"combat", "weight": 4})
	pool.append({"type": &"story", "weight": 3})
	if run.encounter_number() > 3:
		pool.append({"type": &"hard_combat", "weight": 2})
	if _shop_allowed(run):
		pool.append({"type": &"shop", "weight": 2})
	if _treasure_allowed(run):
		pool.append({"type": &"treasure", "weight": 2})
	if _casino_allowed(run):
		pool.append({"type": &"casino", "weight": 2})

	var candidates := pool.filter(
		func(entry: Dictionary) -> bool: return not exclude.has(entry.type))
	var total := 0
	for entry: Dictionary in candidates:
		total += int(entry.weight)
	var roll := rng.randi_range(1, total)
	for entry: Dictionary in candidates:
		roll -= int(entry.weight)
		if roll <= 0:
			return _finalize(entry.type, rng)
	return _finalize(&"combat", rng)


static func _finalize(type: StringName, rng: RandomNumberGenerator) -> Dictionary:
	if type == &"hard_combat":
		var variant := "buffed" if rng.randi_range(0, 1) == 0 else "advanced"
		return {"type": type, "variant": variant}
	return {"type": type}
