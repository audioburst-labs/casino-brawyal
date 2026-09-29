extends GutTest
## Which theme plays under which screen. Pure, so `Game.goto_screen` can ask
## it without the autoload knowing the list.


func test_every_shipped_screen_has_a_track() -> void:
	for scene in _walk("res://scenes/screens", "tscn"):
		var track := ScreenMusic.track_for(scene)
		assert_true(SoundBank.MUSIC_IDS.has(track),
			"%s has no theme (got %s); a new screen cannot ship silent" % [scene, track])


func test_the_named_screens() -> void:
	assert_eq(ScreenMusic.track_for("res://scenes/screens/main_menu.tscn"), &"menu")
	assert_eq(ScreenMusic.track_for("res://scenes/screens/map_screen.tscn"), &"map")
	assert_eq(ScreenMusic.track_for("res://scenes/screens/combat_screen.tscn"), &"combat")
	assert_eq(ScreenMusic.track_for("res://scenes/screens/shop_screen.tscn"), &"shop")
	assert_eq(ScreenMusic.track_for("res://scenes/screens/casino_screen.tscn"), &"shop")
	assert_eq(ScreenMusic.track_for("res://scenes/screens/story_screen.tscn"), &"story")
	assert_eq(ScreenMusic.track_for("res://scenes/screens/rest_screen.tscn"), &"story")
	assert_eq(ScreenMusic.track_for("res://scenes/screens/treasure_screen.tscn"), &"story")
	assert_eq(ScreenMusic.track_for("res://scenes/screens/victory_screen.tscn"), &"victory")
	assert_eq(ScreenMusic.track_for("res://scenes/screens/game_over_screen.tscn"), &"defeat")
	assert_eq(ScreenMusic.track_for("res://scenes/screens/reward_screen.tscn"), &"map")


func test_the_args_override_wins_for_the_boss() -> void:
	assert_eq(ScreenMusic.track_for("res://scenes/screens/combat_screen.tscn",
		{"music": "boss"}), &"boss")


func test_an_unknown_override_is_ignored() -> void:
	assert_eq(ScreenMusic.track_for("res://scenes/screens/combat_screen.tscn",
		{"music": "kazoo"}), &"combat")


func test_an_unknown_screen_has_no_track() -> void:
	assert_eq(ScreenMusic.track_for("res://scenes/nowhere.tscn"), &"")


func test_ambience_plays_on_the_hub_screens_only() -> void:
	assert_eq(ScreenMusic.ambience_for("res://scenes/screens/map_screen.tscn"), &"amb_casino_floor")
	assert_eq(ScreenMusic.ambience_for("res://scenes/screens/shop_screen.tscn"), &"amb_casino_floor")
	assert_eq(ScreenMusic.ambience_for("res://scenes/screens/casino_screen.tscn"), &"amb_casino_floor")
	assert_eq(ScreenMusic.ambience_for("res://scenes/screens/combat_screen.tscn"), &"")
	assert_eq(ScreenMusic.ambience_for("res://scenes/screens/main_menu.tscn"), &"")
	assert_eq(ScreenMusic.ambience_for("res://scenes/screens/victory_screen.tscn"), &"")


func _walk(dir_path: String, ext: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			found.append_array(_walk(full, ext))
		elif entry.get_extension() == ext:
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return found
