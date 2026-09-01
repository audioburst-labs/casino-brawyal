class_name UnitView
extends VBoxContainer
## One combatant on the combat screen: intent (enemies), sprite, HP bar,
## block and status icons. Built procedurally; refresh() re-reads the actor.

signal clicked(actor_id: StringName)

## One constant size that fits up to 4 enemies side by side (patch 0.13).
const UNIT_HEIGHT := 330.0
## Patch 0.18: narrower units, so a full 4-slot line stays clear of the
## End Turn button no matter how many fighters are on the field.
const UNIT_WIDTH := 214.0

## Local "flame origin" point inside the Mark's wrapper (bottom-center
## anchored to _mark_row — see _build_mark).
const MARK_ORIGIN := Vector2(50.0, 48.0)

var actor: CombatActor
var sprite_height := UNIT_HEIGHT

var _mark_row: Control
var _mark_icon: TextureRect
var _mark_glow: Control
var _mark_glow_outer: Control
var _mark_particles: CPUParticles2D
var _mark_tween: Tween
var _intent_row: HBoxContainer
var _sprite_holder: CenterContainer
var _sprite: TextureRect
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
var _frame_outline: FrameOutline
var _base_sprite_position := Vector2.ZERO
var _shown_block := 0              # block currently drawn under the HP bar


## The blue target circle drawn under the targeted enemy's model (patch 0.13).
class TargetRing:
	extends Control

	func _draw() -> void:
		var center := Vector2(size.x * 0.5, size.y - 14.0)
		draw_set_transform(center, 0.0, Vector2(1.0, 0.35))
		draw_arc(Vector2.ZERO, size.x * 0.42, 0, TAU, 48, Color(0.35, 0.7, 1.0, 0.9), 5.0, true)
		draw_arc(Vector2.ZERO, size.x * 0.42 + 6.0, 0, TAU, 48, Color(0.35, 0.7, 1.0, 0.35), 9.0, true)


## Targeted marker (patch 0.17): only the outer frame of the name/HP
## panel outlines blue — the panel's fill and text stay normal, instead
## of the whole box getting tinted.
class FrameOutline:
	extends Control

	func _draw() -> void:
		draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)),
			Color(0.45, 0.8, 1.0, 0.95), false, 3.0)


func setup(combat_actor: CombatActor) -> void:
	actor = combat_actor
	alignment = BoxContainer.ALIGNMENT_END
	custom_minimum_size = Vector2(UNIT_WIDTH, 0)

	# The Mark gets its OWN reserved band above the intent text, same trick
	# as intent_row's fixed height: a slot that always exists (so it can
	## never overlap the intent line below it or the character's face
	# further down), and one that's a sibling of _sprite rather than a
	# child of it — so hit-squash/lunge/sway transforms never distort it.
	_mark_row = Control.new()
	_mark_row.custom_minimum_size = Vector2(0, 70)
	_mark_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mark_row)
	_build_mark(_mark_row)

	_intent_row = HBoxContainer.new()
	_intent_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_intent_row.add_theme_constant_override("separation", 6)
	# Fixed height: clearing the intent must not reflow the sprite upward
	# (patch 0.1: "opponent moves slightly up when first attacking").
	_intent_row.custom_minimum_size = Vector2(0, 42)
	add_child(_intent_row)

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

	if texture == null:
		_fallback = ColorRect.new()
		_fallback.color = Color(0.4, 0.2, 0.3)
		_fallback.custom_minimum_size = Vector2(sprite_height * 0.45, sprite_height * 0.85)
		sprite_holder.add_child(_fallback)

	_hp_holder = PanelContainer.new()
	add_child(_hp_holder)
	var hp_box := VBoxContainer.new()
	_hp_holder.add_child(hp_box)
	_frame_outline = FrameOutline.new()
	_frame_outline.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_outline.visible = false
	_hp_holder.add_child(_frame_outline)

	var name_label := Label.new()
	name_label.text = actor.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.theme_type_variation = &"SubtitleLabel"
	# One line always — a long name (Mr. Moneybags) shrinks to fit rather than
	# wrapping, which would push the whole unit up out of line with its
	# neighbours, or clipping against the panel edge (patch 0.18).
	name_label.clip_text = true
	hp_box.add_child(name_label)
	# Sized only once it is in the tree — the theme variation's real font is
	# what has to be measured, and an orphan Control resolves the plain
	# default instead.
	name_label.add_theme_font_size_override("font_size",
		_name_font_size(name_label, actor.display_name))

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

	# A separate section below the name/HP square (patch 0.17), not packed
	# into hp_box — so a growing number of buff/debuff icons can never widen
	# or resize the HP panel itself (it used to visibly "swell").
	_status_row = HBoxContainer.new()
	_status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_status_row.add_theme_constant_override("separation", 4)
	# Fixed size reserved whether or not any statuses are showing — an icon
	# appearing/disappearing must not change size or reflow the sprite
	# (that reflow was pushing the whole unit upward: designer note).
	_status_row.custom_minimum_size = Vector2(UNIT_WIDTH, 36)
	_status_row.clip_contents = true
	add_child(_status_row)

	gui_input.connect(_on_gui_input)
	mouse_filter = Control.MOUSE_FILTER_STOP
	refresh()


