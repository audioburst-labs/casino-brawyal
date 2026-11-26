class_name NeonHeart
extends Control
## A fine neon line heart with a heartbeat through it (build 1.30, the rest screen's
## icon): drawn, not a picture, so it is crisp at any size and glows like the UI's
## tube edges.

const COLOUR := Color(1.0, 0.44, 0.58)
## The outline as cubic segments (p0, c1, c2, p1) on a 100 x 100 canvas.
const SEGMENTS: Array = [
	[Vector2(50, 87), Vector2(22, 64), Vector2(11, 47), Vector2(11, 32)],
	[Vector2(11, 32), Vector2(11, 19), Vector2(20, 12), Vector2(31, 12)],
	[Vector2(31, 12), Vector2(40, 12), Vector2(46.5, 17), Vector2(50, 24)],
	[Vector2(50, 24), Vector2(53.5, 17), Vector2(60, 12), Vector2(69, 12)],
	[Vector2(69, 12), Vector2(80, 12), Vector2(89, 19), Vector2(89, 32)],
	[Vector2(89, 32), Vector2(89, 47), Vector2(78, 64), Vector2(50, 87)],
]
const PULSE: Array[Vector2] = [Vector2(17, 50), Vector2(34, 50), Vector2(41, 36),
	Vector2(52, 64), Vector2(59, 50), Vector2(83, 50)]


## The outline sampled into points (pure, so it can be tested).
static func outline(steps: int = 14) -> PackedVector2Array:
	var points := PackedVector2Array()
	for segment: Array in SEGMENTS:
		for i in steps:
			var t := float(i) / steps
			var u := 1.0 - t
			points.append(u * u * u * segment[0] + 3 * u * u * t * segment[1]
				+ 3 * u * t * t * segment[2] + t * t * t * segment[3])
	points.append(SEGMENTS[0][0])
	return points


func _draw() -> void:
	var side := minf(size.x, size.y)
	var k := side / 100.0
	var origin := (size - Vector2(side, side)) * 0.5
	var shape := outline()
	var mapped := PackedVector2Array()
	for p in shape:
		mapped.append(origin + p * k)
	draw_colored_polygon(mapped, Color(COLOUR, 0.13))
	for glow: Array in [[16.0, 0.08], [9.0, 0.16], [5.0, 0.32]]:
		draw_polyline(mapped, Color(COLOUR, glow[1]), glow[0] * k * 0.5, true)
	draw_polyline(mapped, COLOUR.lightened(0.15), 3.0 * k, true)
	var pulse := PackedVector2Array()
	for p in PULSE:
		pulse.append(origin + p * k)
	for glow: Array in [[9.0, 0.14], [5.0, 0.3]]:
		draw_polyline(pulse, Color(COLOUR, glow[1]), glow[0] * k * 0.5, true)
	draw_polyline(pulse, COLOUR.lightened(0.2), 2.6 * k, true)
