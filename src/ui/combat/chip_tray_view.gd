class_name ChipTrayView
extends PanelContainer
## The chip tray: one stack per suit with a count badge. Clicking a stack
## selects that suit for socketing; the selected stack lifts and glows.

signal chip_selected(suit: StringName)

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
	var button := Button.new()
	button.custom_minimum_size = Vector2(96, 96)
	button.tooltip_text = "%s chips: %d" % [suit, count]
	var texture := SuitAssets.chip_texture(suit)
	if texture != null:
		button.icon = texture
		button.expand_icon = true
		button.text = " x%d" % count
	else:
		button.text = "%s x%d" % [String(suit).left(1).to_upper(), count]
		button.add_theme_color_override("font_color", SuitAssets.suit_color(suit).lightened(0.5))
	if selected_suit == suit:
		button.modulate = Color(1.25, 1.2, 0.9)
		button.position.y -= 6
	button.pressed.connect(func() -> void:
		selected_suit = suit if selected_suit != suit else &""
		refresh()
		chip_selected.emit(selected_suit))
	return button
