class_name TutorialScript
extends RefCounted
## The scripted first fight (doc "Tutorial"): Ace against the Bouncer, with the
## dice and the Bouncer's opening move fixed so every step the teacher talks
## about is guaranteed to be on the table.
##
## Pure data and two rules, no scene tree: `Game` asks `applies()` and then
## folds `apply()` into the combat config, and `CombatSim` plays the script
## through its `scripted_spins` / `first_moves` options. Everything the PLAYER
## sees (bubbles, the dimmed screen, the ghost hand) lives in the presenter.

## The Bouncer fight, drawn from the lineups: the tutorial replaces Encounter 1
## but keeps its reward, so it is the very same lineup.
const LINEUP := &"door_duty"

## Round 1: 2 Clubs + 1 Diamond. Round 2: 2 Spades + 1 Club. Round 3: three
## Hearts, which pay three chips and a bonus fourth. After that, real dice.
const SPINS: Array = [
	[&"club", &"club", &"diamond"],
	[&"spade", &"spade", &"club"],
	[&"heart", &"heart", &"heart"],
]

## "He starts with his Attack #2 from the data sheet": Deal 2X3.
const FIRST_MOVES := {"bouncer": "double_jab"}

## The two abilities the walk-through teaches. Ace starts with both.
const TAUGHT: Array[StringName] = [&"card_sling", &"quick_maneuvers"]


## True when a run's `encounter_number` combat should be the tutorial: the
## first encounter, with the taught abilities in the kit.
static func applies(encounter_number: int, ability_ids: Array) -> bool:
	if encounter_number != 1:
		return false
	for id in TAUGHT:
		if not ability_ids.has(id):
			return false
	return true


## Folds the script into a combat config (returns a new dictionary).
static func apply(config: Dictionary) -> Dictionary:
	var out := config.duplicate()
	out["tutorial"] = true
	out["scripted_spins"] = SPINS.duplicate(true)
	out["first_moves"] = FIRST_MOVES.duplicate()
	return out
