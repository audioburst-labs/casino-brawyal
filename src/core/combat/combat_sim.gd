class_name CombatSim
extends RefCounted
## The combat rules engine. Pure logic: no Nodes, no awaits, no UI.
## Every state change appends a CombatEvent; presenters drain and animate them.
##
## Round flow:
##   begin_round()      ROUND_START -> ASSIGNMENT (intents shown, machine spun)
##   assign_chip()...   fills ability sockets; full abilities fire immediately
##   end_assignment()   discards tray, runs the enemy phase, ticks statuses,
##                      then returns to ROUND_START (or ENDED on win/loss)

enum Phase { ROUND_START, ASSIGNMENT, ENDED }

var phase: Phase = Phase.ROUND_START
var round_number := 0

var hero: CombatActor
var enemies: Array[CombatActor] = []
var abilities: Array[AbilityState] = []
var tray := ChipTray.new()
var machine: SlotMachine
var targeting := Targeting.new()
var rng: GameRng
var pending_rewards: Array[Dictionary] = []  # gain_coins / grant_relic ops for the run layer

var _db: ContentDB
var _brains: Dictionary = {}        # enemy id -> EnemyBrain
var _intents: Dictionary = {}       # enemy id -> move Dictionary
var _dmg_mult := 1.0
var _events: Array[CombatEvent] = []


func _init(db: ContentDB, config: Dictionary) -> void:
	_db = db
	rng = GameRng.new(int(config.get("seed", 0)))
	machine = config.get("machine", SlotMachine.new())
	_dmg_mult = float(config.get("dmg_mult", 1.0))
	var hp_mult := float(config.get("hp_mult", 1.0))

	var hero_def := db.get_hero(StringName(str(config.get("hero", "ace"))))
	hero = CombatActor.new(&"hero", hero_def.id, hero_def.name, hero_def.max_hp, true)
	if config.has("hero_hp"):
		hero.hp = int(config["hero_hp"])

	for ability_id in config.get("abilities", []):
		abilities.append(AbilityState.new(db.get_ability(StringName(str(ability_id)))))

	var index := 0
	for enemy_id in config.get("enemies", []):
		var def := db.get_enemy(StringName(str(enemy_id)))
		var enemy := CombatActor.new(StringName("enemy_%d" % index), def.id,
			def.name, int(round(def.hp * hp_mult)))
		enemies.append(enemy)
		_brains[enemy.id] = EnemyBrain.new(def.brain, def.moves)
		index += 1


func drain_events() -> Array[CombatEvent]:
	var out := _events
	_events = []
	return out


func emit_event(type: StringName, data: Dictionary = {}) -> void:
	_events.append(CombatEvent.new(type, data))


func begin_round() -> bool:
	if phase != Phase.ROUND_START:
		return false
	round_number += 1
	hero.on_round_start()
	for enemy in enemies:
		enemy.on_round_start()
	emit_event(&"round_started", {"round": round_number})

	_intents.clear()
	var shown := []
	for enemy in enemies:
		if not enemy.is_alive():
			continue
		var brain: EnemyBrain = _brains[enemy.id]
		var move_id := brain.next_move(rng.stream(&"combat"), float(enemy.hp) / enemy.max_hp)
		var move: Dictionary = _db.get_enemy(enemy.def_id).moves.get(move_id, {})
		_intents[enemy.id] = move
		shown.append({"actor": enemy.id, "move": move_id, "intent": move.get("intent", {})})
	emit_event(&"intents_shown", {"intents": shown})

	var result := machine.spin(rng.stream(&"combat"))
	tray.add_payout(result.payout)
	emit_event(&"spin_resolved", {"symbols": result.symbols, "payout": result.payout})

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
	phase = Phase.ROUND_START
	return true


func check_death(actor: CombatActor) -> void:
	if actor.is_alive() or actor.is_hero:
		return
	emit_event(&"actor_died", {"actor": actor.id})
	if targeting.manual_target_id == actor.id:
		targeting.manual_target_id = &""
	if enemies.all(func(e: CombatActor) -> bool: return not e.is_alive()):
		emit_event(&"combat_won", {})
		phase = Phase.ENDED


func _fire_ability(ability: AbilityState) -> void:
	var target := targeting.effective_target(enemies)
	emit_event(&"ability_fired", {"ability": ability.def.id, "target": target.id if target else &""})
	EffectInterpreter.execute(ability.def.effects, self, hero, target)
	if ability.bonus_active():
		EffectInterpreter.execute(ability.def.bonus_effects, self, hero, target)
	ability.clear()


func _run_enemy_phase() -> void:
	for enemy in enemies:
		if not enemy.is_alive():
			continue
		if enemy.has_status(&"stun"):
			emit_event(&"enemy_move", {"actor": enemy.id, "skipped": true})
			continue
		var move: Dictionary = _intents.get(enemy.id, {})
		var intent: Dictionary = move.get("intent", {})
		emit_event(&"enemy_move", {"actor": enemy.id, "skipped": false})

		var instances := int(intent.get("instances", 0))
		var per_hit := int(round(int(intent.get("per_hit", 0)) * _dmg_mult))
		for i in instances:
			if not hero.is_alive():
				break
			var damage := StatusRules.attack_damage(per_hit, enemy)
			damage = StatusRules.damage_taken(damage, hero)
			var hp_lost := hero.take_damage(damage)
			emit_event(&"damage_dealt", {
				"source": enemy.id, "target": hero.id,
				"amount": damage, "hp_lost": hp_lost,
			})
		for debuff: Dictionary in intent.get("debuffs", []):
			if not hero.is_alive():
				break
			var status := StringName(str(debuff.get("status", "")))
			var stacks := int(debuff.get("stacks", 1))
			hero.apply_status(status, stacks)
			emit_event(&"status_applied",
				{"actor": hero.id, "status": status, "stacks": stacks})

		if not hero.is_alive():
			emit_event(&"combat_lost", {})
			phase = Phase.ENDED
			return
