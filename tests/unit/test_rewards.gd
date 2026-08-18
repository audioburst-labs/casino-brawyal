extends GutTest
## Rewards: coin rolls, ability choice pairs, relic draws — all from unowned pools.

var _db: ContentDB


func before_all() -> void:
	_db = ContentDB.new()
	assert_true(_db.load_all("res://data"), str(_db.errors))


func _rng(seed_value: int = 5) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func test_coin_roll_stays_in_encounter_scaled_range() -> void:
	var rng := _rng()
	for encounter in range(1, 11):
		for i in 30:
			var coins := Rewards.roll_coins(encounter, rng)
			assert_between(coins, encounter * 8, encounter * 12)


func test_ability_choices_are_distinct_and_unowned() -> void:
	var run := RunState.new()
	run.ability_ids = [&"card_flick", &"dagger_throw", &"card_guard"]
	var rng := _rng()
	for i in 20:
		var choices := Rewards.ability_choices(_db, run, rng)
		assert_eq(choices.size(), 2)
		assert_ne(choices[0], choices[1])
		for id: StringName in choices:
			assert_does_not_have(run.ability_ids, id)


func test_ability_choices_shrink_when_pool_runs_dry() -> void:
	var run := RunState.new()
	for id in _db.all_ability_ids():
		run.ability_ids.append(id)
	assert_eq(Rewards.ability_choices(_db, run, _rng()).size(), 0)


func test_relic_draw_excludes_owned_and_empties_gracefully() -> void:
	var run := RunState.new()
	var rng := _rng()
	var drawn: Array[StringName] = []
	while true:
		var relic := Rewards.random_unowned_relic(_db, run, rng)
		if relic == &"":
			break
		assert_does_not_have(drawn, relic, "relic drawn twice")
		drawn.append(relic)
		run.relic_ids.append(relic)
	assert_gt(drawn.size(), 0, "data should ship at least one relic")
	assert_eq(Rewards.random_unowned_relic(_db, run, rng), &"")
