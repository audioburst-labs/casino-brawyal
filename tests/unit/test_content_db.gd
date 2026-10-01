extends GutTest
## ContentDB: loads all JSON game content, validates it, exposes id lookups.
## This test doubles as the linter for res://data — if content is malformed,
## it fails here before the game ever boots.


func _loaded_db() -> ContentDB:
	var db := ContentDB.new()
	var ok := db.load_all("res://data")
	assert_true(ok, "load_all should succeed; errors: " + str(db.errors))
	return db


func test_loads_shipped_data_without_errors() -> void:
	var db := _loaded_db()
	assert_eq(db.errors, [] as Array[String])


func test_ability_lookup_parses_cost_and_effects() -> void:
	var db := _loaded_db()
	var ability := db.get_ability(&"card_sling")
	assert_not_null(ability)
	assert_eq(ability.name, "Card Sling")
	assert_gt(ability.cost.size(), 0)
	assert_gt(ability.effects.size(), 0)
	assert_has(ability.keywords, &"mark")


func test_hero_starting_abilities_exist() -> void:
	var db := _loaded_db()
	var hero := db.get_hero(&"ace")
	assert_not_null(hero)
	assert_gt(hero.max_hp, 0)
	for ability_id: StringName in hero.starting_abilities:
		assert_not_null(db.get_ability(ability_id),
			"missing starting ability: %s" % ability_id)


func test_enemy_lookup_parses_brain_and_moves() -> void:
	var db := _loaded_db()
	var enemy := db.get_enemy(&"bouncer")
	assert_not_null(enemy)
	assert_gt(enemy.hp_min, 0)
	assert_gte(enemy.hp_max, enemy.hp_min)
	assert_gt(enemy.moves.size(), 0)


func test_status_lookup() -> void:
	var db := _loaded_db()
	assert_not_null(db.get_status(&"weak"))
	assert_not_null(db.get_status(&"taunt"))


func test_rejects_unknown_suit_in_ability_cost() -> void:
	var db := ContentDB.new()
	var ok := db.load_all("res://tests/fixtures/bad_data")
	assert_false(ok)
	assert_gt(db.errors.size(), 0)


func test_rejects_reference_to_unknown_status() -> void:
	var db := ContentDB.new()
	db.load_all("res://tests/fixtures/bad_data")
	var joined := " | ".join(db.errors)
	assert_string_contains(joined, "unknown status")


## The codex lists every keyword and status straight from the content (0.121).
func test_keyword_and_status_ids_are_listed_for_the_codex() -> void:
	var db := ContentDB.new()
	assert_true(db.load_all("res://data"), str(db.errors))
	assert_gt(db.all_keyword_ids().size(), 10)
	assert_true(db.all_keyword_ids().has(&"mark"))
	assert_eq(db.all_status_ids().size(), 10)
	assert_true(db.all_status_ids().has(&"vulnerable"))
