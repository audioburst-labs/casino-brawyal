class_name UnitView
extends VBoxContainer
## One combatant on the combat screen: intent (enemies), sprite, HP bar,
## block and status icons. Built procedurally; refresh() re-reads the actor.

signal clicked(actor_id: StringName)

## One constant size that fits up to 4 enemies side by side (patch 0.13).
const UNIT_HEIGHT := 330.0

var actor: CombatActor
var sprite_height := UNIT_HEIGHT

var _intent_row: HBoxContainer
var _intent_icon: TextureRect
var _intent_label: Label
var _sprite_holder: CenterContainer
var _sprite: TextureRect
var _mark_icon: TextureRect
var _mark_tween: Tween
var _sway_tween: Tween
var _idle_texture: Texture2D
var _poses: Dictionary = {}        # pose name -> Texture2D
var _ghost_layer: Node = null      # CombatVfx, for motion smears
var _fallback: ColorRect
var _hp_holder: PanelContainer
var _hp_bar: ProgressBar
var _hp_label: Label
var _block_label: Label
var _status_row: HBoxContainer
var _target_ring: TargetRing
var _base_sprite_position := Vector2.ZERO


## The blue target circle drawn under the targeted enemy's model (patch 0.13).
class TargetRing:
	extends Control

	func _draw() -> void:
		var center := Vector2(size.x * 0.5, size.y - 14.0)
		draw_set_transform(center, 0.0, Vector2(1.0, 0.35))
		draw_arc(Vector2.ZERO, size.x * 0.42, 0, TAU, 48, Color(0.35, 0.7, 1.0, 0.9), 5.0, true)
		draw_arc(Vector2.ZERO, size.x * 0.42 + 6.0, 0, TAU, 48, Color(0.35, 0.7, 1.0, 0.35), 9.0, true)


