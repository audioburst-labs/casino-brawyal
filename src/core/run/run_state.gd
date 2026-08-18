class_name RunState
extends RefCounted
## Everything that persists across one run: hero condition, economy, the
## machine, owned content, and the encounter history the map generator reads.

var hero_id: StringName = &"ace"
var hp := 70
var max_hp := 70
var coins := 0
var machine := SlotMachine.new()
var ability_ids: Array[StringName] = []
var relic_ids: Array[StringName] = []
var seed_value := 0
var history: Array[StringName] = []   # encounter type per completed choice
var seen_events: Array[StringName] = []
var sticker_inventory: Array[StringName] = []  # bought, unplaced sticker suits


## 1-based number of the encounter the player is about to choose/play.
func encounter_number() -> int:
	return history.size() + 1


func record_visit(encounter_type: StringName) -> void:
	history.append(encounter_type)


func count_visited(encounter_type: StringName) -> int:
	return history.count(encounter_type)


func last_visited() -> StringName:
	return history[-1] if not history.is_empty() else &""


func spend(amount: int) -> bool:
	if coins < amount:
		return false
	coins -= amount
	return true


func to_dict() -> Dictionary:
	var reels: Array = []
	for reel in machine.reels:
		reels.append(reel.symbols.map(func(s: StringName) -> String: return String(s)))
	return {
		"hero_id": String(hero_id),
		"hp": hp,
		"max_hp": max_hp,
		"coins": coins,
		"seed_value": seed_value,
		"ability_ids": ability_ids.map(func(s: StringName) -> String: return String(s)),
		"relic_ids": relic_ids.map(func(s: StringName) -> String: return String(s)),
		"sticker_inventory": sticker_inventory.map(func(s: StringName) -> String: return String(s)),
		"seen_events": seen_events.map(func(s: StringName) -> String: return String(s)),
		"history": history.map(func(s: StringName) -> String: return String(s)),
		"reels": reels,
	}


static func from_dict(data: Dictionary) -> RunState:
	var run := RunState.new()
	run.hero_id = StringName(str(data.get("hero_id", "ace")))
	run.hp = int(data.get("hp", 1))
	run.max_hp = int(data.get("max_hp", 1))
	run.coins = int(data.get("coins", 0))
	run.seed_value = int(data.get("seed_value", 0))
	for id in data.get("ability_ids", []):
		run.ability_ids.append(StringName(str(id)))
	for id in data.get("relic_ids", []):
		run.relic_ids.append(StringName(str(id)))
	for suit in data.get("sticker_inventory", []):
		run.sticker_inventory.append(StringName(str(suit)))
	for id in data.get("seen_events", []):
		run.seen_events.append(StringName(str(id)))
	for type in data.get("history", []):
		run.history.append(StringName(str(type)))
	var reels: Array = data.get("reels", [])
	while run.machine.reels.size() < reels.size():
		run.machine.add_reel()
	for reel_index in reels.size():
		for slot_index in (reels[reel_index] as Array).size():
			run.machine.reels[reel_index].symbols[slot_index] = \
				StringName(str(reels[reel_index][slot_index]))
	return run
