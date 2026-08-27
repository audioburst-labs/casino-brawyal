class_name ReelStrip
extends PanelContainer
## The slot machine's reel window. Each reel is a clipped, vertically
## scrolling strip of symbols that spins fast, decelerates, and settles on
## the landed symbol with a bounce — like a real one-armed bandit, not a
## flickering texture swap.

const WINDOW := Vector2(110, 130)
const FACE := 104.0            # symbol cell height inside the strip
const STRIP_FACES := 14        # cells per strip; the landing cell is near the end
const BASE_DURATION := 0.85
const STAGGER := 0.3

var _windows: Array[Control] = []   # clip containers, one per reel
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
	_windows.clear()
	for i in count:
		var frame := PanelContainer.new()
		frame.custom_minimum_size = WINDOW
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.96, 0.93, 0.85)
		style.border_color = Color(0.83, 0.69, 0.22)
		style.set_border_width_all(3)
		style.set_corner_radius_all(12)
		style.shadow_color = Color(0, 0, 0, 0.3)
		style.shadow_size = 3
		frame.add_theme_stylebox_override("panel", style)
		var clip := Control.new()
		clip.clip_contents = true
		clip.custom_minimum_size = WINDOW - Vector2(8, 8)
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(clip)
		_row.add_child(frame)
		_windows.append(clip)
		_populate(clip, ContentDB.SUITS[i % ContentDB.SUITS.size()])


## Fills a reel window with a fresh strip whose landing cell shows `final`.
## Returns the strip and the y-offset that centers the landing cell.
func _populate(clip: Control, final: StringName) -> Dictionary:
	for child in clip.get_children():
		child.queue_free()
	var strip := VBoxContainer.new()
	strip.add_theme_constant_override("separation", 0)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(strip)
	var landing_index := STRIP_FACES - 2
	for face_index in STRIP_FACES:
		var cell := CenterContainer.new()
		cell.custom_minimum_size = Vector2(WINDOW.x - 8, FACE)
		var suit: StringName = final if face_index == landing_index \
			else ContentDB.SUITS[randi() % ContentDB.SUITS.size()]
		var face := TextureRect.new()
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		face.custom_minimum_size = Vector2(84, 84)
		face.pivot_offset = Vector2(42, 42)
		var texture := SuitAssets.suit_texture(suit)
		if texture != null:
			face.texture = texture
		cell.add_child(face)
		strip.add_child(cell)
	# Start showing cell 0; the landing offset centers the landing cell.
	strip.position.y = 0.0
	var land_y := -(FACE * landing_index) + (clip.custom_minimum_size.y - FACE) * 0.5
	return {"strip": strip, "land_y": land_y, "landing_index": landing_index}


## Spins every reel: constant blur-fast scroll into a long deceleration,
## overshooting the landing cell and springing back — staggered left to right.
func spin_to(symbols: Array) -> void:
	var spins: Array[Dictionary] = []
	for i in mini(symbols.size(), _windows.size()):
		spins.append(_populate(_windows[i], symbols[i]))
	var last_tween: Tween = null
	for i in spins.size():
		var strip: VBoxContainer = spins[i].strip
		var land_y: float = spins[i].land_y
		var duration: float = BASE_DURATION + i * STAGGER
		var tween := create_tween()
		# Decelerating scroll all the way down the strip...
		tween.tween_property(strip, "position:y", land_y - 16.0, duration) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		# ...16px past the mark, then the classic reel spring-back.
		tween.tween_property(strip, "position:y", land_y, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_callback(_pop_landed.bind(strip, int(spins[i].landing_index)))
		last_tween = tween
	if last_tween != null:
		await last_tween.finished
	await get_tree().create_timer(0.1).timeout


func _pop_landed(strip: VBoxContainer, landing_index: int) -> void:
	if landing_index >= strip.get_child_count():
		return
	var cell: CenterContainer = strip.get_child(landing_index)
	if cell.get_child_count() == 0:
		return
	var face: TextureRect = cell.get_child(0)
	face.scale = Vector2(1.35, 1.35)
	var tween := face.create_tween()
	tween.tween_property(face, "scale", Vector2.ONE, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
