class_name TitleWalk
extends RefCounted
## The people who walk to the casino on the title screen (patch 0.125).
##
## Pure maths, like everything in src/core: positions, leg phases and the
## silhouette polygons are all computed here, and `TitleWalkers` only draws them.
## The walk is a real gait cycle (sagittal-plane gait data): `phi` runs 0..1 from
## one heel strike to the next. The hip is flexed at heel strike and extended at
## toe-off; the knee flexes a little as the weight lands, is nearly straight in
## mid-stance and folds to about 55 degrees in the swing; the foot lands heel
## first, lies flat, then the heel lifts. The other leg runs half a cycle behind.
## Angles are radians from straight down, positive = forward.
##
## The leg cycle is tied to the DISTANCE walked (divided by the figure's height
## there), not to a clock: that keeps the planted foot on the ground while the
## body moves over it, instead of skating, which is what the first version did.

const PEOPLE_COUNT := 17            # 13 in the designer's mock, plus 30%
const SPEED := 0.0135               # path fraction per second: slow, but steps still read as steps
const PATH_LENGTH := 998.0
## Five loose groups became seven when the crowd grew; [path position, how many].
const CLUSTERS := [[0.03, 3], [0.17, 2], [0.30, 3], [0.45, 2], [0.58, 3], [0.72, 2], [0.87, 2]]

## Four gaits, shared between the figures: a steady plod, a limp, a heavy trudge and a stagger.
const GAITS: Array[Dictionary] = [
	{"name": "plod", "a": 0.62, "flex": 1.0, "arm": 0.09, "lean": 0.05, "bow": 0.05, "limp": false, "roll": 0.0},
	{"name": "limp", "a": 0.58, "flex": 0.9, "arm": 0.05, "lean": 0.07, "bow": 0.07, "limp": true, "roll": 0.0},
	{"name": "trudge", "a": 0.50, "flex": 0.8, "arm": 0.07, "lean": 0.08, "bow": 0.11, "limp": false, "roll": 0.012},
	{"name": "stagger", "a": 0.60, "flex": 1.1, "arm": 0.12, "lean": 0.04, "bow": 0.06, "limp": false, "roll": 0.02},
]

const _TABLE_STEPS := 240
static var _phi_table := PackedFloat32Array()
static var _strides := {}


static func _bump(x: float, c: float, w: float) -> float:
	var d := absf(x - c)
	d = minf(d, 1.0 - d)
	return exp(-(d / w) * (d / w))


static func leg_angles(phi: float, gait: Dictionary, weak: bool) -> Dictionary:
	var a: float = float(gait.a) * (0.78 if weak else 1.0)
	var fl: float = float(gait.flex) * (0.7 if weak else 1.0)
	var foot: float
	if phi < 0.1:
		foot = 0.2 * (1.0 - phi / 0.1)
	elif phi < 0.4:
		foot = 0.0
	elif phi < 0.62:
		foot = -0.6 * ((phi - 0.4) / 0.22)
	elif phi < 0.75:
		foot = -0.6 + 0.5 * ((phi - 0.62) / 0.13)
	else:
		foot = -0.1 + 0.3 * ((phi - 0.75) / 0.25)
	return {
		"hip": a * (0.12 + 0.38 * cos(TAU * phi)),
		"knee": fl * (0.08 + 0.22 * _bump(phi, 0.12, 0.07) + 0.95 * _bump(phi, 0.72, 0.13)),
		"foot": foot,
	}


## Stride length of a gait in body heights, measured from the model itself: how
## far the planted foot travels back under the body during stance.
static func stride_units(gait: Dictionary) -> float:
	var key := str(gait.name)
	if _strides.has(key):
		return _strides[key]
	var lo := 1e9
	var hi := -1e9
	var s := 0.02
	while s <= 0.55:
		var an := leg_angles(s, gait, false)
		var x := sin(an.hip) * 0.25 + sin(float(an.hip) - float(an.knee)) * 0.25
		lo = minf(lo, x)
		hi = maxf(hi, x)
		s += 0.01
	_strides[key] = (hi - lo) / 0.53
	return _strides[key]


## The path from the lower left corner to the palace gates, in the 1536x1024
## painting's own coordinates. `h` is how tall a person is there (perspective).
static func path_point(u: float) -> Dictionary:
	return {
		"x": -90.0 + u * 960.0,
		"y": 990.0 - 292.0 * pow(u, 0.92),
		"h": 410.0 - (410.0 - 64.0) * pow(u, 0.78),
	}


static func envelope(u: float) -> float:
	return clampf(u / 0.05, 0.0, 1.0) * clampf((1.0 - u) / 0.07, 0.0, 1.0)


