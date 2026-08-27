class_name AbilityCard
extends PanelContainer
## One ability on the bar: icon, name, description text, and cost sockets.
## All cards share one fixed size. Chips arrive by click (select chip, click
## socket) or drag-and-drop. Hovering shows keyword bubbles above the card
## immediately (patch 0.1).

signal socket_clicked(ability_index: int, slot_index: int)
signal chip_dropped(ability_index: int, slot_index: int, suit: StringName)

const CARD_SIZE := Vector2(225, 300)   # patch 0.13 sizing, fits above the screen edge
const SOCKET_SIZE := 48.0

## Keyword words in ability text render as inline icons (patch 0.13).
const KEYWORD_ICONS := {
	&"mark": "res://assets/icons/status_mark.png",
	&"weak": "res://assets/icons/status_weak.png",
	&"vulnerable": "res://assets/icons/status_vulnerable.png",
	&"block": "res://assets/icons/status_block.png",
	&"taunt": "res://assets/icons/status_taunt.png",
	&"stun": "res://assets/icons/status_stun.png",
	&"cash_in": "res://assets/icons/keyword_cash_in.png",
	&"go_again": "res://assets/icons/keyword_go_again.png",
	&"repeat": "res://assets/icons/keyword_repeat.png",
}

var ability_index := -1

var _state: AbilityState
var _sim: CombatSim = null
var _sockets: Array[Button] = []
var _socket_faces: Array[TextureRect] = []
var _socket_labels: Array[Label] = []
var _description: RichTextLabel
var _highlight_suit: StringName = &""
var _keyword_panel: PanelContainer = null


class SocketButton:
	extends Button
	var card: AbilityCard
	var slot := 0

	func _can_drop_data(_position: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("suit") \
			and card.accepts_chip(slot, data.suit)

	func _drop_data(_position: Vector2, data: Variant) -> void:
		card.chip_dropped.emit(card.ability_index, slot, data.suit)


func accepts_chip(slot: int, suit: StringName) -> bool:
	return not _state.exhausted() and _state.can_accept(slot, suit)


func setup(state: AbilityState, index: int, sim: CombatSim = null) -> void:
	_state = state
	_sim = sim
	ability_index = index
	custom_minimum_size = CARD_SIZE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pivot_offset = Vector2(CARD_SIZE.x * 0.5, CARD_SIZE.y)
	mouse_entered.connect(_on_hover_entered)
	mouse_exited.connect(_on_hover_exited)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	var icon_holder := CenterContainer.new()
	icon_holder.custom_minimum_size = Vector2(0, 72)
	box.add_child(icon_holder)
	var icon_texture := SuitAssets.ability_texture(_state.def.id)
	if icon_texture != null:
		var icon := TextureRect.new()
		icon.texture = icon_texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(80, 80)
		icon_holder.add_child(icon)

	var name_label := Label.new()
	name_label.text = _state.def.name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_label.theme_type_variation = &"SubtitleLabel"
	name_label.add_theme_font_size_override("font_size", 24)
	box.add_child(name_label)

	_description = RichTextLabel.new()
	_description.bbcode_enabled = true
	_description.fit_content = true
	_description.scroll_active = false
	_description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_description.add_theme_font_size_override("normal_font_size", 16)
	_description.add_theme_color_override("default_color", Color(0.9, 0.86, 0.78))
	_description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_description)

	# Once-per-turn indicator badge (patch 0.13), explained on hover.
	# Wrapped in a plain Control overlay so the PanelContainer can't stretch it.
	if _state.def.per_turn > 0 and ResourceLoader.exists("res://assets/icons/badge_per_turn.png"):
		var overlay := Control.new()
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(overlay)
		var badge := TextureRect.new()
		badge.texture = load("res://assets/icons/badge_per_turn.png")
		badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge.size = Vector2(34, 34)
		badge.position = Vector2(CARD_SIZE.x - 42, 6)
		badge.tooltip_text = "Once per turn: usable %d time(s) each round." % _state.def.per_turn
		badge.mouse_filter = Control.MOUSE_FILTER_PASS
		overlay.add_child(badge)

	# Socket rows: odd costs of 5+ put 2 on top, the rest in rows of 3
	# (patch 0.13); otherwise up to 3 per centered row.
	var socket_box := VBoxContainer.new()
	socket_box.alignment = BoxContainer.ALIGNMENT_CENTER
	socket_box.add_theme_constant_override("separation", 5)
	box.add_child(socket_box)
	var rows := _socket_rows(_state.def.cost.size())
	var socket_rows: Array[HBoxContainer] = []
	for row_size in rows:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 5)
		socket_box.add_child(row)
		socket_rows.append(row)
	var row_index := 0
	var placed_in_row := 0
	var socket_row: HBoxContainer = socket_rows[0]
	var socket_style := StyleBoxFlat.new()
	socket_style.bg_color = Color(0.94, 0.9, 0.8)
	socket_style.border_color = Color(0.83, 0.69, 0.22)
	socket_style.set_border_width_all(2)
	socket_style.set_corner_radius_all(10)
	for slot in _state.def.cost.size():
		if placed_in_row >= int(rows[row_index]):
			row_index += 1
			placed_in_row = 0
			socket_row = socket_rows[row_index]
		placed_in_row += 1
		var socket := SocketButton.new()
		socket.card = self
		socket.slot = slot
		socket.custom_minimum_size = Vector2(SOCKET_SIZE, SOCKET_SIZE)
		for style_name in ["normal", "hover", "pressed", "disabled"]:
			socket.add_theme_stylebox_override(style_name, socket_style)
		socket.pressed.connect(_on_socket_pressed.bind(slot))
		socket_row.add_child(socket)
		_sockets.append(socket)
		var face := TextureRect.new()
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		face.set_anchors_preset(Control.PRESET_FULL_RECT)
		face.offset_left = 6
		face.offset_top = 6
		face.offset_right = -6
		face.offset_bottom = -6
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		socket.add_child(face)
		_socket_faces.append(face)
		var fallback := Label.new()
		fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.add_theme_color_override("font_color", Color(0.35, 0.25, 0.2))
		fallback.add_theme_font_size_override("font_size", 22)
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		socket.add_child(fallback)
		_socket_labels.append(fallback)
	refresh()


