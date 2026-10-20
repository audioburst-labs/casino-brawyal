class_name NeonChevron
extends Control
## The gold double chevron that points at the selected menu button (patch 0.125):
## drawn as two strokes with a soft glow, mirrored for the right-hand side, and
## nudged outward and back so it always looks about to move.

const SIZE := 50.0
const GOLD := Color(1.0, 0.8, 0.31)

var mirrored := false
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var k := SIZE / 28.0
	var nudge := (0.5 - 0.5 * cos(TAU * _t / 1.1)) * 12.0
	draw_set_transform(Vector2((SIZE - nudge) if mirrored else nudge, 0.0), 0.0, Vector2(-1.0 if mirrored else 1.0, 1.0))
	for stroke in [[PackedVector2Array([Vector2(13, 5), Vector2(4, 14), Vector2(13, 23)])], [PackedVector2Array([Vector2(23, 5), Vector2(14, 14), Vector2(23, 23)])]]:
		var line: PackedVector2Array = stroke[0]
		var pts := PackedVector2Array()
		for p in line:
			pts.append(p * k)
		draw_polyline(pts, Color(GOLD, 0.2), 14.0 * k / 3.4, true)
		draw_polyline(pts, Color(GOLD, 0.45), 8.0 * k / 3.4, true)
		draw_polyline(pts, GOLD, 3.4 * k, true)
