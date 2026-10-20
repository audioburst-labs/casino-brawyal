class_name NeonToggle
extends Control
## A small square check box in the title screen's neon style (patch 0.125, the
## designer's "Play Tutorial" toggle). Marked, it holds a gold checkmark BIGGER
## than the square, spilling out of its top right like a hand-drawn tick; unmarked
## the square is empty. Click, Space or Enter flips it.

signal toggled(on: bool)

const BOX := 29.0
const GAP := 28.0
const CYAN := Color(0.49, 0.91, 1.0)
const GOLD := Color(1.0, 0.8, 0.31)

var text := "Play Tutorial"
var font_size := 20
var font: Font
var button_pressed := false:
	set(value):
		button_pressed = value
		_pop = 0.0
		queue_redraw()

var _font: Font
var _hover := false
var _pop := 1.0    # 0..1, the tick drops in with a little overshoot


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_font = font if font != null else get_theme_default_font()
	var w := BOX + GAP + _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	custom_minimum_size = Vector2(w + 6.0, BOX + 40.0)
	mouse_entered.connect(func() -> void: _hover = true; queue_redraw())
	mouse_exited.connect(func() -> void: _hover = false; queue_redraw())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func _process(delta: float) -> void:
	if _pop < 1.0:
		_pop = minf(1.0, _pop + delta * 5.0)
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var flip := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		flip = true
	elif event.is_action_pressed(&"ui_accept"):
		flip = true
	if flip:
		button_pressed = not button_pressed
		Audio.play_sfx(&"ui_press")
		toggled.emit(button_pressed)
		accept_event()


func _draw() -> void:
	var box := Rect2(3.0, (size.y - BOX) * 0.5, BOX, BOX)
	var bright := _hover or has_focus()
	var edge := GOLD if button_pressed else (Color.WHITE if bright else CYAN)
	draw_rect(box.grow(7.0), Color(edge, 0.10 if button_pressed else 0.07))
	draw_rect(box, Color(0.035, 0.047, 0.15, 0.6))
	draw_rect(box, Color(edge, 0.85), false, 2.0)
	if button_pressed:
		# the tick: bigger than the box, from its lower left up past its top right
		var k := 52.0 / 40.0
		var o := box.position + Vector2(-3.0, -22.0)
		var pivot := o + Vector2(10.4, 41.6)
		var s := 0.3 + 0.7 * _ease_back(_pop)
		var pts := PackedVector2Array()
		for p in [Vector2(5, 22), Vector2(15, 34), Vector2(37, 4)]:
			pts.append(pivot + (o + p * k - pivot) * s)
		draw_polyline(pts, Color(GOLD, 0.22), 18.0, true)
		draw_polyline(pts, Color(GOLD, 0.5), 11.0, true)
		draw_polyline(pts, Color(1.0, 0.86, 0.45), 6.0, true)
	var colour := Color.WHITE if (button_pressed or bright) else Color(0.82, 0.8, 0.94, 0.85)
	draw_string(_font, Vector2(box.end.x + GAP, box.position.y + BOX * 0.5 + font_size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)


static func _ease_back(x: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)
