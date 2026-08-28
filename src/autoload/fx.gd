extends Node
## Autoload: juice services — screen shake, floating damage numbers, hit-stop.
## UI-only; the sim layer never calls this.

var _shake_strength := 0.0
var _shake_rotation := 0.0
var _zoom_punch := 0.0
var _shake_target: Control = null

var _cursor_idle: ImageTexture = null
var _cursor_grab: ImageTexture = null
const CURSOR_HOTSPOT := Vector2(8, 4)


func _process(delta: float) -> void:
	if _shake_target == null:
		return
	var dirty := false
	if _shake_strength > 0.1:
		_shake_target.position = Vector2(
			randf_range(-_shake_strength, _shake_strength),
			randf_range(-_shake_strength, _shake_strength))
		_shake_target.rotation = randf_range(-_shake_rotation, _shake_rotation)
		_shake_strength = lerpf(_shake_strength, 0.0, 10.0 * delta)
		_shake_rotation = lerpf(_shake_rotation, 0.0, 10.0 * delta)
		dirty = true
	elif _shake_target.position != Vector2.ZERO:
		_shake_target.position = Vector2.ZERO
		_shake_target.rotation = 0.0
		_shake_strength = 0.0
	if _zoom_punch > 0.001:
		_shake_target.pivot_offset = _shake_target.size * 0.5
		_shake_target.scale = Vector2.ONE * (1.0 + _zoom_punch)
		_zoom_punch = lerpf(_zoom_punch, 0.0, 8.0 * delta)
		dirty = true
	elif _shake_target.scale != Vector2.ONE:
		_shake_target.scale = Vector2.ONE
	if dirty:
		pass  # values keep decaying next frame


## The screen root that shake/zoom displaces (set once by Main).
func set_shake_target(target: Control) -> void:
	_shake_target = target


## Ace's own hand as the in-game cursor (doc's Mouse spec): a neutral point
## by default, briefly a grabbing fist while a chip is held.
func init_cursor() -> void:
	_cursor_idle = _load_cursor("res://assets/icons/cursor_ace_hand.png")
	_cursor_grab = _load_cursor("res://assets/icons/cursor_ace_hand_grab.png")
	if _cursor_idle != null:
		Input.set_custom_mouse_cursor(_cursor_idle, Input.CURSOR_ARROW, CURSOR_HOTSPOT)


func _load_cursor(path: String) -> ImageTexture:
	if not ResourceLoader.exists(path):
		return null
	var image: Image = (load(path) as Texture2D).get_image()
	image.resize(48, 48, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(image)


func set_cursor_grabbing(active: bool) -> void:
	if _cursor_idle == null:
		return
	var texture := _cursor_grab if (active and _cursor_grab != null) else _cursor_idle
	Input.set_custom_mouse_cursor(texture, Input.CURSOR_ARROW, CURSOR_HOTSPOT)


## Tiered shake: big requests also kick a slight screen rotation —
## "the art of screenshake" says rotation is what sells the heavy tier.
func shake(strength: float = 12.0) -> void:
	_shake_strength = maxf(_shake_strength, strength)
	if strength >= 14.0:
		_shake_rotation = maxf(_shake_rotation, 0.012)


## A quick zoom-in punch on the whole battlefield for big impacts.
func punch_zoom(amount := 0.04) -> void:
	_zoom_punch = maxf(_zoom_punch, amount)


## Freeze-frame. Scale with damage: ~0.04s for chip damage, ~0.12s finishers.
func hitstop(duration := 0.06) -> void:
	Engine.time_scale = 0.05
	get_tree().create_timer(duration * 0.05, true, false, true).timeout.connect(
		func() -> void: Engine.time_scale = 1.0)


## Floating damage/heal number: pops in with an overshoot punch, tilts like a
## thrown chip, scales with magnitude, and goes gold on big hits (20+).
func spawn_number(global_pos: Vector2, text: String, color := Color(1.0, 0.35, 0.3)) -> void:
	var amount := text.to_int()
	var big := amount >= 20
	var label := Label.new()
	label.text = text
	label.z_index = 100
	label.add_theme_font_size_override("font_size",
		int(clampf(40.0 + absf(amount) * 1.2, 40.0, 92.0)))
	label.add_theme_color_override("font_color",
		Color(1.0, 0.85, 0.3) if big and amount > 0 and color == Color(1.0, 0.35, 0.3) else color)
	label.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.05))
	label.add_theme_constant_override("outline_size", 12)
	label.theme_type_variation = &"TitleLabel"
	label.rotation = randf_range(-0.14, 0.14)
	get_tree().root.add_child(label)
	label.global_position = global_pos + Vector2(randf_range(-24, 24), -24)
	label.pivot_offset = label.size * 0.5
	label.scale = Vector2(0.3, 0.3)
	var tween := label.create_tween()
	# Punch in...
	tween.tween_property(label, "scale", Vector2(1.35, 1.35) if big else Vector2.ONE, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if big:
		tween.tween_property(label, "scale", Vector2.ONE, 0.12)
	# ...hang for a readable beat, then drift and fade.
	tween.tween_interval(0.18 if big else 0.08)
	tween.set_parallel(true)
	tween.tween_property(label, "global_position:y", label.global_position.y - 96.0, 0.6) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(label, "modulate:a", 0.0, 0.6).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)
