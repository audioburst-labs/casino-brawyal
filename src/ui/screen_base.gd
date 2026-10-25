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
	# Patch 0.20: art held back a further 10% so foreground UI reads cleanly.
	dim.color = Color(0.05, 0.02, 0.03, 0.42)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	add_child(_idle_curtains())

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


## The stage curtains hanging at the sides (patch 0.125: every screen wears
## them, and the transition curtain gathers onto them when it opens). They sit
## above the painting and below the UI, so nothing the player uses is covered.
func _idle_curtains() -> TextureRect:
	var curtains := TextureRect.new()
	curtains.set_anchors_preset(Control.PRESET_FULL_RECT)
	curtains.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	curtains.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	curtains.mouse_filter = Control.MOUSE_FILTER_IGNORE
	curtains.add_to_group(CurtainTransition.GROUP)   # the transition stands in for it
	if ResourceLoader.exists(LivingBackdrop.CURTAINS):
		curtains.texture = load(LivingBackdrop.CURTAINS)
	if ResourceLoader.exists(LivingBackdrop.CLOTH_SHADER):
		var cloth := ShaderMaterial.new()
		cloth.shader = load(LivingBackdrop.CLOTH_SHADER)
		curtains.material = cloth
	return curtains


func set_title(text: String) -> void:
	_title_label.text = text


## A small spaced line of capitals above the title (0.126): where you are, in one
## line. Sits between the title and the content.
func add_eyebrow(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", NeonPalette.current().tube)
	label.theme_type_variation = &"SubtitleLabel"
	_title_label.get_parent().add_child(label)
	_title_label.get_parent().move_child(label, _title_label.get_index())
	return label


## The lit pill at the foot of a card that is itself the button: it only SHOWS
## what the card does, so the click goes through to the card.
func choose_tag(text := "Choose") -> Label:
	var tag := Label.new()
	tag.text = text.to_upper()
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.theme_type_variation = &"SubtitleLabel"
	tag.add_theme_font_size_override("font_size", 18)
	var project := ThemeDB.get_project_theme()
	if project != null and project.has_stylebox("normal", "PrimaryButton"):
		tag.add_theme_stylebox_override("normal", project.get_stylebox("normal", "PrimaryButton"))
	return tag


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
