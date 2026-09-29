extends GutTest
## The audio manifest, the SoundBank and the UI's requests must agree. This
## is the "check, don't trust" test for sound, in the shape of
## `test_copy_style.gd`: an id asked for by a screen that nobody generated is
## a silent beat nobody notices until a player does.

const MANIFEST := "res://tools/audio/audio_manifest.json"


func _manifest() -> Dictionary:
	assert_true(FileAccess.file_exists(MANIFEST), "manifest missing: %s" % MANIFEST)
	if not FileAccess.file_exists(MANIFEST):
		return {}
	var reader := JSON.new()
	assert_eq(reader.parse(FileAccess.get_file_as_string(MANIFEST)), OK, "manifest must parse")
	return reader.data if reader.data is Dictionary else {}


func _entries() -> Array:
	return _manifest().get("assets", [])


func test_manifest_ids_are_exactly_the_sound_bank() -> void:
	var manifest_ids := {}
	for entry: Dictionary in _entries():
		var id := StringName(str(entry.get("id", "")))
		assert_false(manifest_ids.has(id), "%s listed twice in the manifest" % id)
		manifest_ids[id] = true
		assert_true(SoundBank.is_known(id), "manifest names %s, which the bank does not know" % id)
	for id: StringName in SoundBank.all_ids():
		assert_true(manifest_ids.has(id), "%s is in the bank but nobody generates it" % id)


func test_each_entry_is_shipped_or_marked_pending() -> void:
	for entry: Dictionary in _entries():
		var id := StringName(str(entry.get("id", "")))
		var variants := int(entry.get("variants", 0))
		var shipped := FileAccess.file_exists(SoundBank.path_for(id)) \
			or (variants > 0 and FileAccess.file_exists(SoundBank.path_for(id, 1)))
		assert_true(shipped or bool(entry.get("pending", false)),
			"%s: no file at %s and not marked pending" % [id, SoundBank.path_for(id)])


func test_each_entry_category_matches_the_bank() -> void:
	for entry: Dictionary in _entries():
		var id := StringName(str(entry.get("id", "")))
		assert_eq(str(entry.get("category", "")), SoundBank.category_of(id),
			"%s: manifest category disagrees with the bank" % id)
		if SoundBank.category_of(id) != "sfx":
			assert_true(bool(entry.get("loop", false)), "%s: music and ambience loop" % id)


func test_every_entry_has_a_prompt_or_a_library_source() -> void:
	for entry: Dictionary in _entries():
		var id := str(entry.get("id", ""))
		var library := str(entry.get("source", "")) == "library"
		assert_true(library or str(entry.get("prompt", "")).length() > 20,
			"%s needs a prompt or source: library" % id)


## Every literal id a screen asks the autoload for is a real sound.
func test_every_id_the_ui_asks_for_is_known() -> void:
	var pattern := RegEx.create_from_string("&\"([a-z_]+)\"")
	var asked := 0
	for path in _walk("res://src/ui", "gd") + _walk("res://src/autoload", "gd"):
		var source := FileAccess.get_file_as_string(path)
		for line in source.split("\n"):
			if not line.contains("Audio.play_"):
				continue
			for found in pattern.search_all(line):
				var id := StringName(found.get_string(1))
				asked += 1
				assert_true(SoundBank.is_known(id), "%s asks for unknown sound %s" % [path, id])
	assert_gt(asked, 40, "the presenters should be asking for sounds")


## The two helpers in the combat presenter choose between ids the regex
## cannot see through a call; pin them here.
func test_the_presenter_helpers_choose_known_ids() -> void:
	for id: StringName in [&"mark_apply", &"stun", &"debuff_apply", &"buff_apply",
			&"block_absorb", &"hit_hero", &"hit_enemy", &"hit_heavy"]:
		assert_true(SoundBank.is_known(id), "%s is chosen by a helper but unknown" % id)


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
