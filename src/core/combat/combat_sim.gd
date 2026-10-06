class_name CombatSim
extends RefCounted
## The combat rules engine. Pure logic: no Nodes, no awaits, no UI.
## Every state change appends a CombatEvent; presenters drain and animate them.
##
## Round flow:
##   begin_round()      ROUND_START -> ASSIGNMENT (hero turn start: buffs tick,
##                      passives fire, intents shown, machine spun)
##   assign_chip()...   fills ability sockets; full abilities fire immediately
##   end_assignment()   hero turn end (debuffs tick), discards tray, runs the
##                      enemy phase — each enemy ticks its own buffs before it
##                      acts and its own debuffs after — then returns to
##                      ROUND_START (or ENDED on win/loss)

## CHOICE is the doc's "Options In Combat": the round pauses after the intents
## are shown, the presenter dims the field and offers the player a decision,
## and `choose()` resumes the round start (patch 0.22).
enum Phase { ROUND_START, CHOICE, ASSIGNMENT, ENDED }

const MAX_ENEMIES := 4      # patch 0.13: the field holds at most 4 fighters
const EMBLEM_MULTIPLIER := 1.3
const LUCKY_FOOT_CHANCE := 0.1
## Rage X: "your next attack deals X bonus damage". The designer's call is that
## the bonus lands on EVERY hit of that attack, so a Rage 10 into a 2x0 move
## deals 20 (patch 0.22).
const RAGE_PER_HIT := true
## Loans are offered on the Loan Shark's 1st, 4th, 7th... round.
const LOAN_FIRST_ROUND := 1

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
var _intent_ids: Dictionary = {}    # enemy id -> move id (for display refresh)
## Chips a Gift move promised; handed over after the next spin so the player
## sees them arrive with the payout.
var _pending_gift_chips := 0
var _gift_giver: StringName = &""   # who promised them, for the arrival animation
var _pending_choice: Dictionary = {}
## Run-level ops that must land NOW rather than when the fight ends (0.117):
## a loan's coins. "Cash Advance should always give coins" - a lost fight
## paid nothing while they sat in pending_rewards. The presenter applies each
## one as its `run_effect` event plays; the bot applies the list afterwards.
var run_ops: Array[Dictionary] = []
var settling_loan := false
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
var _exclusive_lock: AbilityState = null   # set when an exclusive ability fires
var _summon_counter := 0
## Scripted fights (the tutorial): the symbols the machine lands on for the Nth
## spin of the fight, and the move a given enemy kind opens with. Anything
## past the script falls back to the dice, so a scripted fight ends as a normal
## one. `config["scripted_spins"]` is an array of per-spin symbol arrays.
var _scripted_spins: Array = []
var _spin_index := 0
var _first_moves: Dictionary = {}


func _init(db: ContentDB, config: Dictionary) -> void:
	_db = db
	rng = GameRng.new(int(config.get("seed", 0)))
	machine = config.get("machine", SlotMachine.new())
	_dmg_mult = float(config.get("dmg_mult", 1.0))
	_hp_mult = float(config.get("hp_mult", 1.0))
	_scripted_spins = (config.get("scripted_spins", []) as Array).duplicate(true)
	_first_moves = (config.get("first_moves", {}) as Dictionary).duplicate()

	var hero_def := db.get_hero(StringName(str(config.get("hero", "ace"))))
	# The run's ceiling, not the def's (0.117): a raised max HP used to reach
	# the header but never the fighter, so the two readings disagreed.
	var ceiling := int(config.get("hero_max_hp", hero_def.max_hp))
	hero = CombatActor.new(&"hero", hero_def.id, hero_def.name, ceiling, true)
	if config.has("hero_hp"):
		hero.hp = mini(int(config["hero_hp"]), ceiling)

	# Each equipped ability enters at the tier the run owns it at (v0.19).
	var tiers: Dictionary = config.get("ability_tiers", {})
	for ability_id in config.get("abilities", []):
		var id := StringName(str(ability_id))
		abilities.append(AbilityState.new(db.get_ability(id, int(tiers.get(id, 0)))))

	for relic_id in config.get("relics", []):
		var relic := db.get_relic(StringName(str(relic_id)))
		if relic == null:
			continue
		_relics.append(relic)
		match relic.id:
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
func ability_multiplier(ability: AbilityState) -> float:
	if ability == null:
		return 1.0
	var cost := ability.def.cost
	if _has_dark_emblem and (cost.has(&"spade") or cost.has(&"club")):
		return EMBLEM_MULTIPLIER
	if _has_red_emblems and (cost.has(&"heart") or cost.has(&"diamond")):
		return EMBLEM_MULTIPLIER
	return 1.0


