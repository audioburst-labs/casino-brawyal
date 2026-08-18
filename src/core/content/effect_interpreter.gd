class_name EffectInterpreter
extends RefCounted
## Executes declarative effect-op arrays (from abilities, story choices,
## simple relics) against a CombatSim. Run-layer ops (gain_coins, grant_relic)
## are collected on the sim as pending rewards for the run layer to apply.


static func execute(effects: Array[Dictionary], sim: CombatSim,
		source: CombatActor, target: CombatActor) -> void:
	for effect in effects:
		match str(effect.get("op", "")):
			"damage":
				_op_damage(effect, sim, source, target)
			"apply_status":
				_op_apply_status(effect, sim, source, target)
			"gain_block":
				source.gain_block(int(effect.get("amount", 0)))
				sim.emit_event(&"block_gained",
					{"actor": source.id, "amount": int(effect.get("amount", 0))})
			"heal_pct":
				var amount := int(ceil(source.max_hp * float(effect.get("pct", 0.0))))
				source.heal(amount)
				sim.emit_event(&"healed", {"actor": source.id, "amount": amount})
			"add_chips":
				var suit := StringName(str(effect.get("suit", "")))
				var count := int(effect.get("count", 1))
				sim.tray.add(suit, count)
				sim.emit_event(&"chips_generated", {"suit": suit, "count": count})
			"convert_chips":
				_op_convert_chips(effect, sim)
			"respin_reel":
				_op_respin(sim)
			"gain_coins", "grant_relic":
				sim.pending_rewards.append(effect)
			var unknown:
				push_error("EffectInterpreter: unknown op '%s'" % unknown)


static func _op_damage(effect: Dictionary, sim: CombatSim,
		source: CombatActor, target: CombatActor) -> void:
	var times := int(effect.get("times", 1))
	for i in times:
		if target == null or not target.is_alive():
			return
		var damage := StatusRules.attack_damage(int(effect.get("amount", 0)), source)
		damage = StatusRules.damage_taken(damage, target)
		var hp_lost := target.take_damage(damage)
		sim.emit_event(&"damage_dealt", {
			"source": source.id, "target": target.id,
			"amount": damage, "hp_lost": hp_lost,
		})
		sim.check_death(target)


static func _op_apply_status(effect: Dictionary, sim: CombatSim,
		source: CombatActor, target: CombatActor) -> void:
	var recipient := source if str(effect.get("target", "enemy")) == "self" else target
	if recipient == null or not recipient.is_alive():
		return
	var status := StringName(str(effect.get("status", "")))
	var stacks := int(effect.get("stacks", 1))
	recipient.apply_status(status, stacks)
	sim.emit_event(&"status_applied",
		{"actor": recipient.id, "status": status, "stacks": stacks})


static func _op_convert_chips(effect: Dictionary, sim: CombatSim) -> void:
	var to_suit := StringName(str(effect.get("to_suit", "")))
	var count := int(effect.get("count", 1))
	var from_suit := StringName(str(effect.get("from_suit", "")))
	var converted := 0
	if from_suit != &"":
		if sim.tray.convert(from_suit, to_suit, count):
			converted = count
	else:
		# No source suit specified: convert from whatever is available.
		for suit in ContentDB.SUITS:
			if suit == to_suit:
				continue
			while converted < count and sim.tray.convert(suit, to_suit, 1):
				converted += 1
	if converted > 0:
		sim.emit_event(&"chips_converted", {"to_suit": to_suit, "count": converted})


static func _op_respin(sim: CombatSim) -> void:
	var result := sim.machine.spin(sim.rng.stream(&"combat"))
	sim.tray.add_payout(result.payout)
	sim.emit_event(&"spin_resolved", {"symbols": result.symbols, "payout": result.payout})