## Largest font size at which `text` still fits the panel on one line.
static func _name_font_size(label: Label, text: String) -> int:
	var font := label.get_theme_font("font")
	if font == null:
		return 24
	for font_size in range(24, 13, -1):
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1,
				font_size).x <= UNIT_WIDTH - 24.0:
			return font_size
	return 14


func refresh() -> void:
	_hp_bar.max_value = actor.max_hp
	_hp_bar.value = actor.hp
	_hp_label.text = "%d / %d" % [actor.hp, actor.max_hp]
	_shown_block = actor.block
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
			rect.tooltip_text = status_tooltip(status_id, stacks)
			rect.mouse_filter = Control.MOUSE_FILTER_PASS
			_status_row.add_child(rect)
		var stack_label := Label.new()
		stack_label.add_theme_font_size_override("font_size", 18)
		stack_label.text = ("%s %d " % [status_id, stacks]) if icon == null else ("%d " % stacks)
		stack_label.tooltip_text = status_tooltip(status_id, stacks)
		stack_label.mouse_filter = Control.MOUSE_FILTER_PASS
		_status_row.add_child(stack_label)
	modulate = Color.WHITE if actor.is_alive() else Color(0.35, 0.3, 0.3, 0.5)
	_refresh_mark()


## One human-readable explanation for a status/keyword, used by every hover
## surface in combat: the buff/debuff strip under a unit and the icons on an
## enemy's announced intent (patch 0.18 — "hovering should display the
## keyword, like hovering a player ability").
static func status_tooltip(status_id: StringName, stacks: int = 0) -> String:
	var title := String(status_id).capitalize()
	var body := ""
	var keyword := Db.content.get_keyword(status_id)
	if keyword != null:
		title = keyword.name
		body = keyword.text
	else:
		var status := Db.content.get_status(status_id)
		if status != null:
			title = status.name
			body = status.description
	if stacks > 0:
		title = "%s %d" % [title, stacks]
	return title if body == "" else "%s — %s" % [title, body]


## Builds the Mark's living-flame assembly: a soft additive glow, rising
## fire particles (green/teal/purple per the design doc), and a spade icon
## on top for readability — all inside a small wrapper anchored to the
## bottom-center of `row`, so it stays put across any width and never
## needs the actor's sprite size at build time.
func _build_mark(row: Control) -> void:
	var wrapper := Control.new()
	wrapper.anchor_left = 0.5
	wrapper.anchor_right = 0.5
	wrapper.anchor_top = 1.0
	wrapper.anchor_bottom = 1.0
	wrapper.offset_left = -50.0
	wrapper.offset_right = 50.0
	wrapper.offset_top = -70.0
	wrapper.offset_bottom = 0.0
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(wrapper)

	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	# Two-tone bloom (bigger, softer purple halo behind a brighter teal
	# core) so the "green/teal/purple flame" reads as more than one color
	# even before the particles add their own cycling hues.
	_mark_glow_outer = CombatVfx.Glow.new()
	_mark_glow_outer.glow_color = Color(0.6, 0.35, 1.0, 0.4)
	_mark_glow_outer.reach = 52.0
	_mark_glow_outer.material = additive
	_mark_glow_outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark_glow_outer.position = MARK_ORIGIN
	_mark_glow_outer.visible = false
	wrapper.add_child(_mark_glow_outer)

	_mark_glow = CombatVfx.Glow.new()
	_mark_glow.glow_color = Color(0.4, 1.0, 0.8, 0.65)
	_mark_glow.reach = 36.0
	_mark_glow.material = additive
	_mark_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark_glow.position = MARK_ORIGIN
	_mark_glow.visible = false
	wrapper.add_child(_mark_glow)

	_mark_particles = CPUParticles2D.new()
	_mark_particles.emitting = false
	_mark_particles.amount = 26
	_mark_particles.lifetime = 1.1
	_mark_particles.preprocess = 1.1  # already "burning" the instant it appears
	_mark_particles.randomness = 0.55
	_mark_particles.direction = Vector2.UP
	_mark_particles.spread = 24.0
	_mark_particles.initial_velocity_min = 26.0
	_mark_particles.initial_velocity_max = 50.0
	_mark_particles.gravity = Vector2(0, -22)
	_mark_particles.scale_amount_min = 3.5
	_mark_particles.scale_amount_max = 7.5
	_mark_particles.color_ramp = _mark_flame_gradient()
	_mark_particles.material = additive
	_mark_particles.position = MARK_ORIGIN + Vector2(0, 6)
	wrapper.add_child(_mark_particles)

	_mark_icon = TextureRect.new()
	if ResourceLoader.exists("res://assets/icons/status_mark.png"):
		_mark_icon.texture = load("res://assets/icons/status_mark.png")
	_mark_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mark_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_mark_icon.size = Vector2(54, 54)
	_mark_icon.position = MARK_ORIGIN - Vector2(27.0, 27.0)
	_mark_icon.pivot_offset = Vector2(27, 27)
	_mark_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark_icon.visible = false
	wrapper.add_child(_mark_icon)


