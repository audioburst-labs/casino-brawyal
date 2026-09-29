extends GutTest
## `SoundBank` is the one list of every sound the game can ask for. The
## manifest, the autoload and the UI all key off it, so it has to be
## internally consistent and to answer for an unknown id without throwing.


func test_the_eight_screen_themes_are_the_music_ids() -> void:
	assert_eq(SoundBank.MUSIC_IDS, [&"menu", &"map", &"combat", &"boss",
		&"shop", &"story", &"victory", &"defeat"] as Array[StringName])


func test_ids_are_unique_across_every_list() -> void:
	var seen := {}
	for id: StringName in SoundBank.all_ids():
		assert_false(seen.has(id), "%s appears twice" % id)
		seen[id] = true
	assert_eq(seen.size(), SoundBank.MUSIC_IDS.size() + SoundBank.SFX_IDS.size()
		+ SoundBank.AMBIENCE_IDS.size())


func test_category_of_each_list() -> void:
	assert_eq(SoundBank.category_of(&"combat"), "music")
	assert_eq(SoundBank.category_of(&"hit_enemy"), "sfx")
	assert_eq(SoundBank.category_of(&"amb_casino_floor"), "ambience")
	assert_eq(SoundBank.category_of(&"no_such_sound"), "")


func test_path_follows_the_category_folder_convention() -> void:
	assert_eq(SoundBank.path_for(&"combat"), "res://assets/audio/music/combat.ogg")
	assert_eq(SoundBank.path_for(&"hit_enemy"), "res://assets/audio/sfx/hit_enemy.ogg")
	assert_eq(SoundBank.path_for(&"amb_casino_floor"),
		"res://assets/audio/ambience/amb_casino_floor.ogg")


func test_a_variant_take_gets_a_numbered_file() -> void:
	assert_eq(SoundBank.path_for(&"hit_enemy", 2), "res://assets/audio/sfx/hit_enemy_2.ogg")
	assert_eq(SoundBank.path_for(&"hit_enemy", 0), "res://assets/audio/sfx/hit_enemy.ogg")


func test_an_unknown_id_has_no_path_and_is_not_known() -> void:
	assert_eq(SoundBank.path_for(&"no_such_sound"), "")
	assert_false(SoundBank.is_known(&"no_such_sound"))
	assert_true(SoundBank.is_known(&"lever_pull"))


func test_stingers_and_jingles_never_get_pitch_jitter() -> void:
	for id: StringName in SoundBank.PITCH_LOCKED:
		assert_true(SoundBank.is_known(id), "%s is locked but not a sound" % id)
		assert_eq(SoundBank.default_variance(id), 0.0, "%s must play at pitch" % id)
	assert_eq(SoundBank.default_variance(&"hit_enemy"), SoundBank.DEFAULT_VARIANCE)
	assert_gt(SoundBank.DEFAULT_VARIANCE, 0.0)
	assert_eq(SoundBank.default_variance(&"no_such_sound"), 0.0)


func test_music_is_never_pitch_jittered() -> void:
	for id: StringName in SoundBank.MUSIC_IDS:
		assert_eq(SoundBank.default_variance(id), 0.0)
