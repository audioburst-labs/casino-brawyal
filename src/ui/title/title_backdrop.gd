class_name TitleBackdrop
extends Control
## The title screen's night scene (patch 0.125): the Dreams Casino in the rain.
##
## One 1536x1024 "stage" holds the painting and every animated layer in the
## painting's own pixel coordinates, scaled to cover the screen like the other
## backdrops (the same crop of the top and bottom the designer's mock showed).
## From the bottom up: the painting (its clouds drift and its puddle ripples in
## `title_scene.gdshader`), the lights, the walkers and the rain, then the
## searchlights and the lightning. A vignette sits over the lot.

const PAINTING := "res://assets/backgrounds/bg_title.png"
const SHADER := "res://assets/shaders/title_scene.gdshader"
const STAGE := Vector2(1536, 1024)
const PARALLAX_PX := Vector2(10.0, 6.0)

var _stage: Control
var _picture: TextureRect
var _material: ShaderMaterial
var _t := 0.0
var _parallax := Vector2.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_stage = Control.new()
	_stage.size = STAGE
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)

	_picture = TextureRect.new()
	_picture.size = STAGE
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_SCALE
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(PAINTING):
		_picture.texture = load(PAINTING)
	if ResourceLoader.exists(SHADER):
		_material = ShaderMaterial.new()
		_material.shader = load(SHADER)
		_picture.material = _material
	_stage.add_child(_picture)
	_stage.add_child(TitleLights.new())
	_stage.add_child(TitleWalkers.new())
	_stage.add_child(TitleBeams.new())

	# darkened corners, a little clearer toward the casino on the right
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0.016, 0.008, 0.055, 0.0), Color(0.016, 0.008, 0.055, 0.0), Color(0.016, 0.008, 0.055, 0.66)])
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.62, 0.5)
	tex.fill_to = Vector2(1.3, 1.15)
	tex.width = 256
	tex.height = 256
	var vignette := TextureRect.new()
	vignette.texture = tex
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)

	resized.connect(_layout)
	_layout()


func _process(delta: float) -> void:
	_t += delta
	if _material != null:
		_material.set_shader_parameter("time", _t)
	# the room leans a few pixels away from the cursor, eased
	var rect := get_viewport_rect().size
	var m := get_viewport().get_mouse_position()
	var target := Vector2.ZERO
	if rect.x > 0.0 and rect.y > 0.0:
		target = -((m / rect) - Vector2(0.5, 0.5)).clamp(Vector2(-0.5, -0.5), Vector2(0.5, 0.5)) * PARALLAX_PX
	_parallax = _parallax.lerp(target, clampf(delta * 3.0, 0.0, 1.0))
	_layout()


func _layout() -> void:
	if _stage == null:
		return
	var s := maxf(size.x / STAGE.x, size.y / STAGE.y)
	_stage.scale = Vector2(s, s)
	_stage.position = (size - STAGE * s) * 0.5 + _parallax