## More, brighter stops so the green -> teal -> purple progression is
## clearly visible as particles rise and age, instead of fading to
## near-nothing halfway through their life. Set as parallel arrays
## (rather than chained add_point calls) so the offset-to-color mapping
## can't be thrown off by add_point's index-shifting insert behavior.
static func _mark_flame_gradient() -> Gradient:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.3, 0.6, 0.85, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.6, 1.0, 0.5, 1.0),    # bright green base
		Color(0.45, 1.0, 0.85, 1.0),  # teal-green
		Color(0.4, 0.75, 1.0, 0.9),   # teal-blue
		Color(0.65, 0.4, 1.0, 0.7),   # purple
		Color(0.75, 0.3, 1.0, 0.0),   # fades out at the very tip
	])
	return gradient


## Living flame above the enemy's head while marked — particles + a pulsing
## glow + a gently bobbing spade icon, all in the reserved _mark_row (never
## a child of _sprite, so hit-squash/lunge/sway never distorts it).
func _refresh_mark() -> void:
	if _mark_icon == null:
		return
	var marked := actor.has_status(&"mark") and actor.is_alive()
	if marked and not _mark_icon.visible:
		_mark_icon.visible = true
		_mark_glow.visible = true
		_mark_glow_outer.visible = true
		_mark_particles.emitting = true
		_mark_icon.scale = Vector2(0.2, 0.2)
		var pop := _mark_icon.create_tween()
		pop.tween_property(_mark_icon, "scale", Vector2.ONE, 0.3) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_mark_tween = create_tween().set_loops()
		_mark_tween.set_parallel(true)
		_mark_tween.tween_property(_mark_icon, "position:y", MARK_ORIGIN.y - 33.0, 0.7) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_mark_tween.tween_property(_mark_glow, "modulate:a", 0.5, 0.7) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_mark_tween.tween_property(_mark_glow_outer, "modulate:a", 0.7, 0.7) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_mark_tween.tween_property(_mark_glow_outer, "scale", Vector2(1.15, 1.15), 0.7) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_mark_tween.chain().set_parallel(true)
		_mark_tween.tween_property(_mark_icon, "position:y", MARK_ORIGIN.y - 23.0, 0.7) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_mark_tween.tween_property(_mark_glow, "modulate:a", 1.0, 0.7) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_mark_tween.tween_property(_mark_glow_outer, "modulate:a", 1.0, 0.7) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_mark_tween.tween_property(_mark_glow_outer, "scale", Vector2.ONE, 0.7) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	elif not marked and _mark_icon.visible:
		if _mark_tween != null:
			_mark_tween.kill()
		_mark_icon.visible = false
		_mark_glow.visible = false
		_mark_glow_outer.visible = false
		_mark_particles.emitting = false


