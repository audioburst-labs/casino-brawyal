class_name TutorialDirector
extends Control
## Stage management for the scripted first fight (doc "Tutorial"): the dimmed
## screen with lit windows, talking and thinking bubbles, an arrow, and the
## translucent hand that shows a chip being dragged onto a card.
##
## It draws and animates; it decides nothing. `TutorialFlow` tells it what to
## show, and the game underneath keeps running and keeps receiving the
## player's clicks: the overlay never swallows input (mouse_filter IGNORE), so
## the real drag-and-drop is what completes a step, not a stand-in.
##
## Everything is positioned from the targets' global rects every frame, never
## from anchors: a freshly created Control does not resolve anchor percentages
## against the real viewport in the frame it is born (the same rule the old
## first-fight guide and the header overlays follow).

const DIM_COLOR := Color(0.0, 0.0, 0.0, 0.58)
const WINDOW_PAD := 12.0
const RING_COLOR := Color(1.0, 0.86, 0.45, 0.95)
const PAPER := Color(0.97, 0.94, 0.86)
const INK := Color(0.16, 0.1, 0.1)
const BUBBLE_WIDTH := 330.0
const HAND_SIZE := 72.0
const CHIP_SIZE := 58.0
## Bubble fades, 30% slower than the first cut (designer, 0.122).
const FADE_IN := 0.39
const FADE_OUT := 0.325


## One bubble on stage. `thinking` bubbles are square with a trail of dots;
## talking bubbles are rounded with a tail. Both fade in and out.
class Bubble:
	extends Control

	var anchor: Callable = Callable()          # -> Control the bubble belongs to
	var side := "above"                        # which side of the anchor it sits
	var distance := 34.0                           # distance from the anchor
	var thinking := false
	var label: Label
	var panel: PanelContainer
	var _tail_to := Vector2.ZERO               # local point the tail aims at

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel = PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = PAPER
		style.border_color = INK
		style.set_border_width_all(3)
		style.set_corner_radius_all(6 if thinking else 20)
		style.content_margin_left = 16
		style.content_margin_right = 16
		style.content_margin_top = 12
		style.content_margin_bottom = 12
		style.shadow_color = Color(0, 0, 0, 0.35)
		style.shadow_size = 6
		panel.add_theme_stylebox_override("panel", style)
		add_child(panel)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(BUBBLE_WIDTH - 32.0, 0)
		label.add_theme_font_size_override("font_size", 19)
		label.add_theme_color_override("font_color", INK)
		panel.add_child(label)

	## The bubble's box is the panel; the tail or dots are drawn outside it.
	func box_size() -> Vector2:
		return panel.get_combined_minimum_size() if panel != null else Vector2(BUBBLE_WIDTH, 80)

	func aim_at(point_local: Vector2) -> void:
		_tail_to = point_local
		queue_redraw()

	func _draw() -> void:
		if panel == null:
			return
		var rect := Rect2(Vector2.ZERO, box_size())
		var from := rect.get_center()
		var toward := (_tail_to - from)
		if toward.length() < 4.0:
			return
		var dir := toward.normalized()
		# Where the line from the centre to the target leaves the box.
		var edge := from
		var scale_x := INF if absf(dir.x) < 0.001 else (rect.size.x * 0.5) / absf(dir.x)
		var scale_y := INF if absf(dir.y) < 0.001 else (rect.size.y * 0.5) / absf(dir.y)
		edge = from + dir * minf(scale_x, scale_y)
		var gap := minf(toward.length() - (edge - from).length() - 6.0, 46.0)
		if gap < 6.0:
			return
		if thinking:
			# Three dots of falling size trailing toward the thinker.
			for i in 3:
				var t := (float(i) + 0.6) / 3.2
				var radius := lerpf(8.0, 3.5, float(i) / 2.0)
				var at := edge + dir * gap * t
				draw_circle(at, radius + 2.0, INK)
				draw_circle(at, radius, PAPER)
		else:
			var normal := Vector2(-dir.y, dir.x)
			var base := edge - dir * 2.0
			var tip := edge + dir * gap
			var tail := PackedVector2Array([base + normal * 13.0, tip, base - normal * 13.0])
			draw_colored_polygon(tail, PAPER)
			draw_polyline(PackedVector2Array([base + normal * 13.0, tip, base - normal * 13.0]),
				INK, 3.0, true)
			# Cover the seam where the tail meets the box outline.
			draw_line(base + normal * 11.0, base - normal * 11.0, PAPER, 5.0)


