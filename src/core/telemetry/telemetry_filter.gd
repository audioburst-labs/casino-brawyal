class_name TelemetryFilter
extends RefCounted
## Which of the sim's ~34 event types become a telemetry row, and which are
## folded into a combat summary or dropped outright.
##
## The designer's level is "player moves + outcomes": every decision a person
## makes, plus per-combat and per-run totals. Not the firehose — `damage_dealt`
## alone is multistrike x instances x enemies x rounds, an order of magnitude
## more rows than everything else combined, and the aggregate answers every
## question anyone would ask of it.
##
## Pure. No Node, no autoload, no network — `test_telemetry_filter.gd` drives a
## real CombatSim through it.

## One row each: the things a player chose, and the low-volume beats that make
## a fight readable afterwards.
const KEEP: Array[StringName] = [
	# player decisions
	&"chip_assigned", &"chip_unassigned", &"ability_fired", &"loan_taken",
	&"choice_offered",
	# outcomes worth a row, at most a handful per round
	&"round_started", &"spin_resolved", &"chips_discarded", &"actor_died",
	&"enemy_busted", &"enemy_summoned", &"loan_due", &"enemy_move",
	&"combat_won", &"combat_lost",
]

## Counted into the combat summary, never a row of their own.
const AGGREGATE: Array[StringName] = [
	&"damage_dealt", &"block_gained", &"healed", &"status_applied",
	&"relic_triggered", &"mark_cashed", &"encore", &"rage_spent",
	&"damage_negated", &"chips_generated",
]

## Animation chatter: reconstructable from the rows above, or worthless.
const DROP: Array[StringName] = [
	&"intents_shown", &"turn_started", &"turn_ended", &"round_ended",
	&"actor_removed", &"chips_converted", &"chips_absorbed", &"gift_promised",
	&"passive_gained", &"passive_fired", &"passive_counter", &"loan_ticked",
]


## True when this type has been given a decision. A type in none of the three
## lists is new and unclassified — `test_telemetry_filter.gd` fails on that, so
## a 35th event cannot slip in without somebody choosing what to do with it.
static func is_classified(type: StringName) -> bool:
	return KEEP.has(type) or AGGREGATE.has(type) or DROP.has(type)


static func keeps(type: StringName) -> bool:
	return KEEP.has(type)


## The row payload for a kept event: only the fields worth storing, so the
## shape is stable and a sim change cannot silently widen every row.
##
## `hero_id` is needed because `turn_ended` and the death events are emitted
## for both sides, and enemy actor ids (`enemy_0`...) are minted per combat and
## mean nothing across runs — the enemy's `def_id` is what carries.
static func project(type: StringName, data: Dictionary,
		hero_id: StringName, def_ids: Dictionary) -> Dictionary:
	var d := {}
	match type:
		&"chip_assigned", &"chip_unassigned":
			d = {"ability": str(data.get("ability", "")),
				"slot": int(data.get("slot", -1)),
				"suit": str(data.get("suit", ""))}
		&"ability_fired":
			d = {"ability": str(data.get("ability", "")),
				"target": _def_of(data.get("target", &""), hero_id, def_ids)}
		&"loan_taken":
			d = {"loan": str(data.get("id", data.get("loan", "")))}
		&"choice_offered":
			var offered: Array = []
			for option in data.get("options", []):
				offered.append(str((option as Dictionary).get("id", "")))
			d = {"kind": str(data.get("kind", "")), "options": offered}
		&"round_started":
			d = {"round": int(data.get("round", 0))}
		&"spin_resolved":
			var symbols: Array = []
			for symbol in data.get("symbols", []):
				symbols.append(str(symbol))
			d = {"symbols": symbols}
		&"chips_discarded":
			d = {"count": int(data.get("count", 0))}
		&"actor_died":
			var who: StringName = StringName(str(data.get("actor", "")))
			d = {"actor": _def_of(who, hero_id, def_ids),
				"hero": who == hero_id}
		&"enemy_busted", &"enemy_summoned":
			d = {"actor": _def_of(data.get("actor", &""), hero_id, def_ids)}
		&"enemy_move":
			d = {"actor": _def_of(data.get("actor", &""), hero_id, def_ids),
				"skipped": bool(data.get("skipped", false))}
		&"loan_due":
			d = {"loan": str(data.get("id", data.get("loan", "")))}
		&"combat_won":
			d = {"won": true}
		&"combat_lost":
			d = {"won": false}
	return d


static func _def_of(actor: Variant, hero_id: StringName, def_ids: Dictionary) -> String:
	var id := StringName(str(actor))
	if id == &"" :
		return ""
	if id == hero_id:
		return "hero"
	return str(def_ids.get(id, id))
