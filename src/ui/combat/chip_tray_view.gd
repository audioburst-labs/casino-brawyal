class_name ChipTrayView
extends PanelContainer
## The chip tray: one stack per suit with a count badge. Chips move to
## ability sockets by drag-and-drop only (patch 0.11), with the drag preview
## centered on the cursor.

var _tray: ChipTray
var _row: HBoxContainer


class ChipButton:
	extends Button
	var suit: StringName = &""

	func _get_drag_data(_position: Vector2) -> Variant:
		var preview_texture := SuitAssets.chip_texture(suit)
		if preview_texture != null:
			# Wrap so the chip is centered on the mouse (patch 0.11).
			var wrapper := Control.new()
			var image := TextureRect.new()
			image.texture = preview_texture
			image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			image.custom_minimum_size = Vector2(64, 64)
			image.size = Vector2(64, 64)
			image.position = Vector2(-32, -32)
			image.modulate.a = 0.9
			wrapper.add_child(image)
			set_drag_preview(wrapper)
		return {"suit": suit}


func _ready() -> void:
	# Constant footprint whether the tray holds 0 or 4 suits (patch 0.12).
	custom_minimum_size = Vector2(4 * 96 + 3 * 14 + 32, 112)
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
	for suit: StringName in ContentDB.SUITS:
		var count := _tray.count(suit)
		if count > 0:
			_row.add_child(_build_stack(suit, count))


func _build_stack(suit: StringName, count: int) -> Control:
	var button := ChipButton.new()
	button.suit = suit
	button.custom_minimum_size = Vector2(96, 96)
	button.tooltip_text = "%s chips: %d — drag onto an ability socket" % [suit, count]
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
	return button
