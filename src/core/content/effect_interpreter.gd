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
		if not _condition_met(effect, sim, target):
			continue
		match str(effect.get("op", "")):
			"damage":
				var had_rage := source.has_status(&"rage")
				for recipient in _damage_targets(effect, sim, target):
					_deal_damage(int(effect.get("amount", 0)) , int(effect.get("times", 1)),
						sim, source, recipient)
				_spend_rage(sim, source, had_rage)
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
				_grant_block_per_unit(int(effect.get("amount", 0)), living, sim, source)
			"block_per_chip":
				var chips: int = sim.last_payout.get(StringName(str(effect.get("suit", ""))), 0)
				_grant_block_per_unit(int(effect.get("amount", 0)), chips, sim, source)
			"mark_random_unmarked":
				_op_mark_random(sim, int(effect.get("count", 1)))
			"damage_per_ability":
				# The River: "for each ability that is expended for the turn". The
				# River itself counts - `abilities_fired_this_round` is incremented
				# before effects run - so it can never deal nothing.
				var each := int(effect.get("amount", 0)) * sim.abilities_fired_this_round
				var had_rage_river := source.has_status(&"rage")
				for recipient in _damage_targets(effect, sim, target):
					_deal_damage(each, 1, sim, source, recipient)
				_spend_rage(sim, source, had_rage_river)
			"damage_bonus_pct":
				# All In: everything the hero throws for the rest of this turn.
				source.damage_bonus_pct += float(effect.get("pct", 0.0))
				sim.emit_event(&"damage_bonus",
					{"actor": source.id, "pct": source.damage_bonus_pct})
			"rage_per_weak":
				# Slow Playing: "Gain Rage 1 for each Weak on an enemy" - counted in
				# STACKS, so Weak 2 on one enemy is worth Weak 1 on two.
				var stacks := 0
				for enemy in sim.enemies:
					if enemy.is_alive():
						stacks += enemy.status_stacks(&"weak")
				var rage := stacks * maxi(1, int(effect.get("amount", 1)))
				if rage > 0:
					source.apply_status(&"rage", rage)
					sim.emit_event(&"status_applied",
						{"actor": source.id, "status": &"rage", "stacks": rage})
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
				# Earn, in the doc's vocabulary (sheet v0.122). "random" rolls per
				# chip (Loans, Chip Tricks); "used" hands back a chip this ability
				# was paid with.
				var count := int(effect.get("count", 1))
				var wanted := StringName(str(effect.get("suit", "")))
				for i in count:
					var suit := wanted
					if suit == &"random":
						suit = ContentDB.SUITS[sim.rng.stream(&"combat").randi_range(
							0, ContentDB.SUITS.size() - 1)]
					elif suit == &"used":
						# Hit and All In hand back a chip they were paid with, which is
						# what makes them nearly free.
						var spent := _socketed(sim)
						if spent.is_empty():
							continue
						suit = spent[mini(i, spent.size() - 1)]
					sim.tray.add(suit, 1)
					# "earn" tells the presenter this chip came from an ability, so
					# it flies from Ace rather than appearing in the drawer (0.117).
					sim.emit_event(&"chips_generated", {"suit": suit, "count": 1, "source": "earn"})
				# Earn: "when you Earn..." passives fire once per op, not per
				# chip, so Chip Tricks pays the same for one chip or three.
				sim.on_chips_earned(count)
			"convert_chips":
				_op_convert_chips(effect, sim)
			"respin_reel":
				sim.spin_again()
			"gain_coins", "grant_relic", "lose_coins":
				if sim.settling_loan and str(effect.get("op", "")) != "grant_relic":
					# A loan's coins land now (0.117): queued for the end of
					# the fight, a lost fight paid nothing and a won one paid
					# late. RunEffects clamps lose_coins at zero, which is the
					# sheet's "taking as many as it can".
					sim.run_ops.append(effect)
					sim.emit_event(&"run_effect", effect.duplicate())
				else:
					sim.pending_rewards.append(effect)
			var unknown:
				push_error("EffectInterpreter: unknown op '%s'" % unknown)


