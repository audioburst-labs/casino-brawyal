class_name Rewards
extends RefCounted
## Reward draws after encounters: coins scale with encounter number,
## ability/relic draws always come from the unowned pool.


static func roll_coins(encounter_number: int, rng: RandomNumberGenerator) -> int:
	return rng.randi_range(encounter_number * 8, encounter_number * 12)


## Up to `count` distinct unowned abilities (fewer when the pool runs dry).
static func ability_choices(db: ContentDB, run: RunState,
		rng: RandomNumberGenerator, count: int = 2) -> Array[StringName]:
	var pool: Array[StringName] = []
	for id: StringName in db.all_ability_ids():
		if not run.ability_ids.has(id) and db.get_ability(id).pool != "starter":
			pool.append(id)
	var choices: Array[StringName] = []
	while choices.size() < count and not pool.is_empty():
		var index := rng.randi_range(0, pool.size() - 1)
		choices.append(pool[index])
		pool.remove_at(index)
	return choices


## One random unowned relic, or &"" when the pool is exhausted.
static func random_unowned_relic(db: ContentDB, run: RunState,
		rng: RandomNumberGenerator) -> StringName:
	var pool: Array[StringName] = []
	for id: StringName in db.all_relic_ids():
		if not run.relic_ids.has(id):
			pool.append(id)
	if pool.is_empty():
		return &""
	return pool[rng.randi_range(0, pool.size() - 1)]
