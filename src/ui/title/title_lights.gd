class_name TitleLights
extends Control
## The lights of the Dreams Casino (patch 0.125), drawn additively over the
## painting in its own 1536x1024 coordinates: the windows twinkle, the roof neon
## pulses, the bulbs chase round the marquee and the portico, the street lamp
## flickers, and the distant city blinks. Everything is a glow sprite or a line;
## no per-frame allocation beyond what `_draw` needs.

const SIZE := Vector2(1536, 1024)
const SIGN := Vector2(962, 346)
const LAMP := Vector2(255, 548)
## [x, y, width, height, violet] for each lit window of the facade.
const WINDOWS := [
	[757, 532, 76, 108, 0], [808, 528, 66, 98, 0], [962, 468, 130, 180, 0], [843, 470, 84, 124, 1],
	[1082, 470, 84, 124, 1], [1181, 510, 84, 108, 0], [1262, 507, 84, 108, 0], [1396, 497, 96, 108, 0],
	[1190, 606, 96, 118, 0], [1278, 606, 96, 118, 0], [1418, 612, 96, 118, 0], [660, 612, 76, 98, 0],
	[1089, 598, 76, 98, 0], [692, 532, 60, 80, 0],
]
## [x, y, length, angle in degrees] for the neon strips along the roofs.
const STRIPS := [[606, 562, 126, -5], [640, 497, 92, -4], [1306, 543, 230, 2], [1312, 448, 176, -6], [1334, 442, 150, -4]]

var _t := 0.0
var _glow: GradientTexture2D
var _wins: Array[Vector2] = []     # per window: [duration, delay]
var _city: Array[Dictionary] = []
var _bulbs: Array[Vector3] = []    # x, y, phase


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = SIZE
	size = SIZE
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = add
	_glow = _radial()
	var rng := RandomNumberGenerator.new()
	rng.seed = 125
	for w in WINDOWS:
		_wins.append(Vector2(3.2 + rng.randf() * 4.5, -rng.randf() * 6.0))
	for i in 70:
		_city.append({"p": Vector2(rng.randf() * 610.0, 395.0 + rng.randf() * 250.0), "s": 2.0 + rng.randf() * 2.2,
			"d": 2.0 + rng.randf() * 6.0, "dl": -rng.randf() * 8.0})
	for i in 40:
		var a := TAU * i / 40.0
		_bulbs.append(Vector3(SIGN.x + cos(a) * 97.0, SIGN.y + 1.0 + sin(a) * 41.0, -float(i) / 40.0 * 1.8))
	for k in 18:
		_bulbs.append(Vector3(838.0 + k * 12.4, 560.0 - sin(float(k) / 17.0 * PI) * 3.0, -float(k) / 18.0 * 1.8))


func _radial() -> GradientTexture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	g.offsets = PackedFloat32Array([0.0, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	return tex


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


## The CSS-style keyframe track the mock used: linear between (time, value) stops over one cycle.
static func _track(stops: Array, phase: float) -> float:
	for i in range(stops.size() - 1):
		var a: Array = stops[i]
		var b: Array = stops[i + 1]
		if phase <= float(b[0]):
			return lerpf(float(a[1]), float(b[1]), inverse_lerp(float(a[0]), float(b[0]), phase))
	return float(stops[stops.size() - 1][1])


static func _twinkle(t: float, duration: float, delay: float) -> float:
	return _track([[0.0, 0.15], [0.3, 0.75], [0.55, 0.35], [0.8, 0.9], [1.0, 0.15]], fposmod((t - delay) / duration, 1.0))


func _draw() -> void:
	# windows
	for i in WINDOWS.size():
		var w: Array = WINDOWS[i]
		var a := _twinkle(_t, _wins[i].x, _wins[i].y)
		var c := Color(0.745, 0.43, 1.0, 0.65 * a) if int(w[4]) == 1 else Color(1.0, 0.745, 0.33, 0.6 * a)
		draw_texture_rect(_glow, Rect2(w[0] - w[2] / 2.0, w[1] - w[3] / 2.0, w[2], w[3]), false, c)
	# the marquee sign breathes
	var e := 0.5 - 0.5 * cos(TAU * _t / 4.2)
	var s := 0.96 + 0.09 * e
	var sw := 330.0 * s
	var sh := 150.0 * s
	draw_texture_rect(_glow, Rect2(SIGN.x - sw / 2.0, SIGN.y - sh / 2.0, sw, sh), false, Color(1.0, 0.8, 0.43, 0.55 * (0.55 + 0.45 * e)))
	# the street lamp flickers: steps, not fades
	var lp := fposmod(_t / 5.0, 1.0)
	var lamp := 0.95
	if lp >= 0.18 and lp < 0.2: lamp = 0.8
	elif lp >= 0.2 and lp < 0.47: lamp = 0.98
	elif lp >= 0.47 and lp < 0.49: lamp = 0.9
	elif lp >= 0.49 and lp < 0.51: lamp = 0.7
	elif lp >= 0.51: lamp = 0.96
	draw_texture_rect(_glow, Rect2(LAMP.x - 170.0, LAMP.y - 170.0, 340.0, 340.0), false, Color(1.0, 0.78, 0.43, 0.7 * lamp))
	# roof neon
	for i in STRIPS.size():
		var st: Array = STRIPS[i]
		var a := _track([[0.0, 0.3], [0.45, 0.95], [0.52, 0.55], [0.6, 1.0], [1.0, 0.3]], fposmod((_t + i * 0.7) / 3.4, 1.0))
		var dir := Vector2.RIGHT.rotated(deg_to_rad(float(st[3])))
		var p0 := Vector2(st[0], st[1])
		var p1 := p0 + dir * float(st[2])
		draw_line(p0, p1, Color(1.0, 0.35, 0.88, 0.12 * a), 18.0)
		draw_line(p0, p1, Color(1.0, 0.4, 0.9, 0.3 * a), 8.0)
		draw_line(p0, p1, Color(1.0, 0.82, 1.0, 0.9 * a), 3.0)
	# marquee and portico bulbs chase
	for b in _bulbs:
		var ph := fposmod((_t - b.z) / 1.8, 1.0)
		var a := _track([[0.0, 0.15], [0.12, 1.0], [0.3, 0.5], [1.0, 0.15]], ph)
		var sc := _track([[0.0, 0.7], [0.12, 1.15], [0.3, 0.9], [1.0, 0.7]], ph)
		draw_texture_rect(_glow, Rect2(b.x - 11.0 * sc, b.y - 11.0 * sc, 22.0 * sc, 22.0 * sc), false, Color(1.0, 0.8, 0.4, 0.8 * a))
		draw_circle(Vector2(b.x, b.y), 2.6 * sc, Color(1.0, 0.97, 0.82, a))
	# the distant city blinks
	for c in _city:
		var a := _twinkle(_t, float(c.d), float(c.dl))
		var sz: float = c.s
		draw_texture_rect(_glow, Rect2(c.p.x - sz * 2.0, c.p.y - sz * 2.0, sz * 4.0, sz * 4.0), false, Color(1.0, 0.85, 0.55, 0.7 * a))
