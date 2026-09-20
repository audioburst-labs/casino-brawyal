class_name CombatSummary
extends RefCounted
## The per-fight totals, accumulated from the event stream as it drains.
##
## This is where the high-volume types go instead of becoming rows: every
## `damage_dealt` in a fight collapses into two numbers. Pure — the presenter
## feeds it, `test_combat_summary.gd` drives it from a real CombatSim played by
## the GreedyBot and reconciles the totals against the enemies' starting HP.

var combat_id := ""
var run_id := ""
var encounter_number := 0
var encounter_type := ""
var lineup_id := ""
var enemy_ids: Array[String] = []
var combat_seed := 0

var rounds := 0
var won := false
var finished := false
var hp_before := 0
var hp_after := 0
var damage_dealt := 0        # by the hero, to anyone
var damage_taken := 0        # by the hero
var block_gained := 0        # by the hero
var chips_spun := 0
var chips_spent := 0
var abilities_fired := 0
var started_ms := 0


func _init(id: String = "", run: String = "") -> void:
	combat_id = id
	run_id = run
	started_ms = Time.get_ticks_msec()


## One drained event. `hero_id` tells the two sides apart; `def_ids` maps a
## runtime actor id to its content id.
func feed(type: StringName, data: Dictionary, hero_id: StringName) -> void:
	match type:
		&"round_started":
			rounds = maxi(rounds, int(data.get("round", 0)))
		&"damage_dealt":
			var hp_lost := int(data.get("hp_lost", 0))
			if StringName(str(data.get("target", ""))) == hero_id:
				damage_taken += hp_lost
			elif StringName(str(data.get("source", ""))) == hero_id:
				damage_dealt += hp_lost
		&"block_gained":
			if StringName(str(data.get("actor", ""))) == hero_id:
				block_gained += int(data.get("amount", 0))
		&"chips_generated":
			chips_spun += int(data.get("count", 1))
		&"chip_assigned":
			chips_spent += 1
		&"chip_unassigned":
			chips_spent = maxi(0, chips_spent - 1)
		&"ability_fired":
			abilities_fired += 1
		&"combat_won":
			won = true
			finished = true
		&"combat_lost":
			won = false
			finished = true


func duration_sec() -> int:
	return int(round((Time.get_ticks_msec() - started_ms) / 1000.0))


## The `combat_started` payload: everything known before a blow is struck.
func opening() -> Dictionary:
	return {
		"lineup": lineup_id,
		"encounter_type": encounter_type,
		"enemies": enemy_ids,
		"seed": combat_seed,
		"hp_before": hp_before,
	}


## The `combat_ended` payload. `reason` is "won", "lost" or "abandoned" — the
## last of those is a player who walked out of a fight through the menu, which
## is a real and interesting outcome rather than missing data.
func closing(reason: String) -> Dictionary:
	return {
		"won": won,
		"reason": reason,
		"rounds": rounds,
		"hp_before": hp_before,
		"hp_after": hp_after,
		"damage_dealt": damage_dealt,
		"damage_taken": damage_taken,
		"block_gained": block_gained,
		"chips_spun": chips_spun,
		"chips_spent": chips_spent,
		"abilities_fired": abilities_fired,
		"duration_sec": duration_sec(),
	}
