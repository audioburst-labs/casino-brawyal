class_name UnitView
extends VBoxContainer
## One combatant on the combat screen: intent (enemies), sprite, HP bar,
## block and status icons. Built procedurally; refresh() re-reads the actor.

signal clicked(actor_id: StringName)
## Fired on the exact frame an attack pose connects (the strike/release
## frame, or the snap of the plain lunge), so impact VFX can land on it
## instead of after the whole animation has returned (0.0.111).
signal strike_landed

## One constant size that fits up to 4 enemies side by side (patch 0.13).
## Patch 0.20: every unit 10% larger. The four-slot line still fits — 4 x 198
## + 3 x 16 gap = 840 px inside a 893 px band.
const UNIT_HEIGHT := 315.0
const UNIT_WIDTH := 198.0
## The sprite's own minimum width, as a fraction of its height. It has to stay
## under UNIT_WIDTH or an occupied slot measures wider than an empty spacer
## and the line stops lining up (it was 0.66 of 330 = 217.8 vs a 214 slot).
const SPRITE_WIDTH_RATIO := 0.60

## Local "flame origin" point inside the Mark's wrapper (bottom-center
## anchored to _mark_row — see _build_mark).
const MARK_ORIGIN := Vector2(55.0, 53.0)

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
var _breath: Control = null
var _breath_phase := 0.0
const BREATH_PX := 2.2
const BREATH_PERIOD := 3.1
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
var _shown_passive := -1           # last enemy-passive number drawn, for its flash


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


