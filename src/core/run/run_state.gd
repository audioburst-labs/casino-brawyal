class_name RunState
extends RefCounted
## Everything that persists across one run: hero condition, economy, the
## machine, owned content, and the encounter history the map generator reads.
##
## Ability loadout (doc v0.11): `ability_ids` is everything owned; at most
## EQUIP_CAP of them are equipped (used in combat), at most STORAGE_CAP sit in
## storage, and one can sit in the trash slot — deleted when combat begins.

const EQUIP_CAP := 6
const STORAGE_CAP := 6

var hero_id: StringName = &"ace"
var hp := 70
var max_hp := 70
var coins := 0
var machine := SlotMachine.new()
var ability_ids: Array[StringName] = []
var equipped_ids: Array[StringName] = []
var trash_id: StringName = &""
var needs_loadout := false
var relic_ids: Array[StringName] = []
var seed_value := 0
var history: Array[StringName] = []   # encounter type per completed choice
var seen_events: Array[StringName] = []
var sticker_inventory: Array[StringName] = []  # bought, unplaced sticker suits
var shop_offers := 0                           # shop options shown so far (>= 2 guaranteed)


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


func stored_ids() -> Array[StringName]:
	var stored: Array[StringName] = []
	for id in ability_ids:
		if not equipped_ids.has(id) and id != trash_id:
			stored.append(id)
	return stored


## Auto-funnel (doc v0.11): Equipped first, then Storage, then the Trash slot
## (replacing and deleting its previous occupant), never displacing others.
func acquire_ability(id: StringName) -> void:
	if equipped_ids.size() < EQUIP_CAP:
		ability_ids.append(id)
		equipped_ids.append(id)
		return
	if stored_ids().size() < STORAGE_CAP:
		ability_ids.append(id)
		needs_loadout = true
		return
	if trash_id != &"":
		ability_ids.erase(trash_id)
	ability_ids.append(id)
	trash_id = id
	needs_loadout = true


func equip(id: StringName) -> bool:
	if equipped_ids.size() >= EQUIP_CAP or equipped_ids.has(id) \
			or not ability_ids.has(id) or id == trash_id:
		return false
	equipped_ids.append(id)
	return true


func unequip(id: StringName) -> bool:
	if not equipped_ids.has(id) or stored_ids().size() >= STORAGE_CAP:
		return false
	equipped_ids.erase(id)
	return true


func move_to_trash(id: StringName) -> bool:
	if not ability_ids.has(id) or id == trash_id:
		return false
	if trash_id != &"":
		ability_ids.erase(trash_id)  # old occupant is deleted for good
	equipped_ids.erase(id)
	trash_id = id
	return true


func restore_from_trash() -> bool:
	if trash_id == &"":
		return false
	if equipped_ids.size() < EQUIP_CAP:
		equipped_ids.append(trash_id)
	elif stored_ids().size() >= STORAGE_CAP:
		return false
	trash_id = &""
	return true


## The trash empties for good when the next combat begins (doc v0.11).
func process_trash() -> void:
	if trash_id != &"":
		ability_ids.erase(trash_id)
		trash_id = &""
	needs_loadout = false


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
		"equipped_ids": equipped_ids.map(func(s: StringName) -> String: return String(s)),
		"trash_id": String(trash_id),
		"needs_loadout": needs_loadout,
		"relic_ids": relic_ids.map(func(s: StringName) -> String: return String(s)),
		"sticker_inventory": sticker_inventory.map(func(s: StringName) -> String: return String(s)),
		"seen_events": seen_events.map(func(s: StringName) -> String: return String(s)),
		"history": history.map(func(s: StringName) -> String: return String(s)),
		"reels": reels,
		"shop_offers": shop_offers,
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
	for id in data.get("equipped_ids", []):
		run.equipped_ids.append(StringName(str(id)))
	run.trash_id = StringName(str(data.get("trash_id", "")))
	run.needs_loadout = bool(data.get("needs_loadout", false))
	for id in data.get("relic_ids", []):
		run.relic_ids.append(StringName(str(id)))
	for suit in data.get("sticker_inventory", []):
		run.sticker_inventory.append(StringName(str(suit)))
	for id in data.get("seen_events", []):
		run.seen_events.append(StringName(str(id)))
	for type in data.get("history", []):
		run.history.append(StringName(str(type)))
	run.shop_offers = int(data.get("shop_offers", 0))
	var reels: Array = data.get("reels", [])
	while run.machine.reels.size() < reels.size():
		run.machine.add_reel()
	for reel_index in reels.size():
		for slot_index in (reels[reel_index] as Array).size():
			run.machine.reels[reel_index].symbols[slot_index] = \
				StringName(str(reels[reel_index][slot_index]))
	return run
