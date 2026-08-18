extends GutTest
## RunState: persistent state for one run — hp, coins, machine, owned content,
## and the encounter history the map generator reads.


func test_new_run_starts_at_encounter_one() -> void:
	var run := RunState.new()
	assert_eq(run.encounter_number(), 1)
	assert_eq(run.history, [] as Array[StringName])


func test_record_visit_advances_the_encounter_number() -> void:
	var run := RunState.new()
	run.record_visit(&"combat")
	run.record_visit(&"shop")
	assert_eq(run.encounter_number(), 3)
	assert_eq(run.count_visited(&"shop"), 1)
	assert_eq(run.last_visited(), &"shop")


func test_coins_never_go_negative() -> void:
	var run := RunState.new()
	run.coins = 30
	assert_false(run.spend(50))
	assert_eq(run.coins, 30)
	assert_true(run.spend(30))
	assert_eq(run.coins, 0)
