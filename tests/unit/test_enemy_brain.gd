extends GutTest
## EnemyBrain: interprets an enemy's brain config to pick the next move.
## Types: sequence (looping script), weighted (random with optional no-repeat),
## phased (hp-threshold sub-brains, for the boss).

const MOVES := {"jab": {}, "haymaker": {}, "nuke": {}}


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	return rng


func test_sequence_brain_loops_its_steps() -> void:
	var brain := EnemyBrain.new(
		{"type": "sequence", "loop": true, "steps": ["jab", "jab", "haymaker"]}, MOVES)
	var rng := _rng()
	var picks: Array[String] = []
	for i in 7:
		picks.append(brain.next_move(rng))
	assert_eq(picks, ["jab", "jab", "haymaker", "jab", "jab", "haymaker", "jab"] as Array[String])


func test_weighted_brain_only_picks_known_moves() -> void:
	var brain := EnemyBrain.new(
		{"type": "weighted", "weights": {"jab": 2, "haymaker": 1}}, MOVES)
	var rng := _rng()
	for i in 50:
		assert_has(["jab", "haymaker"], brain.next_move(rng))


func test_weighted_brain_never_repeats_a_no_repeat_move() -> void:
	var brain := EnemyBrain.new(
		{"type": "weighted", "weights": {"jab": 1, "haymaker": 5}, "no_repeat": "haymaker"}, MOVES)
	var rng := _rng()
	var previous := ""
	for i in 100:
		var move := brain.next_move(rng)
		if previous == "haymaker":
			assert_ne(move, "haymaker", "no_repeat move picked twice in a row")
		previous = move


func test_phased_brain_switches_below_hp_threshold() -> void:
	var brain := EnemyBrain.new({
		"type": "phased",
		"phases": [
			{"hp_below": 1.0, "brain": {"type": "sequence", "loop": true, "steps": ["jab"]}},
			{"hp_below": 0.5, "brain": {"type": "sequence", "loop": true, "steps": ["nuke"]}},
		],
	}, MOVES)
	var rng := _rng()
	assert_eq(brain.next_move(rng, 1.0), "jab")
	assert_eq(brain.next_move(rng, 0.6), "jab")
	assert_eq(brain.next_move(rng, 0.5), "nuke")
	assert_eq(brain.next_move(rng, 0.2), "nuke")