func active_ability_multiplier() -> float:
	return ability_multiplier(_active_ability)


## What a damage op's base would deal right now (hero modifiers + emblems,
## before the target's defenses). Used for live numbers on ability cards.
func preview_damage(base: int, ability: AbilityState) -> int:
	var damage := StatusRules.attack_damage(base + hero.status_stacks(&"rage"), hero, _weak_pct)
	return int(floor(damage * ability_multiplier(ability) + 0.5))


## What a block op's base would actually grant right now — Frail taxes it
## (patch 0.22: "Block numbers on abilities should be affected by
## buffs/debuffs and show the correct numbers when used").
## The ability currently resolving, for effects that need to read the chips
## that paid for it (Rainbow's two suits, Earn-the-used-chip).
func active_ability() -> AbilityState:
	return _active_ability


## Earn (sheet v0.122): chips arriving in the tray from an ability. Fires the
## "when you Earn" passives - Chip Tricks turns every Earn into Block.
func on_chips_earned(count: int) -> void:
	if count <= 0:
		return
	_fire_triggered_passives("earn")


## Mark landing on an enemy fires the "when you Mark" passives (Sharp Edge).
func on_enemy_marked(actor: CombatActor) -> void:
	if actor == null:
		return
	_fire_triggered_passives("mark", actor)


## Passives that wait for something to happen rather than for a round to
## start. Re-entrancy is guarded: a triggered passive that Earns or Marks
## again must not fire itself forever.
var _triggering := false


func _fire_triggered_passives(trigger: String, target: CombatActor = null) -> void:
	if _triggering:
		return
	_triggering = true
	for def: Defs.AbilityDef in passives:
		if def.passive_trigger != trigger:
			continue
		emit_event(&"passive_fired", {"ability": def.id})
		EffectInterpreter.execute(def.effects, self, hero,
			target if target != null else targeting.effective_target(enemies))
	_triggering = false


func preview_block(base: int) -> int:
	return StatusRules.block_gained(base, hero)


func begin_round() -> bool:
	if phase != Phase.ROUND_START:
		return false
	round_number += 1
	abilities_fired_this_round = 0
	_exclusive_lock = null
	# The hero's turn begins: his shield drops and his buffs tick (patch 0.22).
	# Enemies tick their own at their own slot in the enemy phase.
	hero.on_turn_start()
	emit_event(&"turn_started", {"actor": hero.id})
	for ability in abilities:
		ability.uses_this_round = 0
	emit_event(&"round_started", {"round": round_number})
	if round_number == 1:
		_fire_relics(&"combat_started")
	_fire_relics(&"round_started")
	_fire_passives()

	_intents.clear()
	_intent_ids.clear()
	var shown := []
	for enemy in enemies:
		if not enemy.is_alive():
			continue
		var brain: EnemyBrain = _brains[enemy.id]
		var move_id := brain.next_move(rng.stream(&"combat"), float(enemy.hp) / enemy.max_hp)
		move_id = _skip_summon_if_full(enemy, move_id)
		var move: Dictionary = _db.get_enemy(enemy.def_id).moves.get(move_id, {})
		_intents[enemy.id] = move
		_intent_ids[enemy.id] = move_id
		var entry := _build_intent_entry(enemy, move_id)
		shown.append(entry)
	emit_event(&"intents_shown", {"intents": shown})

	# An enemy may interrupt here to put a choice to the player (the Loan
	# Shark). The machine is not spun until they have answered.
	if _offer_pending_choice():
		phase = Phase.CHOICE
		return true
	_finish_round_start()
	return true


## The rest of the round start, after any "Options In Combat" decision.
func _finish_round_start() -> void:
	_spin_machine()
	_deliver_gift_chips()
	phase = Phase.ASSIGNMENT

## Gift X (sheet v0.120): "give the player X random chips at the start of their
## next turn". Handed over after the spin so they are seen landing with the
## payout rather than appearing out of nowhere.
func _deliver_gift_chips() -> void:
	if _pending_gift_chips <= 0:
		return
	var count := _pending_gift_chips
	_pending_gift_chips = 0
	for i in count:
		_grant_random_chip(&"gift")