## `entry` is the intents_shown payload: intent dict + display_per_hit /
## display_instances (strength-buffed values) + optional blackjack fields.
## Icons belong on enemy intents, not player ability text (patch 0.17): each
## debuff/buff gets its status icon inline, ahead of its stack count.
func show_intent(entry: Dictionary) -> void:
	clear_intent()
	var intent: Dictionary = entry.get("intent", {})
	for debuff: Dictionary in intent.get("debuffs", []):
		_add_intent_chunk(StringName(str(debuff.get("status", ""))),
			"%d" % int(debuff.get("stacks", 1)))
	for buff: Dictionary in intent.get("self_status", []):
		_add_intent_chunk(StringName(str(buff.get("status", ""))),
			"+%d" % int(buff.get("stacks", 1)))
	if not intent.get("summon", {}).is_empty():
		# Patch 0.18: a summon reads as an icon like every other intent, not
		# as bare text in the middle of the icon row.
		_add_intent_chunk(&"summon",
			"x%d" % int(intent.get("summon").get("count", 1)))
	if intent.get("heal_allies", 0) > 0:
		_add_intent_chunk(&"heal_allies", "%d" % int(intent.get("heal_allies")))
	if intent.get("ally_attack_again", false):
		_add_intent_chunk(&"encore", "")
	var instances := int(entry.get("display_instances", intent.get("instances", 0)))
	var per_hit := int(entry.get("display_per_hit", intent.get("per_hit", 0)))
	if entry.get("bust", false):
		_add_intent_text("BUST!")
	elif instances > 1:
		_add_intent_chunk(&"attack", "%dx%d" % [instances, per_hit])
	elif instances == 1:
		_add_intent_chunk(&"attack", "%d" % per_hit)


## Non-status intent parts that still deserve an icon + a hover explanation.
const INTENT_ICONS := {
	&"attack": "res://assets/icons/intent_attack.png",
	&"summon": "res://assets/icons/intent_summon.png",
	&"heal_allies": "res://assets/icons/fx_heal.png",
	&"encore": "res://assets/icons/keyword_go_again.png",
}
const INTENT_HINTS := {
	&"attack": "Attack — [instances] x [damage per hit].",
	&"summon": "Summon — brings new enemies onto the field.",
	&"heal_allies": "Heal Allies — restores health to every living enemy.",
	&"encore": "Encore — another enemy attacks a second time.",
}


## One icon (status_<id>.png, or an intent icon, falling back to the generic
## attack dagger) plus its stack/damage number. Both halves carry the same
## hover text so the whole chunk explains itself (patch 0.18).
func _add_intent_chunk(status_id: StringName, label_text: String) -> void:
	var texture: Texture2D = null
	if not INTENT_ICONS.has(status_id):
		texture = SuitAssets.status_texture(status_id)
	var fallback_path: String = INTENT_ICONS.get(status_id, INTENT_ICONS[&"attack"])
	if texture == null and ResourceLoader.exists(fallback_path):
		texture = load(fallback_path)
	if texture == null and ResourceLoader.exists(INTENT_ICONS[&"attack"]):
		texture = load(INTENT_ICONS[&"attack"])
	var hint: String = INTENT_HINTS.get(status_id, status_tooltip(status_id, label_text.to_int()))
	if texture != null:
		var icon := TextureRect.new()
		icon.texture = texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(30, 30)
		icon.tooltip_text = hint
		icon.mouse_filter = Control.MOUSE_FILTER_PASS
		_intent_row.add_child(icon)
	if label_text != "":
		_add_intent_text(label_text, hint)


func _add_intent_text(text: String, hint: String = "") -> void:
	var label := Label.new()
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	label.add_theme_font_size_override("font_size", 22)
	label.text = text
	if hint != "":
		label.tooltip_text = hint
		label.mouse_filter = Control.MOUSE_FILTER_PASS
	_intent_row.add_child(label)


func clear_intent() -> void:
	for child in _intent_row.get_children():
		child.queue_free()


## ---- pose-frame animation ----
##
## Actions animate by hard-cutting between generated pose keyframes (the way
## Darkest Dungeon / hand-drawn 2D games do it) while motion tweens, smears
## and impact FX cover the low frame count. Any actor lacking pose files
## simply falls back to the tween-only lunge.

const POSE_NAMES := [
	"throw_windup", "throw_release", "throw_follow",
	"slash_windup", "slash_strike", "slash_follow",
	"punch_windup", "punch_strike", "punch_follow",
]


func _load_poses() -> void:
	for pose in POSE_NAMES:
		var path := "res://assets/characters/%s_%s.png" % [actor.def_id, pose]
		if ResourceLoader.exists(path):
			_poses[pose] = load(path)