func refresh(highlight_suit: StringName = &"") -> void:
	_highlight_suit = highlight_suit
	modulate = Color(0.6, 0.58, 0.55) if _state.exhausted() else Color.WHITE
	for slot in _sockets.size():
		_render_socket(slot, _state.filled[slot])
	_refresh_description()


## Row layout for cost sockets: <=3 one row; 4 = 2+2; odd 5+ = 2 on top then
## rows of 3 (patch 0.13); even 6+ = rows of 3.
static func _socket_rows(count: int) -> Array:
	if count <= 3:
		return [count]
	if count == 4:
		return [2, 2]
	var rows := []
	var remaining := count
	if count % 2 == 1:
		rows.append(2)
		remaining -= 2
	while remaining > 0:
		rows.append(mini(3, remaining))
		remaining -= 3
	return rows


## Live numbers (patch 0.12) + inline keyword icons (patch 0.13): damage
## figures reflect the hero's current modifiers, and keyword words render
## as their icons (the hover popup spells them out).
func _refresh_description() -> void:
	var text := _state.def.description
	if _sim != null:
		for effect: Dictionary in _state.def.effects:
			if str(effect.get("op", "")) != "damage":
				continue
			var base := int(effect.get("amount", 0))
			var modified := _sim.preview_damage(base, _state)
			if modified != base:
				text = text.replace(str(base), "[color=#f0cf5d]%d[/color]" % modified)
	for keyword_id: StringName in _state.def.keywords:
		var keyword := Db.content.get_keyword(keyword_id)
		var icon_path: String = KEYWORD_ICONS.get(keyword_id, "")
		if keyword == null or icon_path == "" or not ResourceLoader.exists(icon_path):
			continue
		var word := keyword.name.trim_suffix(" X")
		text = text.replace(word, "[img=20]%s[/img]" % icon_path)
	_description.text = "[center]%s[/center]" % text