var _bubbles: Dictionary = {}                  # key -> Bubble
var _holes: Array = []                         # Callables returning Control
var _dim := 0.0                                # 0..1, tweened
var _dim_tween: Tween = null
var _arrow: Callable = Callable()              # -> Control the arrow points at
var _arrow_from_key := ""                      # bubble the arrow leaves from
var _pulse := 0.0
var _demo_token := 0
var _hand: TextureRect = null
var _ghost_chip: TextureRect = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 190
	_hand = TextureRect.new()
	_hand.texture = load("res://assets/icons/cursor_ace_hand.png")
	_hand.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hand.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hand.custom_minimum_size = Vector2(HAND_SIZE, HAND_SIZE)
	_hand.size = Vector2(HAND_SIZE, HAND_SIZE)
	_hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hand.modulate = Color(1, 1, 1, 0.0)
	_hand.z_index = 2
	add_child(_hand)
	_ghost_chip = TextureRect.new()
	_ghost_chip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ghost_chip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ghost_chip.size = Vector2(CHIP_SIZE, CHIP_SIZE)
	_ghost_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost_chip.modulate = Color(1, 1, 1, 0.0)
	_ghost_chip.z_index = 1
	add_child(_ghost_chip)


# ---------------------------------------------------------------- bubbles

## A bubble keyed by `key` (saying it again replaces the text). `anchor` is a
## Callable returning the Control it belongs to; `side` is where it sits.
func say(key: String, text: String, thinking: bool, anchor: Callable,
		side := "above", gap := 34.0) -> void:
	hush(key, true)
	var bubble := Bubble.new()
	bubble.thinking = thinking
	bubble.anchor = anchor
	bubble.side = side
	bubble.distance = gap
	bubble.label = Label.new()
	bubble.label.text = text
	bubble.modulate.a = 0.0
	add_child(bubble)
	_bubbles[key] = bubble
	create_tween().tween_property(bubble, "modulate:a", 1.0, FADE_IN)


func hush(key: String, instantly := false) -> void:
	if not _bubbles.has(key):
		return
	var bubble: Bubble = _bubbles[key]
	_bubbles.erase(key)
	if instantly:
		bubble.queue_free()
		return
	var tween := create_tween()
	tween.tween_property(bubble, "modulate:a", 0.0, FADE_OUT)
	tween.tween_callback(bubble.queue_free)


func hush_all() -> void:
	for key: String in _bubbles.keys():
		hush(key)


func has_bubble(key: String) -> bool:
	return _bubbles.has(key)


# --------------------------------------------------------------- spotlight

## Darkens everything except these windows. Each entry is a Callable returning
## the Control to leave lit, or a global Rect2 for a part of one (the Bouncer's
## head and shoulders) (resolved every frame, so it follows layout).
func spotlight(holes: Array) -> void:
	_holes = holes
	_tween_dim(1.0)


func lights_up() -> void:
	_tween_dim(0.0)


func is_dim() -> bool:
	return _dim > 0.01


func _tween_dim(target: float) -> void:
	if _dim_tween != null:
		_dim_tween.kill()
	_dim_tween = create_tween()
	_dim_tween.tween_property(self, "_dim", target, 0.35)
	if target <= 0.0:
		_dim_tween.tween_callback(func() -> void: _holes = [])


## An arrow from the bubble `from_key` to `target`.
func arrow(from_key: String, target: Callable) -> void:
	_arrow_from_key = from_key
	_arrow = target


