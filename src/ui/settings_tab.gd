class_name SettingsTab
extends Control
## Settings Tab overlay (doc): Continue, Display Mode, Frame Rate, Volume
## (slider revealed on hover + mute toggle), Exit to Main Menu, Leave Game.

const FRAME_RATES := [30, 60, 120, 144]

var _volume_row: HBoxContainer
var _volume_slider: HSlider
var _volume_dragging := false
var _mute_button: Button
var _muted := false


func _ready() -> void:
	# A freshly-instantiated Control's own anchored `size` isn't reliably
	# resolved synchronously within the same _ready() (it's a next-frame
	# layout pass) — position everything from the viewport size directly
	# instead of trusting anchor percentages relative to `self`.
	var vp := get_viewport_rect().size
	position = Vector2.ZERO
	size = vp
	z_index = 200

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.01, 0.02, 0.72)
	backdrop.position = Vector2.ZERO
	backdrop.size = vp
	backdrop.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_close())
	add_child(backdrop)

	var panel_size := Vector2(520, 460)
	var panel := PanelContainer.new()
	panel.position = vp * 0.5 - panel_size * 0.5
	panel.size = panel_size
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)

	var title := Label.new()
	title.text = "Settings"
	title.theme_type_variation = &"TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var display_row := HBoxContainer.new()
	display_row.add_theme_constant_override("separation", 12)
	column.add_child(display_row)
	display_row.add_child(_label("Display Mode"))
	var display_toggle := Button.new()
	display_toggle.text = "Fullscreen" if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN \
		else "Windowed"
	display_toggle.pressed.connect(func() -> void:
		var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		if fullscreen:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			display_toggle.text = "Windowed"
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			display_toggle.text = "Fullscreen")
	display_row.add_child(display_toggle)

	var fps_row := HBoxContainer.new()
	fps_row.add_theme_constant_override("separation", 12)
	column.add_child(fps_row)
	fps_row.add_child(_label("Frame Rate"))
	for fps: int in FRAME_RATES:
		var fps_button := Button.new()
		fps_button.text = str(fps)
		fps_button.toggle_mode = true
		fps_button.button_pressed = Engine.max_fps == fps
		fps_button.pressed.connect(func() -> void:
			Engine.max_fps = fps
			for sibling in fps_row.get_children():
				if sibling is Button:
					sibling.button_pressed = sibling == fps_button)
		fps_row.add_child(fps_button)

	_volume_row = HBoxContainer.new()
	_volume_row.add_theme_constant_override("separation", 12)
	column.add_child(_volume_row)
	_volume_row.add_child(_label("Volume"))
	_mute_button = Button.new()
	_mute_button.text = "🔊"
	_mute_button.pressed.connect(_toggle_mute)
	_volume_row.add_child(_mute_button)
	_volume_slider = HSlider.new()
	_volume_slider.min_value = 0
	_volume_slider.max_value = 100
	_volume_slider.value = _current_volume_pct()
	_volume_slider.custom_minimum_size = Vector2(140, 0)
	# Stays visible (and so keeps receiving drag input) at all times — only
	# its opacity toggles on hover. Toggling `visible` instead (patch 0.17
	# bug) cut the slider's input off mid-drag the instant the mouse
	# wandered a pixel off it, making it "only clickable, not slidable."
	_volume_slider.modulate.a = 0.0
	_volume_slider.value_changed.connect(_on_volume_changed)
	_volume_slider.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_volume_dragging = event.pressed)
	_volume_row.add_child(_volume_slider)
	_volume_row.mouse_entered.connect(func() -> void: _volume_slider.modulate.a = 1.0)
	_volume_row.mouse_exited.connect(func() -> void:
		if not _volume_dragging:
			_volume_slider.modulate.a = 0.0)

	column.add_child(HSeparator.new())

	var continue_button := Button.new()
	continue_button.text = "Continue"
	continue_button.pressed.connect(_close)
	column.add_child(continue_button)

	var exit_menu_button := Button.new()
	exit_menu_button.text = "Exit to Main Menu"
	exit_menu_button.pressed.connect(_exit_to_main_menu)
	column.add_child(exit_menu_button)

	var leave_button := Button.new()
	leave_button.text = "Leave Game"
	leave_button.pressed.connect(_leave_game)
	column.add_child(leave_button)


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(140, 0)
	return label


func _master_bus() -> int:
	return AudioServer.get_bus_index("Master")


func _current_volume_pct() -> float:
	var db := AudioServer.get_bus_volume_db(_master_bus())
	return clampf(db_to_linear(db), 0.0, 1.0) * 100.0


func _on_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(_master_bus(), linear_to_db(clampf(value / 100.0, 0.001, 1.0)))
	if value > 0.0 and _muted:
		_muted = false
		AudioServer.set_bus_mute(_master_bus(), false)
		_mute_button.text = "🔊"


func _toggle_mute() -> void:
	_muted = not _muted
	AudioServer.set_bus_mute(_master_bus(), _muted)
	_mute_button.text = "🔇" if _muted else "🔊"


func _exit_to_main_menu() -> void:
	if Game.run != null:
		RunSave.save_run(Game.run)
	_close()
	Game.goto_screen("res://scenes/screens/main_menu.tscn")


func _leave_game() -> void:
	if Game.run != null:
		RunSave.save_run(Game.run)
	get_tree().quit()


func _close() -> void:
	queue_free()


## Esc closes the tab (patch 0.19). Handled as *unhandled* input and marked
## consumed, so with both overlays somehow open only the topmost one closes,
## and Esc never leaks through to the screen underneath.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()
