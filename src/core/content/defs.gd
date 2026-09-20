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
	## A passive with no trigger fires at every round start (House Edge, Face
	## Reader). One WITH a trigger fires when that thing happens instead -
	## "when you Earn" (Chip Tricks), "when you Mark" (Sharp Edge).
	var passive_trigger: String = ""
	## A triggered passive's "Active:" half - what happens the turn you play it,
	## as opposed to `effects`, which is what the trigger runs later.
	var active_effects: Array[Dictionary] = []
	var per_turn: int = 0                     # max activations per round; 0 = unlimited
	var per_combat: int = 0                   # max activations per combat; 0 = unlimited
	var passive: bool = false                 # once fired, effects recur at every round start
	var exclusive: bool = false               # firing this locks all other abilities this round
	var keywords: Array[StringName] = []      # keyword ids shown as hover bubbles
	var description: String
	var rarity: String = "common"
	var pool: String = "reward"               # "starter" | "reward" | "shop_only"
	var tier: int = 0                         # 0 base, 1 silver, 2 gold (doc "Ability Upgrades")


class EnemyDef:
	var id: StringName
	var name: String
	var hp_min: int
	var hp_max: int
	var brain: Dictionary = {}                # {type: sequence|weighted|graph|phased, ...}
	var moves: Dictionary = {}                # move id -> {intent: {...}}
	## Always-on behaviour, see ContentDB.KNOWN_PASSIVES (patch 0.22):
	## {"type": "bust"|"break"|"loan", ...}. Empty for a plain enemy.
	var passive: Dictionary = {}


## One "Options In Combat" loan (doc "Loan"): a reward now, a price in N turns.
class LoanDef:
	var id: StringName
	var title: String
	var turns: int = 3
	var reward_text: String
	var penalty_text: String
	## Sheet v0.122's Notes column: "" offers always, "wounded" hides the loan
	## while the hero is on full health (a heal you cannot use is not a choice).
	var requires: String = ""
	var reward: Array[Dictionary] = []
	var penalty: Array[Dictionary] = []


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
	var kind: String = "debuff"               # "buff" | "debuff" — when it ticks
	var description: String
