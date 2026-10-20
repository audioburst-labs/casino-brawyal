class_name TitleBeams
extends Control
## The searchlights and the lightning over the Dreams Casino (patch 0.125),
## drawn additively in the painting's 1536x1024 coordinates.
##
## Each beam hangs from a point behind the roofline and sways 45 degrees to
## either side of straight up: 7.15 s each way, a full cycle of about 14 s (the
## designer asked for 10 s and then 30% slower), on its own phase so they never
## move in step. A beam is a few stacked tapered polygons, widest and faintest
## outermost, which is how it gets a soft edge without a blur.

const SIZE := Vector2(1536, 1024)
const BEAM_LENGTH := 1800.0
const HALF_CYCLE := 7.15
const MAX_ANGLE := 45.0
## [origin x, origin y, phase offset in seconds]
const BEAMS := [[880.0, 330.0, 0.0], [1040.0, 330.0, 4.7], [1290.0, 420.0, 2.3], [1440.0, 390.0, 6.3]]
const LAYERS := [[1.0, 0.3], [1.12, 0.22], [1.25, 0.17], [1.4, 0.13], [1.6, 0.1], [1.85, 0.08]]   # [width scale, share of the brightness]
const BEAM_BRIGHTNESS := 0.5          # 20% above the first mock

var _t := 0.0
var _bolt := 0.0
var _next_bolt := 7.0 + randf() * 6.0
var _bolt_age := -1.0
var _glow: GradientTexture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = SIZE
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = add
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	g.offsets = PackedFloat32Array([0.0, 1.0])
	_glow = GradientTexture2D.new()
	_glow.gradient = g
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1.0, 0.5)
	_glow.width = 128
	_glow.height = 128


## One flash: it hits hard, drops, flares again and fades over under a second.
const BOLT_SECONDS := 0.9
static func bolt_value(age: float) -> float:
	return TitleLights._track([[0.0, 0.0], [0.04, 0.95], [0.09, 0.15], [0.14, 0.8], [0.3, 0.35], [1.0, 0.0]], clampf(age / BOLT_SECONDS, 0.0, 1.0))


## The angle of a beam `t` seconds in: a smooth sweep one way, then back.
static func angle_at(t: float, phase: float) -> float:
	var p := fposmod(t + phase, 2.0 * HALF_CYCLE) / HALF_CYCLE
	if p > 1.0:
		p = 2.0 - p
	return lerpf(-MAX_ANGLE, MAX_ANGLE, smoothstep(0.0, 1.0, p))


func _process(delta: float) -> void:
	_t += delta
	_next_bolt -= delta
	if _next_bolt <= 0.0:
		_bolt_age = 0.0
		_next_bolt = 9.0 + randf() * 9.0
	if _bolt_age >= 0.0:
		_bolt_age += delta
		_bolt = bolt_value(_bolt_age)
		if _bolt_age > BOLT_SECONDS:
			_bolt_age = -1.0
			_bolt = 0.0
	queue_redraw()


func _draw() -> void:
	for b in BEAMS:
		var origin := Vector2(b[0], b[1])
		var rot := deg_to_rad(angle_at(_t, float(b[2])))
		draw_set_transform(origin, rot, Vector2.ONE)
		for layer in LAYERS:
			_beam(float(layer[0]), BEAM_BRIGHTNESS * float(layer[1]))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _bolt > 0.001:
		draw_rect(Rect2(Vector2.ZERO, SIZE), Color(0.74, 0.78, 1.0, 0.42 * _bolt))
		draw_texture_rect(_glow, Rect2(-300.0, -450.0, 1700.0, 1000.0), false, Color(0.78, 0.72, 1.0, 0.75 * _bolt))


## One tapered polygon of a beam, pointing up, base at the local origin.
func _beam(width_scale: float, alpha: float) -> void:
	var base := 9.2 * width_scale
	var top := 62.0 * width_scale
	var mid_y := -BEAM_LENGTH * 0.34
	var far_y := -BEAM_LENGTH * 0.9
	var hw_mid := base + (top - base) * 0.34
	var hw_far := base + (top - base) * 0.9
	var warm := Color(1.0, 0.925, 0.745)
	var c0 := Color(warm, alpha)
	var c1 := Color(warm, alpha * 0.432)
	var c2 := Color(warm, 0.0)
	draw_polygon(PackedVector2Array([Vector2(-base, 0), Vector2(base, 0), Vector2(hw_mid, mid_y), Vector2(-hw_mid, mid_y)]),
		PackedColorArray([c0, c0, c1, c1]))
	draw_polygon(PackedVector2Array([Vector2(-hw_mid, mid_y), Vector2(hw_mid, mid_y), Vector2(hw_far, far_y), Vector2(-hw_far, far_y)]),
		PackedColorArray([c1, c1, c2, c2]))
