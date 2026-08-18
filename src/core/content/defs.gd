class_name Defs
extends RefCounted
## Plain content definition classes, parsed from res://data JSON by ContentDB.
## Engine-agnostic on purpose: no Nodes, no Resources.


class AbilityDef:
	var id: StringName
	var name: String
	var cost: Array[StringName] = []          # suit per socket; &"any" = wildcard
	var effects: Array[Dictionary] = []       # effect ops, run by EffectInterpreter
	var bonus_suit: StringName = &""          # suit that unlocks the bonus, if any
	var bonus_condition: String = ""          # e.g. "all_slots_bonus_suit"
	var bonus_effects: Array[Dictionary] = []
	var description: String
	var rarity: String = "common"
	var pool: String = "reward"               # "starter" | "reward" | "shop_only"


class EnemyDef:
	var id: StringName
	var name: String
	var hp: int
	var stage: int = 1                        # 1..3 (act progression), boss uses 99
	var brain: Dictionary = {}                # {type: sequence|weighted|phased, ...}
	var moves: Dictionary = {}                # move id -> {intent: {...}, effects: [...]}


class HeroDef:
	var id: StringName
	var name: String
	var max_hp: int
	var starting_abilities: Array[StringName] = []


class StatusDef:
	var id: StringName
	var name: String
	var stack_mode: String = "duration"       # "duration" | "intensity"
	var description: String
