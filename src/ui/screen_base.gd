class_name ScreenBase
extends Control
## Shared scaffolding for run screens: full-rect layout, themed background,
## title, centered content column, and a bottom continue button.

var content: VBoxContainer

var _title_label: Label


func build_screen(title: String, background_path: String) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var background := TextureRect.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if ResourceLoader.exists(background_path):
		background.texture = load(background_path)
	else:
		var fallback := ColorRect.new()
		fallback.color = Color(0.07, 0.2, 0.13)
		fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(fallback)
	add_child(background)

	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.02, 0.03, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var column := VBoxContainer.new()
	column.anchor_left = 0.18
	column.anchor_right = 0.82
	column.anchor_top = 0.075  # below the persistent run header bar
	column.anchor_bottom = 0.95
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 24)
	add_child(column)

	_title_label = Label.new()
	_title_label.text = title
	_title_label.theme_type_variation = &"TitleLabel"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title_label)

	content = VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 18)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(content)


func set_title(text: String) -> void:
	_title_label.text = text


func add_continue_button(text := "Continue", callback := Callable()) -> Button:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(row)
	var button := Button.new()
	button.text = text
	if callback.is_valid():
		button.pressed.connect(callback)
	else:
		button.pressed.connect(Game.encounter_finished)
	row.add_child(button)
	return button


func add_info_label(text: String, size := 24) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(720, 0)
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	label.add_theme_font_size_override("font_size", size)
	content.add_child(label)
	return label


func make_card(title: String, lines: Array[String], on_pressed: Callable) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(340, 150)
	button.text = "%s\n%s" % [title, "\n".join(lines)]
	button.pressed.connect(on_pressed)
	return button
