class_name CombatVfx
extends Control
## The combat screen's "wow layer": additive-blend glows, shockwaves, ray
## bursts, ghost trails, confetti and vignette dims. Everything here is
## presentation-only and self-cleaning.

var _additive: CanvasItemMaterial


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_additive = CanvasItemMaterial.new()
	_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD


class Ring:
	extends Control
	var progress := 0.0
	var ring_color := Color.WHITE
	var max_radius := 120.0

	func _draw() -> void:
		if progress <= 0.0:
			return
		var alpha := 1.0 - progress
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.6))
		draw_arc(Vector2.ZERO, max_radius * progress, 0, TAU, 48,
			Color(ring_color.r, ring_color.g, ring_color.b, alpha), 10.0 * (1.0 - progress) + 2.0, true)


class Rays:
	extends Control
	var ray_color := Color(1.0, 0.9, 0.5)
	var reach := 160.0

	func _draw() -> void:
		for i in 12:
			var angle := TAU * i / 12.0
			var width := 0.10 if i % 2 == 0 else 0.05
			var points := PackedVector2Array([
				Vector2.ZERO,
				Vector2.from_angle(angle - width) * reach,
				Vector2.from_angle(angle + width) * reach,
			])
			draw_colored_polygon(points, ray_color)


## Expanding luminous shockwave ring — the punctuation mark of every impact.
func shockwave(at: Vector2, color := Color(1.0, 0.85, 0.5), radius := 130.0) -> void:
	var ring := Ring.new()
	ring.ring_color = color
	ring.max_radius = radius
	ring.material = _additive
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.z_index = 96
	add_child(ring)
	ring.global_position = at
	var tween := ring.create_tween()
	tween.tween_method(func(p: float) -> void:
		ring.progress = p
		ring.queue_redraw(), 0.05, 1.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(ring.queue_free)


## Rotating golden god-rays behind a big reveal or jackpot.
func ray_burst(at: Vector2, color := Color(1.0, 0.9, 0.5, 0.55), reach := 180.0,
		duration := 0.8) -> void:
	var rays := Rays.new()
	rays.ray_color = color
	rays.reach = reach
	rays.material = _additive
	rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rays.z_index = 85
	rays.scale = Vector2(0.2, 0.2)
	add_child(rays)
	rays.global_position = at
	rays.queue_redraw()
	var tween := rays.create_tween()
	tween.set_parallel(true)
	tween.tween_property(rays, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(rays, "rotation", 0.9, duration)
	tween.chain().tween_property(rays, "modulate:a", 0.0, 0.25)
	tween.chain().tween_callback(rays.queue_free)


## Fading afterimages behind a fast-moving node (ghost trail).
func ghost(node: TextureRect) -> void:
	if node.texture == null:
		return
	var copy := TextureRect.new()
	copy.texture = node.texture
	copy.expand_mode = node.expand_mode
	copy.stretch_mode = node.stretch_mode
	copy.size = node.size
	copy.rotation = node.rotation
	copy.pivot_offset = node.pivot_offset
	copy.modulate = Color(node.modulate.r, node.modulate.g, node.modulate.b, 0.45)
	copy.material = _additive
	copy.z_index = 88
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(copy)
	copy.global_position = node.global_position
	var tween := copy.create_tween()
	tween.tween_property(copy, "modulate:a", 0.0, 0.22)
	tween.tween_callback(copy.queue_free)


## A quick full-screen dim for dramatic beats (ultimates, boss moves).
func vignette(depth := 0.45, hold := 0.5) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.z_index = 80
	add_child(dim)
	var tween := dim.create_tween()
	tween.tween_property(dim, "color:a", depth, 0.12)
	tween.tween_interval(hold)
	tween.tween_property(dim, "color:a", 0.0, 0.3)
	tween.tween_callback(dim.queue_free)


## A single full-screen white blink (one frame of light on huge impacts).
func screen_flash(strength := 0.35) -> void:
	var blink := ColorRect.new()
	blink.color = Color(1, 1, 1, strength)
	blink.set_anchors_preset(Control.PRESET_FULL_RECT)
	blink.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blink.z_index = 99
	add_child(blink)
	var tween := blink.create_tween()
	tween.tween_property(blink, "color:a", 0.0, 0.18)
	tween.tween_callback(blink.queue_free)


## Casino confetti: falling suit-colored rectangles for jackpots/victories.
func confetti(at: Vector2, amount := 26) -> void:
	var particles := CPUParticles2D.new()
	particles.one_shot = true
	particles.emitting = true
	particles.amount = amount
	particles.lifetime = 1.4
	particles.explosiveness = 1.0
	particles.direction = Vector2.UP
	particles.spread = 70.0
	particles.initial_velocity_min = 260.0
	particles.initial_velocity_max = 480.0
	particles.gravity = Vector2(0, 720)
	particles.scale_amount_min = 3.0
	particles.scale_amount_max = 7.0
	particles.color_ramp = _confetti_gradient()
	particles.z_index = 97
	add_child(particles)
	particles.global_position = at
	get_tree().create_timer(1.8).timeout.connect(particles.queue_free)


static func _confetti_gradient() -> Gradient:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.95, 0.8, 0.35))
	gradient.set_color(1, Color(0.8, 0.25, 0.3))
	gradient.add_point(0.5, Color(0.3, 0.65, 0.95))
	return gradient
