class_name CombatSim
extends RefCounted
## The combat rules engine. Pure logic: no Nodes, no awaits, no UI.
## Every state change appends a CombatEvent; presenters drain and animate them.
##
## Round flow:
##   begin_round()      ROUND_START -> ASSIGNMENT (passives fire, intents shown,
##                      machine spun)
##   assign_chip()...   fills ability sockets; full abilities fire immediately
##   end_assignment()   discards tray, runs the enemy phase, ticks statuses,
##                      then returns to ROUND_START (or ENDED on win/loss)

enum Phase { ROUND_START, ASSIGNMENT, ENDED }

const CASH_IN_BONUS := 10
const EMBLEM_MULTIPLIER := 1.3
const LUCKY_FOOT_CHANCE := 0.1
const HIGH_STAKES_PCT := 0.5

var phase: Phase = Phase.ROUND_START
var round_number := 0

var hero: CombatActor
var enemies: Array[CombatActor] = []
var abilities: Array[AbilityState] = []
var tray := ChipTray.new()
var machine: SlotMachine
var targeting := Targeting.new()
var rng: GameRng
var pending_rewards: Array[Dictionary] = []  # run-level ops for the run layer
var passives: Array = []                     # Defs.AbilityDef fired as passives
var abilities_fired_this_round := 0
var last_symbols: Array[StringName] = []
var last_payout: Dictionary = {}

var _db: ContentDB
var _brains: Dictionary = {}        # enemy id -> EnemyBrain
var _intents: Dictionary = {}       # enemy id -> move Dictionary
var _blackjack: Dictionary = {}     # enemy id -> {total, bust}
var _dmg_mult := 1.0
var _hp_mult := 1.0
var _events: Array[CombatEvent] = []
var _relics: Array = []             # Defs.RelicDef, in acquisition order
var _weak_pct := StatusRules.WEAK_PCT
var _vuln_pct := StatusRules.VULNERABLE_PCT
var _has_dark_emblem := false
var _has_red_emblems := false
var _has_lucky_foot := false
var _active_ability: AbilityState = null
var _summon_counter := 0


func _init(db: ContentDB, config: Dictionary) -> void:
	_db = db
	rng = GameRng.new(int(config.get("seed", 0)))
	machine = config.get("machine", SlotMachine.new())
	_dmg_mult = float(config.get("dmg_mult", 1.0))
	_hp_mult = float(config.get("hp_mult", 1.0))

	var hero_def := db.get_hero(StringName(str(config.get("hero", "ace"))))
	hero = CombatActor.new(&"hero", hero_def.id, hero_def.name, hero_def.max_hp, true)
	if config.has("hero_hp"):
		hero.hp = int(config["hero_hp"])

	for ability_id in config.get("abilities", []):
		abilities.append(AbilityState.new(db.get_ability(StringName(str(ability_id)))))

	for relic_id in config.get("relics", []):
		var relic := db.get_relic(StringName(str(relic_id)))
		if relic == null:
			continue
		_relics.append(relic)
		match relic.id:
			&"high_stakes":
				_weak_pct = HIGH_STAKES_PCT
				_vuln_pct = HIGH_STAKES_PCT
			&"dark_emblem":
				_has_dark_emblem = true
			&"red_emblems":
				_has_red_emblems = true
			&"lucky_foot":
				_has_lucky_foot = true

	for enemy_id in config.get("enemies", []):
		_spawn_enemy(StringName(str(enemy_id)), false)


func drain_events() -> Array[CombatEvent]:
	var out := _events
	_events = []
	return out


func emit_event(type: StringName, data: Dictionary = {}) -> void:
	_events.append(CombatEvent.new(type, data))


func weak_pct() -> float:
	return _weak_pct


func vulnerable_pct() -> float:
	return _vuln_pct


## Emblem relics boost abilities whose cost names a matching suit.
func active_ability_multiplier() -> float:
	if _active_ability == null:
		return 1.0
	var cost := _active_ability.def.cost
	if _has_dark_emblem and (cost.has(&"spade") or cost.has(&"club")):
		return EMBLEM_MULTIPLIER
	if _has_red_emblems and (cost.has(&"heart") or cost.has(&"diamond")):
		return EMBLEM_MULTIPLIER
	return 1.0


