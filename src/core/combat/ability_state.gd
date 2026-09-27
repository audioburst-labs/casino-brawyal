class_name AbilityState
extends RefCounted
## An owned ability during combat: its definition plus the chips currently
## socketed into its cost slots. Partially filled slots persist across rounds;
## everything clears when the ability fires or the encounter ends.

var def: Defs.AbilityDef
var filled: Array[StringName] = []  # one entry per cost slot; &"" = empty
var uses_this_round := 0            # for per_turn-limited abilities
var uses_this_combat := 0           # for per_combat-limited abilities


## Spent for this round, either way: per_turn resets at the round start,
## per_combat never does (sheet v0.19 — House Edge and Face Reader).
func exhausted() -> bool:
	if def.per_turn > 0 and uses_this_round >= def.per_turn:
		return true
	return def.per_combat > 0 and uses_this_combat >= def.per_combat


func _init(ability_def: Defs.AbilityDef) -> void:
	def = ability_def
	for i in def.cost.size():
		filled.append(&"")


func can_accept(slot_index: int, suit: StringName) -> bool:
	if slot_index < 0 or slot_index >= filled.size() or filled[slot_index] != &"":
		return false
	var required := def.cost[slot_index]
	return required == &"any" or required == suit


## Where a chip dropped on the CARD rather than on a socket should go (doc
## "Chip Placement on Abilities", patch 0.117): the first empty slot that
## asks for this exact suit, else the leftmost empty generic slot, else -1.
## Pure, so the presenter's drop handler and the tests agree.
func placement_slot(suit: StringName) -> int:
	for i in filled.size():
		if filled[i] == &"" and def.cost[i] == suit:
			return i
	for i in filled.size():
		if filled[i] == &"" and def.cost[i] == &"any":
			return i
	return -1


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
