extends GutTest
## The balance instrument: a greedy bot plays complete seeded runs through the
## pure logic layer. Asserts every run terminates cleanly; prints win-rate and
## death statistics for balance tuning.

const RUNS := 40

var _db: ContentDB


func before_all() -> void:
	_db = ContentDB.new()
	assert_true(_db.load_all("res://data"), str(_db.errors))


func test_bot_plays_full_runs_to_completion() -> void:
	var wins := 0
	var death_encounters: Array[int] = []
	var total_coins := 0
	for seed_value in RUNS:
		var result := RunBot.play(_db, seed_value)
		assert_true(result.finished, "run %d did not terminate" % seed_value)
		assert_between(result.encounters, 1, 10)
		if result.won:
			wins += 1
		else:
			death_encounters.append(result.encounters)
		total_coins += result.coins
	var avg_death := 0.0
	for encounter in death_encounters:
		avg_death += encounter
	if not death_encounters.is_empty():
		avg_death /= death_encounters.size()
	print("=== RUN BOT STATS: %d/%d wins (%.0f%%) | avg death at encounter %.1f | avg coins %.0f ===" % [
		wins, RUNS, 100.0 * wins / RUNS, avg_death, float(total_coins) / RUNS])
	assert_eq(wins + death_encounters.size(), RUNS)


func test_encounter_factory_builds_valid_combat_configs() -> void:
	var run := RunState.new()
	run.ability_ids = [&"card_flick"]
	run.record_visit(&"combat")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var config := EncounterFactory.combat_config(_db, run, rng, {"type": &"combat"})
	assert_eq(config.hero, run.hero_id)
	assert_gt((config.enemies as Array).size(), 0)

	for i in 4:
		run.record_visit(&"combat")
	var hard := EncounterFactory.combat_config(_db, run, rng,
		{"type": &"hard_combat", "variant": "buffed"})
	assert_eq(hard.hp_mult, 1.25)

	for i in 4:
		run.record_visit(&"combat")
	var boss := EncounterFactory.combat_config(_db, run, rng, {"type": &"boss"})
	assert_has(boss.enemies, &"mr_moneyman")
