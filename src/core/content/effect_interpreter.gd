class_name EffectInterpreter
extends RefCounted
## Executes declarative effect-op arrays (abilities, story choices, relics)
## against a CombatSim. Run-layer ops (gain_coins, grant_relic, lose_coins)
## are collected on the sim as pending rewards for the run layer to apply.
##
## Optional per-effect "condition" (see ContentDB.KNOWN_CONDITIONS) gates
## individual ops. "target": "all_enemies" fans damage/status ops out.


static func execute(effects: Array[Dictionary], sim: CombatSim,
		source: CombatActor, target: CombatActor) -> void:
	for effect in effects:
		if not _condition_met(effect, sim):
			continue
		match str(effect.get("op", "")):
			"damage":
				for recipient in _damage_targets(effect, sim, target):
					_deal_damage(int(effect.get("amount", 0)) , int(effect.get("times", 1)),
						sim, source, recipient)
			"damage_missing_pct":
				if target != null and target.is_alive():
					var missing := target.max_hp - target.hp
					var base := int(floor(missing * float(effect.get("pct", 0.0)) + 0.5))
					_deal_flat_damage(base, sim, source, target)
			"cash_in":
				_op_cash_in(effect, sim, source, target)
			"apply_status":
				_op_apply_status(effect, sim, source, target)
			"gain_block":
				_grant_block(int(effect.get("amount", 0)), sim, source)
			"block_per_enemy":
				var living := sim.enemies.filter(
					func(e: CombatActor) -> bool: return e.is_alive()).size()
				_grant_block(int(effect.get("amount", 0)) * living, sim, source)
			"block_per_chip":
				var chips: int = sim.last_payout.get(StringName(str(effect.get("suit", ""))), 0)
				_grant_block(chips * int(effect.get("amount", 0)), sim, source)
			"mark_random_unmarked":
				_op_mark_random(sim, int(effect.get("count", 1)))
			"heal":
				var healed := int(effect.get("amount", 0))
				source.heal(healed)
				sim.emit_event(&"healed", {"actor": source.id, "amount": healed})
			"lose_hp":
				# A loan coming due hits like any other blow: Block can eat it,
				# and it can kill (unlike a story wound, which RunEffects
				# clamps to leave 1 HP).
				var loss := int(effect.get("amount", 0))
				var taken := sim.hero.take_damage(loss)
				sim.emit_event(&"damage_dealt", {
					"source": &"loan", "target": sim.hero.id,
					"amount": loss, "hp_lost": taken,
					"blocked": sim.hero.last_absorbed,
				})
			"heal_pct":
				var amount := int(ceil(source.max_hp * float(effect.get("pct", 0.0))))
				source.heal(amount)
				sim.emit_event(&"healed", {"actor": source.id, "amount": amount})
			"add_chips":
				# "suit": "random" rolls per chip (the doc's Loans hand out
				# random chips; patch 0.22).
				var count := int(effect.get("count", 1))
				var wanted := StringName(str(effect.get("suit", "")))
				for i in count:
					var suit := wanted
					if suit == &"random":
						suit = ContentDB.SUITS[sim.rng.stream(&"combat").randi_range(
							0, ContentDB.SUITS.size() - 1)]
					sim.tray.add(suit, 1)
					sim.emit_event(&"chips_generated", {"suit": suit, "count": 1})
			"convert_chips":
				_op_convert_chips(effect, sim)
			"respin_reel":
				sim.spin_again()
			"gain_coins", "grant_relic", "lose_coins":
				sim.pending_rewards.append(effect)
			var unknown:
				push_error("EffectInterpreter: unknown op '%s'" % unknown)


static func _condition_met(effect: Dictionary, sim: CombatSim) -> bool:
	match str(effect.get("condition", "")):
		"":
			return true
		"no_enemy_marked":
			return sim.enemies.all(func(e: CombatActor) -> bool:
				return not e.is_alive() or not e.has_status(&"mark"))
		"enemy_marked":
			return sim.enemies.any(func(e: CombatActor) -> bool:
				return e.is_alive() and e.has_status(&"mark"))
		"solo_ability_this_round":
			return sim.abilities_fired_this_round == 1
		"spin_has_triple":
			for suit: StringName in sim.last_payout:
				if sim.last_payout[suit] >= 3:
					return true
			return false
	return false


static func _damage_targets(effect: Dictionary, sim: CombatSim,
		target: CombatActor) -> Array:
	match str(effect.get("target", "enemy")):
		"all_enemies":
			return sim.enemies.filter(func(e: CombatActor) -> bool: return e.is_alive())
		"random_enemy":
			var living := sim.enemies.filter(func(e: CombatActor) -> bool: return e.is_alive())
			if living.is_empty():
				return []
			return [living[sim.rng.stream(&"combat").randi_range(0, living.size() - 1)]]
	return [target] if target != null else []


