extends SceneTree
## Headless combat playground: plays a seeded combat with a greedy bot and
## prints a readable transcript. Deterministic per seed — paste a seed from a
## bug report to replay it exactly.
##
## Usage:
##   godot --headless -s tools/sim_cli.gd -- [seed] [enemy_id enemy_id ...]
##   (defaults: seed 1, enemies security_goon card_shark)

const MAX_ROUNDS := 40


func _init() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_value := int(args[0]) if args.size() > 0 else 1
	var enemy_ids: Array = args.slice(1) if args.size() > 1 else ["bouncer", "server"]

	var db := ContentDB.new()
	if not db.load_all("res://data"):
		push_error("content errors: " + str(db.errors))
		_finish(1)
		return

	var sim := CombatSim.new(db, {
		"hero": "ace",
		"abilities": ["card_sling", "quick_maneuvers", "color_up", "double_down"],
		"enemies": enemy_ids,
		"seed": seed_value,
	})
	print("=== Casino Brawyal combat sim | seed %d | enemies: %s ===" % [seed_value, ", ".join(enemy_ids)])

	while sim.phase != CombatSim.Phase.ENDED and sim.round_number < MAX_ROUNDS:
		sim.begin_round()
		GreedyBot.assign_greedily(sim)
		if sim.phase == CombatSim.Phase.ASSIGNMENT:
			sim.end_assignment()
		_print_events(sim.drain_events(), sim)

	print("\n=== result: %s after %d rounds | hero %d/%d hp ===" % [
		"WON" if sim.hero.is_alive() else "LOST", sim.round_number, sim.hero.hp, sim.hero.max_hp])
	_finish(0)


## quit() during _init reports exit code 255; defer it past startup instead.
func _finish(code: int) -> void:
	await process_frame
	quit(code)


func _print_events(events: Array[CombatEvent], sim: CombatSim) -> void:
	for event in events:
		match event.type:
			&"round_started":
				print("\n-- round %d --" % event.data.round)
			&"intents_shown":
				for intent: Dictionary in event.data.intents:
					var i: Dictionary = intent.intent
					print("  intent  %s: %s (%dx%d)%s" % [intent.actor, intent.move,
						i.get("instances", 0), i.get("per_hit", 0),
						" +debuffs" if not i.get("debuffs", []).is_empty() else ""])
			&"spin_resolved":
				print("  spin    %s -> %s" % [str(event.data.symbols), str(event.data.payout)])
			&"ability_fired":
				print("  fire    %s -> %s" % [event.data.ability, event.data.target])
			&"damage_dealt":
				print("  damage  %s hits %s for %d" % [event.data.source, event.data.target, event.data.amount])
			&"status_applied":
				print("  status  %s gets %s x%d" % [event.data.actor, event.data.status, event.data.stacks])
			&"block_gained":
				print("  block   %s +%d" % [event.data.actor, event.data.amount])
			&"actor_died":
				print("  DEATH   %s" % event.data.actor)
			&"chips_discarded":
				print("  discard %d chips" % event.data.count)
			&"combat_won":
				print("  ** VICTORY **")
			&"combat_lost":
				print("  ** DEFEAT **")
