class_name Targeting
extends RefCounted
## Resolves which enemy the hero's abilities hit, per the design doc:
## Taunt overrides (leftmost) > living manual target > lowest-HP living enemy.
## The manual choice persists across rounds until changed or the target dies.

var manual_target_id: StringName = &""


func set_target(actor_id: StringName) -> void:
	manual_target_id = actor_id


func effective_target(enemies: Array[CombatActor]) -> CombatActor:
	var living := enemies.filter(func(e: CombatActor) -> bool: return e.is_alive())
	if living.is_empty():
		return null

	for enemy: CombatActor in living:
		if enemy.has_status(&"taunt"):
			return enemy

	if living.size() == 1:
		return living[0]

	for enemy: CombatActor in living:
		if enemy.id == manual_target_id:
			return enemy

	var lowest: CombatActor = living[0]
	for enemy: CombatActor in living:
		if enemy.hp < lowest.hp:
			lowest = enemy
	return lowest