func _grant_random_chip(source: StringName) -> void:
	var suit: StringName = ContentDB.SUITS[
		rng.stream(&"combat").randi_range(0, ContentDB.SUITS.size() - 1)]
	tray.add(suit, 1)
	var data := {"suit": suit, "count": 1, "source": source}
	if source == &"gift":
		data["actor"] = _gift_giver
	emit_event(&"chips_generated", data)


## Loan passive: "at the start of every 3 rounds, offer 1 of 2 loans".
func _offer_pending_choice() -> bool:
	for enemy in enemies:
		if not enemy.is_alive():
			continue
		var passive: Dictionary = _db.get_enemy(enemy.def_id).passive
		if str(passive.get("type", "")) != "loan":
			continue
		var every := maxi(1, int(passive.get("every_rounds", 3)))
		if (round_number - LOAN_FIRST_ROUND) % every != 0 or round_number < LOAN_FIRST_ROUND:
			continue
		var pool: Array = _db.all_loan_ids().filter(
			func(id: StringName) -> bool: return _loan_offerable(_db.get_loan(id)))
		if pool.is_empty():
			continue
		var offers: Array = []
		var wanted := mini(int(passive.get("offers", 2)), pool.size())
		for i in wanted:
			var index := rng.stream(&"combat").randi_range(0, pool.size() - 1)
			var loan: Defs.LoanDef = _db.get_loan(pool[index])
			pool.remove_at(index)
			offers.append({
				"id": String(loan.id), "title": loan.title, "turns": loan.turns,
				"reward_text": loan.reward_text, "penalty_text": loan.penalty_text,
			})
		_pending_choice = {"actor": enemy.id, "kind": "loan", "options": offers}
		emit_event(&"choice_offered", _pending_choice.duplicate(true))
		return true
	return false


## Sheet v0.122: a loan that heals is not offered to a hero on full health —
## it would buy a reward of nothing with a real penalty (patch 0.114).
func _loan_offerable(loan: Defs.LoanDef) -> bool:
	if loan == null:
		return false
	match loan.requires:
		"wounded":
			return hero.hp < hero.max_hp
	return true


func pending_choice() -> Dictionary:
	return _pending_choice


## The player picks one of the offered options; its reward lands immediately
## and the round start resumes (doc: "Selecting an option immediately executes
## its corresponding outcome before resuming standard battle progression").
func choose(index: int) -> bool:
	if phase != Phase.CHOICE:
		return false
	var options: Array = _pending_choice.get("options", [])
	if index < 0 or index >= options.size():
		return false
	var loan: Defs.LoanDef = _db.get_loan(StringName(str(options[index].id)))
	_pending_choice = {}
	if loan == null:
		_finish_round_start()
		return true
	settling_loan = true
	EffectInterpreter.execute(loan.reward, self, hero, targeting.effective_target(enemies))
	settling_loan = false
	hero.loans.append({"id": loan.id, "turns_left": loan.turns})
	emit_event(&"loan_taken", {"loan": loan.id, "title": loan.title,
		"turns": loan.turns, "penalty_text": loan.penalty_text})
	_finish_round_start()
	return true


## Patch 0.13: with all MAX_ENEMIES slots full, summon moves are swapped for
## the enemy's next non-summon move.
func _skip_summon_if_full(enemy: CombatActor, move_id: String) -> String:
	var moves: Dictionary = _db.get_enemy(enemy.def_id).moves
	if moves.get(move_id, {}).get("intent", {}).get("summon", {}).is_empty():
		return move_id
	if _living_count() < MAX_ENEMIES:
		return move_id
	var keys := moves.keys()
	var start := keys.find(move_id)
	for offset in range(1, keys.size()):
		var candidate: String = keys[(start + offset) % keys.size()]
		if moves[candidate].get("intent", {}).get("summon", {}).is_empty():
			return candidate
	return move_id


func _living_count() -> int:
	return enemies.filter(func(e: CombatActor) -> bool: return e.is_alive()).size()


func _build_intent_entry(enemy: CombatActor, move_id: String) -> Dictionary:
	var move: Dictionary = _intents.get(enemy.id, {})
	var intent: Dictionary = move.get("intent", {})
	var entry := {"actor": enemy.id, "move": move_id, "intent": intent}
	# Multistrike and Rage move the announced numbers, so the intent has to
	# show what will actually land (patch 0.22) — and since 0.114 that means
	# the HERO's Vulnerable too. Announcing the pre-Vulnerable figure and then
	# hitting for 50% more is the intent lying about the one number the player
	# plans their whole turn around.
	entry["display_per_hit"] = StatusRules.damage_taken(
		StatusRules.attack_damage(_move_per_hit(enemy, intent), enemy, _weak_pct),
		hero, _vuln_pct)
	entry["display_instances"] = _move_instances(enemy, intent)
	if not _db.get_enemy(enemy.def_id).passive.is_empty():
		entry["passive"] = _db.get_enemy(enemy.def_id).passive
		entry["passive_count"] = enemy.passive_counter
	return entry


