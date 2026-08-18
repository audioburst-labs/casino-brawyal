class_name ChipTrayView
extends PanelContainer
## The chip tray: one stack per suit with a count badge. Chips can be
## drag-and-dropped onto ability sockets (patch 0.1), or click-selected
## (stack glows, then click a socket).

signal chip_selected(suit: StringName)


class ChipButton:
	extends Button
	var suit: StringName = &""

	func _get_drag_data(_position: Vector2) -> Variant:
		var preview_texture := SuitAssets.chip_texture(suit)
		if preview_texture != null:
			var preview := TextureRect.new()
			preview.texture = preview_texture
			preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			preview.custom_minimum_size = Vector2(64, 64)
			preview.modulate.a = 0.9
			set_drag_preview(preview)
		return {"suit": suit}

var selected_suit: StringName = &""

var _tray: ChipTray
var _row: HBoxContainer


func _ready() -> void:
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 18)
	add_child(_row)


func bind(tray: ChipTray) -> void:
	_tray = tray
	refresh()


func refresh() -> void:
	for child in _row.get_children():
		child.queue_free()
	if _tray == null:
		return
	var any := false
	for suit: StringName in ContentDB.SUITS:
		var count := _tray.count(suit)
		if count <= 0:
			if selected_suit == suit:
				selected_suit = &""
			continue
		any = true
		_row.add_child(_build_stack(suit, count))
	if not any:
		selected_suit = &""
		var empty := Label.new()
		empty.text = "no chips"
		empty.add_theme_color_override("font_color", Color(0.7, 0.65, 0.6))
		_row.add_child(empty)


func deselect() -> void:
	selected_suit = &""
	refresh()


func _build_stack(suit: StringName, count: int) -> Control:
	var button := ChipButton.new()
	button.suit = suit
	button.custom_minimum_size = Vector2(104, 104)
	button.tooltip_text = "%s chips: %d" % [suit, count]
	var texture := SuitAssets.chip_texture(suit)
	if texture != null:
		var chip := TextureRect.new()
		chip.texture = texture
		chip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		chip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		chip.set_anchors_preset(Control.PRESET_FULL_RECT)
		chip.offset_left = 8
		chip.offset_top = 8
		chip.offset_right = -8
		chip.offset_bottom = -8
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(chip)
		var badge := Label.new()
		badge.text = "x%d" % count
		badge.theme_type_variation = &"SubtitleLabel"
		badge.add_theme_font_size_override("font_size", 22)
		badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		badge.offset_left = -44
		badge.offset_top = -30
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(badge)
	else:
		button.text = "%s x%d" % [String(suit).left(1).to_upper(), count]
		button.add_theme_color_override("font_color", SuitAssets.suit_color(suit).lightened(0.5))
	if selected_suit == suit:
		button.modulate = Color(1.25, 1.2, 0.9)
	button.pressed.connect(func() -> void:
		selected_suit = suit if selected_suit != suit else &""
		refresh()
		chip_selected.emit(selected_suit))
	return button
