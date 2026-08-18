class_name AbilityState
extends RefCounted
## An owned ability during combat: its definition plus the chips currently
## socketed into its cost slots. Partially filled slots persist across rounds;
## everything clears when the ability fires or the encounter ends.

var def: Defs.AbilityDef
var filled: Array[StringName] = []  # one entry per cost slot; &"" = empty


func _init(ability_def: Defs.AbilityDef) -> void:
	def = ability_def
	for i in def.cost.size():
		filled.append(&"")


func can_accept(slot_index: int, suit: StringName) -> bool:
	if slot_index < 0 or slot_index >= filled.size() or filled[slot_index] != &"":
		return false
	var required := def.cost[slot_index]
	return required == &"any" or required == suit


func fill(slot_index: int, suit: StringName) -> void:
	filled[slot_index] = suit


## Empties a slot and returns the chip suit that was in it (&"" if empty).
func unfill(slot_index: int) -> StringName:
	var suit := filled[slot_index]
	filled[slot_index] = &""
	return suit


func is_full() -> bool:
	return not filled.has(&"")


## True when the suit-bonus condition is met by the socketed chips.
func bonus_active() -> bool:
	if def.bonus_suit == &"" or def.bonus_condition != "all_slots_bonus_suit":
		return false
	for suit in filled:
		if suit != def.bonus_suit:
			return false
	return true


func clear() -> void:
	for i in filled.size():
		filled[i] = &""
