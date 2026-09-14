extends GutTest
## Encounter lineups (stage-tagged enemy groups) and story events in ContentDB.

var _db: ContentDB


func before_all() -> void:
	_db = ContentDB.new()
	assert_true(_db.load_all("res://data"), str(_db.errors))


func test_every_stage_has_at_least_one_lineup() -> void:
	for stage in [1, 2, 3, 4, 5]:
		assert_gt(_db.lineups_for_stage(stage).size(), 0, "stage %d has no lineups" % stage)


func test_lineups_carry_gold_ranges() -> void:
	for stage in [1, 2, 3, 4, 5]:
		for lineup: Dictionary in _db.lineups_for_stage(stage):
			assert_gt(int(lineup.gold_min), 0, "%s has no gold" % lineup.id)
			assert_gte(int(lineup.gold_max), int(lineup.gold_min))


func test_boss_lineup_exists() -> void:
	var boss_lineups := _db.lineups_for_stage(ContentDB.BOSS_STAGE)
	assert_eq(boss_lineups.size(), 1)
	assert_has(boss_lineups[0].enemies, &"mr_moneybags")


func test_lineup_enemies_all_exist() -> void:
	for stage in [1, 2, 3, 4, 5, ContentDB.BOSS_STAGE]:
		for lineup: Dictionary in _db.lineups_for_stage(stage):
			for enemy_id: StringName in lineup.enemies:
				assert_not_null(_db.get_enemy(enemy_id), "missing enemy %s" % enemy_id)


func test_story_events_exist_with_choices() -> void:
	var ids := _db.all_story_event_ids()
	assert_gt(ids.size(), 2)
	for id: StringName in ids:
		var event := _db.get_story_event(id)
		assert_between(event.choices.size(), 2, 4)
		for choice: Dictionary in event.choices:
			assert_true(choice.has("label"), "choice needs a label")


## Patch 0.22: the sheet's Elites tab. They sit outside the stage ladder, so
## `lineups_for_stage` never offers one as a normal fight.
func test_elite_lineups_are_their_own_pool() -> void:
	var elites := _db.elite_lineups()
	assert_eq(elites.size(), 2)
	var ids: Array[StringName] = []
	for lineup: Dictionary in elites:
		ids.append(lineup.id)
		assert_eq((lineup.enemies as Array).size(), 1, "one mini-boss each")
		assert_gte(int(lineup.gold_min), 77, "the sheet's elite reward")
		assert_lte(int(lineup.gold_max), 83)
	assert_has(ids, &"vault_golem")
	assert_has(ids, &"loan_office")
	for stage in range(1, 7):
		for lineup: Dictionary in _db.lineups_for_stage(stage):
			assert_false(bool(lineup.get("elite", false)),
				"stage %d offers no elites" % stage)
