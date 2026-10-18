class_name CurtainTransition
extends Control
## The theatre curtain that masks a screen change (patch 0.125, third pass).
##
## Each side is ONE long curtain: the idle curtain's artwork hangs at the edge
## of the screen exactly as it always does, and the cloth carries on off-screen
## behind it. `cover()` slides the whole curtain in until the two sides meet and
## overlap in the middle; the caller swaps the screen behind them; `reveal()`
## slides them back out to where they started. Nothing is copied or stretched.
## (curtain_long.gdshader draws it: the artwork, then its own mirror to finish
## the cut tassel, then velvet in the artwork's palette.)
##
## The curtain hangs from a rail. The rail is what moves, on a smooth curve; the
## cloth below it is a damped pendulum driven by the rail's acceleration, so the
## hem lags while it is pulled, overshoots when the rail stops and keeps
## swinging, each side at its own pace, and the sway billows while it moves.
##
## While active the two curtains stand in for the screen's own idle curtains
## (group "idle_curtain"), which are hidden meanwhile and shown again at the end,
## so nothing is ever drawn twice. The overlay sits in a CanvasLayer BELOW the
## header (HP and gold stay readable, designer's call), swallows clicks while
## busy and ignores `Engine.time_scale`. Timing is in ScreenTransitionRules.

const ART := "res://assets/backgrounds/curtains_overlay.png"
const SHADER := "res://assets/shaders/curtain_long.gdshader"
const GROUP := &"idle_curtain"
## How far each curtain slides, as a fraction of the screen width: a little less
## than the half way, because the artwork's swag adds to it and the two sides
## overlap in the middle.
const REACH := 0.5
## How much cloth hangs off-screen behind the artwork, as a fraction of the
## screen width. More than REACH plus the swing, so no edge ever shows.
const EXTENSION := 0.72
## The last part of opening is spent letting the swing die out, so the hand-off
## to the idle curtains does not jump.
const SETTLE_SEC := 0.25
## The right curtain is pulled a hair after the left.
const SIDE_LAG := 0.03
const MAX_TIP_PX := 120.0
## How much of the rail's acceleration reaches the hem. 1.0 would be a rigid
## pendulum; cloth drags, so it is a fraction.
const DRIVE := 0.22
const BILLOW_SPEED := 2400.0

enum Phase { NONE, COVER, HOLD, REVEAL }


class Hanging:
	extends RefCounted
	var node: ColorRect
	var material: ShaderMaterial
	var dir := 1.0          # +1 the left curtain (slides right), -1 the right one
	var reach := 0.0        # px the rail travels when shut
	var delay := 0.0
	var rail := 0.0         # px from home
	var rail_vel := 0.0
	var accel := 0.0
	var tip := 0.0          # px the hem lags behind the rail
	var tip_vel := 0.0
	var omega := 7.0
	var zeta := 0.25
	var home_x := 0.0       # where the node sits at rest


var _sides: Array[Hanging] = []
var _base_pos := Vector2.ZERO
var _base_size := Vector2.ZERO
var _phase := Phase.NONE
var _clock := 0.0
var _last_us := 0
var _hidden_idle: Array[Node] = []
var _busy := false
var _covering := false
var _done := false


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_busy() -> bool:
	return _busy


## True from the first frame of the close until the screen has been swapped.
func is_covering() -> bool:
	return _covering


## Slides the curtains shut. Returns once the screen is fully hidden.
func cover() -> void:
	_busy = true
	_covering = true
	_show_overlay()
	_build()
	_adopt_idle()
	_begin(Phase.COVER)
	await _wait_done()
	_phase = Phase.HOLD   # shut, and still swinging
	_covering = false


## The screen has just been swapped: hang the curtains where the NEW screen's
## idle curtains hang, and keep those hidden until the cloth has gone.
func adopt_screen() -> void:
	_adopt_idle()


## Slides them back out, to the rails they came from.
func reveal() -> void:
	_begin(Phase.REVEAL)
	await _wait_done()
	_phase = Phase.NONE
	for node in _hidden_idle:
		if is_instance_valid(node):
			node.visible = true
	_hidden_idle.clear()
	_clear()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false


## Review hook: hold the curtains at `progress` (0 open, 1 shut) so a still can
## be taken of any moment of the act.
func debug_pose(progress: float) -> void:
	_show_overlay()
	_build()
	_adopt_idle()
	for side in _sides:
		side.rail = side.dir * side.reach * progress
		_place(side)


func _show_overlay() -> void:
	var view := get_viewport_rect().size
	position = Vector2.ZERO
	size = view
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func _begin(phase: Phase) -> void:
	_phase = phase
	_clock = 0.0
	_done = false
	_last_us = Time.get_ticks_usec()


func _wait_done() -> void:
	while not _done:
		await get_tree().process_frame


func _clear() -> void:
	for side in _sides:
		side.node.queue_free()
	_sides.clear()