## Instances of damage this move will deal, Multistrike included.
func _move_instances(enemy: CombatActor, intent: Dictionary) -> int:
	var instances := int(intent.get("instances", 0))
	if instances <= 0:
		return 0
	return instances + enemy.status_stacks(&"multistrike")


## Damage per hit, dmg_mult and Rage included.
func _move_per_hit(enemy: CombatActor, intent: Dictionary) -> int:
	var per_hit := int(round(int(intent.get("per_hit", 0)) * _dmg_mult))
	if int(intent.get("instances", 0)) > 0 and RAGE_PER_HIT:
		per_hit += enemy.status_stacks(&"rage")
	return per_hit


## Current intent numbers for one enemy, recomputed with its live statuses —
## the UI refreshes shown damage when buffs/debuffs land (patch 0.13).
func intent_display(enemy_id: StringName) -> Dictionary:
	for enemy in enemies:
		if enemy.id == enemy_id and _intents.has(enemy_id):
			return _build_intent_entry(enemy, str(_intent_ids.get(enemy_id, "")))
	return {}


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
	if _exclusive_lock != null and ability != _exclusive_lock:
		return false  # e.g. Slow Playing locks the rest of the turn
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

	# The hero's turn ends here, BEFORE the enemy phase: his debuffs each
	# covered a full turn of his (patch 0.22).
	hero.tick_turn_end()
	_tick_loans()
	emit_event(&"turn_ended", {"actor": hero.id})
	if phase == Phase.ENDED:
		return true

	_run_enemy_phase()
	if phase == Phase.ENDED:
		return true

	emit_event(&"round_ended", {"round": round_number})
	_fire_relics(&"round_ended")
	phase = Phase.ROUND_START
	return true


## Every point of damage an enemy takes runs through here, so its passive can
## react (patch 0.22). Called by EffectInterpreter right after `damage_dealt`.
## The number an enemy passive starts its countdown at, or -1 for a passive
## that keeps no count. Patch 0.113: the sheet reads "count DOWN all damage
## taken", and the unit wears the number as a permanent buff, ticking to 0.
static func passive_start(passive: Dictionary) -> int:
	match str(passive.get("type", "")):
		"bust":
			return maxi(1, int(passive.get("threshold", 21)))
		"break":
			return maxi(1, int(passive.get("every", 20)))
	return -1


## Every point of damage an enemy takes runs through here, so its passive can
## react (patch 0.22). Called by EffectInterpreter right after `damage_dealt`.
func on_enemy_damaged(actor: CombatActor, hp_lost: int) -> void:
	if actor == null or actor.is_hero or hp_lost <= 0:
		return
	var passive: Dictionary = _db.get_enemy(actor.def_id).passive
	if passive.is_empty():
		return
	var start := passive_start(passive)
	if actor.passive_counter < 0:
		actor.passive_counter = start
	var remaining := actor.passive_counter - hp_lost
	match str(passive.get("type", "")):
		"bust":
			# Dealer: the count runs down from 21 and fires at 0 — it is
			# stunned and its Strength is wiped, then the count resets.
			if remaining <= 0:
				remaining = start
				actor.statuses.erase(&"strength")
				actor.apply_status(&"stun", 1)
				emit_event(&"enemy_busted", {"actor": actor.id, "threshold": start})
				emit_event(&"status_applied",
					{"actor": actor.id, "status": &"stun", "stacks": 1})
		"break":
			# Chip Golem: a chip for every 20 health it loses.
			while remaining <= 0:
				remaining += start
				_grant_random_chip(&"break")
	actor.passive_counter = remaining
	emit_event(&"passive_counter", {"actor": actor.id, "value": remaining})


