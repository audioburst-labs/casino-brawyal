class_name CombatEvent
extends RefCounted
## One typed state-change record emitted by CombatSim.
## The UI presenter drains these and plays an animation per event;
## the sim never talks to the scene tree directly.
##
## Types used so far:
##   round_started, intents_shown, spin_resolved, chip_assigned, chip_unassigned,
##   ability_fired, damage_dealt, block_gained, status_applied, healed,
##   chips_converted, chips_discarded, actor_died, actor_removed, enemy_move,
##   enemy_summoned, round_ended, combat_won, combat_lost

var type: StringName
var data: Dictionary


func _init(event_type: StringName, event_data: Dictionary = {}) -> void:
	type = event_type
	data = event_data
