class_name ReelStrip
extends PanelContainer
## The slot machine's reel window: one framed slot per reel, spin animation
## cycles suit faces rapidly then settles left-to-right with an overshoot pop.

const CYCLE_INTERVAL := 0.06
const STOP_STAGGER := 0.28

var _reel_faces: Array[TextureRect] = []
var _reel_fallbacks: Array[Label] = []
var _row: HBoxContainer


func _ready() -> void:
	theme_type_variation = &"FeltPanel"
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 14)
	add_child(_row)


func set_reel_count(count: int) -> void:
	for child in _row.get_children():
		child.queue_free()
	_reel_faces.clear()
	_reel_fallbacks.clear()
	for i in count:
		var frame := PanelContainer.new()
		frame.custom_minimum_size = Vector2(110, 130)
		# Cream slot window (like the cabinet art) so dark suits stay readable.
		var window := StyleBoxFlat.new()
		window.bg_color = Color(0.96, 0.93, 0.85)
		window.border_color = Color(0.83, 0.69, 0.22)
		window.set_border_width_all(3)
		window.set_corner_radius_all(12)
		window.shadow_color = Color(0, 0, 0, 0.3)
		window.shadow_size = 3
		frame.add_theme_stylebox_override("panel", window)
		var face := TextureRect.new()
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		face.custom_minimum_size = Vector2(86, 86)
		face.pivot_offset = Vector2(43, 43)
		frame.add_child(face)
		var fallback := Label.new()
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.add_theme_font_size_override("font_size", 44)
		frame.add_child(fallback)
		_row.add_child(frame)
		_reel_faces.append(face)
		_reel_fallbacks.append(fallback)


## Animates all reels cycling, then stops each on its final symbol in order.
func spin_to(symbols: Array) -> void:
	var cycling := symbols.map(func(_s: Variant) -> bool: return true)
	var elapsed := 0.0
	var suits := ContentDB.SUITS
	var cycle_index := 0
	while cycling.has(true):
		await get_tree().create_timer(CYCLE_INTERVAL).timeout
		elapsed += CYCLE_INTERVAL
		cycle_index += 1
		for i in symbols.size():
			if not cycling[i]:
				continue
			if elapsed >= 0.5 + i * STOP_STAGGER:
				cycling[i] = false
				_show_face(i, symbols[i])
				var face := _reel_faces[i]
				face.scale = Vector2(1.45, 1.45)
				var tween := face.create_tween()
				tween.tween_property(face, "scale", Vector2.ONE, 0.3) \
					.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			else:
				_show_face(i, suits[(cycle_index + i) % suits.size()])
	await get_tree().create_timer(0.15).timeout


func _show_face(index: int, suit: StringName) -> void:
	var texture := SuitAssets.suit_texture(suit)
	_reel_faces[index].texture = texture
	if texture == null:
		_reel_fallbacks[index].text = String(suit).left(1).to_upper()
		_reel_fallbacks[index].add_theme_color_override(
			"font_color", SuitAssets.suit_color(suit))
	else:
		_reel_fallbacks[index].text = ""
