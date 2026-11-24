extends GutTest
## Build 1.29: the Act I Choice screen as a top-down casino floorplan. The layout is
## pure arithmetic over the painting; the presenter only decides which room is
## which state, from the run's history and the path.

var _db: ContentDB


func before_all() -> void:
	_db = ContentDB.new()
	assert_true(_db.load_all("res://data"), str(_db.errors))


func _plan(history: Array[StringName], options: Array[Dictionary]) -> FloorplanMap:
	var plan := FloorplanMap.new()
	autofree(plan)
	plan._stop = history.size() + 1
	plan._build_rooms(history, MapGenerator.path_by_id(_db, &"path_1"), options)
	return plan


func _rooms_at(plan: FloorplanMap, stop: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for room: Dictionary in plan._rooms:
		if int(room.stop) == stop:
			out.append(room)
	return out


# ---- the layout ----

func test_there_are_eight_columns_of_pairs_between_the_lobby_and_the_penthouse() -> void:
	assert_eq(FloorplanLayout.slot_count(1), 1)
	assert_eq(FloorplanLayout.slot_count(10), 1)
	for stop in range(2, 10):
		assert_eq(FloorplanLayout.slot_count(stop), 2, "stop %d" % stop)
	assert_eq(FloorplanLayout.column_x(2), 345.0)
	assert_eq(FloorplanLayout.column_x(9), 345.0 + 175.0 * 7.0)


func test_the_columns_run_left_to_right_in_stop_order() -> void:
	for stop in range(1, 10):
		assert_lt(FloorplanLayout.column_x(stop), FloorplanLayout.column_x(stop + 1), "stop %d" % stop)


func test_every_room_sits_inside_the_painting_and_none_overlap() -> void:
	var stage := Rect2(Vector2.ZERO, FloorplanLayout.STAGE)
	var rects: Array[Rect2] = []
	for stop in range(1, 11):
		for slot in FloorplanLayout.slot_count(stop):
			var rect := FloorplanLayout.room_rect(stop, slot)
			assert_true(stage.encloses(rect), "stop %d slot %d is on the painting" % [stop, slot])
			rects.append(rect)
	for a in rects.size():
		for b in range(a + 1, rects.size()):
			assert_false(rects[a].intersects(rects[b]), "rooms %d and %d overlap" % [a, b])


func test_a_pair_is_one_room_above_the_promenade_and_one_below() -> void:
	for stop in range(2, 10):
		var above := FloorplanLayout.room_rect(stop, 0)
		var below := FloorplanLayout.room_rect(stop, 1)
		assert_lt(above.end.y, FloorplanLayout.HALL_Y)
		assert_gt(below.position.y, FloorplanLayout.HALL_Y)
		assert_eq(FloorplanLayout.token_position(stop, 0).x, FloorplanLayout.column_x(stop))
		assert_lt(FloorplanLayout.door_position(stop, 0).y, FloorplanLayout.HALL_Y)
		assert_gt(FloorplanLayout.door_position(stop, 1).y, FloorplanLayout.HALL_Y)


func test_a_marker_sits_inside_its_own_room() -> void:
	for stop in range(1, 11):
		for slot in FloorplanLayout.slot_count(stop):
			assert_true(FloorplanLayout.room_rect(stop, slot).has_point(FloorplanLayout.token_position(stop, slot)),
				"stop %d slot %d" % [stop, slot])


func test_the_room_a_visited_type_was_is_found_by_type() -> void:
	assert_eq(FloorplanLayout.slot_of([&"story", &"combat"], &"combat"), 1)
	assert_eq(FloorplanLayout.slot_of([&"story", &"combat"], &"story"), 0)
	assert_eq(FloorplanLayout.slot_of([&"story", &"combat"], &"shop"), 0, "unknown falls back to the top room")


func test_the_painting_exists() -> void:
	assert_true(ResourceLoader.exists(FloorplanMap.PAINTING))
	for type: StringName in FloorplanMap.LEGEND:
		assert_true(ResourceLoader.exists(FloorplanMap.ICON % String(type)), "icon for %s" % type)
		assert_true(FloorplanMap.TYPE_NAME.has(type))
		assert_true(FloorplanMap.TYPE_DESC.has(type))


# ---- the paths ----

func test_the_path_helpers_read_the_authored_data() -> void:
	var path := MapGenerator.path_by_id(_db, &"path_1")
	assert_false(path.is_empty())
	assert_eq(MapGenerator.pair_at(path, 1), [&"combat"] as Array[StringName])
	assert_eq(MapGenerator.pair_at(path, 3), [&"combat", &"treasure"] as Array[StringName])
	assert_eq(MapGenerator.pair_at(path, 10), [&"boss"] as Array[StringName])
	assert_true(MapGenerator.path_by_id(_db, &"nope").is_empty())


# ---- which room is which ----

func test_at_stop_three_the_road_so_far_the_pair_on_offer_and_the_rest_ahead() -> void:
	var plan := _plan([&"combat", &"story"] as Array[StringName],
		[{"type": &"combat"}, {"type": &"treasure"}] as Array[Dictionary])
	assert_eq(plan._rooms.size(), 18, "lobby, 8 pairs, penthouse")
	assert_eq(_rooms_at(plan, 1)[0].state, FloorplanMap.State.DONE)
	var second := _rooms_at(plan, 2)       # path_1 stop 2: story / combat, Ace took the story
	assert_eq([second[0].type, second[1].type], [&"story", &"combat"])
	assert_eq([second[0].state, second[1].state], [FloorplanMap.State.DONE, FloorplanMap.State.CLOSED])
	var here := _rooms_at(plan, 3)
	assert_eq(here.size(), 2)
	for room: Dictionary in here:
		assert_eq(room.state, FloorplanMap.State.HERE)
		assert_false((room.option as Dictionary).is_empty(), "an open door carries what choosing it does")
	for stop in range(4, 10):
		for room: Dictionary in _rooms_at(plan, stop):
			assert_eq(room.state, FloorplanMap.State.FUTURE, "stop %d is ahead" % stop)
	assert_eq(_rooms_at(plan, 10)[0].state, FloorplanMap.State.FUTURE)


func test_the_other_room_of_a_visited_pair_is_the_one_not_taken() -> void:
	var plan := _plan([&"combat", &"combat"] as Array[StringName],
		[{"type": &"combat"}, {"type": &"treasure"}] as Array[Dictionary])
	var second := _rooms_at(plan, 2)
	assert_eq([second[0].state, second[1].state], [FloorplanMap.State.CLOSED, FloorplanMap.State.DONE],
		"the combat (the second room) was the one taken")


func test_the_future_pairs_are_the_paths_own_pairs() -> void:
	var plan := _plan([&"combat"] as Array[StringName], [{"type": &"story"}, {"type": &"combat"}] as Array[Dictionary])
	var path := MapGenerator.path_by_id(_db, &"path_1")
	for stop in range(3, 10):
		var types: Array = []
		for room: Dictionary in _rooms_at(plan, stop):
			types.append(room.type)
		assert_eq(types, MapGenerator.pair_at(path, stop), "stop %d" % stop)


func test_the_first_screen_after_the_opening_fight_offers_stop_two() -> void:
	var plan := _plan([&"combat"] as Array[StringName], [{"type": &"story"}, {"type": &"combat"}] as Array[Dictionary])
	assert_eq(_rooms_at(plan, 1)[0].state, FloorplanMap.State.DONE)
	assert_eq(_rooms_at(plan, 2)[0].state, FloorplanMap.State.HERE)


func test_the_last_stop_offers_only_the_penthouse() -> void:
	var history: Array[StringName] = [&"combat", &"story", &"treasure", &"elite", &"rest", &"shop", &"elite", &"story", &"shop"]
	var plan := _plan(history, [{"type": &"boss"}] as Array[Dictionary])
	var boss := _rooms_at(plan, 10)
	assert_eq(boss.size(), 1)
	assert_eq(boss[0].state, FloorplanMap.State.HERE)
	assert_eq(boss[0].type, &"boss")
	for stop in range(2, 10):
		var states: Array = _rooms_at(plan, stop).map(func(r: Dictionary) -> int: return r.state)
		assert_has(states, FloorplanMap.State.DONE)
		assert_has(states, FloorplanMap.State.CLOSED)


func test_every_shipped_path_draws_a_full_plan_at_every_stop() -> void:
	for path: Dictionary in _db.all_paths():
		for stop in range(1, 11):
			var plan := FloorplanMap.new()
			autofree(plan)
			plan._stop = stop
			var history: Array[StringName] = []
			for visited in range(1, stop):
				history.append(MapGenerator.pair_at(path, visited)[0])
			var offered: Array[Dictionary] = []
			for type in MapGenerator.pair_at(path, stop):
				offered.append({"type": type})
			plan._build_rooms(history, path, offered)
			assert_eq(plan._rooms.size(), 18, "%s at stop %d" % [path.id, stop])
			var here := plan._rooms.filter(func(r: Dictionary) -> bool: return r.state == FloorplanMap.State.HERE)
			assert_eq(here.size(), FloorplanLayout.slot_count(stop), "%s stop %d: the doors on offer" % [path.id, stop])


# ---- reverting ----

func test_the_old_screen_is_still_there_to_switch_back_to() -> void:
	var script: GDScript = load("res://src/ui/map_screen.gd")
	assert_true(script.get_script_constant_map().has("USE_FLOORPLAN"), "the one-line switch")
	assert_true(script.get_script_method_list().any(func(m: Dictionary) -> bool: return m.name == "_option_card"),
		"the encounter cards are kept")
	assert_true(ResourceLoader.exists("res://src/ui/map/path_ribbon.gd"), "and so is the ribbon")