func _build() -> void:
	_clear()
	var view := get_viewport_rect().size
	var art: Texture2D = load(ART) if ResourceLoader.exists(ART) else null
	var shader: Shader = load(SHADER) if ResourceLoader.exists(SHADER) else null
	var rng := RandomNumberGenerator.new()
	rng.seed = 125
	for dir in [1.0, -1.0]:
		var side := Hanging.new()
		side.dir = dir
		side.reach = view.x * REACH
		side.delay = 0.0 if dir > 0.0 else SIDE_LAG
		side.omega = rng.randf_range(6.6, 8.2)
		side.zeta = rng.randf_range(0.17, 0.27)
		var node := ColorRect.new()
		node.color = Color.WHITE
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if shader != null:
			var material := ShaderMaterial.new()
			material.shader = shader
			material.set_shader_parameter("art", art)
			material.set_shader_parameter("dir", dir)
			node.material = material
			side.material = material
		side.node = node
		add_child(node)
		_sides.append(side)


## Hang the curtains where the screen's idle curtains hang (the combat screen's
## are a little larger than the frame and lean with the mouse), and hide those
## so these are the only curtains drawn.
func _adopt_idle() -> void:
	var view := get_viewport_rect().size
	_base_pos = Vector2.ZERO
	_base_size = view
	var found := false
	for node in get_tree().get_nodes_in_group(GROUP):
		if is_instance_valid(node) and node is Control:
			if not found:
				_base_pos = (node as Control).global_position
				_base_size = (node as Control).size
				found = true
			if not _hidden_idle.has(node):
				_hidden_idle.append(node)
			(node as Control).visible = false
	# The picture as the idle node draws it: covered into its rect.
	var art_size := Vector2(1536.0, 1024.0)
	var fit := maxf(_base_size.x / art_size.x, _base_size.y / art_size.y)
	var drawn := art_size * fit
	var offset := (_base_size - drawn) * 0.5
	var extension := view.x * EXTENSION
	for side in _sides:
		var width := extension + _base_size.x * 0.5
		var origin_x := _base_pos.x - extension if side.dir > 0.0 else _base_pos.x + _base_size.x * 0.5
		side.home_x = origin_x
		side.node.size = Vector2(width, _base_size.y)
		side.node.position.y = _base_pos.y
		var art_origin_x := (_base_pos.x + offset.x) - origin_x
		side.material.set_shader_parameter("rect_px", side.node.size)
		side.material.set_shader_parameter("art_rect",
			Vector4(art_origin_x, offset.y, drawn.x, drawn.y))
		_place(side)


func _place(side: Hanging) -> void:
	side.node.position.x = side.home_x + side.rail
	if side.material != null:
		side.material.set_shader_parameter("tip_px", side.tip)
		side.material.set_shader_parameter("billow",
			clampf(absf(side.rail_vel) / BILLOW_SPEED, 0.0, 1.0))


func _process(_delta: float) -> void:
	if _phase == Phase.NONE or _sides.is_empty():
		return
	# Wall clock, like the rest of the act: a hit-stop or the 2x speed must not
	# change how long it takes, and a hitch must not make the cloth teleport.
	var now := Time.get_ticks_usec()
	var dt := clampf((now - _last_us) / 1_000_000.0, 0.0, 1.0 / 20.0)
	_last_us = now
	_clock += dt
	if dt <= 0.0:
		return
	for side in _sides:
		_step(side, dt)
	match _phase:
		Phase.COVER:
			if _clock >= ScreenTransitionRules.COVER_SEC:
				_done = true
		Phase.REVEAL:
			if _clock >= ScreenTransitionRules.REVEAL_SEC:
				_done = true


func _step(side: Hanging, dt: float) -> void:
	var u := 1.0
	match _phase:
		Phase.COVER:
			var travel := ScreenTransitionRules.COVER_SEC - SIDE_LAG
			u = _ease(clampf((_clock - side.delay) / travel, 0.0, 1.0))
		Phase.REVEAL:
			var travel := ScreenTransitionRules.REVEAL_SEC - SETTLE_SEC - SIDE_LAG
			u = 1.0 - _ease(clampf((_clock - side.delay) / travel, 0.0, 1.0))
		Phase.HOLD:
			u = 1.0
	var target := side.dir * side.reach * u
	var vel := (target - side.rail) / dt
	# Smoothed: a numerical second difference is jittery.
	side.accel = lerpf(side.accel, (vel - side.rail_vel) / dt, 0.35)
	side.rail_vel = vel
	side.rail = target
	# The hem hangs from the rail: a damped pendulum pushed by the rail's
	# acceleration. Critically damped over the last stretch of opening.
	var zeta := side.zeta
	var drive := DRIVE
	if _phase == Phase.REVEAL and _clock > ScreenTransitionRules.REVEAL_SEC - SETTLE_SEC:
		zeta = 1.0
		drive = 0.0
	var steps := 3
	var h := dt / steps
	for i in steps:
		var acc := -side.omega * side.omega * side.tip \
			- 2.0 * zeta * side.omega * side.tip_vel - side.accel * drive
		side.tip_vel += acc * h
		side.tip = clampf(side.tip + side.tip_vel * h, -MAX_TIP_PX, MAX_TIP_PX)
	_place(side)


func _ease(u: float) -> float:
	return 0.5 - 0.5 * cos(PI * u)
