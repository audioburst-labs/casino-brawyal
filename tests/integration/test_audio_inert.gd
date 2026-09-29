extends GutTest
## The Audio autoload must be inert under --headless: no players, no tweens,
## and every public method a silent no-op for real and bogus ids alike. That
## is what keeps `tools/verify.ps1` quiet and the balance bot deaf by
## construction. The bus layout, on the other hand, must exist everywhere.


func test_audio_is_not_live_under_headless() -> void:
	assert_eq(DisplayServer.get_name(), "headless", "the suite runs headless")
	assert_false(Audio.is_live())
	assert_eq(Audio.get_child_count(), 0, "an inert Audio builds no players")


func test_every_public_method_is_a_no_op_when_inert() -> void:
	for id: StringName in [&"hit_enemy", &"combat", &"amb_casino_floor", &"no_such_sound", &""]:
		Audio.play_sfx(id)
		Audio.play_music(id)
		Audio.play_ambience(id)
	Audio.stop_music(0.2)
	Audio.duck()
	Audio.set_bus_pct("Music", 50.0)
	Audio.set_bus_pct("Kazoo", 50.0)
	Audio.apply_settings(AppSettings.new())
	assert_eq(Audio.get_child_count(), 0)
	assert_eq(Audio.current_music(), &"")


func test_the_three_buses_exist() -> void:
	for bus in ["Music", "Sfx", "Ambience"]:
		assert_gt(AudioServer.get_bus_index(bus), 0, "%s bus missing from the layout" % bus)
	var ambience := AudioServer.get_bus_index("Ambience")
	assert_eq(AudioServer.get_bus_send(ambience), &"Master")


func test_audio_references_no_other_autoload() -> void:
	var source := FileAccess.get_file_as_string("res://src/autoload/audio.gd")
	var pattern := RegEx.create_from_string("\\b(Telemetry|Game|Db|Fx)\\.")
	for line in source.split("\n"):
		var code := line.strip_edges()
		if code.begins_with("#"):
			continue
		assert_null(pattern.search(code), "audio.gd must not reach for another autoload: %s" % code)
