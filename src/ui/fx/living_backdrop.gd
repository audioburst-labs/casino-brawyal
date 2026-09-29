class_name LivingBackdrop
extends Control
## A background that behaves like a place (patch 0.119, the designer's "make it
## more alive"). Three layers over one still painting:
##   1. the painting itself, through `living_backdrop.gdshader` (drift, curtain
##      sway, pulsing lights, scrolling reel windows, haze; rain, wet ground,
##      searchlights and lightning for the night exterior);
##   2. drifting dust motes in the light (CPUParticles2D, so it also runs on a
##      machine with no GPU particles and under the headless smoke boot);
##   3. an optional foreground curtain cutout through `curtain_cloth.gdshader`,
##      which moves with more parallax than the painting behind it.
## A few pixels of mouse parallax tie the layers together, and `react()` lets a
## heavy hit kick the fabric. Everything is presentation: no rule lives here.
##
## Regions are ellipses/rects in the painting's own UV space (the TextureRect
## covers, so UV is the painting), measured off the 1536x1024 art by eye.
## The overlay is drawn ABOVE the painting and BELOW the fighters and the UI:
## the Flush card already overlaps the painted right curtain, so a curtain in
## front of the cards would cover it.

const SHADER := "res://assets/shaders/living_backdrop.gdshader"
const CLOTH_SHADER := "res://assets/shaders/curtain_cloth.gdshader"
const CURTAINS := "res://assets/backgrounds/curtains_overlay.png"

## Mouse parallax, in UV for the painting and in pixels for the overlay. Small
## on purpose: dragging a chip across the screen must never lurch the room.
const PARALLAX_UV := 0.004
const PARALLAX_PX := 9.0
const PARALLAX_EASE := 3.0

var painting: TextureRect
var curtains: TextureRect = null
var _motes: CPUParticles2D = null
var _material: ShaderMaterial = null
var _cloth: ShaderMaterial = null
var _parallax := Vector2.ZERO
var _impulse := 0.0
var _lightning := 0.0
var _next_lightning := 0.0
var _storm := false


## The combat floor: swaying curtains, the chandelier and machine lights,
## eight little reel windows rolling, warm haze, gold dust.
static func casino_floor(texture_path := "res://assets/backgrounds/bg_casino_floor.png") -> LivingBackdrop:
	var backdrop := LivingBackdrop.new()
	backdrop._build(texture_path, {
		"curtain_width": 0.13, "curtain_sway": 0.005, "curtain_speed": 0.32,
		"drift_zoom": 0.012, "drift_speed": 0.05,
		"light_count": 5, "lights": [
			Vector4(0.545, 0.115, 0.075, 0.085),   # the chandelier
			Vector4(0.805, 0.195, 0.035, 0.045),   # the right lantern
			Vector4(0.26, 0.27, 0.16, 0.06),       # left machine faces
			Vector4(0.84, 0.29, 0.07, 0.05),       # right machine faces
			Vector4(0.55, 0.31, 0.11, 0.045),      # the distant machines
		],
		# 0.13 read as still in a two-second frame diff; 0.18 is the quietest
		# setting at which the chandelier is seen to breathe.
		"light_pulse": 0.18,
		"reel_count": 8, "reels": [
			Vector4(0.135, 0.275, 0.048, 0.05),
			Vector4(0.192, 0.285, 0.045, 0.045),
			Vector4(0.252, 0.29, 0.045, 0.045),
			Vector4(0.308, 0.30, 0.04, 0.045),
			Vector4(0.36, 0.30, 0.038, 0.042),
			Vector4(0.79, 0.30, 0.035, 0.04),
			Vector4(0.838, 0.30, 0.034, 0.04),
			Vector4(0.876, 0.29, 0.03, 0.04),
		],
		"reel_speed": 0.32, "reel_alpha": 0.38,
		"haze_top": 0.5, "haze_amp": 0.0012,
		"rain": 0.0, "shimmer": 0.0, "beam_count": 0,
		"vignette": 0.14,
	}, true, true)
	return backdrop


## The main menu's rainy night outside the casino: rain, the wet street
## shimmering, the spade sign and the canopy bulbs breathing, two searchlights
## sweeping the clouds, and lightning now and then. No curtains.
static func night_exterior(texture_path := "res://assets/backgrounds/bg_main_menu.png") -> LivingBackdrop:
	var backdrop := LivingBackdrop.new()
	backdrop._build(texture_path, {
		"curtain_width": 0.0, "curtain_sway": 0.0,
		"drift_zoom": 0.01, "drift_speed": 0.04,
		"light_count": 6, "lights": [
			Vector4(0.535, 0.24, 0.085, 0.115),    # the golden spade
			Vector4(0.545, 0.425, 0.13, 0.02),     # canopy bulbs
			Vector4(0.395, 0.505, 0.022, 0.05),    # left lantern
			Vector4(0.695, 0.505, 0.022, 0.05),    # right lantern
			Vector4(0.545, 0.55, 0.075, 0.06),     # the doors
			Vector4(0.36, 0.115, 0.03, 0.03),      # the sign atop the left tower
		],
		"light_pulse": 0.16,
		"reel_count": 0,
		"haze_top": 1.0, "haze_amp": 0.0,
		"rain": 1.0, "ground_y": 0.63, "shimmer": 0.007,
		"beam_count": 2, "beams": [
			Vector4(0.175, 0.44, -1.15, 0.22),
			Vector4(0.245, 0.47, -1.35, 0.18),
		],
		"vignette": 0.13,
	}, false, false)
	backdrop._storm = true
	backdrop._next_lightning = randf_range(6.0, 14.0)
	return backdrop


