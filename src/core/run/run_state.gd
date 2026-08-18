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