## Immediately paints a chip into a socket, even if the sim already cleared
## the ability (patch 0.1: the final chip must be visible before firing).
func show_chip(slot: int, suit: StringName) -> void:
	_render_socket(slot, suit)


func _render_socket(slot: int, filled: StringName) -> void:
	var socket := _sockets[slot]
	var face := _socket_faces[slot]
	var fallback := _socket_labels[slot]
	var required := _state.def.cost[slot]
	if filled != &"":
		var chip := SuitAssets.chip_texture(filled)
		face.texture = chip
		face.modulate = Color.WHITE
		fallback.text = "" if chip != null else String(filled).left(1).to_upper()
		socket.modulate = Color.WHITE
		socket.tooltip_text = "%s chip socketed (click to return)" % filled
	else:
		var ghost := SuitAssets.suit_texture(required)
		face.texture = ghost
		face.modulate = Color(1, 1, 1, 0.45)
		fallback.text = "" if ghost != null else \
			("?" if required == &"any" else String(required).left(1).to_upper())
		socket.tooltip_text = "needs: any suit" if required == &"any" else "needs: %s" % required
		var eligible := _highlight_suit != &"" and accepts_chip(slot, _highlight_suit)
		if eligible:
			socket.modulate = Color(1.25, 1.2, 0.75)
			face.modulate = Color(1, 1, 1, 0.85)
		else:
			socket.modulate = Color.WHITE


func flash_fire() -> void:
	var tween := create_tween()
	modulate = Color(1.8, 1.6, 1.0)
	scale = Vector2(1.08, 1.08)
	pivot_offset = size * 0.5
	tween.tween_property(self, "modulate", Color.WHITE, 0.35)
	tween.parallel().tween_property(self, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Balatro-style hover: the card leans up at you and settles back springily.
func _on_hover_entered() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.06, 1.06), 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_show_keywords()


func _on_hover_exited() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ONE, 0.14) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hide_keywords()


func _show_keywords() -> void:
	if (_state.def.keywords.is_empty() and _state.def.per_turn == 0) \
			or _keyword_panel != null:
		return
	_keyword_panel = PanelContainer.new()
	_keyword_panel.top_level = true
	_keyword_panel.z_index = 200
	_keyword_panel.theme_type_variation = &"TooltipPanel"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_keyword_panel.add_child(box)
	for keyword_id: StringName in _state.def.keywords:
		var keyword := Db.content.get_keyword(keyword_id)
		if keyword == null:
			continue
		var entry := PanelContainer.new()
		var label := Label.new()
		label.text = "%s — %s" % [keyword.name, keyword.text]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(280, 0)
		label.add_theme_font_size_override("font_size", 15)
		entry.add_child(label)
		box.add_child(entry)
	if _state.def.per_turn > 0:
		var limit_entry := PanelContainer.new()
		var limit_label := Label.new()
		limit_label.text = "Once per turn — usable %d time(s) each round." % _state.def.per_turn
		limit_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		limit_label.custom_minimum_size = Vector2(280, 0)
		limit_label.add_theme_font_size_override("font_size", 15)
		limit_entry.add_child(limit_label)
		box.add_child(limit_entry)
	add_child(_keyword_panel)
	# Above the card, clamped to the screen.
	await get_tree().process_frame
	if _keyword_panel == null:
		return
	var panel_size := _keyword_panel.get_combined_minimum_size()
	var pos := global_position + Vector2((size.x - panel_size.x) * 0.5, -panel_size.y - 8)
	pos.x = clampf(pos.x, 8, get_viewport_rect().size.x - panel_size.x - 8)
	pos.y = maxf(pos.y, 8)
	_keyword_panel.global_position = pos


func _hide_keywords() -> void:
	if _keyword_panel != null:
		_keyword_panel.queue_free()
		_keyword_panel = null


func _exit_tree() -> void:
	_hide_keywords()


func _on_socket_pressed(slot: int) -> void:
	socket_clicked.emit(ability_index, slot)