func _build(texture_path: String, params: Dictionary, with_curtains: bool, with_motes: bool) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	painting = TextureRect.new()
	painting.set_anchors_preset(Control.PRESET_FULL_RECT)
	painting.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	painting.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	painting.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(texture_path):
		painting.texture = load(texture_path)
	if ResourceLoader.exists(SHADER):
		_material = ShaderMaterial.new()
		_material.shader = load(SHADER)
		for key in params:
			var value = params[key]
			if value is Array:
				# Uniform arrays take a PackedVector4Array (the shader's vec4[]).
				var packed := PackedVector4Array()
				for v in value:
					packed.append(v)
				_material.set_shader_parameter(key, packed)
			else:
				_material.set_shader_parameter(key, value)
		# CB_DEBUG_BACKDROP_LOUD=1: every motion at several times its amplitude,
		# so each effect can be seen (and frame-diffed) on a still. The shipped
		# values are "subtle, always alive"; this is for checking the regions
		# sit on the right pixels, never for play.
		if OS.get_environment("CB_DEBUG_BACKDROP_LOUD") == "1":
			for key in ["light_pulse", "curtain_sway", "reel_alpha", "haze_amp", "shimmer"]:
				var v = _material.get_shader_parameter(key)
				if v != null:
					_material.set_shader_parameter(key, float(v) * 4.0)
			_material.set_shader_parameter("reel_speed", 1.6)
			_material.set_shader_parameter("light_pulse", 0.6)
		painting.material = _material
	add_child(painting)

	if with_motes:
		_motes = _make_motes()
		add_child(_motes)

	if with_curtains and ResourceLoader.exists(CURTAINS):
		curtains = TextureRect.new()
		curtains.set_anchors_preset(Control.PRESET_FULL_RECT)
		# A hair larger than the frame, so the parallax never shows an edge.
		curtains.offset_left = -PARALLAX_PX * 1.5
		curtains.offset_right = PARALLAX_PX * 1.5
		curtains.offset_top = -PARALLAX_PX * 1.5
		curtains.offset_bottom = PARALLAX_PX * 1.5
		curtains.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		curtains.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		curtains.mouse_filter = Control.MOUSE_FILTER_IGNORE
		curtains.texture = load(CURTAINS)
		if ResourceLoader.exists(CLOTH_SHADER):
			_cloth = ShaderMaterial.new()
			_cloth.shader = load(CLOTH_SHADER)
			curtains.material = _cloth
		add_child(curtains)


## Gold dust drifting up through the chandelier light: a slow, sparse column
## that catches the eye only when it stops.
func _make_motes() -> CPUParticles2D:
	var motes := CPUParticles2D.new()
	motes.amount = 70
	motes.lifetime = 9.0
	motes.preprocess = 9.0
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	motes.emission_rect_extents = Vector2(700.0, 260.0)
	motes.position = Vector2(960.0, 380.0)
	motes.direction = Vector2(-0.2, -1.0)
	motes.spread = 40.0
	motes.gravity = Vector2(0.0, -2.0)
	motes.initial_velocity_min = 4.0
	motes.initial_velocity_max = 14.0
	motes.scale_amount_min = 1.5
	motes.scale_amount_max = 3.2
	motes.color = Color(1.0, 0.86, 0.5, 0.0)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.86, 0.5, 0.0))
	ramp.add_point(0.3, Color(1.0, 0.88, 0.55, 0.32))
	ramp.add_point(0.7, Color(1.0, 0.9, 0.6, 0.28))
	ramp.set_color(ramp.get_point_count() - 1, Color(1.0, 0.86, 0.5, 0.0))
	motes.color_ramp = ramp
	motes.angular_velocity_min = -20.0
	motes.angular_velocity_max = 20.0
	return motes


func _process(delta: float) -> void:
	# Mouse parallax: the room leans a few pixels away from the cursor, the
	# foreground more than the painting, eased so a fast drag reads as air.
	var target := Vector2.ZERO
	var rect := get_viewport_rect()
	if rect.size.x > 0.0 and rect.size.y > 0.0:
		var mouse := get_viewport().get_mouse_position()
		target = ((mouse / rect.size) - Vector2(0.5, 0.5)).clamp(Vector2(-0.5, -0.5), Vector2(0.5, 0.5))
	_parallax = _parallax.lerp(target, clampf(delta * PARALLAX_EASE, 0.0, 1.0))
	_impulse = lerpf(_impulse, 0.0, clampf(delta * 3.0, 0.0, 1.0))

	if _material != null:
		_material.set_shader_parameter("parallax", -_parallax * PARALLAX_UV)
		_material.set_shader_parameter("impulse", _impulse)
	if curtains != null:
		curtains.position = -_parallax * PARALLAX_PX * 2.0
		if _cloth != null:
			_cloth.set_shader_parameter("impulse", _impulse)
	if _motes != null:
		_motes.position = Vector2(960.0, 380.0) - _parallax * PARALLAX_PX * 1.3

	if _storm and _material != null:
		_next_lightning -= delta
		if _next_lightning <= 0.0:
			_lightning = randf_range(0.6, 1.0)
			_next_lightning = randf_range(7.0, 18.0)
		# A strike is bright for two frames and gone in half a second.
		_lightning = lerpf(_lightning, 0.0, clampf(delta * 6.0, 0.0, 1.0))
		_material.set_shader_parameter("lightning", _lightning)


## Something heavy landed: the curtains kick. `strength` is the same figure
## the screen shake gets, so the two read as one impact.
func react(strength: float) -> void:
	_impulse = maxf(_impulse, clampf(strength / 18.0, 0.0, 1.0))
