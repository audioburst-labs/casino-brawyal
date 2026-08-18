class_name StatusRules
extends RefCounted
## Hard-coded damage math for statuses. Kept in code (not data) on purpose:
## only a handful of statuses alter the damage formula, and the ordering
## below is the contract the whole game balances against.
##
## Order per hit: base + Strength -> Weak (-25%, floor, min 1)
##                -> Vulnerable on target (+50%, floor) -> Block -> HP.

const DURATION_STATUSES: Array[StringName] = [&"weak", &"vulnerable", &"taunt", &"stun"]


## Damage a hit deals after the ATTACKER's modifiers.
static func attack_damage(base: int, attacker: CombatActor) -> int:
	var damage := base + attacker.status_stacks(&"strength")
	if attacker.has_status(&"weak"):
		damage = maxi(1, int(floor(damage * 0.75)))
	return damage


## Damage after the TARGET's modifiers (before block).
static func damage_taken(incoming: int, target: CombatActor) -> int:
	if target.has_status(&"vulnerable"):
		return int(floor(incoming * 1.5))
	return incoming