static func _phi_at(u: float) -> float:
	if _phi_table.is_empty():
		_phi_table.resize(_TABLE_STEPS + 1)
		_phi_table[0] = 0.0
		for i in range(1, _TABLE_STEPS + 1):
			var h: float = path_point(float(i) / _TABLE_STEPS).h
			_phi_table[i] = _phi_table[i - 1] + PATH_LENGTH / _TABLE_STEPS / h
	var f := clampf(u, 0.0, 1.0) * _TABLE_STEPS
	var i := mini(_TABLE_STEPS - 1, int(floor(f)))
	return lerpf(_phi_table[i], _phi_table[i + 1], f - i)


## Where this person is in their leg cycle at path position `u`.
static func phase(person: Dictionary, u: float) -> float:
	var gait: Dictionary = GAITS[int(person.gait)]
	return fposmod(_phi_at(u) / (stride_units(gait) * float(person.hgt)) + float(person.ph), 1.0)


static func make_people(seed_value := 125) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var people: Array[Dictionary] = []
	var qi := 0
	for cluster in CLUSTERS:
		var members: int = cluster[1]
		for m in members:
			people.append({
				"off": float(cluster[0]) + (m - (members - 1) / 2.0) * 0.045 + (rng.randf() - 0.5) * 0.02,
				# golden-ratio spread across the width of the pavement
				"lane": -0.55 + fposmod(qi * 0.618, 1.0) * 1.45 + (rng.randf() - 0.5) * 0.1,
				"hgt": 0.93 + rng.randf() * 0.14,
				"bw": 0.94 + rng.randf() * 0.14,
				"coat": rng.randf() > 0.6,
				"gait": (qi * 3) % 4,
				"ph": rng.randf(),
				"loll": rng.randf() * TAU,
			})
			qi += 1
	return people


## Where a person is at time `t` seconds: position on the painting, height, leg phase, fade.
static func state(person: Dictionary, t: float) -> Dictionary:
	var u := fposmod(t * SPEED + float(person.off), 1.0)
	var pt := path_point(u)
	var yoff: float = float(person.lane) * 120.0 * (1.0 - u * 0.85)
	return {
		"u": u,
		"x": float(pt.x) + yoff * 0.35,
		"y": float(pt.y) + yoff,
		"h": float(pt.h) * float(person.hgt) * (1.0 + yoff / 520.0),
		"phi": phase(person, u),
		"env": envelope(u),
	}


# ---- the silhouette ---------------------------------------------------------

static func _ellipse(c: Vector2, rx: float, ry: float, rot: float, n := 14) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot))
	return pts


## A limb that changes width along its length, round at both ends.
static func _limb(out: Array, a: Vector2, b: Vector2, w1: float, wm: float, w2: float) -> void:
	var d := b - a
	var length := maxf(d.length(), 0.0001)
	var n := Vector2(-d.y, d.x) / length
	var m := a + d * 0.4
	out.append(PackedVector2Array([
		a + n * w1 / 2.0, m + n * wm / 2.0, b + n * w2 / 2.0,
		b - n * w2 / 2.0, m - n * wm / 2.0, a - n * w1 / 2.0]))
	out.append(_ellipse(a, w1 / 2.0, w1 / 2.0, 0.0, 10))
	out.append(_ellipse(b, w2 / 2.0, w2 / 2.0, 0.0, 10))


static func _bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, steps := 6) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(1, steps + 1):
		var t := float(i) / steps
		pts.append(p0.bezier_interpolate(p1, p2, p3, t))
	return pts


static func _quad(p0: Vector2, c: Vector2, p1: Vector2, steps := 5) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(1, steps + 1):
		var t := float(i) / steps
		pts.append(p0.lerp(c, t).lerp(c.lerp(p1, t), t))
	return pts