func clear_arrow() -> void:
	_arrow = Callable()
	_arrow_from_key = ""


# ------------------------------------------------------------ ghost drag

## The translucent hand picks a chip up at `from` and drops it at `to`, and
## starts again half a second after the drop, until `stop_demo()`.
func demo_drag(from: Callable, to: Callable, suit: StringName) -> void:
	stop_demo()
	_demo_token += 1
	_run_demo(_demo_token, from, to, suit)


func stop_demo() -> void:
	_demo_token += 1
	if _hand != null:
		_hand.modulate.a = 0.0
	if _ghost_chip != null:
		_ghost_chip.modulate.a = 0.0


func _centre(source: Callable) -> Variant:
	var control: Variant = source.call() if source.is_valid() else null
	if control is Control and is_instance_valid(control) and (control as Control).is_inside_tree():
		return (control as Control).get_global_rect().get_center() - global_position
	return null


func _run_demo(token: int, from: Callable, to: Callable, suit: StringName) -> void:
	_ghost_chip.texture = SuitAssets.chip_texture(suit)
	var open_hand: Texture2D = load("res://assets/icons/cursor_ace_hand.png")
	var grab_hand: Texture2D = load("res://assets/icons/cursor_ace_hand_grab.png")
	while token == _demo_token and is_inside_tree():
		var a: Variant = _centre(from)
		var b: Variant = _centre(to)
		if a == null or b == null:
			await get_tree().create_timer(0.3).timeout
			continue
		var start: Vector2 = a + Vector2(70, 50)
		_hand.texture = open_hand
		_hand.position = start - _hand.size * 0.15
		_hand.modulate.a = 0.0
		_ghost_chip.modulate.a = 0.0
		var fade := create_tween()
		fade.tween_property(_hand, "modulate:a", 0.6, 0.25)
		await fade.finished
		if token != _demo_token:
			return
		# Reach for the chip.
		var reach := create_tween()
		reach.tween_property(_hand, "position", a - _hand.size * 0.15, 0.45) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await reach.finished
		if token != _demo_token:
			return
		# Pick it up: the chip is translucent too.
		_hand.texture = grab_hand
		_ghost_chip.position = a - _ghost_chip.size * 0.5
		_ghost_chip.modulate.a = 0.6
		await get_tree().create_timer(0.15).timeout
		# Carry it over, hand and chip together.
		var carry := create_tween()
		carry.set_parallel(true)
		carry.tween_property(_hand, "position", b - _hand.size * 0.15, 0.8) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		carry.tween_property(_ghost_chip, "position", b - _ghost_chip.size * 0.5, 0.8) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await carry.finished
		if token != _demo_token:
			return
		# Let go, and the whole thing starts again half a second later.
		_hand.texture = open_hand
		var drop := create_tween()
		drop.set_parallel(true)
		drop.tween_property(_ghost_chip, "modulate:a", 0.0, 0.25)
		drop.tween_property(_hand, "modulate:a", 0.0, 0.3)
		await drop.finished
		await get_tree().create_timer(0.5).timeout


# ------------------------------------------------------------------ frame

func _process(delta: float) -> void:
	_pulse += delta
	var viewport := get_viewport_rect().size
	for key: String in _bubbles:
		var bubble: Bubble = _bubbles[key]
		var control: Variant = bubble.anchor.call() if bubble.anchor.is_valid() else null
		var size := bubble.box_size()
		bubble.size = size
		if control is Control and is_instance_valid(control):
			var rect := (control as Control).get_global_rect()
			rect.position -= global_position
			var gap := bubble.distance
			var at := Vector2.ZERO
			match bubble.side:
				"below":
					at = Vector2(rect.get_center().x - size.x * 0.5, rect.end.y + gap)
				"right":
					at = Vector2(rect.end.x + gap, rect.get_center().y - size.y * 0.5)
				"left":
					at = Vector2(rect.position.x - gap - size.x, rect.get_center().y - size.y * 0.5)
				_:
					at = Vector2(rect.get_center().x - size.x * 0.5, rect.position.y - gap - size.y)
			at.x = clampf(at.x, 8.0, viewport.x - size.x - 8.0)
			# Under the header bar, which is drawn on a layer above the screen.
			at.y = clampf(at.y, 76.0, viewport.y - size.y - 8.0)
			bubble.position = at
			bubble.aim_at(rect.get_center() - at)
	queue_redraw()


