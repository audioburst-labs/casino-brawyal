extends GutTest
## Patch 0.125: the redesigned title screen's menu column.


func _panel(has_save: bool, tutorial_on := false) -> TitlePanel:
	var panel := TitlePanel.new()
	add_child_autofree(panel)
	panel.setup(has_save, tutorial_on)
	return panel


func _labels(panel: TitlePanel) -> Array[String]:
	var out: Array[String] = []
	for b in panel._buttons:
		out.append(b.text)
	return out


func test_without_a_saved_run_there_is_no_continue() -> void:
	assert_eq(_labels(_panel(false)), ["Play", "Settings", "Quit"] as Array[String])


func test_with_a_saved_run_continue_sits_under_play() -> void:
	assert_eq(_labels(_panel(true)), ["Play", "Continue", "Settings", "Quit"] as Array[String])


func test_the_four_buttons_are_stacked_with_even_gaps() -> void:
	var panel := _panel(true)
	for i in range(1, panel._buttons.size()):
		var step: float = panel._buttons[i].position.y - panel._buttons[i - 1].position.y
		assert_almost_eq(step, TitlePanel.BUTTON_SIZE.y + TitlePanel.GAP, 0.01)


func test_the_panel_is_the_left_quarter_of_the_screen() -> void:
	var panel := _panel(false)
	assert_almost_eq(panel.size.x / 1920.0, 0.27, 0.005)
	assert_eq(panel.size.y, 1080.0)


func test_the_tutorial_toggle_starts_as_it_was_saved() -> void:
	assert_true(_panel(false, true)._toggle.button_pressed)
	assert_false(_panel(false, false)._toggle.button_pressed)


func test_flipping_the_toggle_says_so() -> void:
	var panel := _panel(false, false)
	watch_signals(panel)
	panel._toggle.button_pressed = true
	panel.tutorial_toggled.emit(true)
	assert_signal_emitted_with_parameters(panel, "tutorial_toggled", [true])


func test_each_button_reports_its_own_press() -> void:
	var panel := _panel(true)
	watch_signals(panel)
	panel._buttons[0].pressed.emit()
	panel._buttons[1].pressed.emit()
	panel._buttons[2].pressed.emit()
	panel._buttons[3].pressed.emit()
	assert_signal_emitted(panel, "play_pressed")
	assert_signal_emitted(panel, "continue_pressed")
	assert_signal_emitted(panel, "settings_pressed")
	assert_signal_emitted(panel, "quit_pressed")


func test_the_beams_sway_forty_five_degrees_each_way() -> void:
	var lo := 999.0
	var hi := -999.0
	var t := 0.0
	while t < 30.0:
		var a := TitleBeams.angle_at(t, 0.0)
		lo = minf(lo, a)
		hi = maxf(hi, a)
		t += 0.05
	assert_almost_eq(lo, -45.0, 0.5)
	assert_almost_eq(hi, 45.0, 0.5)


func test_a_beam_takes_about_fourteen_seconds_for_a_full_cycle() -> void:
	assert_almost_eq(TitleBeams.angle_at(0.0, 0.0), TitleBeams.angle_at(14.3, 0.0), 0.01)
	assert_ne(snappedf(TitleBeams.angle_at(0.0, 0.0), 0.01), snappedf(TitleBeams.angle_at(7.15, 0.0), 0.01))