## The figure as a list of simple polygons, in the figure's own coordinates:
## feet at y = 0, up is negative, walking toward +x. `H0` is the figure's height
## in pixels and `phi0` its leg phase. A real person's body rises and dips as they
## walk because the lowest foot always carries them, which is what `lift` does.
static func silhouette(person: Dictionary, H0: float, phi0: float) -> Array[PackedVector2Array]:
	var g: Dictionary = GAITS[int(person.gait)]
	var bw := float(person.bw)
	var hip_y := -H0 * 0.5
	var thigh := H0 * 0.25
	var shin := H0 * 0.25
	var B := H0 * bw

	var legs: Array[Dictionary] = []
	for k in 2:
		var an := leg_angles(fposmod(phi0 + k * 0.5, 1.0), g, bool(g.limp) and k == 1)
		var knee := Vector2(sin(an.hip) * thigh, hip_y + cos(an.hip) * thigh)
		var sh: float = float(an.hip) - float(an.knee)
		var ankle := knee + Vector2(sin(sh), cos(sh)) * shin
		var cs := cos(an.foot)
		var sn := sin(an.foot)
		var heel := ankle + Vector2(-H0 * 0.035 * cs + H0 * 0.042 * sn, H0 * 0.035 * sn + H0 * 0.042 * cs)
		var toe := ankle + Vector2(H0 * 0.1 * cs + H0 * 0.042 * sn, -H0 * 0.1 * sn + H0 * 0.042 * cs)
		var top := ankle + Vector2(H0 * 0.055 * cs - H0 * 0.004 * sn, -H0 * 0.055 * sn - H0 * 0.004 * cs)
		legs.append({"knee": knee, "ankle": ankle, "heel": heel, "toe": toe, "top": top, "low": maxf(heel.y, toe.y)})

	var polys: Array = []
	# far leg first, near leg after: the legs overlap like a real walker's
	for k in [1, 0]:
		var L: Dictionary = legs[k]
		var hip := Vector2(H0 * 0.01 if k == 1 else -H0 * 0.01, hip_y + H0 * 0.02)
		_limb(polys, hip, L.knee, H0 * 0.12 * bw, H0 * 0.105 * bw, H0 * 0.075)
		_limb(polys, L.knee, L.ankle, H0 * 0.072, H0 * 0.082, H0 * 0.044)
		polys.append(PackedVector2Array([L.ankle + Vector2(-H0 * 0.02, -H0 * 0.01), L.top, L.toe, L.heel]))

	# body, almost upright
	var lean := float(g.lean) + cos(phi0 * TAU * 2.0) * 0.008
	var at := func(p: Vector2) -> Vector2: return Vector2(0.0, hip_y) + p.rotated(lean)
	var body := PackedVector2Array()
	if bool(person.coat):
		body.append(Vector2(-B * 0.16, H0 * 0.15)); body.append(Vector2(B * 0.15, H0 * 0.15)); body.append(Vector2(B * 0.1, H0 * 0.02))
	else:
		body.append(Vector2(-B * 0.1, H0 * 0.03)); body.append(Vector2(B * 0.1, H0 * 0.03))
	var cur: Vector2 = body[body.size() - 1]
	var seg := _bezier(cur, Vector2(B * 0.09, -H0 * 0.08), Vector2(B * 0.115, -H0 * 0.16), Vector2(B * 0.12, -H0 * 0.235))
	body.append_array(seg)
	body.append_array(_quad(Vector2(B * 0.12, -H0 * 0.235), Vector2(B * 0.1, -H0 * 0.3), Vector2(B * 0.04, -H0 * 0.322)))
	body.append(Vector2(-B * 0.04, -H0 * 0.322))
	body.append_array(_quad(Vector2(-B * 0.04, -H0 * 0.322), Vector2(-B * 0.11, -H0 * 0.3), Vector2(-B * 0.125, -H0 * 0.235)))
	body.append_array(_bezier(Vector2(-B * 0.125, -H0 * 0.235), Vector2(-B * 0.12, -H0 * 0.16), Vector2(-B * 0.09, -H0 * 0.08), Vector2(-B * 0.1, H0 * 0.03)))
	if bool(person.coat):
		body.append(Vector2(-B * 0.16, H0 * 0.15))
	var world_body := PackedVector2Array()
	for p in body:
		world_body.append(at.call(p))
	polys.append(world_body)
	# neck and head, bowed a little
	var bow := float(g.bow) + sin(phi0 * TAU + float(person.loll)) * 0.012
	_limb(polys, at.call(Vector2(0.0, -H0 * 0.31)), at.call(Vector2(H0 * 0.018 + bow * H0 * 0.3, -H0 * 0.365)), H0 * 0.052, H0 * 0.046, H0 * 0.044)
	polys.append(_ellipse(at.call(Vector2(H0 * 0.02 + bow * H0 * 0.45, -H0 * 0.415)), H0 * 0.047, H0 * 0.06, lean + bow * 1.4))
	# arms hang straight down and just swing, opposite to the legs
	var sx := sin(lean) * H0 * 0.29
	var sy := hip_y - cos(lean) * H0 * 0.29
	for k in 2:
		var sw := cos(TAU * (phi0 + k * 0.5)) * float(g.arm) * (1.0 if k == 1 else -1.0)
		var t1 := 0.03 + sw
		var t2 := t1 + 0.1 + maxf(0.0, sw) * 0.5
		var o := Vector2(sx + (H0 * 0.01 if k == 1 else -H0 * 0.01), sy + H0 * 0.012)
		var e := o + Vector2(sin(t1), cos(t1)) * H0 * 0.19
		var h := e + Vector2(sin(t2), cos(t2)) * H0 * 0.17
		_limb(polys, o, e, H0 * 0.066, H0 * 0.06, H0 * 0.05)
		_limb(polys, e, h, H0 * 0.05, H0 * 0.046, H0 * 0.034)
		polys.append(_ellipse(h + Vector2(H0 * 0.003, H0 * 0.02), H0 * 0.024, H0 * 0.034, 0.1))

	var lift := -maxf(float(legs[0].low), float(legs[1].low))
	var roll := sin(phi0 * TAU) * float(g.roll) * H0
	var out: Array[PackedVector2Array] = []
	for poly: PackedVector2Array in polys:
		var moved := PackedVector2Array()
		for p in poly:
			moved.append(p + Vector2(roll, lift))
		out.append(moved)
	return out