## The loan countdown runs with the hero's own debuffs, at the end of his turn
## (doc: "at the end of each turn, this number is reduced by one").
func _tick_loans() -> void:
	if hero.loans.is_empty():
		return
	var due: Array[Dictionary] = []
	for loan: Dictionary in hero.loans:
		loan.turns_left = int(loan.turns_left) - 1
		emit_event(&"loan_ticked",
			{"loan": loan.id, "turns_left": int(loan.turns_left)})
		if int(loan.turns_left) <= 0:
			due.append(loan)
	for loan: Dictionary in due:
		hero.loans.erase(loan)
		var def: Defs.LoanDef = _db.get_loan(StringName(str(loan.id)))
		if def == null:
			continue
		emit_event(&"loan_due", {"loan": def.id, "title": def.title,
			"penalty_text": def.penalty_text})
		settling_loan = true
		EffectInterpreter.execute(def.penalty, self, hero, null)
		settling_loan = false
		_check_hero_death()
		if phase == Phase.ENDED:
			return


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


## Re-spins the machine and adds the payout (Go Again / High Roller).
## No-op once the combat has ended (patch 0.13 crash fix: winning with
## Pay Line must not spin into a dead encounter).
func spin_again() -> void:
	if phase == Phase.ENDED:
		return
	_spin_machine()


func _spin_machine() -> void:
	var forced: Array = []
	if _spin_index < _scripted_spins.size():
		forced = _scripted_spins[_spin_index]
	_spin_index += 1
	var result := machine.spin(rng.stream(&"combat"), forced)
	last_symbols = result.symbols
	last_payout = result.payout
	tray.add_payout(result.payout)
	emit_event(&"spin_resolved", {"symbols": result.symbols, "payout": result.payout})
	_fire_relics(&"spin_resolved")


## `enemies` is ordered from the centre of the field outward: index 0 is the
## slot closest to the middle of the screen, index 3 the furthest. That order
## is also the enemy phase's "left to right" acting order.
func _spawn_enemy(def_id: StringName, announce := true,
		summoner: CombatActor = null) -> void:
	var def := _db.get_enemy(def_id)
	var stream := rng.stream(&"combat")
	var hp := int(round(stream.randi_range(def.hp_min, def.hp_max) * _hp_mult))
	var enemy := CombatActor.new(StringName("enemy_%d" % _summon_counter), def.id, def.name, hp)
	enemy.passive_counter = passive_start(def.passive)
	_summon_counter += 1
	var slot := _summon_slot(summoner)
	if slot < 0:
		enemies.append(enemy)
	else:
		enemies.insert(slot, enemy)
	_brains[enemy.id] = EnemyBrain.new(def.brain, def.moves)
	if _first_moves.has(String(def.id)):
		_brains[enemy.id].start_with(str(_first_moves[String(def.id)]))
	_evict_outermost_corpse()
	if announce:
		emit_event(&"enemy_summoned",
			{"actor": enemy.id, "def_id": def.id, "name": def.name, "hp": hp,
			"slot": enemies.find(enemy)})


## Doc "Unit Positioning": a summon takes the nearest empty slot between its
## summoner and the centre of the field; failing that the summoner shifts one
## position further out to make room. An "empty" inner slot is one whose
## occupant is dead — that corpse is cleared away as the new unit takes over.
func _summon_slot(summoner: CombatActor) -> int:
	if summoner == null:
		return -1
	var index := enemies.find(summoner)
	if index < 0:
		return -1
	for inner in range(index - 1, -1, -1):
		if not enemies[inner].is_alive():
			_remove_actor(enemies[inner])
			return inner
	return index  # no inner slot: the summoner is pushed one step outward


## Keeps the field within its MAX_ENEMIES slots by clearing the corpse
## furthest from the centre (living fighters are never displaced).
func _evict_outermost_corpse() -> void:
	while enemies.size() > MAX_ENEMIES:
		var victim: CombatActor = null
		for index in range(enemies.size() - 1, -1, -1):
			if not enemies[index].is_alive():
				victim = enemies[index]
				break
		if victim == null:
			return
		_remove_actor(victim)


func _remove_actor(actor: CombatActor) -> void:
	enemies.erase(actor)
	_brains.erase(actor.id)
	_intents.erase(actor.id)
	_intent_ids.erase(actor.id)
	emit_event(&"actor_removed", {"actor": actor.id})


func _fire_relics(trigger: StringName) -> void:
	for relic: Defs.RelicDef in _relics:
		if relic.trigger != trigger or relic.effects.is_empty():
			continue
		emit_event(&"relic_triggered", {"relic": relic.id})
		EffectInterpreter.execute(relic.effects, self, hero,
			targeting.effective_target(enemies))


func _fire_passives() -> void:
	for def: Defs.AbilityDef in passives:
		# A passive with a trigger waits for that trigger instead (0.115).
		if def.passive_trigger != "":
			continue
		emit_event(&"passive_fired", {"ability": def.id})
		EffectInterpreter.execute(def.effects, self, hero,
			targeting.effective_target(enemies))