func begin_round() -> bool:
	if phase != Phase.ROUND_START:
		return false
	round_number += 1
	abilities_fired_this_round = 0
	hero.on_round_start()
	for enemy in enemies:
		enemy.on_round_start()
	for ability in abilities:
		ability.uses_this_round = 0
	emit_event(&"round_started", {"round": round_number})
	if round_number == 1:
		_fire_relics(&"combat_started")
	_fire_relics(&"round_started")
	_fire_passives()

	_intents.clear()
	_blackjack.clear()
	var shown := []
	for enemy in enemies:
		if not enemy.is_alive():
			continue
		var brain: EnemyBrain = _brains[enemy.id]
		var move_id := brain.next_move(rng.stream(&"combat"), float(enemy.hp) / enemy.max_hp)
		var move: Dictionary = _db.get_enemy(enemy.def_id).moves.get(move_id, {})
		_intents[enemy.id] = move
		var intent: Dictionary = move.get("intent", {})
		var entry := {"actor": enemy.id, "move": move_id, "intent": intent}
		if intent.get("blackjack", false):
			var raffle := _raffle_blackjack()
			_blackjack[enemy.id] = raffle
			entry["blackjack_total"] = raffle.total
			entry["bust"] = raffle.bust
			entry["display_per_hit"] = 0 if raffle.bust else raffle.total
			entry["display_instances"] = 0 if raffle.bust else 1
		else:
			entry["display_per_hit"] = StatusRules.attack_damage(
				int(round(int(intent.get("per_hit", 0)) * _dmg_mult)), enemy, _weak_pct)
			entry["display_instances"] = int(intent.get("instances", 0))
		shown.append(entry)
	emit_event(&"intents_shown", {"intents": shown})

	_spin_machine()
	phase = Phase.ASSIGNMENT
	return true


func set_target(actor_id: StringName) -> void:
	targeting.set_target(actor_id)


func assign_chip(suit: StringName, ability_index: int, slot_index: int) -> bool:
	if phase != Phase.ASSIGNMENT:
		return false
	if ability_index < 0 or ability_index >= abilities.size():
		return false
	var ability := abilities[ability_index]
	if ability.exhausted():
		return false
	if not ability.can_accept(slot_index, suit):
		return false
	if not tray.take(suit, 1):
		return false
	ability.fill(slot_index, suit)
	emit_event(&"chip_assigned",
		{"ability": ability.def.id, "slot": slot_index, "suit": suit})
	if ability.is_full():
		_fire_ability(ability)
	return true


func unassign_chip(ability_index: int, slot_index: int) -> bool:
	if phase != Phase.ASSIGNMENT:
		return false
	var ability := abilities[ability_index]
	var suit := ability.unfill(slot_index)
	if suit == &"":
		return false
	tray.add(suit, 1)
	emit_event(&"chip_unassigned",
		{"ability": ability.def.id, "slot": slot_index, "suit": suit})
	return true


func end_assignment() -> bool:
	if phase != Phase.ASSIGNMENT:
		return false
	if tray.total() > 0:
		emit_event(&"chips_discarded", {"count": tray.total()})
		tray.discard_all()

	_run_enemy_phase()
	if phase == Phase.ENDED:
		return true

	hero.tick_round_end()
	for enemy in enemies:
		enemy.tick_round_end()
	emit_event(&"round_ended", {"round": round_number})
	_fire_relics(&"round_ended")
	phase = Phase.ROUND_START
	return true


func check_death(actor: CombatActor) -> void:
	if actor.is_alive() or actor.is_hero:
		return
	emit_event(&"actor_died", {"actor": actor.id})
	if targeting.manual_target_id == actor.id:
		targeting.manual_target_id = &""
	_fire_relics(&"enemy_killed")
	if enemies.all(func(e: CombatActor) -> bool: return not e.is_alive()):
		emit_event(&"combat_won", {})
		phase = Phase.ENDED
		_fire_relics(&"combat_won")


## Re-spins the machine and adds the payout (Go Again / High Roller / round start).
func spin_again() -> void:
	_spin_machine()


func _spin_machine() -> void:
	var result := machine.spin(rng.stream(&"combat"))
	last_symbols = result.symbols
	last_payout = result.payout
	tray.add_payout(result.payout)
	emit_event(&"spin_resolved", {"symbols": result.symbols, "payout": result.payout})
	_fire_relics(&"spin_resolved")


func _raffle_blackjack() -> Dictionary:
	# Draw three cards (1-10) and deal their total. Past 21 is a bust:
	# the attack is negated and the dealer sits this round out.
	var stream := rng.stream(&"combat")
	var total := 0
	for i in 3:
		total += stream.randi_range(1, 10)
	return {"total": total, "bust": total > 21}


func _spawn_enemy(def_id: StringName, announce := true) -> void:
	var def := _db.get_enemy(def_id)
	var stream := rng.stream(&"combat")
	var hp := int(round(stream.randi_range(def.hp_min, def.hp_max) * _hp_mult))
	var enemy := CombatActor.new(StringName("enemy_%d" % _summon_counter), def.id, def.name, hp)
	_summon_counter += 1
	enemies.append(enemy)
	_brains[enemy.id] = EnemyBrain.new(def.brain, def.moves)
	if announce:
		emit_event(&"enemy_summoned",
			{"actor": enemy.id, "def_id": def.id, "name": def.name, "hp": hp})


func _fire_relics(trigger: StringName) -> void:
	for relic: Defs.RelicDef in _relics:
		if relic.trigger != trigger or relic.effects.is_empty():
			continue
		emit_event(&"relic_triggered", {"relic": relic.id})
		EffectInterpreter.execute(relic.effects, self, hero,
			targeting.effective_target(enemies))