## Full pipeline: attacker modifiers + emblem bonus -> target modifiers -> block.
static func _deal_damage(amount: int, times: int, sim: CombatSim,
		source: CombatActor, target: CombatActor) -> void:
	for i in times:
		if target == null or not target.is_alive():
			return
		var damage := StatusRules.attack_damage(amount, source, sim.weak_pct())
		damage = int(floor(damage * sim.active_ability_multiplier() + 0.5))
		damage = StatusRules.damage_taken(damage, target, sim.vulnerable_pct())
		var hp_lost := target.take_damage(damage)
		sim.emit_event(&"damage_dealt", {
			"source": source.id, "target": target.id,
			"amount": damage, "hp_lost": hp_lost,
			"blocked": target.last_absorbed,
		})
		sim.on_enemy_damaged(target, hp_lost)
		sim.check_death(target)


## Bypasses attacker modifiers (used for missing-health damage).
static func _deal_flat_damage(base: int, sim: CombatSim,
		source: CombatActor, target: CombatActor) -> void:
	var damage := StatusRules.damage_taken(base, target, sim.vulnerable_pct())
	var hp_lost := target.take_damage(damage)
	sim.emit_event(&"damage_dealt", {
		"source": source.id, "target": target.id,
		"amount": damage, "hp_lost": hp_lost,
		"blocked": target.last_absorbed,
	})
	sim.on_enemy_damaged(target, hp_lost)
	sim.check_death(target)


## Cash In (sheet v0.19): "If an enemy is marked, Remove it to gain a bonus
## effect." The payoff is no longer a global constant — each ability carries
## its own `effects`, plus optional `else_effects` for the "Deal X instead"
## wording (Double Down, On a Roll). An ability with no `else_effects` simply
## does nothing when the target is unmarked (Bust).
##
## The Mark has to be on the SELECTED target: the player chooses who to hit,
## so cashing a mark off some other enemy would move the damage somewhere they
## did not aim it.
static func _op_cash_in(effect: Dictionary, sim: CombatSim,
		source: CombatActor, target: CombatActor) -> void:
	var cashed := target != null and target.is_alive() and target.has_status(&"mark")
	if cashed:
		target.statuses[&"mark"] -= 1
		if target.statuses[&"mark"] <= 0:
			target.statuses.erase(&"mark")
		sim.emit_event(&"mark_cashed", {"actor": target.id})
	var payoff := _effect_list(effect, "effects" if cashed else "else_effects")
	if not payoff.is_empty():
		execute(payoff, sim, source, target)


## Nested effect arrays arrive from JSON as an untyped Array; execute() wants
## Array[Dictionary].
static func _effect_list(effect: Dictionary, key: String) -> Array[Dictionary]:
	var typed: Array[Dictionary] = []
	for entry in effect.get(key, []):
		typed.append(entry)
	return typed


static func _op_apply_status(effect: Dictionary, sim: CombatSim,
		source: CombatActor, target: CombatActor) -> void:
	var status := StringName(str(effect.get("status", "")))
	var stacks := int(effect.get("stacks", 1))
	var recipients: Array = []
	match str(effect.get("target", "enemy")):
		"self":
			recipients = [source]
		"all_enemies":
			recipients = sim.enemies.filter(func(e: CombatActor) -> bool: return e.is_alive())
		_:
			recipients = [target] if target != null else []
	for recipient: CombatActor in recipients:
		if not recipient.is_alive():
			continue
		recipient.apply_status(status, stacks)
		sim.emit_event(&"status_applied",
			{"actor": recipient.id, "status": status, "stacks": stacks})


## `count` marks that many distinct unmarked enemies — House Edge's silver tier
## marks two (v0.19); its gold tier marks everyone and uses apply_status instead.
static func _op_mark_random(sim: CombatSim, count: int = 1) -> void:
	var unmarked := sim.enemies.filter(func(e: CombatActor) -> bool:
		return e.is_alive() and not e.has_status(&"mark"))
	for i in count:
		if unmarked.is_empty():
			return
		var index := sim.rng.stream(&"combat").randi_range(0, unmarked.size() - 1)
		var chosen: CombatActor = unmarked[index]
		unmarked.remove_at(index)
		chosen.apply_status(&"mark", 1)
		sim.emit_event(&"status_applied", {"actor": chosen.id, "status": &"mark", "stacks": 1})


static func _op_convert_chips(effect: Dictionary, sim: CombatSim) -> void:
	var to_suit := StringName(str(effect.get("to_suit", "")))
	var count := int(effect.get("count", 1))
	var from_suit := StringName(str(effect.get("from_suit", "")))
	var converted := 0
	if from_suit != &"":
		if sim.tray.convert(from_suit, to_suit, count):
			converted = count
	else:
		for suit in ContentDB.SUITS:
			if suit == to_suit:
				continue
			while converted < count and sim.tray.convert(suit, to_suit, 1):
				converted += 1
	if converted > 0:
		sim.emit_event(&"chips_converted", {"to_suit": to_suit, "count": converted})


## Every Block an ability grants goes through here so Frail (v0.120) taxes all
## three block ops the same way; the event carries what was actually gained.
static func _grant_block(amount: int, sim: CombatSim, source: CombatActor) -> void:
	var gained := StatusRules.block_gained(amount, source)
	if gained <= 0:
		return
	source.gain_block(gained)
	sim.emit_event(&"block_gained", {"actor": source.id, "amount": gained})
