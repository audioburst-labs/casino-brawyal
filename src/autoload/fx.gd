extends Node
## Autoload: juice services — screen shake, floating damage numbers, hit-stop.
## UI-only; the sim layer never calls this.

var _shake_strength := 0.0
var _shake_target: Control = null


func _process(delta: float) -> void:
	if _shake_target == null:
		return
	if _shake_strength > 0.1:
		_shake_target.position = Vector2(
			randf_range(-_shake_strength, _shake_strength),
			randf_range(-_shake_strength, _shake_strength))
		_shake_strength = lerpf(_shake_strength, 0.0, 10.0 * delta)
	else:
		_shake_target.position = Vector2.ZERO
		_shake_strength = 0.0


## The screen root that shake displaces (set once by Main).
func set_shake_target(target: Control) -> void:
	_shake_target = target


func shake(strength: float = 12.0) -> void:
	_shake_strength = maxf(_shake_strength, strength)


func hitstop(duration := 0.06) -> void:
	Engine.time_scale = 0.05
	get_tree().create_timer(duration * 0.05, true, false, true).timeout.connect(
		func() -> void: Engine.time_scale = 1.0)


## Floating damage/heal number at a global position.
func spawn_number(global_pos: Vector2, text: String, color := Color(1.0, 0.35, 0.3)) -> void:
	var label := Label.new()
	label.text = text
	label.z_index = 100
	label.add_theme_font_size_override("font_size", 44)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.05))
	label.add_theme_constant_override("outline_size", 10)
	label.theme_type_variation = &"TitleLabel"
	get_tree().root.add_child(label)
	label.global_position = global_pos + Vector2(randf_range(-20, 20), -20)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position:y", label.global_position.y - 90.0, 0.7) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(label, "modulate:a", 0.0, 0.7).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)
