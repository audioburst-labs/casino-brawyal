extends GutTest
## The intro comic (patch 0.129): a two-page spread whose panels land one after
## another. The layout and the timeline are pure data, so they are tested here;
## `IntroComic` only draws them.



func test_seven_panels_in_reading_order() -> void:
	var panels := IntroComicScript.panels()
	assert_eq(panels.size(), 7)
	for i in panels.size():
		assert_eq(int(panels[i].id), i + 1)


func test_panels_reveal_one_after_another() -> void:
	var panels := IntroComicScript.panels()
	for i in range(1, panels.size()):
		assert_gt(float(panels[i].reveal), float(panels[i - 1].reveal), "panel %d" % (i + 1))
	assert_lt(float(panels[6].reveal) + IntroComicScript.FADE, IntroComicScript.COMPLETE_AT, "the last panel is in before everything settles")


func test_the_first_four_panels_are_the_left_page_and_the_rest_the_right() -> void:
	var panels := IntroComicScript.panels()
	for i in panels.size():
		var page: Rect2 = IntroComicScript.PAGES[0] if i < 4 else IntroComicScript.PAGES[1]
		assert_true(page.encloses(panels[i].rect), "panel %d sits on its page" % (i + 1))


func test_every_gutter_is_the_same_width() -> void:
	# The designer's rule (0.129): panels differ in size but share one even gutter.
	var panels := IntroComicScript.panels()
	for a in panels.size():
		for b in range(a + 1, panels.size()):
			var ra: Rect2 = panels[a].rect
			var rb: Rect2 = panels[b].rect
			assert_false(ra.intersects(rb), "panels %d and %d overlap" % [a + 1, b + 1])
			if ra.grow(IntroComicScript.GUTTER + 0.5).intersects(rb):
				assert_false(ra.grow(IntroComicScript.GUTTER - 0.5).intersects(rb),
					"panels %d and %d are closer than the gutter" % [a + 1, b + 1])


func test_each_page_is_filled_edge_to_edge() -> void:
	var panels := IntroComicScript.panels()
	for page_index in 2:
		var bounds := Rect2()
		var first := true
		for i in panels.size():
			if (i < 4) != (page_index == 0):
				continue
			bounds = panels[i].rect if first else bounds.merge(panels[i].rect)
			first = false
		assert_eq(bounds, IntroComicScript.PAGES[page_index].grow(-IntroComicScript.PAGE_PADDING), "page %d" % (page_index + 1))


func test_captions_are_where_the_designer_wanted_them() -> void:
	var panels := IntroComicScript.panels()
	var texts: Array[String] = []
	for panel in panels:
		texts.append(String(panel.caption.get("text", "")))
	assert_eq(texts, ["Straight flush.", "The pot is his.", "Take him out.",
		"He never sees them coming.", "", "", "He is not done."])
	for text in texts:
		assert_false(text.contains("—") or text.contains("–"), "no long dashes in anything a player reads")


func test_cover_rect_fills_the_cell_and_keeps_the_picture_square() -> void:
	var cell := Vector2(520, 300)
	var tex := Vector2(2528, 1696)
	var r := IntroComicScript.cover_rect(cell, tex, 0.5, 0.5)
	assert_gte(r.size.x, cell.x - 0.01)
	assert_gte(r.size.y, cell.y - 0.01)
	assert_almost_eq(r.size.x / r.size.y, tex.x / tex.y, 0.001)


func test_cover_rect_pins_to_the_requested_edge() -> void:
	var cell := Vector2(326, 300)
	var tex := Vector2(2528, 1696)
	var left := IntroComicScript.cover_rect(cell, tex, 0.0, 0.5)
	assert_almost_eq(left.position.x, 0.0, 0.001)
	var right := IntroComicScript.cover_rect(cell, tex, 1.0, 0.5)
	assert_almost_eq(right.position.x + right.size.x, cell.x, 0.001)
	var wide := IntroComicScript.cover_rect(Vector2(856, 330), tex, 0.5, 0.0)
	assert_almost_eq(wide.position.y, 0.0, 0.001)
	var low := IntroComicScript.cover_rect(Vector2(856, 330), tex, 0.5, 1.0)
	assert_almost_eq(low.position.y + low.size.y, 330.0, 0.001)


func test_alpha_ramps_from_zero_to_one() -> void:
	assert_eq(IntroComicScript.alpha_at(0.5, 1.0, 0.5), 0.0)
	assert_almost_eq(IntroComicScript.alpha_at(1.25, 1.0, 0.5), 0.5, 0.0001)
	assert_eq(IntroComicScript.alpha_at(2.0, 1.0, 0.5), 1.0)


func test_the_logo_flickers_but_is_mostly_lit() -> void:
	var dim := 0
	var total := 0
	var t := 0.0
	while t < 30.0:
		var a := IntroComicScript.flicker(t)
		assert_true(is_equal_approx(a, 1.0) or is_equal_approx(a, IntroComicScript.FLICKER_DIM), "only lit or dimmed")
		if is_equal_approx(a, IntroComicScript.FLICKER_DIM):
			dim += 1
		total += 1
		t += 0.01
	assert_gt(dim, 0, "it does flicker")
	assert_lt(float(dim) / float(total), 0.12, "and it is mostly on")


func test_the_play_button_pulses_only_once_it_has_replaced_skip() -> void:
	assert_eq(IntroComicScript.pulse(IntroComicScript.PLAY_AT - 1.0), 1.0)
	assert_almost_eq(IntroComicScript.pulse(IntroComicScript.PLAY_AT), 1.0, 0.0001)
	assert_almost_eq(IntroComicScript.pulse(IntroComicScript.PLAY_AT + IntroComicScript.PULSE_PERIOD * 0.5), 1.0 + IntroComicScript.PULSE_DEPTH * 2.0, 0.0001)
	assert_almost_eq(IntroComicScript.pulse(IntroComicScript.PLAY_AT + IntroComicScript.PULSE_PERIOD), 1.0, 0.0001)


func test_skip_hands_over_to_play_after_the_final_panel_begins() -> void:
	var last_reveal := float(IntroComicScript.panels()[6].reveal)
	assert_gt(IntroComicScript.SKIP_FADE_AT, last_reveal, "Skip stays until the last panel is arriving")
	assert_gte(IntroComicScript.PLAY_AT, IntroComicScript.SKIP_FADE_AT)
	assert_lte(IntroComicScript.PLAY_AT, IntroComicScript.COMPLETE_AT)


func test_every_panel_picture_and_the_logo_exist() -> void:
	for panel in IntroComicScript.panels():
		assert_true(ResourceLoader.exists(String(panel.texture)), String(panel.texture))
	assert_true(ResourceLoader.exists(IntroComicScript.LOGO))
	assert_true(ResourceLoader.exists(IntroComicScript.BACKDROP))


func test_the_intro_flag_round_trips() -> void:
	var path := "user://test_intro_settings.json"
	var settings := AppSettings.new()
	assert_false(settings.intro_seen, "a fresh install has not seen the intro")
	settings.intro_seen = true
	assert_true(settings.save(path))
	assert_true(AppSettings.load_settings(path).intro_seen)
	DirAccess.remove_absolute(path)


func test_without_a_window_the_intro_hands_straight_over() -> void:
	# Tests and the bots run headless: the comic must never stand between them
	# and the first fight.
	var called := [false]
	Game.play_intro(func() -> void: called[0] = true)
	assert_true(called[0])
	assert_false(Game.cinematic_playing)
