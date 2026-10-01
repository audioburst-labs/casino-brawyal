class_name EnemyBrain
extends RefCounted
## Picks an enemy's next move from its brain config (see act1_enemies.json).
## Types:
##   sequence  — looping (or one-shot) scripted move order
##   weighted  — weighted random; no_repeat: <move> blocks one move from
##               repeating, no_repeat_last: true blocks any immediate repeat
##   pair_then — the sheet's "1 -> 2 / 2 -> 1, 3" pattern per designer ruling:
##               opening pair in random order, then the tail moves in order,
##               looping (pair re-shuffled each cycle)
##   intro_loop — plays "intro" once in order, then loops "loop" in order
##               (the boss's "1,2,3,4,5 -> repeat 2,4,5" pattern)
##   phased    — hp-threshold sub-brains; phases authored with descending
##               hp_below (1.0 first), tightest matching phase wins

var _config: Dictionary
var _moves: Dictionary
var _step := 0
var _last_move := ""
var _queue: Array[String] = []
var _phase_brains: Array[EnemyBrain] = []


func _init(config: Dictionary, moves: Dictionary) -> void:
	_config = config
	_moves = moves
	if config.get("type") == "phased":
		for phase: Dictionary in config.get("phases", []):
			_phase_brains.append(EnemyBrain.new(phase.get("brain", {}), moves))


func snapshot() -> Dictionary:
	var phases := []
	for brain in _phase_brains:
		phases.append(brain.snapshot())
	return {"step": _step, "last_move": _last_move, "queue": _queue.duplicate(), "phases": phases}


func restore(snap: Dictionary) -> void:
	_step = int(snap.step)
	_last_move = str(snap.last_move)
	_queue.assign(snap.queue)
	for i in mini(_phase_brains.size(), (snap.phases as Array).size()):
		_phase_brains[i].restore(snap.phases[i])


func next_move(rng: RandomNumberGenerator, hp_ratio: float = 1.0) -> String:
	match _config.get("type", ""):
		"sequence":
			return _next_sequence()
		"weighted":
			return _next_weighted(rng)
		"pair_then":
			return _next_pair_then(rng)
		"intro_loop":
			return _next_intro_loop()
		"phased":
			return _next_phased(rng, hp_ratio)
	push_error("EnemyBrain: unknown brain type '%s'" % _config.get("type"))
	return ""


func _next_sequence() -> String:
	var steps: Array = _config.get("steps", [])
	var move: String = steps[_step % steps.size()]
	_step += 1
	if not _config.get("loop", true):
		_step = mini(_step, steps.size() - 1)
	return move


func _next_weighted(rng: RandomNumberGenerator) -> String:
	var weights: Dictionary = _config.get("weights", {})
	var no_repeat: String = _config.get("no_repeat", "")
	var block_last: bool = _config.get("no_repeat_last", false)
	var candidates: Array[String] = []
	var totals: Array[int] = []
	var total := 0
	for move: String in weights:
		if move == _last_move and (block_last or move == no_repeat):
			continue
		candidates.append(move)
		total += int(weights[move])
		totals.append(total)
	var roll := rng.randi_range(1, total)
	for i in candidates.size():
		if roll <= totals[i]:
			_last_move = candidates[i]
			return _last_move
	return ""


func _next_pair_then(rng: RandomNumberGenerator) -> String:
	if _queue.is_empty():
		var pair: Array = (_config.get("pair", []) as Array).duplicate()
		if rng.randi_range(0, 1) == 1:
			pair.reverse()
		for move in pair:
			_queue.append(str(move))
		for move in _config.get("then", []):
			_queue.append(str(move))
	_last_move = _queue.pop_front()
	return _last_move


func _next_intro_loop() -> String:
	var intro: Array = _config.get("intro", [])
	if _step < intro.size():
		_last_move = str(intro[_step])
		_step += 1
		return _last_move
	var loop: Array = _config.get("loop", [])
	_last_move = str(loop[(_step - intro.size()) % loop.size()])
	_step += 1
	return _last_move


func _next_phased(rng: RandomNumberGenerator, hp_ratio: float) -> String:
	var phases: Array = _config.get("phases", [])
	var chosen := 0
	for i in phases.size():
		if hp_ratio <= float(phases[i].get("hp_below", 1.0)):
			chosen = i
	return _phase_brains[chosen].next_move(rng, hp_ratio)
