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


func test_coin_roll_stays_in_lineup_gold_range() -> void:
	var rng := _rng()
	for i in 30:
		assert_between(Rewards.roll_coins(17, 23, rng), 17, 23)
	assert_eq(Rewards.roll_coins(0, 0, rng), 0, "boss lineup pays no combat gold")


## v0.19: three choices, and an owned ability is eligible as an upgrade —
## only a gold one drops out. The three still have to be distinct.
func test_ability_choices_are_distinct_and_upgradeable() -> void:
	var run := RunState.new()
	run.ability_ids = [&"card_sling", &"quick_maneuvers", &"color_up"]
	var rng := _rng()
	for i in 20:
		var choices := Rewards.ability_choices(_db, run, rng)
		assert_eq(choices.size(), 3)
		assert_eq(choices.size(), _distinct(choices).size(), "no repeats within one offer")
		for id: StringName in choices:
			assert_true(run.can_upgrade(id), "%s still has somewhere to go" % id)


func _distinct(ids: Array[StringName]) -> Array[StringName]:
	var seen: Array[StringName] = []
	for id in ids:
		if not seen.has(id):
			seen.append(id)
	return seen


func test_ability_choices_shrink_when_pool_runs_dry() -> void:
	# Owning everything is not enough now — the pool only empties at gold.
	var run := RunState.new()
	for id in _db.all_ability_ids():
		run.ability_ids.append(id)
	assert_eq(Rewards.ability_choices(_db, run, _rng()).size(), 3,
		"owned abilities are still offered, as upgrades")
	for id in _db.all_ability_ids():
		run.ability_tiers[id] = ContentDB.MAX_TIER
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