static func _condition_met(effect: Dictionary, sim: CombatSim,
		target: CombatActor = null) -> bool:
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
		"target_weak":
			return target != null and target.is_alive() and target.has_status(&"weak")
		"target_not_weak":
			return target == null or not target.is_alive() or not target.has_status(&"weak")
		"any_enemy_weak":
			return sim.enemies.any(func(e: CombatActor) -> bool:
				return e.is_alive() and e.has_status(&"weak"))
		"no_enemy_weak":
			return not sim.enemies.any(func(e: CombatActor) -> bool:
				return e.is_alive() and e.has_status(&"weak"))
		"socket_has_suit":
			return _socketed(sim).has(StringName(str(effect.get("condition_suit", ""))))
		"socket_lacks_suit":
			return not _socketed(sim).has(StringName(str(effect.get("condition_suit", ""))))
	return false


## The suits sitting in the ability currently resolving. Rainbow reads two of
## them independently ("If Club - 10 instead. If Heart - apply Weak"), which
## the single `bonus_suit` slot cannot express. Read before `ability.clear()`,
## which runs after the effects.
static func _socketed(sim: CombatSim) -> Array[StringName]:
	var out: Array[StringName] = []
	var active := sim.active_ability()
	if active == null:
		return out
	for suit: StringName in active.filled:
		if suit != &"":
			out.append(suit)
	return out


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
		var damage := StatusRules.attack_damage(
			amount + source.status_stacks(&"rage"), source, sim.weak_pct())
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


## Rage X: "your next attack deals X bonus damage", on every hit of it, then it
## is spent (designer's call, same as an enemy's Rage). Slow Playing granted
## the stacks for nine patches and nothing ever read them or spent them.
static func _spend_rage(sim: CombatSim, source: CombatActor, had_rage: bool) -> void:
	if not had_rage:
		return
	var spent := source.status_stacks(&"rage")
	source.statuses.erase(&"rage")
	sim.emit_event(&"rage_spent", {"actor": source.id, "amount": spent})


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
		target.statuses.erase(&"mark")   # a toggle: cashing it clears it
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
		var was_marked := recipient.has_status(&"mark")
		if status == &"mark":
			# Mark is a toggle, not a stack (designer, 0.117): an enemy is
			# marked or it is not, and one Cash In spends the whole thing.
			# Before this, three Marks bought three separate Cash Ins.
			recipient.statuses[&"mark"] = 1
			stacks = 1
		else:
			recipient.apply_status(status, stacks)
		sim.emit_event(&"status_applied",
			{"actor": recipient.id, "status": status, "stacks": stacks})
		# Sharp Edge: "when you Mark, also deal X" (sheet v0.122). Only a Mark
		# that actually goes ON an unmarked enemy counts (designer, 0.121:
		# "it shouldn't deal damage when a Mark is applied to a target that's
		# already marked").
		if status == &"mark" and not recipient.is_hero and not was_marked:
			sim.on_enemy_marked(recipient)


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
		sim.on_enemy_marked(chosen)


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


## A per-unit block op ("2 Block per enemy"). Frail taxes the figure the CARD
## SHOWS and the total is that figure times the count (patch 0.113, designer's
## call) — taxing the total instead made "2 per enemy" pay 6 for four enemies,
## which is what "the block math looks completely wrong" was about.
static func _grant_block_per_unit(amount: int, count: int, sim: CombatSim,
		source: CombatActor) -> void:
	if count <= 0 or amount <= 0:
		return
	_grant_block(StatusRules.block_gained(amount, source) * count, sim, source, false)


## Every Block an ability grants goes through here so Frail (v0.120) taxes all
## three block ops the same way; the event carries what was actually gained.
static func _grant_block(amount: int, sim: CombatSim, source: CombatActor,
		taxed := true) -> void:
	var gained := StatusRules.block_gained(amount, source) if taxed else amount
	if gained <= 0:
		return
	source.gain_block(gained)
	sim.emit_event(&"block_gained", {"actor": source.id, "amount": gained})
