class_name RunState
extends RefCounted
## Everything that persists across one run: hero condition, economy, the
## machine, owned content, and the encounter history the map generator reads.
##
## Ability loadout (doc "Ability Choosing Screen"): `ability_ids` is everything
## owned; at most EQUIP_CAP of them are equipped, and one more can sit in the
## trash slot, deleted when combat begins. There is no middle tier as of v0.20
## — an owned ability is either in the battle line or on its way out.

const EQUIP_CAP := 6

var hero_id: StringName = &"ace"
var hp := 70
var max_hp := 70
var coins := 0
var machine := SlotMachine.new()
var ability_ids: Array[StringName] = []
var equipped_ids: Array[StringName] = []
var trash_id: StringName = &""
## Ability id -> owned tier (0 base, 1 silver, 2 gold). Absent means base.
## Kept beside `ability_ids` rather than encoded into the id, because the id is
## the ability's identity everywhere else in the run and combat layers.
var ability_tiers: Dictionary = {}
var needs_loadout := false
var relic_ids: Array[StringName] = []
var seed_value := 0
## Which of the doc's six Paths this run walks (patch 0.114). Rolled the first
## time the map is asked for options; "" on a pre-0.114 save, which simply
## means that save gets one at its next map screen.
var path_id: StringName = &""
var history: Array[StringName] = []   # encounter type per completed choice
var seen_events: Array[StringName] = []
var sticker_inventory: Array[StringName] = []  # bought, unplaced sticker suits
var shop_offers := 0                           # shop options shown so far (>= 2 guaranteed)
## The encounter being played right now, saved with the run so that leaving
## for the main menu mid-encounter resumes it from its beginning instead of
## skipping it (0.0.111). Free-form JSON: at least {"type"}; combat adds the
## lineup and seed so the same fight comes back, screens may stash more.
## Empty once the encounter is finished or its outcome is banked.
var pending_encounter: Dictionary = {}


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


func ability_tier(id: StringName) -> int:
	return int(ability_tiers.get(id, 0))


## True while this ability still has somewhere to go (doc "Ability Upgrades":
## a gold ability leaves the pool until the player trashes it).
func can_upgrade(id: StringName) -> bool:
	return ability_tier(id) < ContentDB.MAX_TIER


## Auto-funnel (doc "Ability Choosing Screen"): Equipped first, then the Trash
## slot — replacing and deleting its previous occupant — never displacing
## others. There is no third "unequipped" tier as of v0.20: an ability the
## hero owns is either in the battle line or on its way to the bin.
##
## A duplicate upgrades instead of stacking (doc v0.19) — the hero never holds
## two copies of the same ability.
func acquire_ability(id: StringName) -> void:
	if ability_ids.has(id):
		ability_tiers[id] = mini(ability_tier(id) + 1, ContentDB.MAX_TIER)
		return
	if equipped_ids.size() < EQUIP_CAP:
		ability_ids.append(id)
		equipped_ids.append(id)
		return
	if trash_id != &"":
		_forget(trash_id)
	ability_ids.append(id)
	trash_id = id
	needs_loadout = true


func equip(id: StringName) -> bool:
	if equipped_ids.size() >= EQUIP_CAP or equipped_ids.has(id) \
			or not ability_ids.has(id) or id == trash_id:
		return false
	equipped_ids.append(id)
	return true


func move_to_trash(id: StringName) -> bool:
	if not ability_ids.has(id) or id == trash_id:
		return false
	if trash_id != &"":
		_forget(trash_id)  # old occupant is deleted for good
	equipped_ids.erase(id)
	trash_id = id
	return true


## Ability Choosing screen (0.0.111): dropping one ability onto another swaps
## them — two equipped abilities exchange positions, and an equipped one
## dropped on the trashed one rescues it while taking its place in the bin.
func swap_abilities(a: StringName, b: StringName) -> bool:
	if a == b or not ability_ids.has(a) or not ability_ids.has(b):
		return false
	var index_a := equipped_ids.find(a)
	var index_b := equipped_ids.find(b)
	if index_a >= 0 and index_b >= 0:
		equipped_ids[index_a] = b
		equipped_ids[index_b] = a
		return true
	if index_a >= 0 and b == trash_id:
		equipped_ids[index_a] = b
		trash_id = a
		return true
	if index_b >= 0 and a == trash_id:
		equipped_ids[index_b] = a
		trash_id = b
		return true
	return false