func _fire_ability(ability: AbilityState) -> void:
	ability.uses_this_round += 1
	ability.uses_this_combat += 1
	abilities_fired_this_round += 1
	if ability.def.exclusive:
		_exclusive_lock = ability
	var target := targeting.effective_target(enemies)
	emit_event(&"ability_fired", {"ability": ability.def.id, "target": target.id if target else &""})
	if ability.def.passive:
		if not passives.has(ability.def):
			passives.append(ability.def)
		emit_event(&"passive_gained", {"ability": ability.def.id})
		# It pays on the turn you play it as well as at every round start
		# after (patch 0.113, designer's call). "At the start of your turn" —
		# you are ON your turn; spending two chips for nothing read as broken
		# math, which is what the Face Reader note was about.
		#
		# A TRIGGERED passive (Chip Tricks, Sharp Edge) is different: it has an
		# active half that runs now, and its passive half waits for the trigger.
		_active_ability = ability
		if ability.def.passive_trigger == "":
			EffectInterpreter.execute(ability.def.effects, self, hero, target)
		else:
			EffectInterpreter.execute(ability.def.active_effects, self, hero, target)
		_active_ability = null
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
		# Its own turn: block drops and buffs tick, it acts, then its debuffs
		# tick — so a Stun is spent by the very action it skipped (patch 0.22).
		enemy.on_turn_start()
		emit_event(&"turn_started", {"actor": enemy.id})
		if enemy.has_status(&"stun"):
			emit_event(&"enemy_move", {"actor": enemy.id, "skipped": true})
			enemy.tick_turn_end()
			emit_event(&"turn_ended", {"actor": enemy.id})
			continue
		_execute_move(enemy, true)
		if phase == Phase.ENDED:
			return
		if enemy.is_alive():
			enemy.tick_turn_end()
			emit_event(&"turn_ended", {"actor": enemy.id})


func _execute_move(enemy: CombatActor, allow_encore: bool) -> void:
	var move: Dictionary = _intents.get(enemy.id, {})
	var intent: Dictionary = move.get("intent", {})

	emit_event(&"enemy_move", {"actor": enemy.id, "skipped": false})

	# Absorb (sheet v0.120): "remove all chips placed on abilities."
	if intent.get("absorb", false):
		var taken := 0
		for ability in abilities:
			for slot in ability.filled.size():
				if ability.filled[slot] != &"":
					taken += 1
			ability.clear()
		emit_event(&"chips_absorbed", {"actor": enemy.id, "count": taken})

	if int(intent.get("self_block", 0)) > 0:
		var shield := int(intent.get("self_block"))
		enemy.gain_block(shield)
		emit_event(&"block_gained", {"actor": enemy.id, "amount": shield})

	if int(intent.get("gift_chips", 0)) > 0:
		_pending_gift_chips += int(intent.get("gift_chips"))
		_gift_giver = enemy.id
		emit_event(&"gift_promised",
			{"actor": enemy.id, "count": int(intent.get("gift_chips"))})

	var summon: Dictionary = intent.get("summon", {})
	if not summon.is_empty():
		for i in int(summon.get("count", 1)):
			if _living_count() >= MAX_ENEMIES:
				break  # the field never holds more than 4 (patch 0.13)
			_spawn_enemy(StringName(str(summon.get("enemy", ""))), true, enemy)

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

	var instances := _move_instances(enemy, intent)
	var per_hit := _move_per_hit(enemy, intent)
	for i in instances:
		if not hero.is_alive():
			break
		_hit_hero(enemy, per_hit)
	if instances > 0 and enemy.has_status(&"rage"):
		# "Your NEXT attack deals X bonus damage" — spent by that attack.
		var spent := enemy.status_stacks(&"rage")
		enemy.statuses.erase(&"rage")
		emit_event(&"rage_spent", {"actor": enemy.id, "amount": spent})
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
		"blocked": hero.last_absorbed,
	})


## The hero dies like anyone else: `actor_died` first, so the presenter can
## play the death animation on the same beat as the killing blow, and only
## then `combat_lost` (patch 0.19 — the defeat banner used to land while Ace
## was still standing, because he never got a death event at all).
func _check_hero_death() -> void:
	if hero.is_alive() or phase == Phase.ENDED:
		return
	emit_event(&"actor_died", {"actor": hero.id})
	emit_event(&"combat_lost", {})
	phase = Phase.ENDED
