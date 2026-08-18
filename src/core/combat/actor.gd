class_name CombatActor
extends RefCounted
## One combatant (hero or enemy): hp, block, and status stacks.
## Damage modifiers (Weak/Vulnerable/Strength) live in StatusRules;
## this class only owns raw state changes.

var id: StringName             # unique within one combat, e.g. &"enemy_0"
var def_id: StringName         # content id (hero or enemy definition)
var display_name: String
var hp: int
var max_hp: int
var block: int = 0
var is_hero: bool
var statuses: Dictionary = {}  # status id -> stacks


func _init(actor_id: StringName, definition_id: StringName, name_text: String,
		hit_points: int, hero: bool = false) -> void:
	id = actor_id
	def_id = definition_id
	display_name = name_text
	hp = hit_points
	max_hp = hit_points
	is_hero = hero


func is_alive() -> bool:
	return hp > 0


## Applies already-modified damage: block absorbs, remainder hits HP.
## Returns the HP actually lost.
func take_damage(amount: int) -> int:
	var absorbed: int = mini(block, amount)
	block -= absorbed
	var hp_loss: int = mini(hp, amount - absorbed)
	hp -= hp_loss
	return hp_loss


func heal(amount: int) -> void:
	hp = mini(max_hp, hp + amount)


func gain_block(amount: int) -> void:
	block += amount


func apply_status(status_id: StringName, stacks: int) -> void:
	statuses[status_id] = status_stacks(status_id) + stacks


func has_status(status_id: StringName) -> bool:
	return status_stacks(status_id) > 0


func status_stacks(status_id: StringName) -> int:
	return statuses.get(status_id, 0)


## Duration statuses lose one stack at the end of each round.
func tick_round_end() -> void:
	for status_id in StatusRules.DURATION_STATUSES:
		if statuses.has(status_id):
			statuses[status_id] -= 1
			if statuses[status_id] <= 0:
				statuses.erase(status_id)


## Block expires when the owner's next round starts.
func on_round_start() -> void:
	block = 0
