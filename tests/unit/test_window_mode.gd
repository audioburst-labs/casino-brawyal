extends GutTest
## Patch 0.125: the window opens the way it was last left, fullscreen at first.

const PATH := "user://test_window_mode.json"


func after_each() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func test_a_new_player_starts_fullscreen() -> void:
	assert_true(AppSettings.new().fullscreen)
	assert_true(AppSettings.load_settings(PATH).fullscreen, "no file yet")


func test_windowed_is_remembered() -> void:
	var settings := AppSettings.new()
	settings.fullscreen = false
	assert_true(settings.save(PATH))
	assert_false(AppSettings.load_settings(PATH).fullscreen)


func test_fullscreen_is_remembered() -> void:
	var settings := AppSettings.new()
	settings.fullscreen = false
	settings.save(PATH)
	var again := AppSettings.load_settings(PATH)
	again.fullscreen = true
	again.save(PATH)
	assert_true(AppSettings.load_settings(PATH).fullscreen)


func test_the_old_never_applied_flag_does_not_count_as_a_choice() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string('{"v": 1, "display": {"fullscreen": false, "max_fps": 60}}')
	file.close()
	assert_true(AppSettings.load_settings(PATH).fullscreen,
		"a file written by an older build has no recorded choice")