func restore_from_trash() -> bool:
	if trash_id == &"":
		return false
	if equipped_ids.size() >= EQUIP_CAP:
		return false   # nowhere to put it back
	equipped_ids.append(trash_id)
	trash_id = &""
	return true


## The trash empties for good when the next combat begins (doc v0.11).
func process_trash() -> void:
	if trash_id != &"":
		_forget(trash_id)
		trash_id = &""
	needs_loadout = false


## Removes an ability for good, tier included — a trashed gold ability returns
## to the offer pool at base, per the doc.
func _forget(id: StringName) -> void:
	ability_ids.erase(id)
	ability_tiers.erase(id)


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
		"path_id": String(path_id),
		"ability_ids": ability_ids.map(func(s: StringName) -> String: return String(s)),
		"equipped_ids": equipped_ids.map(func(s: StringName) -> String: return String(s)),
		"trash_id": String(trash_id),
		"ability_tiers": _tiers_to_dict(),
		"needs_loadout": needs_loadout,
		"relic_ids": relic_ids.map(func(s: StringName) -> String: return String(s)),
		"sticker_inventory": sticker_inventory.map(func(s: StringName) -> String: return String(s)),
		"seen_events": seen_events.map(func(s: StringName) -> String: return String(s)),
		"history": history.map(func(s: StringName) -> String: return String(s)),
		"reels": reels,
		"shop_offers": shop_offers,
		"pending_encounter": pending_encounter,
	}


## StringName keys do not survive JSON; write them as plain strings.
func _tiers_to_dict() -> Dictionary:
	var out := {}
	for id: StringName in ability_tiers:
		out[String(id)] = int(ability_tiers[id])
	return out


static func from_dict(data: Dictionary) -> RunState:
	var run := RunState.new()
	run.hero_id = StringName(str(data.get("hero_id", "ace")))
	run.hp = int(data.get("hp", 1))
	run.max_hp = int(data.get("max_hp", 1))
	run.coins = int(data.get("coins", 0))
	run.seed_value = int(data.get("seed_value", 0))
	run.path_id = StringName(str(data.get("path_id", "")))
	for id in data.get("ability_ids", []):
		run.ability_ids.append(StringName(str(id)))
	for id in data.get("equipped_ids", []):
		run.equipped_ids.append(StringName(str(id)))
	run.trash_id = StringName(str(data.get("trash_id", "")))
	# Saves written before v0.19 have no tiers; everything defaults to base.
	var tiers: Dictionary = data.get("ability_tiers", {})
	for id in tiers:
		run.ability_tiers[StringName(str(id))] = int(tiers[id])
	run.needs_loadout = bool(data.get("needs_loadout", false))
	for id in data.get("relic_ids", []):
		run.relic_ids.append(StringName(str(id)))
	for suit in data.get("sticker_inventory", []):
		run.sticker_inventory.append(StringName(str(suit)))
	for id in data.get("seen_events", []):
		run.seen_events.append(StringName(str(id)))
	for type in data.get("history", []):
		# Patch 0.22 renamed Hard Combat to Elite; an in-flight save keeps
		# playing rather than tripping the placement rules.
		var visited := StringName(str(type))
		run.history.append(&"elite" if visited == &"hard_combat" else visited)
	run.shop_offers = int(data.get("shop_offers", 0))
	var pending: Variant = data.get("pending_encounter", {})
	if pending is Dictionary:
		run.pending_encounter = pending
		if str(run.pending_encounter.get("type", "")) == "hard_combat":
			run.pending_encounter["type"] = "elite"
			run.pending_encounter.erase("variant")
	var reels: Array = data.get("reels", [])
	while run.machine.reels.size() < reels.size():
		run.machine.add_reel()
	for reel_index in reels.size():
		for slot_index in (reels[reel_index] as Array).size():
			run.machine.reels[reel_index].symbols[slot_index] = \
				StringName(str(reels[reel_index][slot_index]))
	return run
