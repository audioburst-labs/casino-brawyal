class_name EnemyBrain
extends RefCounted
## Picks an enemy's next move from its brain config (see act1_enemies.json).
## Types:
##   sequence — looping (or one-shot) scripted move order
##   weighted — weighted random, optional no_repeat move
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
	var candidates: Array[String] = []
	var totals: Array[int] = []
	var total := 0
	for move: String in weights:
		if move == no_repeat and move == _last_move:
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


func _next_phased(rng: RandomNumberGenerator, hp_ratio: float) -> String:
	var phases: Array = _config.get("phases", [])
	var chosen := 0
	for i in phases.size():
		if hp_ratio <= float(phases[i].get("hp_below", 1.0)):
			chosen = i
	return _phase_brains[chosen].next_move(rng, hp_ratio)
