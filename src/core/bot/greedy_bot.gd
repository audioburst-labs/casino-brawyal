class_name GreedyBot
extends RefCounted
## Plays one combat with simple heuristics: when healthy, fill the hardest-
## hitting abilities first (per chip); when hurt, prioritize block. Used by
## sim_cli, the full-run bot, and balance tests.

const MAX_ROUNDS := 60


## Runs the combat to completion. Returns true when the hero won.
static func play_combat(sim: CombatSim) -> bool:
	while sim.phase != CombatSim.Phase.ENDED and sim.round_number < MAX_ROUNDS:
		sim.begin_round()
		# "Options In Combat": pick at random so the balance instrument still
		# plays fights that offer a choice (patch 0.22).
		while sim.phase == CombatSim.Phase.CHOICE:
			if not sim.choose(sim.rng.stream(&"bot").randi_range(
					0, maxi(0, sim.pending_choice().get("options", []).size() - 1))):
				break
		assign_greedily(sim)
		if sim.phase == CombatSim.Phase.ASSIGNMENT:
			sim.end_assignment()
		sim.drain_events()
	return sim.hero.is_alive()


static func assign_greedily(sim: CombatSim) -> void:
	var order := _ability_order(sim)
	var progress := true
	while progress and sim.phase == CombatSim.Phase.ASSIGNMENT:
		progress = false
		for ability_index: int in order:
			var ability := sim.abilities[ability_index]
			if ability.exhausted() or not _completable(sim, ability):
				continue
			# Specific sockets take their suit; wildcards take the most
			# plentiful suit so specific chips aren't wasted on them.
			for slot in _slots_specific_first(ability):
				if ability.filled[slot] != &"":
					continue
				var suit := ability.def.cost[slot]
				if suit == &"any":
					suit = _most_plentiful(sim)
				if suit != &"" and sim.tray.count(suit) > 0 \
						and sim.assign_chip(suit, ability_index, slot):
					progress = true
					break
			if progress:
				break


## Only start filling an ability the current tray can actually finish
## (counting chips already socketed into it).
static func _completable(sim: CombatSim, ability: AbilityState) -> bool:
	var needed := {}
	var wildcards := 0
	for slot in ability.filled.size():
		if ability.filled[slot] != &"":
			continue
		var suit := ability.def.cost[slot]
		if suit == &"any":
			wildcards += 1
		else:
			needed[suit] = needed.get(suit, 0) + 1
	var spare := 0
	for suit: StringName in ContentDB.SUITS:
		var have := sim.tray.count(suit)
		var used: int = needed.get(suit, 0)
		if have < used:
			return false
		spare += have - used
	return spare >= wildcards


static func _slots_specific_first(ability: AbilityState) -> Array:
	var slots := range(ability.filled.size())
	slots.sort_custom(func(a: int, b: int) -> bool:
		return (ability.def.cost[a] != &"any") and (ability.def.cost[b] == &"any"))
	return slots


static func _most_plentiful(sim: CombatSim) -> StringName:
	var best: StringName = &""
	var best_count := 0
	for suit: StringName in ContentDB.SUITS:
		if sim.tray.count(suit) > best_count:
			best = suit
			best_count = sim.tray.count(suit)
	return best


## Value-per-chip, best first; block abilities soak up leftover chips.
static func _ability_order(sim: CombatSim) -> Array:
	var living := sim.enemies.filter(func(e: CombatActor) -> bool: return e.is_alive()).size()
	var indices := range(sim.abilities.size())
	indices.sort_custom(func(a: int, b: int) -> bool:
		return _score(sim.abilities[a].def, living) > _score(sim.abilities[b].def, living))
	return indices


static func _score(def: Defs.AbilityDef, living_enemies: int) -> float:
	return _score_effects(def.effects, living_enemies) / maxf(1.0, def.cost.size())


static func _score_effects(effects: Array[Dictionary], living_enemies: int) -> float:
	var value := 0.0
	for effect: Dictionary in effects:
		match str(effect.get("op", "")):
			"damage":
				var hits := int(effect.get("amount", 0)) * int(effect.get("times", 1))
				value += hits * (living_enemies if str(effect.get("target", "")) == "all_enemies" else 1)
			"cash_in":
				# Cash In carries its own payoff now (v0.19); score the branch
				# it would most likely take rather than a flat guess.
				var branch: Array = effect.get("effects", effect.get("else_effects", []))
				var typed: Array[Dictionary] = []
				for nested in branch:
					typed.append(nested)
				value += _score_effects(typed, living_enemies) * 0.75
			"damage_missing_pct":
				value += 12.0
			"add_chips":
				value += 4.0
			"gain_block":
				value += int(effect.get("amount", 0)) * 0.4
			"block_per_enemy":
				value += int(effect.get("amount", 0)) * living_enemies * 0.4
			"apply_status":
				var stacks := int(effect.get("stacks", 1))
				var per := 5.0 if str(effect.get("status", "")) in ["weak", "vulnerable"] else 2.0
				var targets := living_enemies if str(effect.get("target", "")) == "all_enemies" else 1
				value += per * stacks * targets
	return value


