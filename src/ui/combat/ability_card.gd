class_name AbilityCard
extends PanelContainer
## One ability on the bar: icon, name, cost sockets, and hover description.
## Sockets glow when the currently selected chip suit could legally fill them;
## clicking a socket asks the presenter to assign the chip.

signal socket_clicked(ability_index: int, slot_index: int)

var ability_index := -1

var _state: AbilityState
var _sockets: Array[Button] = []
var _highlight_suit: StringName = &""


func setup(state: AbilityState, index: int) -> void:
	_state = state
	ability_index = index
	custom_minimum_size = Vector2(190, 200)
	tooltip_text = "%s\n%s" % [_state.def.name, _state.def.description]

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(box)

	var icon_texture := SuitAssets.ability_texture(_state.def.id)
	if icon_texture != null:
		var icon := TextureRect.new()
		icon.texture = icon_texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(72, 72)
		box.add_child(icon)

	var name_label := Label.new()
	name_label.text = _state.def.name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_label.theme_type_variation = &"SubtitleLabel"
	name_label.add_theme_font_size_override("font_size", 20)
	box.add_child(name_label)

	var socket_row := HBoxContainer.new()
	socket_row.alignment = BoxContainer.ALIGNMENT_CENTER
	socket_row.add_theme_constant_override("separation", 8)
	box.add_child(socket_row)
	for slot in _state.def.cost.size():
		var socket := Button.new()
		socket.custom_minimum_size = Vector2(52, 52)
		socket.pressed.connect(_on_socket_pressed.bind(slot))
		socket_row.add_child(socket)
		_sockets.append(socket)
	refresh()


func refresh(highlight_suit: StringName = &"") -> void:
	_highlight_suit = highlight_suit
	for slot in _sockets.size():
		var socket := _sockets[slot]
		var filled := _state.filled[slot]
		var required := _state.def.cost[slot]
		if filled != &"":
			var chip := SuitAssets.chip_texture(filled)
			socket.icon = chip
			socket.expand_icon = true
			socket.text = "" if chip != null else String(filled).left(1).to_upper()
			socket.modulate = Color.WHITE
			socket.tooltip_text = "%s chip socketed (click to return)" % filled
		else:
			var ghost := SuitAssets.suit_texture(required) if required != &"any" else null
			socket.icon = ghost
			socket.expand_icon = ghost != null
			socket.text = "?" if required == &"any" else ("" if ghost != null else String(required).left(1).to_upper())
			socket.tooltip_text = "needs: %s" % required
			var eligible := _highlight_suit != &"" and _state.can_accept(slot, _highlight_suit)
			socket.modulate = Color(1.4, 1.3, 0.7) if eligible else Color(0.75, 0.72, 0.68, 0.9)
	var bonus_ready := _state.def.bonus_suit != &""
	if bonus_ready:
		tooltip_text = "%s\n%s" % [_state.def.name, _state.def.description]


func flash_fire() -> void:
	var tween := create_tween()
	modulate = Color(1.8, 1.6, 1.0)
	scale = Vector2(1.08, 1.08)
	tween.tween_property(self, "modulate", Color.WHITE, 0.35)
	tween.parallel().tween_property(self, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_socket_pressed(slot: int) -> void:
	socket_clicked.emit(ability_index, slot)
