class_name Targeting
extends RefCounted
## Resolves which enemy the hero's abilities hit, per the design doc:
## Taunt overrides (choosable among multiple taunters) > living manual
## target > lowest-HP living enemy. The manual choice persists across
## rounds until changed or the target dies — including once a Taunt that
## was forcing the pick wears off (patch 0.17: no surprise re-target) and
## when a summon joins the field (patch 0.20). Every branch that resolves a
## target records it, so the choice is only ever re-made when the current
## one dies.

var manual_target_id: StringName = &""


func set_target(actor_id: StringName) -> void:
	manual_target_id = actor_id


func effective_target(enemies: Array[CombatActor]) -> CombatActor:
	var living := enemies.filter(func(e: CombatActor) -> bool: return e.is_alive())
	if living.is_empty():
		return null

	var taunting := living.filter(func(e: CombatActor) -> bool: return e.has_status(&"taunt"))
	if not taunting.is_empty():
		var chosen: CombatActor = taunting[0]
		for enemy: CombatActor in taunting:
			if enemy.id == manual_target_id:
				chosen = enemy
				break
		# Remember the taunted pick as the manual target, so the target
		# doesn't jump elsewhere the instant Taunt expires.
		manual_target_id = chosen.id
		return chosen

	# A living target is kept, whatever else joins the field. Summons used to
	# steal the marker (patch 0.20) because a lone enemy was returned here
	# WITHOUT being recorded, so `manual_target_id` stayed empty and the
	# lowest-HP fallback below re-ran the moment a second enemy appeared.
	for enemy: CombatActor in living:
		if enemy.id == manual_target_id:
			return enemy

	if living.size() == 1:
		manual_target_id = living[0].id
		return living[0]

	var lowest: CombatActor = living[0]
	for enemy: CombatActor in living:
		if enemy.hp < lowest.hp:
			lowest = enemy
	# Remembered, so the fallback runs once per target rather than every time
	# the roster changes underneath it.
	manual_target_id = lowest.id
	return lowest
