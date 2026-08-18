class_name StatusRules
extends RefCounted
## Hard-coded damage math for statuses. Kept in code (not data) on purpose:
## only a handful of statuses alter the damage formula, and the ordering
## below is the contract the whole game balances against.
##
## Order per hit: base + Strength -> Weak (-25%) -> Vulnerable on target (+25%)
##                -> Block -> HP.
## Rounding is half-up (patch 0.1): 4.5 -> 5, 4.4 -> 4. Weak never drops a hit
## below 1. The High Stakes relic raises both modifiers to 50% via
## `intensity_bonus` on the attacker's/target's sim.

const DURATION_STATUSES: Array[StringName] = [&"weak", &"vulnerable", &"taunt", &"stun"]

const WEAK_PCT := 0.25
const VULNERABLE_PCT := 0.25


static func _round_half_up(value: float) -> int:
	return int(floor(value + 0.5))


## Damage a hit deals after the ATTACKER's modifiers.
## `weak_pct` can be overridden (High Stakes relic).
static func attack_damage(base: int, attacker: CombatActor, weak_pct := WEAK_PCT) -> int:
	var damage := base + attacker.status_stacks(&"strength")
	if attacker.has_status(&"weak"):
		damage = maxi(1, _round_half_up(damage * (1.0 - weak_pct)))
	return damage


## Damage after the TARGET's modifiers (before block).
static func damage_taken(incoming: int, target: CombatActor, vulnerable_pct := VULNERABLE_PCT) -> int:
	if target.has_status(&"vulnerable"):
		return _round_half_up(incoming * (1.0 + vulnerable_pct))
	return incoming