func _draw() -> void:
	var viewport := get_viewport_rect().size
	if _dim > 0.01:
		var windows: Array[Rect2] = []
		for source: Callable in _holes:
			var item: Variant = source.call() if source.is_valid() else null
			var rect := Rect2()
			if item is Control and is_instance_valid(item):
				rect = (item as Control).get_global_rect()
			elif item is Rect2:
				rect = item
			else:
				continue
			rect.position -= global_position
			windows.append(rect.grow(WINDOW_PAD))
		_draw_dim(viewport, windows)
		for rect in windows:
			var ring := StyleBoxFlat.new()
			ring.draw_center = false
			ring.border_color = Color(RING_COLOR, RING_COLOR.a * _dim)
			ring.set_border_width_all(3)
			ring.set_corner_radius_all(14)
			draw_style_box(ring, rect.grow(2.0 * sin(_pulse * 4.0)))
	_draw_arrow()


## The screen minus its windows, as horizontal bands: for each band between two
## consecutive window edges, dim the gaps between the windows that cover it.
func _draw_dim(viewport: Vector2, windows: Array[Rect2]) -> void:
	var color := Color(DIM_COLOR, DIM_COLOR.a * _dim)
	var ys: Array[float] = [0.0, viewport.y]
	for rect in windows:
		ys.append(clampf(rect.position.y, 0.0, viewport.y))
		ys.append(clampf(rect.end.y, 0.0, viewport.y))
	ys.sort()
	for i in ys.size() - 1:
		var top := ys[i]
		var bottom := ys[i + 1]
		if bottom - top < 0.5:
			continue
		var spans: Array[Vector2] = []
		for rect in windows:
			if rect.position.y <= top + 0.1 and rect.end.y >= bottom - 0.1:
				spans.append(Vector2(rect.position.x, rect.end.x))
		spans.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x < q.x)
		var cursor := 0.0
		for span in spans:
			if span.x > cursor:
				draw_rect(Rect2(cursor, top, span.x - cursor, bottom - top), color)
			cursor = maxf(cursor, span.y)
		if cursor < viewport.x:
			draw_rect(Rect2(cursor, top, viewport.x - cursor, bottom - top), color)


func _draw_arrow() -> void:
	if not _arrow.is_valid() or not _bubbles.has(_arrow_from_key):
		return
	var control: Variant = _arrow.call()
	if not (control is Control and is_instance_valid(control)):
		return
	var bubble: Bubble = _bubbles[_arrow_from_key]
	var target := (control as Control).get_global_rect()
	target.position -= global_position
	var bubble_rect := Rect2(bubble.position, bubble.size)
	var from := bubble_rect.get_center()
	var to := target.get_center()
	var dir := (to - from).normalized()
	# From the bubble's edge to the target's edge, with a little bob.
	var start := from + dir * (minf(bubble_rect.size.x, bubble_rect.size.y) * 0.5 + 44.0)
	var stop := to - dir * (minf(target.size.x, target.size.y) * 0.5 + 18.0 + 5.0 * sin(_pulse * 5.0))
	if (stop - start).dot(dir) < 8.0:
		return
	var alpha := bubble.modulate.a
	var color := Color(RING_COLOR, 0.95 * alpha)
	draw_line(start, stop, color, 6.0, true)
	var normal := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([
		stop + dir * 4.0, stop - dir * 26.0 + normal * 16.0, stop - dir * 26.0 - normal * 16.0]),
		color)
