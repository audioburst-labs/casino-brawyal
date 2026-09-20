extends GutTest
## MapGenerator, patch 0.114: a run walks one of the doc's six authored Paths.
##
## The generator has almost no logic left — the interesting content is the six
## paths in `data/encounters/act1_paths.json`, transcribed from the sheet's
## Encounter Choices tab. So these tests check two different things:
##   1. the shipped PATHS satisfy the invariants the old procedural rules used
##      to enforce (a designer editing the sheet can still break a run, and the
##      build should say so), and
##   2. the generator hands back the right pair and remembers its path.

var _db: ContentDB


func before_all() -> void:
	_db = ContentDB.new()
	assert_true(_db.load_all("res://data"), str(_db.errors))


func _rng(seed_value: int = 1) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


# ---- the shipped paths ------------------------------------------------------

func test_six_paths_ship_each_ten_encounters_long() -> void:
	var paths := _db.all_paths()
	assert_eq(paths.size(), 6, "the doc specifies six Paths")
	for path: Dictionary in paths:
		assert_eq(path.encounters.size(), ContentDB.PATH_LENGTH, String(path.id))


func test_every_path_opens_on_combat_and_ends_on_the_boss() -> void:
	for path: Dictionary in _db.all_paths():
		var first: Array = path.encounters[0]
		var last: Array = path.encounters[9]
		assert_eq(first.size(), 1, "%s: encounter 1 is not a choice" % path.id)
		assert_eq(first[0], &"combat", String(path.id))
		assert_eq(last.size(), 1, "%s: encounter 10 is not a choice" % path.id)
		assert_eq(last[0], &"boss", String(path.id))


func test_every_middle_encounter_is_a_real_choice_of_two_kinds() -> void:
	for path: Dictionary in _db.all_paths():
		for index in range(1, 9):
			var offered: Array = path.encounters[index]
			assert_eq(offered.size(), 2,
				"%s: encounter %d offers %d" % [path.id, index + 1, offered.size()])
			assert_ne(offered[0], offered[1],
				"%s: encounter %d offers the same thing twice" % [path.id, index + 1])


## The placement rules the procedural generator used to enforce are now
## properties of the authored data. Same guarantees, checked at the source.
func test_the_authored_paths_keep_the_docs_placement_guarantees() -> void:
	for path: Dictionary in _db.all_paths():
		var id := String(path.id)
		var elites: Array[int] = []
		var rests: Array[int] = []
		var shops: Array[int] = []
		for index in path.encounters.size():
			var number: int = index + 1
			for type: StringName in path.encounters[index]:
				match type:
					&"elite":
						elites.append(number)
					&"rest":
						rests.append(number)
					&"shop":
						shops.append(number)
		assert_eq(elites.size(), 2, "%s: two Elites per run" % id)
		for number: int in elites:
			assert_gt(number, 3, "%s: Elites only after encounter 3" % id)
		assert_gt(elites[1] - elites[0], 2, "%s: two encounters between Elites" % id)
		assert_false(rests.is_empty(), "%s: a run offers Rest" % id)
		for number: int in rests:
			assert_gt(number, 2, "%s: Rest is never encounter 2" % id)
		assert_true(shops.has(9), "%s: the last shop is offered at 9" % id)
		for number: int in shops:
			assert_gt(number, 2, "%s: no shop at encounter 2" % id)


# ---- the generator ----------------------------------------------------------

func test_encounter_one_is_a_single_auto_combat() -> void:
	var run := RunState.new()
	var options := MapGenerator.next_options(_db, run, _rng())
	assert_eq(options.size(), 1)
	assert_eq(options[0].type, &"combat")


func test_encounter_ten_is_the_boss() -> void:
	var run := RunState.new()
	for i in 9:
		run.record_visit(&"combat")
	var options := MapGenerator.next_options(_db, run, _rng())
	assert_eq(options.size(), 1)
	assert_eq(options[0].type, &"boss")


func test_a_run_picks_one_path_and_keeps_it() -> void:
	var run := RunState.new()
	MapGenerator.next_options(_db, run, _rng(7))
	var chosen := run.path_id
	assert_ne(chosen, &"", "a path is rolled on the first ask")
	for step in 5:
		run.record_visit(&"combat")
		# A different rng every step: if the path were re-rolled it would move.
		MapGenerator.next_options(_db, run, _rng(step + 100))
		assert_eq(run.path_id, chosen, "the path is rolled once per run")


func test_the_options_are_the_paths_own_pair() -> void:
	var run := RunState.new()
	run.path_id = &"path_1"
	for i in 3:
		run.record_visit(&"combat")
	var options := MapGenerator.next_options(_db, run, _rng())
	var types := options.map(func(o: Dictionary) -> StringName: return o.type)
	# path_1, encounter 4: Elite or Standard Combat.
	assert_eq(types, [&"elite", &"combat"] as Array)


## Every path is reachable, or five sixths of the authored content is dead.
func test_every_path_can_be_rolled() -> void:
	var seen := {}
	for seed_value in 400:
		var run := RunState.new()
		MapGenerator.next_options(_db, run, _rng(seed_value))
		seen[run.path_id] = true
	assert_eq(seen.size(), 6, "all six paths come up: %s" % [seen.keys()])


## A save that predates 0.114 has no path; it must not be stranded.
func test_a_save_without_a_path_is_given_one() -> void:
	var run := RunState.new()
	run.path_id = &""
	for i in 4:
		run.record_visit(&"combat")
	var options := MapGenerator.next_options(_db, run, _rng(3))
	assert_ne(run.path_id, &"", "an old save is adopted into a path")
	assert_eq(options.size(), 2, "and gets a real choice")


func test_no_option_carries_a_variant() -> void:
	var run := RunState.new()
	for step in 10:
		for option: Dictionary in MapGenerator.next_options(_db, run, _rng(step)):
			assert_false(option.has("variant"),
				"elites replaced the buffed/advanced variants (patch 0.22)")
		run.record_visit(&"combat")
