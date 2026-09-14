extends GutTest
## MapGenerator: lazy per-step encounter options with the doc's placement rules.
## Property-tested: many seeded simulated runs, every rule asserted every step.

const RUNS := 300


func test_encounter_one_is_always_a_single_auto_combat() -> void:
	var run := RunState.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var options := MapGenerator.next_options(run, rng)
	assert_eq(options.size(), 1)
	assert_eq(options[0].type, &"combat")


func test_encounter_ten_is_always_the_boss() -> void:
	var run := RunState.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for i in 9:
		run.record_visit(&"combat")
	var options := MapGenerator.next_options(run, rng)
	assert_eq(options.size(), 1)
	assert_eq(options[0].type, &"boss")


func test_property_all_placement_rules_hold_across_many_runs() -> void:
	var choice_rng := RandomNumberGenerator.new()
	choice_rng.seed = 424242
	for run_index in RUNS:
		var run := RunState.new()
		var rng := RandomNumberGenerator.new()
		rng.seed = run_index
		for step in 10:
			var encounter_number := run.encounter_number()
			var options := MapGenerator.next_options(run, rng)

			if encounter_number == 1:
				assert_eq(options.size(), 1, "enc 1 is a single option")
				assert_eq(options[0].type, &"combat")
			elif encounter_number == 10:
				assert_eq(options.size(), 1, "enc 10 is a single option")
				assert_eq(options[0].type, &"boss")
			else:
				assert_eq(options.size(), 2, "two options at enc %d" % encounter_number)
				assert_ne(options[0].type, options[1].type, "options must differ in type")

			var types := options.map(func(o: Dictionary) -> StringName: return o.type)
			for type: StringName in types:
				match type:
					&"rest":
						assert_true(MapGenerator.REST_ENCOUNTERS.has(encounter_number),
							"rest offered at enc %d" % encounter_number)
					&"shop":
						assert_lt(run.count_visited(&"shop"), 3, "shop cap is 3")
						assert_ne(run.last_visited(), &"shop", "no consecutive shops")
					&"treasure":
						assert_gt(encounter_number, 2, "treasure only after enc 2")
						assert_lt(run.count_visited(&"treasure"), 2, "treasure cap is 2")
						assert_ne(run.last_visited(), &"treasure", "no consecutive treasures")
					&"casino":
						assert_gt(encounter_number, 1, "casino only after enc 1")
						assert_lt(run.count_visited(&"casino"), 2, "casino cap is 2")
						assert_ne(run.last_visited(), &"casino", "no consecutive casinos")
					&"elite":
						# Doc v0.120: after #3, at most twice, two encounters
						# apart (patch 0.22).
						assert_gt(encounter_number, 3, "elites only after enc 3")
						assert_lt(run.count_visited(&"elite"), 2, "at most two elites")
						var previous := run.history.rfind(&"elite")
						if previous >= 0:
							assert_gt(encounter_number - (previous + 1), 2,
								"two encounters between elites")

			if encounter_number == MapGenerator.FINAL_SHOP_ENCOUNTER:
				var has_shop_or_capped: bool = types.has(&"shop") \
					or run.count_visited(&"shop") >= 3 or run.last_visited() == &"shop"
				assert_true(has_shop_or_capped,
					"enc %d offers the final shop when allowed"
						% MapGenerator.FINAL_SHOP_ENCOUNTER)

			for option: Dictionary in options:
				assert_false(option.has("variant"),
					"elites replaced the buffed/advanced variants (patch 0.22)")

			var pick: Dictionary = options[choice_rng.randi_range(0, options.size() - 1)]
			run.record_visit(pick.type)

		assert_eq(run.history.size(), 10)
		assert_eq(run.history[9], &"boss")
