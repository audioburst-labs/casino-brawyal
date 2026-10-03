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
## How much Block absorbed on the most recent take_damage() call. Presenters
## need the split so a blocked hit reads as "the shield ate it" rather than
## the HP bar dropping and springing back (patch 0.18).
var last_absorbed: int = 0
## Loans the hero has taken (doc "Loan"): {id, turns_left}. Counted down with
## his debuffs at the end of his turn; at zero the penalty fires.
var loans: Array[Dictionary] = []
## An enemy passive's running number, worn on the unit as a permanent buff
## (patch 0.113). The Dealer's Bust counts DOWN from 21 and fires at 0; the
## Chip Golem's Break counts down to its next chip. -1 means no passive.
var passive_counter := -1
## "Deal X% more damage this turn" (All In, sheet v0.122). Cleared at the
## owner's turn start like Block, because "this turn" means exactly that.
var damage_bonus_pct := 0.0

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
	var absorbed: int = mini(block, maxi(0, amount))
	last_absorbed = absorbed
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


## Buffs lose a stack when this actor's own turn BEGINS (patch 0.22).
func tick_turn_start() -> void:
	_tick(StatusRules.DURATION_BUFFS)


## Debuffs lose a stack when this actor's own turn ENDS (patch 0.22) — the
## designer's rule, so a debuff always covers a full turn of whoever carries it.
func tick_turn_end() -> void:
	_tick(StatusRules.DURATION_DEBUFFS)


func _tick(ids: Array[StringName]) -> void:
	for status_id in ids:
		if statuses.has(status_id):
			statuses[status_id] -= 1
			if statuses[status_id] <= 0:
				statuses.erase(status_id)


## Block expires when the owner's own next turn starts — for enemies that is
## their slot in the enemy phase, not the hero's round start, or a shield they
## raised (the Chip Golem's Harden) would be gone before Ace could swing at it.
func on_turn_start() -> void:
	block = 0
	damage_bonus_pct = 0.0
	tick_turn_start()
