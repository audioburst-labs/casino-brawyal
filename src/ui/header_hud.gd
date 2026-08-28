class_name HeaderHud
extends Control
## Persistent run header (doc's "Screen UI"): Relics top-left, and
## Timer / Layout Tab / Settings icons top-right, left to right in that
## order. Lives in HudLayer so it survives every screen swap.

var _relics_row: HBoxContainer
var _right_row: HBoxContainer
var _timer_label: Label
var _last_relic_count := -1


static func attach(main_node: Node) -> HeaderHud:
	var hud := HeaderHud.new()
	main_node.get_node("HudLayer").add_child(hud)
	return hud


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_relics_row = HBoxContainer.new()
	_relics_row.position = Vector2(20, 16)
	_relics_row.add_theme_constant_override("separation", 8)
	add_child(_relics_row)

	_right_row = HBoxContainer.new()
	_right_row.add_theme_constant_override("separation", 12)
	add_child(_right_row)
	var right := _right_row

	_timer_label = Label.new()
	_timer_label.theme_type_variation = &"SubtitleLabel"
	_timer_label.text = "00:00"
	right.add_child(_timer_label)

	var layout_button := Button.new()
	layout_button.text = "🎰"
	layout_button.tooltip_text = "Layout"
	layout_button.pressed.connect(_open_layout_tab)
	right.add_child(layout_button)

	var settings_button := Button.new()
	settings_button.text = "⚙"
	settings_button.tooltip_text = "Settings"
	settings_button.pressed.connect(_open_settings_tab)
	right.add_child(settings_button)


func _process(delta: float) -> void:
	visible = Game.run != null
	if not visible:
		return
	if not Game.cinematic_playing:
		Game.run_elapsed_sec += delta
	var total := int(Game.run_elapsed_sec)
	_timer_label.text = "%02d:%02d" % [total / 60, total % 60]
	if Game.run.relic_ids.size() != _last_relic_count:
		_refresh_relics()
	# Anchoring a right-hugging row without a known content width fights
	# Godot's anchor math (it collapses to zero/negative width) — simplest
	# robust fix is to just reposition it against its own computed size.
	_right_row.position = Vector2(
		get_viewport_rect().size.x - _right_row.size.x - 20, 14)


func _refresh_relics() -> void:
	_last_relic_count = Game.run.relic_ids.size()
	for child in _relics_row.get_children():
		child.queue_free()
	for relic_id in Game.run.relic_ids:
		var relic := Db.content.get_relic(relic_id)
		if relic == null:
			continue
		var icon_path := "res://assets/icons/relic_%s.png" % relic_id
		if ResourceLoader.exists(icon_path):
			var icon := TextureRect.new()
			icon.texture = load(icon_path)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(48, 48)
			icon.tooltip_text = "%s — %s" % [relic.name, relic.description]
			icon.mouse_filter = Control.MOUSE_FILTER_STOP
			_relics_row.add_child(icon)


func _open_layout_tab() -> void:
	if get_parent().get_node_or_null("LayoutTabOverlay") != null:
		return
	var overlay := LayoutTab.new()
	overlay.name = "LayoutTabOverlay"
	get_parent().add_child(overlay)


func _open_settings_tab() -> void:
	if get_parent().get_node_or_null("SettingsTabOverlay") != null:
		return
	var overlay := SettingsTab.new()
	overlay.name = "SettingsTabOverlay"
	get_parent().add_child(overlay)
