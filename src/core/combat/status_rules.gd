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

## Duration statuses, split by who benefits (patch 0.22). The designer's rule:
## **buffs tick down at the start of their owner's turn, debuffs at its end.**
## That is what makes an enemy's Weak 2 on Ace cover Ace's next two turns
## (before 0.22 every duration ticked once, together, after the enemy phase, so
## a debuff lost a stack before its victim had acted under it once), and what
## lets the Bouncer's self-applied Taunt 2 hold the player's aim for two turns.
## `statuses.json` carries the same split as a "kind" field.
const DURATION_BUFFS: Array[StringName] = [&"taunt"]
const DURATION_DEBUFFS: Array[StringName] = [&"weak", &"vulnerable", &"stun", &"frail"]
const DURATION_STATUSES: Array[StringName] = [&"weak", &"vulnerable", &"taunt", &"stun", &"frail"]

const WEAK_PCT := 0.25
const VULNERABLE_PCT := 0.25
## Frail (sheet v0.120, the Server's Spilled Drink): "Gain 25% less Block from
## abilities." Applied to every Block an ability op grants, half-up.
const FRAIL_PCT := 0.25


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


## Block an ability grants after the RECIPIENT's modifiers (Frail).
static func block_gained(amount: int, recipient: CombatActor) -> int:
	if recipient.has_status(&"frail"):
		return _round_half_up(amount * (1.0 - FRAIL_PCT))
	return amount
