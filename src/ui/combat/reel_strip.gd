class_name ReelStrip
extends Control
## The slot machine's reels. Each reel is a clipped, vertically scrolling strip
## of faces that spins fast, decelerates, and settles on the landed face with a
## bounce — like a real one-armed bandit, not a flickering texture swap.
##
## Patch 0.22, two changes:
##   * The strip scrolls DOWNWARD (designer's note on the Casino machine, and
##     his answer that both machines should match). See `_populate`.
##   * Everything the Casino's own copy of this code varied — window size,
##     face count, timings, where the faces come from, the gold stop-flash — is
##     a property now, so there is one reel widget in the game instead of two.
##
## It draws no frame of its own when `framed` is false: inside a `SlotCabinet`
## the cabinet art is the frame (patch 0.22).

signal reel_stopped(index: int)

const WINDOW := Vector2(110, 130)
const FACE := 104.0            # symbol cell height inside the strip
const STRIP_FACES := 14        # cells per strip; the landing cell is near the top
const BASE_DURATION := 0.85
const STAGGER := 0.3
const SEPARATION := 14
## Room the reels may use inside the machine area. The cabinet frame and its
## lever take the rest of `CombatScreen.MACHINE_WIDTH`.
const MAX_ROW_WIDTH := 530.0
## The landing cell sits one from the top, so cell 0 still covers the window
## while the strip overshoots downward past its mark.
const LANDING_INDEX := 1

## Geometry and feel, all overridable before `set_reel_count` (the Casino runs
## bigger windows and a much slower, more staggered spin).
var window_size := WINDOW
var face_height := FACE
var face_icon := 84.0
var strip_faces := STRIP_FACES
var base_duration := BASE_DURATION
var stagger := STAGGER
var overshoot := 16.0
var stop_flash := false        # the Casino's gold frame flash on every stop
var framed := true             # draw the felt panel; false inside a cabinet
## The combat machine shrinks its reels so 5-6 of them still fit a fixed area;
## the Casino's three are always full size.
var shrink_to_fit := true
## How a landed/rolling face is drawn. The combat machine shows suits; the
## Casino shows prize icons.
var face_provider: Callable = Callable(SuitAssets, "suit_texture")
var filler_pool: Array = ContentDB.SUITS

var _windows: Array[Control] = []   # clip containers, one per reel
var _frames: Array[PanelContainer] = []
var _row: HBoxContainer
var _panel: PanelContainer = null
var _scale := 1.0                   # 1.0 for <= 4 reels, smaller for 5-6


func _ready() -> void:
	_ensure_row()


## Built on demand: `set_reel_count` is sometimes called before the widget has
## entered the tree.
func _ensure_row() -> void:
	if _row != null:
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", SEPARATION)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if framed:
		_panel = PanelContainer.new()
		_panel.theme_type_variation = &"FeltPanel"
		_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_panel)
		_panel.add_child(_row)
	else:
		_row.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_row)


## The scale that fits `count` reels into the machine area, never above 1.
static func scale_for(count: int) -> float:
	if count <= 0:
		return 1.0
	var fit := (MAX_ROW_WIDTH - SEPARATION * (count - 1)) / (WINDOW.x * count)
	return clampf(fit, 0.5, 1.0)


func _window_size() -> Vector2:
	return (window_size * _scale).floor()


func _face_height() -> float:
	return floorf(face_height * _scale)


## The i-th reel window's centre in global coordinates — where a chip that
## reel paid out actually comes from (patch 0.22).
func reel_centre(index: int) -> Vector2:
	if index < 0 or index >= _windows.size():
		return global_position + size * 0.5
	var window: Control = _windows[index]
	return window.global_position + window.size * 0.5


func reel_count() -> int:
	return _windows.size()


func set_reel_count(count: int) -> void:
	_ensure_row()
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	_windows.clear()
	_frames.clear()
	_scale = scale_for(count) if shrink_to_fit else 1.0
	var box := _window_size()
	for i in count:
		var frame := PanelContainer.new()
		frame.custom_minimum_size = box
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_theme_stylebox_override("panel", _window_style())
		var clip := Control.new()
		clip.clip_contents = true
		clip.custom_minimum_size = box - Vector2(8, 8)
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(clip)
		_row.add_child(frame)
		_windows.append(clip)
		_frames.append(frame)
		var idle := _populate(clip, _idle_symbol(i))
		idle.strip.position.y = idle.land_y
	custom_minimum_size = Vector2(
		box.x * count + SEPARATION * maxi(0, count - 1), box.y)


func _idle_symbol(index: int) -> StringName:
	if filler_pool.is_empty():
		return &""
	return filler_pool[index % filler_pool.size()]


static func _window_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.96, 0.93, 0.85)
	style.border_color = Color(0.83, 0.69, 0.22)
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.shadow_color = Color(0, 0, 0, 0.3)
	style.shadow_size = 3
	return style