func _fire_passives() -> void:
	for def: Defs.AbilityDef in passives:
		emit_event(&"passive_fired", {"ability": def.id})
		EffectInterpreter.execute(def.effects, self, hero,
			targeting.effective_target(enemies))


func _fire_ability(ability: AbilityState) -> void:
	ability.uses_this_round += 1
	abilities_fired_this_round += 1
	var target := targeting.effective_target(enemies)
	emit_event(&"ability_fired", {"ability": ability.def.id, "target": target.id if target else &""})
	if ability.def.passive:
		if not passives.has(ability.def):
			passives.append(ability.def)
		emit_event(&"passive_gained", {"ability": ability.def.id})
	else:
		_active_ability = ability
		var bonus := ability.bonus_active()
		if bonus and ability.def.bonus_mode == "replace":
			EffectInterpreter.execute(ability.def.bonus_effects, self, hero, target)
		else:
			EffectInterpreter.execute(ability.def.effects, self, hero, target)
			if bonus:
				EffectInterpreter.execute(ability.def.bonus_effects, self, hero, target)
		_active_ability = null
	ability.clear()


func _run_enemy_phase() -> void:
	for enemy in enemies.duplicate():  # summons during the phase act next round
		if not enemy.is_alive():
			continue
		if enemy.has_status(&"stun"):
			emit_event(&"enemy_move", {"actor": enemy.id, "skipped": true})
			continue
		_execute_move(enemy, true)
		if phase == Phase.ENDED:
			return


func _execute_move(enemy: CombatActor, allow_encore: bool) -> void:
	var move: Dictionary = _intents.get(enemy.id, {})
	var intent: Dictionary = move.get("intent", {})

	if intent.get("blackjack", false):
		var raffle: Dictionary = _blackjack.get(enemy.id, {"total": 0, "bust": true})
		if raffle.bust:
			emit_event(&"enemy_move", {"actor": enemy.id, "skipped": true, "bust": true})
			return
		emit_event(&"enemy_move", {"actor": enemy.id, "skipped": false})
		_hit_hero(enemy, int(raffle.total))
		_check_hero_death()
		return

	emit_event(&"enemy_move", {"actor": enemy.id, "skipped": false})

	var summon: Dictionary = intent.get("summon", {})
	if not summon.is_empty():
		for i in int(summon.get("count", 1)):
			_spawn_enemy(StringName(str(summon.get("enemy", ""))))

	if intent.get("heal_allies", 0) > 0:
		var amount := int(intent.get("heal_allies"))
		for ally in enemies:
			if ally.is_alive():
				ally.heal(amount)
				emit_event(&"healed", {"actor": ally.id, "amount": amount})

	if intent.get("ally_attack_again", false) and allow_encore:
		var others := enemies.filter(func(e: CombatActor) -> bool:
			return e.is_alive() and e.id != enemy.id and _intents.has(e.id))
		if not others.is_empty():
			var chosen: CombatActor = others[rng.stream(&"combat").randi_range(0, others.size() - 1)]
			emit_event(&"encore", {"actor": chosen.id})
			_execute_move(chosen, false)
			if phase == Phase.ENDED:
				return

	var instances := int(intent.get("instances", 0))
	var per_hit := int(round(int(intent.get("per_hit", 0)) * _dmg_mult))
	for i in instances:
		if not hero.is_alive():
			break
		_hit_hero(enemy, per_hit)
	for debuff: Dictionary in intent.get("debuffs", []):
		if not hero.is_alive():
			break
		var status := StringName(str(debuff.get("status", "")))
		var stacks := int(debuff.get("stacks", 1))
		hero.apply_status(status, stacks)
		emit_event(&"status_applied",
			{"actor": hero.id, "status": status, "stacks": stacks})
	for buff: Dictionary in intent.get("self_status", []):
		var status := StringName(str(buff.get("status", "")))
		var stacks := int(buff.get("stacks", 1))
		enemy.apply_status(status, stacks)
		emit_event(&"status_applied",
			{"actor": enemy.id, "status": status, "stacks": stacks})
	if intent.get("self_heal", 0) > 0:
		var amount := int(intent.get("self_heal"))
		enemy.heal(amount)
		emit_event(&"healed", {"actor": enemy.id, "amount": amount})

	_check_hero_death()


func _hit_hero(enemy: CombatActor, base: int) -> void:
	var damage := StatusRules.attack_damage(base, enemy, _weak_pct)
	damage = StatusRules.damage_taken(damage, hero, _vuln_pct)
	if _has_lucky_foot and rng.stream(&"combat").randf() < LUCKY_FOOT_CHANCE:
		emit_event(&"damage_negated", {"source": enemy.id, "target": hero.id, "amount": damage})
		return
	var hp_lost := hero.take_damage(damage)
	emit_event(&"damage_dealt", {
		"source": enemy.id, "target": hero.id,
		"amount": damage, "hp_lost": hp_lost,
	})


func _check_hero_death() -> void:
	if not hero.is_alive():
		emit_event(&"combat_lost", {})
		phase = Phase.ENDED
