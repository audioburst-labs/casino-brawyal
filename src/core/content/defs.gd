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
	var bonus_mode: String = "extra"          # "extra" adds bonus_effects; "replace" swaps them in
	var bonus_effects: Array[Dictionary] = []
	var per_turn: int = 0                     # max activations per round; 0 = unlimited
	var passive: bool = false                 # once fired, effects recur at every round start
	var exclusive: bool = false               # firing this locks all other abilities this round
	var keywords: Array[StringName] = []      # keyword ids shown as hover bubbles
	var description: String
	var rarity: String = "common"
	var pool: String = "reward"               # "starter" | "reward" | "shop_only"


class EnemyDef:
	var id: StringName
	var name: String
	var hp_min: int
	var hp_max: int
	var brain: Dictionary = {}                # {type: sequence|weighted|graph|phased, ...}
	var moves: Dictionary = {}                # move id -> {intent: {...}}


class KeywordDef:
	var id: StringName
	var name: String
	var text: String


class HeroDef:
	var id: StringName
	var name: String
	var max_hp: int
	var starting_abilities: Array[StringName] = []


class RelicDef:
	var id: StringName
	var name: String
	var trigger: StringName                   # hook name, see ContentDB.KNOWN_TRIGGERS
	var effects: Array[Dictionary] = []       # may be empty for code-implemented relics
	var price_min: int = 20
	var price_max: int = 30
	var description: String
	var rarity: String = "common"


class StoryEventDef:
	var id: StringName
	var title: String
	var description: String
	var image: String                         # res:// path to the illustration
	var choices: Array[Dictionary] = []       # {label, summary, effects: [...]}


class StatusDef:
	var id: StringName
	var name: String
	var stack_mode: String = "duration"       # "duration" | "intensity"
	var description: String