func has_pose(pose: String) -> bool:
	return _poses.has(pose)


## Plays whichever attack animation this actor has pose art for (throw beats
## slash beats punch), falling back to the plain lunge. New pose sets drop in
## automatically for any actor without touching call sites.
func play_attack() -> void:
	if has_pose("throw_release"):
		await play_throw()
	elif has_pose("slash_strike"):
		await play_slash()
	elif has_pose("punch_strike"):
		await play_punch()
	else:
		play_lunge()
		await get_tree().create_timer(0.22).timeout


## Lets the presenter register the VFX layer used for motion smears.
func set_ghost_layer(layer: Node) -> void:
	_ghost_layer = layer


func _show_pose(pose: String) -> void:
	if _poses.has(pose):
		_sprite.texture = _poses[pose]


func _smear() -> void:
	if _ghost_layer != null and _ghost_layer.has_method("ghost"):
		_ghost_layer.ghost(_sprite)


## True cross-dissolve back to the idle art: a throwaway copy of the sprite
## holding the IDLE texture fades up on top of the pose frame, which fades
## out underneath it, so something is always on screen. Patch 0.17 faded the
## one sprite out to alpha 0 and back to hide the silhouette pop — which is
## why the Bouncer briefly vanished mid-transition (patch 0.18).
func _return_to_idle() -> void:
	if _idle_texture == null or _sprite.texture == _idle_texture:
		return
	# The overlay rides INSIDE _sprite (full rect) so it inherits every
	# position/scale tween already in flight, and the outgoing pose fades via
	# self_modulate — which does not drag the overlay down with it.
	var incoming := TextureRect.new()
	incoming.texture = _idle_texture
	incoming.expand_mode = _sprite.expand_mode
	incoming.stretch_mode = _sprite.stretch_mode
	incoming.set_anchors_preset(Control.PRESET_FULL_RECT)
	incoming.mouse_filter = Control.MOUSE_FILTER_IGNORE
	incoming.modulate.a = 0.0
	_sprite.add_child(incoming)

	var blend := create_tween()
	blend.set_parallel(true)
	blend.tween_property(incoming, "modulate:a", 1.0, 0.18)
	blend.tween_property(_sprite, "self_modulate:a", 0.0, 0.18)
	blend.chain().tween_callback(func() -> void:
		_sprite.texture = _idle_texture
		_sprite.self_modulate.a = 1.0
		incoming.queue_free())


## Facing multiplier: heroes lunge toward +x (enemies stand to their right);
## enemies lunge toward -x (the hero stands to their left). Every pose
## animation's travel distances are scaled by this so "forward" always
## means "toward the target," not just "toward the right edge of the screen."
func _facing() -> float:
	return 1.0 if actor.is_hero else -1.0