func setup(combat_actor: CombatActor) -> void:
	actor = combat_actor
	alignment = BoxContainer.ALIGNMENT_END
	custom_minimum_size = Vector2(260, 0)

	_intent_row = HBoxContainer.new()
	_intent_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_intent_row.add_theme_constant_override("separation", 6)
	# Fixed height: clearing the intent must not reflow the sprite upward
	# (patch 0.1: "opponent moves slightly up when first attacking").
	_intent_row.custom_minimum_size = Vector2(0, 42)
	add_child(_intent_row)
	_intent_icon = TextureRect.new()
	_intent_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_intent_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_intent_icon.custom_minimum_size = Vector2(38, 38)
	_intent_icon.visible = false
	if ResourceLoader.exists("res://assets/icons/intent_attack.png"):
		_intent_icon.texture = load("res://assets/icons/intent_attack.png")
	_intent_row.add_child(_intent_icon)
	_intent_label = Label.new()
	_intent_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	_intent_label.add_theme_font_size_override("font_size", 26)
	_intent_label.text = ""
	_intent_row.add_child(_intent_label)

	_sprite_holder = CenterContainer.new()
	_sprite_holder.custom_minimum_size = Vector2(0, sprite_height)
	add_child(_sprite_holder)
	var sprite_holder := _sprite_holder

	var texture := SuitAssets.character_texture(actor.def_id, actor.is_hero)
	_sprite = TextureRect.new()
	_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sprite.custom_minimum_size = Vector2(sprite_height * 0.66, sprite_height)
	if texture != null:
		_sprite.texture = texture
		_idle_texture = texture
	_load_poses()
	# Feet-anchored pivot: squash & stretch reads as weight, not levitation.
	_sprite.pivot_offset = Vector2(sprite_height * 0.33, sprite_height)
	if ResourceLoader.exists("res://assets/shaders/flash.gdshader"):
		var flash_material := ShaderMaterial.new()
		flash_material.shader = load("res://assets/shaders/flash.gdshader")
		_sprite.material = flash_material
	sprite_holder.add_child(_sprite)

	_target_ring = TargetRing.new()
	_target_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_target_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target_ring.show_behind_parent = true
	_target_ring.visible = false
	_sprite.add_child(_target_ring)

	# The Mark: a flaming spade hovering above the head while marked (doc anim).
	if ResourceLoader.exists("res://assets/icons/status_mark.png"):
		_mark_icon = TextureRect.new()
		_mark_icon.texture = load("res://assets/icons/status_mark.png")
		_mark_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_mark_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_mark_icon.size = Vector2(44, 44)
		_mark_icon.visible = false
		_sprite.add_child(_mark_icon)
	if texture == null:
		_fallback = ColorRect.new()
		_fallback.color = Color(0.4, 0.2, 0.3)
		_fallback.custom_minimum_size = Vector2(sprite_height * 0.45, sprite_height * 0.85)
		sprite_holder.add_child(_fallback)

	_hp_holder = PanelContainer.new()
	add_child(_hp_holder)
	var hp_box := VBoxContainer.new()
	_hp_holder.add_child(hp_box)

	var name_label := Label.new()
	name_label.text = actor.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.theme_type_variation = &"SubtitleLabel"
	name_label.add_theme_font_size_override("font_size", 24)
	hp_box.add_child(name_label)

	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(0, 26)
	_hp_bar.show_percentage = false
	hp_box.add_child(_hp_bar)

	var under_bar := HBoxContainer.new()
	under_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	hp_box.add_child(under_bar)
	_hp_label = Label.new()
	_hp_label.add_theme_font_size_override("font_size", 20)
	under_bar.add_child(_hp_label)
	_block_label = Label.new()
	_block_label.add_theme_font_size_override("font_size", 20)
	_block_label.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	under_bar.add_child(_block_label)

	_status_row = HBoxContainer.new()
	_status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	hp_box.add_child(_status_row)

	gui_input.connect(_on_gui_input)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Idle micro-motion: nothing on a casino floor ever stands perfectly
	# still. Rotation-only so it never fights the lunge/hit tweens.
	_sway_tween = create_tween().set_loops()
	var phase := float(hash(actor.id) % 100) / 100.0
	_sway_tween.tween_interval(phase * 1.2)
	_sway_tween.tween_property(_sprite, "rotation", 0.012, 1.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_sway_tween.tween_property(_sprite, "rotation", -0.012, 1.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	refresh()


func refresh() -> void:
	_hp_bar.max_value = actor.max_hp
	_hp_bar.value = actor.hp
	_hp_label.text = "%d / %d" % [actor.hp, actor.max_hp]
	_block_label.text = ("  🛡 %d" % actor.block) if actor.block > 0 else ""
	for child in _status_row.get_children():
		child.queue_free()
	for status_id: StringName in actor.statuses:
		var stacks: int = actor.statuses[status_id]
		var icon := SuitAssets.status_texture(status_id)
		if icon != null:
			var rect := TextureRect.new()
			rect.texture = icon
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			rect.custom_minimum_size = Vector2(30, 30)
			rect.tooltip_text = String(status_id)
			_status_row.add_child(rect)
		var stack_label := Label.new()
		stack_label.add_theme_font_size_override("font_size", 18)
		stack_label.text = ("%s %d " % [status_id, stacks]) if icon == null else ("%d " % stacks)
		_status_row.add_child(stack_label)
	modulate = Color.WHITE if actor.is_alive() else Color(0.35, 0.3, 0.3, 0.5)
	_refresh_mark()


## Floating, bobbing flaming spade while the actor is marked (doc animation).
func _refresh_mark() -> void:
	if _mark_icon == null:
		return
	var marked := actor.has_status(&"mark") and actor.is_alive()
	if marked and not _mark_icon.visible:
		# Bobs INSIDE the sprite's top edge so it never covers the intent
		# text above (patch 0.13 size adjustments).
		_mark_icon.visible = true
		_mark_icon.position = Vector2(_sprite.size.x * 0.5 - 22, 14)
		_mark_icon.scale = Vector2(0.2, 0.2)
		_mark_icon.pivot_offset = Vector2(22, 22)
		var pop := _mark_icon.create_tween()
		pop.tween_property(_mark_icon, "scale", Vector2.ONE, 0.3) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_mark_tween = _mark_icon.create_tween().set_loops()
		_mark_tween.tween_property(_mark_icon, "position:y", 4.0, 0.7) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_mark_tween.tween_property(_mark_icon, "position:y", 18.0, 0.7) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	elif not marked and _mark_icon.visible:
		if _mark_tween != null:
			_mark_tween.kill()
		_mark_icon.visible = false


## `entry` is the intents_shown payload: intent dict + display_per_hit /
## display_instances (strength-buffed values) + optional blackjack fields.
func show_intent(entry: Dictionary) -> void:
	var intent: Dictionary = entry.get("intent", {})
	var parts: Array[String] = []
	for debuff: Dictionary in intent.get("debuffs", []):
		parts.append("%s %d" % [debuff.get("status", "?"), int(debuff.get("stacks", 1))])
	for buff: Dictionary in intent.get("self_status", []):
		parts.append("+%s %d" % [buff.get("status", "?"), int(buff.get("stacks", 1))])
	if not intent.get("summon", {}).is_empty():
		parts.append("summon x%d" % int(intent.get("summon").get("count", 1)))
	if intent.get("heal_allies", 0) > 0:
		parts.append("heal allies")
	if intent.get("ally_attack_again", false):
		parts.append("encore")
	var instances := int(entry.get("display_instances", intent.get("instances", 0)))
	var per_hit := int(entry.get("display_per_hit", intent.get("per_hit", 0)))
	if entry.get("bust", false):
		parts.append("BUST!")
	elif instances > 1:
		parts.append("%dx%d" % [instances, per_hit])
	elif instances == 1:
		parts.append("%d" % per_hit)
	_intent_icon.visible = instances > 0 and _intent_icon.texture != null
	_intent_label.text = "  ".join(parts)


func clear_intent() -> void:
	_intent_label.text = ""
	_intent_icon.visible = false


## ---- pose-frame animation ----
##
## Actions animate by hard-cutting between generated pose keyframes (the way
## Darkest Dungeon / hand-drawn 2D games do it) while motion tweens, smears
## and impact FX cover the low frame count. Any actor lacking pose files
## simply falls back to the tween-only lunge.

const POSE_NAMES := [
	"throw_windup", "throw_release", "throw_follow",
	"slash_windup", "slash_strike",
]


func _load_poses() -> void:
	for pose in POSE_NAMES:
		var path := "res://assets/characters/%s_%s.png" % [actor.def_id, pose]
		if ResourceLoader.exists(path):
			_poses[pose] = load(path)


func has_pose(pose: String) -> bool:
	return _poses.has(pose)


## Lets the presenter register the VFX layer used for motion smears.
func set_ghost_layer(layer: Node) -> void:
	_ghost_layer = layer


func _show_pose(pose: String) -> void:
	if _poses.has(pose):
		_sprite.texture = _poses[pose]


func _smear() -> void:
	if _ghost_layer != null and _ghost_layer.has_method("ghost"):
		_ghost_layer.ghost(_sprite)


func _return_to_idle() -> void:
	if _idle_texture == null:
		return
	# Crossfade home so the pose swap never pops.
	var fade := create_tween()
	fade.tween_property(_sprite, "modulate:a", 0.55, 0.09)
	fade.tween_callback(func() -> void: _sprite.texture = _idle_texture)
	fade.tween_property(_sprite, "modulate:a", 1.0, 0.16)


## Throw: coil back on the wind-up frame, hold, then SNAP to the release
## frame. Returns at the release instant so the caller launches its
## projectile on exactly that frame; the follow-through plays after.
func play_throw() -> void:
	if not has_pose("throw_release"):
		play_lunge()
		await get_tree().create_timer(0.22).timeout
		return
	var origin := _sprite.position
	# Anticipation — the longest beat.
	_show_pose("throw_windup")
	var wind := create_tween()
	wind.set_parallel(true)
	wind.tween_property(_sprite, "position:x", origin.x - 34.0, 0.22) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	wind.tween_property(_sprite, "scale", Vector2(0.96, 1.04), 0.22)
	await wind.finished
	await get_tree().create_timer(0.08).timeout  # the coiled moment
	# Release — snap forward with motion smears.
	_show_pose("throw_release")
	_smear()
	var snap := create_tween()
	snap.set_parallel(true)
	snap.tween_property(_sprite, "position:x", origin.x + 52.0, 0.07) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	snap.tween_property(_sprite, "scale", Vector2(1.06, 0.96), 0.07)
	_smear()
	await snap.finished
	_smear()
	# Follow-through resolves in the background; the caller fires NOW.
	_finish_throw(origin)


func _finish_throw(origin: Vector2) -> void:
	await get_tree().create_timer(0.06).timeout
	_show_pose("throw_follow")
	var settle := create_tween()
	settle.set_parallel(true)
	settle.tween_property(_sprite, "position", origin, 0.34) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	settle.tween_property(_sprite, "scale", Vector2.ONE, 0.34) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(0.22).timeout
	_return_to_idle()


## Slash: raise the dagger, then lunge through the strike frame. Returns on
## the strike instant so the caller lands its slash VFX on that frame.
func play_slash() -> void:
	if not has_pose("slash_strike"):
		play_lunge()
		await get_tree().create_timer(0.22).timeout
		return
	var origin := _sprite.position
	_show_pose("slash_windup")
	var wind := create_tween()
	wind.set_parallel(true)
	wind.tween_property(_sprite, "position:x", origin.x - 30.0, 0.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	wind.tween_property(_sprite, "scale", Vector2(0.95, 1.06), 0.2)
	await wind.finished
	await get_tree().create_timer(0.07).timeout
	_show_pose("slash_strike")
	_smear()
	var strike := create_tween()
	strike.set_parallel(true)
	strike.tween_property(_sprite, "position:x", origin.x + 96.0, 0.09) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	strike.tween_property(_sprite, "scale", Vector2(1.08, 0.94), 0.09)
	_smear()
	await strike.finished
	_smear()
	_finish_slash(origin)


func _finish_slash(origin: Vector2) -> void:
	await get_tree().create_timer(0.12).timeout
	var settle := create_tween()
	settle.set_parallel(true)
	settle.tween_property(_sprite, "position", origin, 0.36) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	settle.tween_property(_sprite, "scale", Vector2.ONE, 0.36) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(0.18).timeout
	_return_to_idle()


## Blue ring around the model + a glow on the stats box (patch 0.13).
func set_targeted(targeted: bool) -> void:
	_target_ring.visible = targeted
	_hp_holder.modulate = Color(0.75, 1.05, 1.45) if targeted else Color.WHITE


func sprite_center() -> Vector2:
	return _sprite.global_position + _sprite.size * 0.5


## Impact: white shader flash, knockback, and a feet-anchored squash that
## springs back — the sprite visibly TAKES the hit.
func play_hit() -> void:
	var target: Control = _sprite if _sprite.texture != null else _fallback
	if _base_sprite_position == Vector2.ZERO:
		_base_sprite_position = target.position
	if _sprite.material is ShaderMaterial:
		_sprite.material.set_shader_parameter("flash", 0.9)
		var flash_tween := create_tween()
		flash_tween.tween_method(func(v: float) -> void:
			_sprite.material.set_shader_parameter("flash", v), 0.9, 0.0, 0.28)
	var direction := -1.0 if actor.is_hero else 1.0
	target.scale = Vector2(1.12, 0.86)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(target, "scale", Vector2.ONE, 0.3) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(target, "position:x", _base_sprite_position.x + 20.0 * direction, 0.06)
	tween.chain().tween_property(target, "position:x", _base_sprite_position.x, 0.22) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Attack: anticipation (pull back and coil), then a snapping strike lunge
## with follow-through overshoot — no more polite drifting.
func play_lunge() -> void:
	var origin := _sprite.position
	var direction := 1.0 if actor.is_hero else -1.0
	var tween := create_tween()
	# Wind-up: pull away and crouch...
	tween.set_parallel(true)
	tween.tween_property(_sprite, "position:x", origin.x - 22.0 * direction, 0.14) \
		.set_ease(Tween.EASE_OUT)
	tween.tween_property(_sprite, "scale", Vector2(0.94, 1.05), 0.14)
	# ...snap forward...
	tween.chain().tween_property(_sprite, "position:x", origin.x + 70.0 * direction, 0.08) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(_sprite, "scale", Vector2(1.08, 0.94), 0.08)
	# ...and settle home with follow-through.
	tween.chain().tween_property(_sprite, "position", origin, 0.3) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_sprite, "scale", Vector2.ONE, 0.3) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Telegraph: a menacing red-tinted rise just before an enemy strikes.
func play_telegraph() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_sprite, "modulate", Color(1.35, 0.75, 0.7), 0.16)
	tween.tween_property(_sprite, "scale", Vector2(1.06, 1.06), 0.16) \
		.set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(_sprite, "modulate", Color.WHITE, 0.2)
	tween.parallel().tween_property(_sprite, "scale", Vector2.ONE, 0.2)


## Death: a white blowout, then the sprite crumples at its feet and fades.
func play_death() -> void:
	if _sway_tween != null:
		_sway_tween.kill()  # the idle sway must not fight the collapse
	if _sprite.material is ShaderMaterial:
		_sprite.material.set_shader_parameter("flash", 1.0)
		var flash_tween := create_tween()
		flash_tween.tween_method(func(v: float) -> void:
			_sprite.material.set_shader_parameter("flash", v), 1.0, 0.0, 0.35)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_sprite, "scale", Vector2(1.25, 0.0), 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_sprite, "rotation", 0.12, 0.45)
	tween.tween_property(self, "modulate:a", 0.0, 0.5)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(actor.id)