func _texture_for(symbol: StringName, override: Texture2D = null) -> Texture2D:
	if override != null:
		return override
	if not face_provider.is_valid():
		return null
	return face_provider.call(symbol)


## Fills a reel window with a fresh strip whose landing cell shows `final`.
##
## The strip scrolls DOWNWARD (patch 0.22): the landing cell sits near the TOP
## of the strip and the strip starts far above the window, so tweening
## `position:y` UPWARD in value walks the faces down past the glass, the way a
## real drum reads. The overshoot carries on downward and the spring lifts it
## back — cell 0 is there to cover the window through both.
func _populate(clip: Control, final: StringName, override: Texture2D = null) -> Dictionary:
	for child in clip.get_children():
		clip.remove_child(child)
		child.queue_free()
	var strip := VBoxContainer.new()
	strip.add_theme_constant_override("separation", 0)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(strip)
	var cell_height := _face_height()
	var icon := floorf(face_icon * _scale)
	var previous: StringName = &""
	for face_index in strip_faces:
		var cell := CenterContainer.new()
		cell.custom_minimum_size = Vector2(clip.custom_minimum_size.x, cell_height)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var symbol: StringName = final
		if face_index != LANDING_INDEX and not filler_pool.is_empty():
			symbol = filler_pool[randi() % filler_pool.size()]
			while filler_pool.size() > 1 and symbol == previous:
				symbol = filler_pool[randi() % filler_pool.size()]
		previous = symbol
		var face := TextureRect.new()
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		face.custom_minimum_size = Vector2(icon, icon)
		face.pivot_offset = Vector2(icon, icon) * 0.5
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.texture = _texture_for(symbol,
			override if face_index == LANDING_INDEX else null)
		cell.add_child(face)
		strip.add_child(cell)
	var land_y := (clip.custom_minimum_size.y - cell_height) * 0.5 - cell_height * LANDING_INDEX
	var start_y := land_y - cell_height * (strip_faces - 1 - LANDING_INDEX)
	strip.position.y = start_y
	return {"strip": strip, "land_y": land_y, "start_y": start_y,
		"landing_index": LANDING_INDEX}


## Spins every reel: a long decelerating scroll downward, overshooting the
## landing cell and springing back — staggered left to right, so the reels
## stop one at a time.
func spin_to(symbols: Array, landing_textures: Array = []) -> void:
	var spins: Array[Dictionary] = []
	for i in mini(symbols.size(), _windows.size()):
		var override: Texture2D = null
		if i < landing_textures.size() and landing_textures[i] is Texture2D:
			override = landing_textures[i]
		spins.append(_populate(_windows[i], symbols[i], override))
	var last_tween: Tween = null
	for i in spins.size():
		var strip: VBoxContainer = spins[i].strip
		var land_y: float = spins[i].land_y
		var duration: float = base_duration + i * stagger
		var tween := create_tween()
		# Decelerating scroll all the way down the strip...
		tween.tween_property(strip, "position:y", land_y + overshoot * _scale, duration) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		# ...past the mark, then the classic reel spring-back.
		tween.tween_property(strip, "position:y", land_y, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_callback(_on_reel_stopped.bind(i, strip))
		last_tween = tween
	if last_tween != null:
		await last_tween.finished
	await get_tree().create_timer(0.1).timeout


## One reel coming to rest: the landed face pops, and on the Casino machine its
## frame flashes gold — so three stops read as three events, not one blur.
func _on_reel_stopped(index: int, strip: VBoxContainer) -> void:
	if LANDING_INDEX < strip.get_child_count():
		var cell: CenterContainer = strip.get_child(LANDING_INDEX)
		if cell.get_child_count() > 0:
			var face: TextureRect = cell.get_child(0)
			face.scale = Vector2(1.35, 1.35)
			var tween := face.create_tween()
			tween.tween_property(face, "scale", Vector2.ONE, 0.28) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if stop_flash and index < _frames.size():
		_flash_frame(_frames[index])
	reel_stopped.emit(index)


func _flash_frame(frame: PanelContainer) -> void:
	var style: StyleBoxFlat = frame.get_theme_stylebox("panel").duplicate()
	frame.add_theme_stylebox_override("panel", style)
	var flash := create_tween()
	flash.tween_method(func(t: float) -> void:
		style.bg_color = Color(0.96, 0.93, 0.85).lerp(Color(1.0, 0.95, 0.6), 1.0 - t)
		style.border_color = Color(0.83, 0.69, 0.22).lerp(Color(1.0, 0.9, 0.4), 1.0 - t),
		0.0, 1.0, 0.45)
	frame.pivot_offset = frame.size * 0.5
	var kick := frame.create_tween()
	kick.tween_property(frame, "scale", Vector2(1.06, 0.96), 0.06)
	kick.tween_property(frame, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