## Throw: coil back on the wind-up frame, hold, then SNAP to the release
## frame. Returns at the release instant so the caller launches its
## projectile on exactly that frame; the follow-through plays after.
func play_throw() -> void:
	if not has_pose("throw_release"):
		play_lunge()
		await get_tree().create_timer(0.22).timeout
		return
	var origin := _sprite.position
	var facing := _facing()
	# Anticipation — the longest beat.
	_show_pose("throw_windup")
	var wind := create_tween()
	wind.set_parallel(true)
	wind.tween_property(_sprite, "position:x", origin.x - 34.0 * facing, 0.22) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	wind.tween_property(_sprite, "scale", Vector2(0.96, 1.04), 0.22)
	await wind.finished
	await get_tree().create_timer(0.08).timeout  # the coiled moment
	# Release — snap forward with motion smears.
	_show_pose("throw_release")
	_smear()
	var snap := create_tween()
	snap.set_parallel(true)
	snap.tween_property(_sprite, "position:x", origin.x + 52.0 * facing, 0.07) \
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
	var facing := _facing()
	_show_pose("slash_windup")
	var wind := create_tween()
	wind.set_parallel(true)
	wind.tween_property(_sprite, "position:x", origin.x - 30.0 * facing, 0.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	wind.tween_property(_sprite, "scale", Vector2(0.95, 1.06), 0.2)
	await wind.finished
	await get_tree().create_timer(0.07).timeout
	_show_pose("slash_strike")
	_smear()
	var strike := create_tween()
	strike.set_parallel(true)
	strike.tween_property(_sprite, "position:x", origin.x + 96.0 * facing, 0.09) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	strike.tween_property(_sprite, "scale", Vector2(1.08, 0.94), 0.09)
	_smear()
	await strike.finished
	_smear()
	_finish_slash(origin)


## Punch: a heavier haymaker — a longer, lower coil (weight sinks into the
## rear leg) than a slash, then a short explosive snap with a harder squash.
## Returns on the strike instant so the caller can land impact FX on it.
func play_punch() -> void:
	if not has_pose("punch_strike"):
		play_lunge()
		await get_tree().create_timer(0.22).timeout
		return
	var origin := _sprite.position
	var facing := _facing()
	_show_pose("punch_windup")
	var wind := create_tween()
	wind.set_parallel(true)
	wind.tween_property(_sprite, "position:x", origin.x - 26.0 * facing, 0.3) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	wind.tween_property(_sprite, "scale", Vector2(1.1, 0.9), 0.3) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await wind.finished
	await get_tree().create_timer(0.1).timeout  # the coiled moment, held longer
	_show_pose("punch_strike")
	_smear()
	var strike := create_tween()
	strike.set_parallel(true)
	strike.tween_property(_sprite, "position:x", origin.x + 74.0 * facing, 0.06) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	strike.tween_property(_sprite, "scale", Vector2(1.16, 0.82), 0.06)
	await strike.finished
	_finish_punch(origin)


func _finish_punch(origin: Vector2) -> void:
	await get_tree().create_timer(0.12).timeout
	_show_pose("punch_follow")
	var settle := create_tween()
	settle.set_parallel(true)
	settle.tween_property(_sprite, "position", origin, 0.36) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	settle.tween_property(_sprite, "scale", Vector2.ONE, 0.36) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(0.18).timeout
	_return_to_idle()


func _finish_slash(origin: Vector2) -> void:
	await get_tree().create_timer(0.12).timeout
	_show_pose("slash_follow")
	var settle := create_tween()
	settle.set_parallel(true)
	settle.tween_property(_sprite, "position", origin, 0.36) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	settle.tween_property(_sprite, "scale", Vector2.ONE, 0.36) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(0.18).timeout
	_return_to_idle()


## Blue ring around the model + a blue outline on just the frame of the
## stats box (patch 0.17: not a full tint over the whole panel).
func set_targeted(targeted: bool) -> void:
	_target_ring.visible = targeted
	_frame_outline.visible = targeted


func sprite_center() -> Vector2:
	return _sprite.global_position + _sprite.size * 0.5


## Steps the readout down by ONE landed hit — the sim resolves every instance
## of a multi-hit attack synchronously, so a plain refresh() would jump to the
## final HP before the later hits even animate (patch 0.17).
##
## `hp_lost` is what actually came off HP, `blocked` what the shield ate.
## Patch 0.18: the bar used to drop
## by the raw damage even when Block soaked it, so the next refresh() popped
## the HP back up and Block read as a heal. Block is spent here instead, and
## only the leftover reaches the HP bar.
func apply_damage_display(hp_lost: int, blocked: int = 0) -> void:
	if blocked > 0:
		_shown_block = maxi(0, _shown_block - blocked)
		_block_label.text = ("  🛡 %d" % _shown_block) if _shown_block > 0 else ""
	if hp_lost <= 0:
		return
	var shown := maxi(0, int(_hp_bar.value) - hp_lost)
	_hp_bar.value = shown
	_hp_label.text = "%d / %d" % [shown, actor.max_hp]



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


## Apply Debuff (doc animation): the target briefly and quickly shifts side
## to side, then settles back.
func play_debuff_shake() -> void:
	var target: Control = _sprite if _sprite.texture != null else _fallback
	if _base_sprite_position == Vector2.ZERO:
		_base_sprite_position = target.position
	var base_x := _base_sprite_position.x
	var tween := create_tween()
	tween.tween_property(target, "position:x", base_x - 14.0, 0.05)
	tween.tween_property(target, "position:x", base_x + 14.0, 0.06)
	tween.tween_property(target, "position:x", base_x - 8.0, 0.06)
	tween.tween_property(target, "position:x", base_x, 0.07) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


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


## Telegraph: a menacing rise just before an enemy strikes.
func play_telegraph() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_sprite, "scale", Vector2(1.06, 1.06), 0.16) \
		.set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(_sprite, "scale", Vector2.ONE, 0.2)


## Death: a white blowout, then the sprite crumples at its feet and fades.
func play_death() -> void:
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
