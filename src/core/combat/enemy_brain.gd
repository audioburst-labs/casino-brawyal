class_name EnemyBrain
extends RefCounted
## Picks an enemy's next move from its brain config (see act1_enemies.json).
## Types:
##   sequence — looping (or one-shot) scripted move order
##   weighted — weighted random; no_repeat: <move> blocks one move from
##              repeating, no_repeat_last: true blocks any immediate repeat
##   graph    — start node + edges map; each turn moves to a random successor
##              (encodes the sheet's "1 -> 2 / 2 -> 1, 3" patterns)
##   phased   — hp-threshold sub-brains; phases authored with descending
##              hp_below (1.0 first), tightest matching phase wins

var _config: Dictionary
var _moves: Dictionary
var _step := 0
var _last_move := ""
var _phase_brains: Array[EnemyBrain] = []


func _init(config: Dictionary, moves: Dictionary) -> void:
	_config = config
	_moves = moves
	if config.get("type") == "phased":
		for phase: Dictionary in config.get("phases", []):
			_phase_brains.append(EnemyBrain.new(phase.get("brain", {}), moves))


func next_move(rng: RandomNumberGenerator, hp_ratio: float = 1.0) -> String:
	match _config.get("type", ""):
		"sequence":
			return _next_sequence()
		"weighted":
			return _next_weighted(rng)
		"graph":
			return _next_graph(rng)
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


func _next_graph(rng: RandomNumberGenerator) -> String:
	if _last_move == "":
		_last_move = str(_config.get("start", ""))
		return _last_move
	var edges: Dictionary = _config.get("edges", {})
	var successors: Array = edges.get(_last_move, [])
	if successors.is_empty():
		_last_move = str(_config.get("start", ""))
		return _last_move
	_last_move = str(successors[rng.randi_range(0, successors.size() - 1)])
	return _last_move


func _next_phased(rng: RandomNumberGenerator, hp_ratio: float) -> String:
	var phases: Array = _config.get("phases", [])
	var chosen := 0
	for i in phases.size():
		if hp_ratio <= float(phases[i].get("hp_below", 1.0)):
			chosen = i
	return _phase_brains[chosen].next_move(rng, hp_ratio)
