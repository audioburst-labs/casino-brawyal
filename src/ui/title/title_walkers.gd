class_name TitleWalkers
extends Control
## The people walking to the casino (patch 0.125), plus the rain that falls on
## them, drawn over the painting in its own 1536x1024 coordinates.
##
## `TitleWalk` does all the thinking (where each person is, their leg phase, the
## silhouette polygons); this only draws. Each person is drawn three times: a
## faint, squashed, upside-down copy for the wet ground, a thin warm copy nudged
## right so the casino seems to light their edge, and the dark silhouette itself.
##
## Building a silhouette is the expensive part (a few dozen polygons), so each
## person's pose is built once per step of their cycle, at unit height, and kept:
## after the first walk through the cycle drawing is a transform and a triangle
## array per pass. (Built every frame this cost about 10 ms on an integrated GPU.)

const SIZE := Vector2(1536, 1024)
const DROPS := 260
const PHASE_STEPS := 96

var _t := 0.0
var _people: Array[Dictionary] = []
var _drops: Array[Dictionary] = []
var _rings: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _poses := {}      # person * 1000 + phase step -> {pts, idx}, at unit height


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = SIZE
	_people = TitleWalk.make_people()
	_rng.seed = 125
	for i in DROPS:
		_drops.append({"x": _rng.randf() * (SIZE.x + 300.0), "y": _rng.randf() * SIZE.y, "v": 900.0 + _rng.randf() * 900.0,
			"l": 12.0 + _rng.randf() * 22.0, "a": 0.1 + _rng.randf() * 0.3, "z": _rng.randf()})


func _process(delta: float) -> void:
	_t += delta
	_rain(delta)
	queue_redraw()


func _rain(dt: float) -> void:
	for d in _drops:
		d.y += d.v * dt
		d.x -= d.v * dt * 0.16
		if d.y > SIZE.y + 30.0:
			if d.z > 0.55:
				_rings.append({"p": Vector2(randf() * SIZE.x, 720.0 + randf() * 290.0), "r": 1.0, "a": 0.35})
			d.y = -40.0
			d.x = randf() * (SIZE.x + 300.0)
	var keep: Array[Dictionary] = []
	for g in _rings:
		g.r += dt * 38.0
		g.a -= dt * 0.55
		if g.a > 0.0:
			keep.append(g)
	_rings = keep


func _draw() -> void:
	# the people, far to near so the near ones overlap the far ones
	var list: Array[Dictionary] = []
	for i in _people.size():
		var s := TitleWalk.state(_people[i], _t)
		s["i"] = i
		list.append(s)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.y) < float(b.y))
	var ci := get_canvas_item()
	for s in list:
		var env: float = s.env
		if env <= 0.0:
			continue
		var h: float = s.h
		var fig := _figure(int(s.i), float(s.phi))
		var at := Vector2(s.x, s.y)
		_fill(ci, fig, Transform2D(Vector2(h, 0.0), Vector2(0.0, -0.5 * h), at), Color(0.91, 0.72, 0.42, env * 0.16))
		_fill(ci, fig, Transform2D(Vector2(h, 0.0), Vector2(0.0, h), at + Vector2(maxf(1.0, h * 0.006), 0.0)), Color(1.0, 0.77, 0.43, env * 0.5))
		_fill(ci, fig, Transform2D(Vector2(h, 0.0), Vector2(0.0, h), at), Color(0.024, 0.016, 0.047, env))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# rain
	var thin := PackedVector2Array()
	var thin_c := PackedColorArray()
	var thick := PackedVector2Array()
	var thick_c := PackedColorArray()
	for d in _drops:
		var a := Vector2(d.x, d.y)
		var b := Vector2(d.x + d.l * 0.16, d.y - d.l)
		var c := Color(0.8, 0.86, 1.0, d.a)
		if d.z > 0.6:
			thick.append(a); thick.append(b); thick_c.append(c)
		else:
			thin.append(a); thin.append(b); thin_c.append(c)
	draw_multiline_colors(thin, thin_c, 1.0)
	draw_multiline_colors(thick, thick_c, 1.6)
	for g in _rings:
		draw_set_transform(g.p, 0.0, Vector2(2.2, 0.7))
		draw_arc(Vector2.ZERO, g.r, 0.0, TAU, 24, Color(0.82, 0.88, 1.0, g.a), 1.2)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A person's triangles at unit height for this step of their cycle, built the first time it is needed.
func _figure(person: int, phi: float) -> Dictionary:
	var step := int(round(phi * PHASE_STEPS)) % PHASE_STEPS
	var key := person * 1000 + step
	if not _poses.has(key):
		_poses[key] = _triangulate(TitleWalk.silhouette(_people[person], 1.0, float(step) / PHASE_STEPS))
	return _poses[key]


## Triangles for a figure's polygons: a fan for the small convex ones, the real triangulator for the body.
func _triangulate(polys: Array[PackedVector2Array]) -> Dictionary:
	var pts := PackedVector2Array()
	var idx := PackedInt32Array()
	for poly in polys:
		var base := pts.size()
		var tri := PackedInt32Array()
		if poly.size() <= 14:
			for i in range(1, poly.size() - 1):
				tri.append(0); tri.append(i); tri.append(i + 1)
		else:
			tri = Geometry2D.triangulate_polygon(poly)
		if tri.is_empty():
			continue
		pts.append_array(poly)
		for i in tri:
			idx.append(base + i)
	return {"pts": pts, "idx": idx}


func _fill(ci: RID, fig: Dictionary, xf: Transform2D, color: Color) -> void:
	var pts: PackedVector2Array = fig.pts
	if pts.is_empty():
		return
	var cols := PackedColorArray()
	cols.resize(pts.size())
	cols.fill(color)
	RenderingServer.canvas_item_add_set_transform(ci, xf)
	RenderingServer.canvas_item_add_triangle_array(ci, fig.idx, pts, cols)
