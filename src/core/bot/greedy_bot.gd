class_name GreedyBot
extends RefCounted
## Plays one combat with a simple policy: stuff every chip into the first
## legal socket, every round, until the fight ends. Used by sim_cli, the
## full-run bot, and balance tests.

const MAX_ROUNDS := 60


## Runs the combat to completion. Returns true when the hero won.
static func play_combat(sim: CombatSim) -> bool:
	while sim.phase != CombatSim.Phase.ENDED and sim.round_number < MAX_ROUNDS:
		sim.begin_round()
		assign_greedily(sim)
		if sim.phase == CombatSim.Phase.ASSIGNMENT:
			sim.end_assignment()
		sim.drain_events()
	return sim.hero.is_alive()


static func assign_greedily(sim: CombatSim) -> void:
	var progress := true
	while progress and sim.phase == CombatSim.Phase.ASSIGNMENT:
		progress = false
		for suit: StringName in ContentDB.SUITS:
			if sim.tray.count(suit) == 0:
				continue
			for ability_index in sim.abilities.size():
				var ability := sim.abilities[ability_index]
				for slot in ability.filled.size():
					if ability.can_accept(slot, suit) \
							and sim.assign_chip(suit, ability_index, slot):
						progress = true
						break
				if progress:
					break
			if progress:
				break