## A minted plaque carrying an enemy passive's running number — the Dealer's
## 21 ticking down to a bust, the Chip Golem's health-to-next-chip (patch
## 0.113). The number is drawn here rather than parented as a Label so the
## whole badge can flash and swell as one piece when it ticks.
class PassiveChip:
	extends Control

	var value := 0
	## The passive's badge art (0.117, designer: "an icon with numbers below
	## it, not a plain square"). With no icon the plaque falls back to the
	## number alone. `show_value` false draws the badge only: the Loan Shark's
	## countdown "serves no purpose for the player".
	var icon: Texture2D = null
	var show_value := true
	var tint := Color(1.0, 0.78, 0.34)
	var pulse := 0.0:
		set(v):
			pulse = v
			queue_redraw()

	## One bright swell as the number moves, fading back to the resting plaque.
	func flash() -> void:
		var tween := create_tween()
		tween.tween_method(func(v: float) -> void: pulse = v, 1.0, 0.0, 0.45) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	func _draw() -> void:
		var plate := Rect2(Vector2.ZERO, size).grow(-1.0)
		# A halo that blooms outward on a tick, drawn first so it sits behind.
		if pulse > 0.0:
			draw_rect(plate.grow(2.0 + 6.0 * pulse),
				Color(tint.r, tint.g, tint.b, 0.55 * pulse), false, 3.0)
		if icon != null:
			# The badge fills the plate's width; the number, if shown, sits
			# in a strip underneath it.
			var side := size.x - 6.0
			draw_texture_rect(icon, Rect2(Vector2(3.0, 2.0), Vector2(side, side)), false)
			if not show_value:
				return
			var font := get_theme_default_font()
			if font == null:
				return
			var body := str(value)
			var font_size := 15 if body.length() < 3 else 13
			var extent := font.get_string_size(body, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var at := Vector2((size.x - extent.x) * 0.5, size.y - 3.0)
			var lit := tint.lerp(Color.WHITE, 0.35 + 0.65 * pulse)
			# A dark keyline so the digit reads over the art.
			draw_string(font, at + Vector2(1, 1), body, HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_size, Color(0, 0, 0, 0.8))
			draw_string(font, at, body, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, lit)
			return
		draw_rect(plate, Color(0.07, 0.06, 0.10, 0.94), true)
		# A doubled bezel reads as a token rather than a flat swatch.
		draw_rect(plate, Color(tint.r, tint.g, tint.b, 0.95), false, 2.0)
		draw_rect(plate.grow(-4.0), Color(tint.r, tint.g, tint.b, 0.30), false, 1.0)
		var font := get_theme_default_font()
		if font == null:
			return
		var body := str(value)
		var font_size := 19 if body.length() < 3 else 16
		var extent := font.get_string_size(body, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var at := Vector2((size.x - extent.x) * 0.5,
			(size.y + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5)
		var lit := tint.lerp(Color.WHITE, 0.35 + 0.65 * pulse)
		draw_string(font, at, body, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, lit)


## The shield that sweeps up a unit when it gains Block (patch 0.114). Drawn
## rather than sprited so it scales with the unit and needs no new art.
class BlockFlash:
	extends Control

	var progress := 0.0:
		set(v):
			progress = v
			queue_redraw()
	var fade := 1.0:
		set(v):
			fade = v
			queue_redraw()

	func _draw() -> void:
		if size.x <= 0.0 or fade <= 0.0:
			return
		var eased := clampf(progress, 0.0, 1.0)
		# Sweeps from the feet to chest height as it grows.
		var centre := Vector2(size.x * 0.5, size.y * (0.86 - 0.34 * eased))
		var reach := size.x * (0.20 + 0.16 * eased)
		var tint := Color(0.62, 0.86, 1.0, fade * (1.0 - eased * 0.35))
		# A ring first, so the shield reads as arriving rather than appearing.
		draw_arc(centre, reach * 1.25, 0.0, TAU, 40,
			Color(tint.r, tint.g, tint.b, tint.a * 0.45), 4.0, true)
		_shield(centre, reach, tint)

	## A heater shield: shoulders, straight sides, a point at the bottom.
	func _shield(at: Vector2, reach: float, tint: Color) -> void:
		var points := PackedVector2Array()
		points.append(at + Vector2(-reach, -reach * 0.78))
		points.append(at + Vector2(reach, -reach * 0.78))
		points.append(at + Vector2(reach, reach * 0.10))
		points.append(at + Vector2(0.0, reach * 1.02))
		points.append(at + Vector2(-reach, reach * 0.10))
		draw_colored_polygon(points, Color(tint.r, tint.g, tint.b, tint.a * 0.30))
		points.append(points[0])
		draw_polyline(points, tint, 3.5, true)


## Seeing stars: the ring that orbits a stunned unit's head while it is out
## (patch 0.113). `phase` is driven by the unit's own tween.
class StunStars:
	extends Control

	const STAR_COUNT := 4

	var phase := 0.0:
		set(v):
			phase = v
			queue_redraw()
	var fade := 1.0:
		set(v):
			fade = v
			queue_redraw()

	func _draw() -> void:
		var centre := Vector2(size.x * 0.5, size.y * 0.5)
		var radius := size.x * 0.34
		for i in STAR_COUNT:
			var angle := phase + TAU * float(i) / float(STAR_COUNT)
			# Squashed orbit: the stars pass behind the head, so the far half of
			# the ring is drawn smaller and dimmer.
			var depth := (sin(angle) + 1.0) * 0.5
			var at := centre + Vector2(cos(angle) * radius, sin(angle) * radius * 0.34)
			var scale := 6.5 + 5.5 * depth
			var alpha := fade * (0.45 + 0.55 * depth)
			_star(at, scale, Color(1.0, 0.92, 0.45, alpha))

	## A four-pointed sparkle, the same shape the hit sparks use.
	func _star(at: Vector2, radius: float, colour: Color) -> void:
		var points := PackedVector2Array()
		for i in 8:
			var angle := TAU * float(i) / 8.0 - PI * 0.5
			var reach := radius if i % 2 == 0 else radius * 0.38
			points.append(at + Vector2(cos(angle), sin(angle)) * reach)
		draw_colored_polygon(points, colour)


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
	_mark_row.custom_minimum_size = Vector2(0, 66)
	_mark_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mark_row)
	_build_mark(_mark_row)

	_intent_row = HBoxContainer.new()
	_intent_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_intent_row.add_theme_constant_override("separation", 6)
	# Fixed height: clearing the intent must not reflow the sprite upward
	# (patch 0.1: "opponent moves slightly up when first attacking").
	_intent_row.custom_minimum_size = Vector2(0, 46)
	add_child(_intent_row)

	_sprite_holder = CenterContainer.new()
	_sprite_holder.custom_minimum_size = Vector2(0, sprite_height)
	add_child(_sprite_holder)
	var sprite_holder := _sprite_holder

	var texture := SuitAssets.character_texture(actor.def_id, actor.is_hero)
	_sprite = TextureRect.new()
	_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sprite.custom_minimum_size = Vector2(sprite_height * SPRITE_WIDTH_RATIO, sprite_height)
	if texture != null:
		_sprite.texture = texture
		_idle_texture = texture
	_load_poses()
	# Feet-anchored pivot: squash & stretch reads as weight, not levitation.
	_sprite.pivot_offset = Vector2(sprite_height * SPRITE_WIDTH_RATIO * 0.5, sprite_height)
	if ResourceLoader.exists("res://assets/shaders/flash.gdshader"):
		var flash_material := ShaderMaterial.new()
		flash_material.shader = load("res://assets/shaders/flash.gdshader")
		_sprite.material = flash_material
	# Idle breathing (0.119): the sprite hangs off a wrapper that bobs a couple
	# of pixels on its own clock, so nobody stands like a cutout between
	# animations. The wrapper, not the sprite, so the pose tweens (position,
	# scale, rotation on `_sprite`) never fight it. The CenterContainer sizes
	# the wrapper to the sprite and re-seats it only on a layout change, when
	# the bob simply restarts from rest.
	_breath = Control.new()
	_breath.custom_minimum_size = _sprite.custom_minimum_size
	_breath.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_breath_phase = randf() * TAU
	sprite_holder.add_child(_breath)
	_breath.add_child(_sprite)

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
	_hp_bar.custom_minimum_size = Vector2(0, 29)
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
	# The slot is the fixed part; the row hangs inside it and may be taller (the
	# Dealer's 21 plaque is 64 px) without moving the unit: a tall row used to
	# push that unit up out of line with its neighbours and with Ace (0.121,
	# "enemies at the same height as the player").
	_status_row.custom_minimum_size = Vector2(UNIT_WIDTH, 0)
	_status_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	var status_slot := Control.new()
	status_slot.custom_minimum_size = Vector2(UNIT_WIDTH, 35)
	status_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_slot.add_child(_status_row)
	add_child(status_slot)

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


## A full re-read of the actor, ANIMATED READOUTS INCLUDED.
##
## Patch 0.113: HP and Block are stepped hit-by-hit by `apply_damage_display`,
## but the sim resolves a whole multi-hit attack before its first hit is drawn
## — so snapping them to the actor's final values midway through the animation
## made health "drop more than it should, then rise back up to the correct
## number". Anything that is not itself an HP or Block change now calls
## `refresh_statuses()`, and only a real full refresh re-syncs the two bars.
func refresh() -> void:
	_hp_bar.max_value = actor.max_hp
	_hp_bar.value = actor.hp
	_hp_label.text = "%d / %d" % [actor.hp, actor.max_hp]
	refresh_block()
	refresh_statuses()


## Re-sync only the Block readout (the other animated number).
func refresh_block() -> void:
	_shown_block = actor.block
	_block_label.text = ("  🛡 %d" % actor.block) if actor.block > 0 else ""


## Statuses, the enemy's passive plaque, loans and the Mark — everything
## except the two animated HP/Block readouts.
func refresh_statuses() -> void:
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
			rect.custom_minimum_size = Vector2(33, 33)
			rect.tooltip_text = status_tooltip(status_id, stacks)
			rect.mouse_filter = Control.MOUSE_FILTER_PASS
			_status_row.add_child(rect)
		var stack_label := Label.new()
		stack_label.add_theme_font_size_override("font_size", 18)
		stack_label.text = ("%s %d " % [status_id, stacks]) if icon == null else ("%d " % stacks)
		stack_label.tooltip_text = status_tooltip(status_id, stacks)
		stack_label.mouse_filter = Control.MOUSE_FILTER_PASS
		_status_row.add_child(stack_label)
	for loan: Dictionary in actor.loans:
		_add_loan_chip(loan)
	_add_passive_chip()
	_add_bonus_chip()
	_update_bonus_fx()
	modulate = Color.WHITE if actor.is_alive() else Color(0.35, 0.3, 0.3, 0.5)
	_refresh_mark()


## An enemy's passive, worn as the permanent buff it is (patch 0.113,
## designer's note: "enemy passives should appear as permanent buffs they
## have"). The plaque carries the passive's running number — the Dealer's
## 21 counting DOWN toward the bust, the Chip Golem's health-to-next-chip —
## and flashes on every tick so the countdown is legible in the fight.
const PASSIVE_TINTS := {
	"bust": Color(1.0, 0.78, 0.34),
	"break": Color(0.62, 0.86, 1.0),
	"loan": Color(0.86, 0.66, 1.0),
}


func _add_passive_chip() -> void:
	if actor == null or actor.is_hero:
		return
	var def := Db.content.get_enemy(actor.def_id)
	if def == null or def.passive.is_empty():
		return
	var kind := str(def.passive.get("type", ""))
	var tint: Color = PASSIVE_TINTS.get(kind, Color(0.9, 0.9, 0.95))
	var keyword := Db.content.get_keyword(StringName(kind))
	var text := keyword.text if keyword != null else "a passive this enemy always has"
	# The number in the tooltip is the DEF's, not the keyword's prose (0.117):
	# the Chip Golem went to "every 30" in the sheet and the tooltip kept
	# saying 20 for two patches. Break reads `every`, Bust `threshold`.
	var figure := int(def.passive.get("every", def.passive.get("threshold", 0)))
	if figure > 0:
		var keyword_figure := 21 if kind == "bust" else 20
		text = text.replace(str(keyword_figure), str(figure))
	var hint := "%s: %s" % [keyword.name if keyword != null else kind.capitalize(), text]
	var chip := PassiveChip.new()
	chip.custom_minimum_size = Vector2(50, 64) if kind != "loan" else Vector2(48, 48)
	chip.tint = tint
	chip.value = actor.passive_counter
	# Badge art per passive (0.117). The Loan Shark shows the badge alone:
	# "numbers in a square that serve no purpose for the player".
	var art: String = {"bust": "res://assets/icons/passive_bust.png",
		"break": "res://assets/icons/passive_break.png",
		"loan": LOAN_ICON}.get(kind, "")
	if art != "" and ResourceLoader.exists(art):
		chip.icon = load(art)
	chip.show_value = kind != "loan"
	chip.tooltip_text = hint
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	_status_row.add_child(chip)
	# It only pulses when the number actually moved, so a plain status refresh
	# does not set every enemy's plaque flashing.
	if _shown_passive >= 0 and _shown_passive != actor.passive_counter:
		chip.flash()
	_shown_passive = actor.passive_counter


## All In (designer, 0.121: "it has no special VFX to show that it's active").
## While the actor carries a damage bonus for the turn it wears an ember aura,
## a warm pulse and a "+30%" chip, all of which end with the bonus at the start
## of its next turn.
const BONUS_TINT := Color(1.0, 0.62, 0.22)
var _bonus_fx: CPUParticles2D = null
var _bonus_tween: Tween = null


func _add_bonus_chip() -> void:
	if actor == null or actor.damage_bonus_pct <= 0.0:
		return
	var percent := int(roundf(actor.damage_bonus_pct * 100.0))
	var hint := "All In: deal %d%% more damage until your next turn." % percent
	var icon := SuitAssets.status_texture(&"strength")
	if icon != null:
		var rect := TextureRect.new()
		rect.texture = icon
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.custom_minimum_size = Vector2(33, 33)
		rect.modulate = BONUS_TINT
		rect.tooltip_text = hint
		rect.mouse_filter = Control.MOUSE_FILTER_PASS
		_status_row.add_child(rect)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", BONUS_TINT)
	label.text = "+%d%% " % percent
	label.tooltip_text = hint
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	_status_row.add_child(label)


func is_empowered() -> bool:
	return _bonus_fx != null


func _update_bonus_fx() -> void:
	var active := actor != null and actor.is_alive() and actor.damage_bonus_pct > 0.0
	if not active:
		if _bonus_tween != null:
			_bonus_tween.kill()
			_bonus_tween = null
		if _bonus_fx != null:
			_bonus_fx.queue_free()
			_bonus_fx = null
		if _sprite != null:
			_sprite.self_modulate = Color.WHITE
		return
	if _bonus_fx != null or _sprite == null:
		return
	var embers := CPUParticles2D.new()
	embers.amount = 22
	embers.lifetime = 1.2
	embers.local_coords = false
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.emission_rect_extents = Vector2(sprite_height * SPRITE_WIDTH_RATIO * 0.32, 6.0)
	embers.position = Vector2(sprite_height * SPRITE_WIDTH_RATIO * 0.5, sprite_height * 0.9)
	embers.direction = Vector2(0, -1)
	embers.spread = 22.0
	embers.gravity = Vector2(0, -34)
	embers.initial_velocity_min = 45.0
	embers.initial_velocity_max = 110.0
	embers.scale_amount_min = 2.5
	embers.scale_amount_max = 5.0
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(1.0, 0.9, 0.5, 1.0), Color(1.0, 0.4, 0.12, 0.7),
		Color(0.8, 0.1, 0.05, 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	embers.color_ramp = ramp
	embers.emitting = true
	_sprite.add_child(embers)
	_bonus_fx = embers
	_bonus_tween = create_tween().set_loops()
	_bonus_tween.tween_property(_sprite, "self_modulate", Color(1.35, 0.88, 0.7), 0.55) \
		.set_trans(Tween.TRANS_SINE)
	_bonus_tween.tween_property(_sprite, "self_modulate", Color(1.05, 1.0, 1.0), 0.55) \
		.set_trans(Tween.TRANS_SINE)


## Doc "Loan": the debt shows as a scroll with the number of turns left on it,
## a different colour per loan, and a hover that names what happens at zero.
const LOAN_ICON := "res://assets/icons/status_loan.png"
const LOAN_TINTS := {
	&"pocket_change": Color(0.55, 0.78, 1.0),
	&"quick_patch": Color(0.55, 1.0, 0.7),
	&"double_stack": Color(0.85, 0.6, 1.0),
	&"house_doctor": Color(1.0, 0.85, 0.5),
	&"cash_advance": Color(1.0, 0.6, 0.55),
}


func _add_loan_chip(loan: Dictionary) -> void:
	var id := StringName(str(loan.get("id", "")))
	var def := Db.content.get_loan(id)
	var tint: Color = LOAN_TINTS.get(id, Color(0.8, 0.8, 0.9))
	var hint := "%s, in %d turn(s): %s" % [
		def.title if def else String(id).capitalize(),
		int(loan.get("turns_left", 0)),
		def.penalty_text if def else "the debt comes due"]
	if ResourceLoader.exists(LOAN_ICON):
		var icon := TextureRect.new()
		icon.texture = load(LOAN_ICON)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(33, 33)
		icon.modulate = tint
		icon.tooltip_text = hint
		icon.mouse_filter = Control.MOUSE_FILTER_PASS
		_status_row.add_child(icon)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", tint)
	label.text = "%d " % int(loan.get("turns_left", 0))
	label.tooltip_text = hint
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	_status_row.add_child(label)


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
	return title if body == "" else "%s: %s" % [title, body]


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
	wrapper.offset_left = -55.0
	wrapper.offset_right = 55.0
	wrapper.offset_top = -77.0
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
	_mark_glow_outer.reach = 57.0
	_mark_glow_outer.material = additive
	_mark_glow_outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark_glow_outer.position = MARK_ORIGIN
	_mark_glow_outer.visible = false
	wrapper.add_child(_mark_glow_outer)

	_mark_glow = CombatVfx.Glow.new()
	_mark_glow.glow_color = Color(0.4, 1.0, 0.8, 0.65)
	_mark_glow.reach = 40.0
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
	_mark_icon.size = Vector2(59, 59)
	_mark_icon.position = MARK_ORIGIN - Vector2(29.5, 29.5)
	_mark_icon.pivot_offset = Vector2(29.5, 29.5)
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
## display_instances (Strength/Multistrike/Rage-adjusted values).
## Icons belong on enemy intents, not player ability text (patch 0.17): each
## debuff/buff gets its status icon inline, ahead of its stack count.
func show_intent(entry: Dictionary) -> void:
	clear_intent()
	# A stunned unit will not act, so it announces nothing (0.121: "when the
	# Dealer is stunned, remove the attack icon above its head").
	if actor != null and actor.has_status(&"stun"):
		return
	var intent: Dictionary = entry.get("intent", {})
	for debuff: Dictionary in intent.get("debuffs", []):
		_add_intent_chunk(StringName(str(debuff.get("status", ""))),
			"%d" % int(debuff.get("stacks", 1)))
	for buff: Dictionary in intent.get("self_status", []):
		# No "+" in front of the number (patch 0.19): the icon already says
		# which way the buff goes, so the sign only added noise.
		_add_intent_chunk(StringName(str(buff.get("status", ""))),
			"%d" % int(buff.get("stacks", 1)))
	if not intent.get("summon", {}).is_empty():
		# Patch 0.18: a summon reads as an icon like every other intent, not
		# as bare text in the middle of the icon row.
		_add_intent_chunk(&"summon",
			"x%d" % int(intent.get("summon").get("count", 1)))
	if intent.get("heal_allies", 0) > 0:
		_add_intent_chunk(&"heal_allies", "%d" % int(intent.get("heal_allies")))
	# Its own heal is part of the move too (0.122: the Drunk Patron's Liquid
	# Courage healed and never said so above its head).
	if int(intent.get("self_heal", 0)) > 0:
		_add_intent_chunk(&"heal", "%d" % int(intent.get("self_heal")))
	if intent.get("ally_attack_again", false):
		_add_intent_chunk(&"encore", "")
	if int(intent.get("self_block", 0)) > 0:
		_add_intent_chunk(&"block", "%d" % int(intent.get("self_block")))
	if int(intent.get("gift_chips", 0)) > 0:
		_add_intent_chunk(&"gift", "%d" % int(intent.get("gift_chips")))
	if intent.get("absorb", false):
		_add_intent_chunk(&"absorb", "")
	var instances := int(entry.get("display_instances", intent.get("instances", 0)))
	var per_hit := int(entry.get("display_per_hit", intent.get("per_hit", 0)))
	if instances > 1:
		_add_intent_chunk(&"attack", "%dx%d" % [instances, per_hit])
	elif instances == 1:
		_add_intent_chunk(&"attack", "%d" % per_hit)


## Non-status intent parts that still deserve an icon + a hover explanation.
const INTENT_ICONS := {
	&"attack": "res://assets/icons/intent_attack.png",
	&"gift": "res://assets/icons/chip_spade.png",
	&"absorb": "res://assets/icons/fx_explosion.png",
	&"summon": "res://assets/icons/intent_summon.png",
	&"heal_allies": "res://assets/icons/fx_heal.png",
	&"heal": "res://assets/icons/fx_heal.png",
	&"encore": "res://assets/icons/keyword_go_again.png",
}
const INTENT_HINTS := {
	&"attack": "Attack: [instances] x [damage per hit].",
	&"gift": "Gift: you receive this many random chips next turn.",
	&"absorb": "Absorb: every chip you have placed on an ability is taken.",
	&"summon": "Summon: brings new enemies onto the field.",
	&"heal_allies": "Heal Allies: restores health to every living enemy.",
	&"heal": "Heal: this enemy restores its own health.",
	&"encore": "Encore: another enemy attacks a second time.",
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
		icon.custom_minimum_size = Vector2(33, 33)
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
		strike_landed.emit()
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
	strike_landed.emit()
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
		strike_landed.emit()
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
	strike_landed.emit()
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
		strike_landed.emit()
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
	strike_landed.emit()
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


## The name/health panel, for a tutorial arrow to point at.
func hp_panel() -> Control:
	return _hp_holder


## Shoulders and head, with the intent row above them (global rect): what the
## tutorial leaves lit when it talks about what the enemy is about to do.
func head_rect() -> Rect2:
	var sprite_rect := _sprite.get_global_rect()
	var rect := Rect2(sprite_rect.position.x, sprite_rect.position.y,
		sprite_rect.size.x, sprite_rect.size.y * 0.36)
	return rect.merge(_intent_row.get_global_rect())


func sprite_center() -> Vector2:
	return _sprite.global_position + _sprite.size * 0.5


## The HP the bar is currently SHOWING — which trails the actor's real HP
## during a multi-hit attack (see apply_damage_display).
func shown_hp() -> int:
	return int(_hp_bar.value)


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
	tween.tween_property(target, "position:x", _base_sprite_position.x + 22.0 * direction, 0.06)
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


## Block gained, from ANY source (patch 0.114): a golden shield sweeps up over
## the unit and the HP panel pulses blue.
##
## The event was always emitted and the old cue was always played — but at a
## round start the relic/passive grants land a beat BEFORE the reels spin, so a
## small icon that faded in 0.4 s was over while the player was still watching
## the machine. This is slower, larger, and lands on the unit itself, so it
## reads wherever the block came from.
func play_block_gain(amount: int) -> void:
	if amount <= 0:
		return
	var shield := BlockFlash.new()
	shield.set_anchors_preset(Control.PRESET_FULL_RECT)
	shield.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shield.z_index = 40
	add_child(shield)
	var rise := create_tween()
	rise.set_parallel(true)
	rise.tween_method(func(v: float) -> void: shield.progress = v, 0.0, 1.0, 0.42) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	rise.chain().tween_method(func(v: float) -> void: shield.fade = v, 1.0, 0.0, 0.26)
	rise.chain().tween_callback(shield.queue_free)
	# The panel answers too, so the number and the effect are one event.
	if _hp_holder != null:
		var pulse := create_tween()
		pulse.tween_property(_hp_holder, "modulate", Color(0.72, 0.9, 1.15), 0.10)
		pulse.tween_property(_hp_holder, "modulate", Color.WHITE, 0.34)


func _process(delta: float) -> void:
	if _breath == null or actor == null or not actor.is_alive():
		return
	_breath_phase = fposmod(_breath_phase + delta * TAU / BREATH_PERIOD, TAU)
	_breath.position.y = sin(_breath_phase) * BREATH_PX


## Stun (patch 0.113, designer's note: "stun should have a stun animation").
## The unit's head snaps aside from the blow, then sways where it stands while
## a ring of stars orbits over it — the classic read, so a skipped enemy turn
## is obviously a stun and not the game losing track of a move.
func play_stun(duration: float = 1.5) -> void:
	var target: Control = _sprite if _sprite.texture != null else _fallback
	var stars := StunStars.new()
	stars.set_anchors_preset(Control.PRESET_TOP_WIDE)
	# Above the head rather than over the face: anchored to the sprite's own
	# rect, so it follows the wobble instead of hovering next to it.
	stars.offset_top = -30.0
	stars.offset_bottom = 52.0
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target.add_child(stars)
	var spin := create_tween()
	spin.tween_method(func(v: float) -> void: stars.phase = v, 0.0, TAU * 2.0, duration)
	var out := create_tween()
	out.tween_interval(duration * 0.66)
	out.tween_method(func(v: float) -> void: stars.fade = v, 1.0, 0.0, duration * 0.34)
	out.tween_callback(stars.queue_free)
	var sway := create_tween()
	sway.tween_property(target, "rotation", 0.17, 0.09) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	sway.tween_property(target, "rotation", -0.11, 0.36).set_trans(Tween.TRANS_SINE)
	sway.tween_property(target, "rotation", 0.07, 0.36).set_trans(Tween.TRANS_SINE)
	sway.tween_property(target, "rotation", 0.0, 0.3) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Attack: anticipation (pull back and coil), then a snapping strike lunge
## with follow-through overshoot — no more polite drifting.
func play_lunge() -> void:
	var origin := _sprite.position
	var direction := 1.0 if actor.is_hero else -1.0
	var tween := create_tween()
	# Wind-up: pull away and crouch...
	tween.set_parallel(true)
	tween.tween_property(_sprite, "position:x", origin.x - 24.0 * direction, 0.14) \
		.set_ease(Tween.EASE_OUT)
	tween.tween_property(_sprite, "scale", Vector2(0.94, 1.05), 0.14)
	# ...snap forward...
	tween.chain().tween_property(_sprite, "position:x", origin.x + 77.0 * direction, 0.08) \
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


## Ace's own death (0.121: "add a player death animation"): he is not an
## enemy cashing out, so no blowout and no fade. He reels from the killing
## blow, drops to his knees, falls backwards away from the line and stays
## down, greyed. Returns when he is on the floor, so the caller can hold the
## banner until then. The caller waits for the killing blow's own animation
## before calling it.
func play_hero_death() -> void:
	_update_bonus_fx()
	var back := -1.0 if actor.is_hero else 1.0
	if _sprite.material is ShaderMaterial:
		_sprite.material.set_shader_parameter("flash", 0.8)
		var flash := create_tween()
		flash.tween_method(func(v: float) -> void:
			_sprite.material.set_shader_parameter("flash", v), 0.8, 0.0, 0.3)
	var origin := _sprite.position
	var tween := create_tween()
	# Reel from the blow.
	tween.tween_property(_sprite, "position:x", origin.x + 16.0 * back, 0.14) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Down on the knees.
	tween.tween_property(_sprite, "scale", Vector2(1.06, 0.8), 0.28) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Over backwards, pivoting on the feet, and the colour drains as he goes.
	tween.set_parallel(true)
	tween.tween_property(_sprite, "rotation", 1.45 * back, 0.55) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_sprite, "position:x", origin.x + 34.0 * back, 0.55)
	tween.tween_property(_sprite, "scale", Vector2(1.0, 0.92), 0.55)
	tween.tween_property(_sprite, "modulate", Color(0.62, 0.56, 0.66, 1.0), 0.6)
	# A small bounce as he lands.
	tween.chain().tween_property(_sprite, "rotation", 1.37 * back, 0.1) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(_sprite, "rotation", 1.45 * back, 0.14) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(actor.id)
