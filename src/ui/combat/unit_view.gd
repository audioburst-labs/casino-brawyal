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


## Blue ring around the model + a glow on the stats box (patch 0.13).
func set_targeted(targeted: bool) -> void:
	_target_ring.visible = targeted
	_hp_holder.modulate = Color(0.75, 1.05, 1.45) if targeted else Color.WHITE


func sprite_center() -> Vector2:
	return _sprite.global_position + _sprite.size * 0.5


func play_hit() -> void:
	var target: Control = _sprite if _sprite.texture != null else _fallback
	if _base_sprite_position == Vector2.ZERO:
		_base_sprite_position = target.position
	var tween := create_tween()
	target.modulate = Color(3.0, 1.2, 1.2)
	tween.tween_property(target, "modulate", Color.WHITE, 0.25)
	tween.parallel().tween_property(target, "position:x", _base_sprite_position.x + 14.0, 0.06)
	tween.tween_property(target, "position:x", _base_sprite_position.x, 0.18) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func play_lunge() -> void:
	# Animate a wrapper-independent offset via the sprite's pivot-safe
	# position, always restoring the exact captured origin so container
	# re-layouts can't leave the sprite drifted (patch 0.1 fix).
	var origin := _sprite.position
	var direction := 1.0 if actor.is_hero else -1.0
	var tween := create_tween()
	tween.tween_property(_sprite, "position:x", origin.x + 46.0 * direction, 0.1) \
		.set_ease(Tween.EASE_OUT)
	tween.tween_property(_sprite, "position", origin, 0.22) \
		.set_ease(Tween.EASE_IN_OUT)


func play_death() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(0.35, 0.3, 0.3, 0.5), 0.5)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(actor.id)
