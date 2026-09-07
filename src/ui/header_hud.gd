class_name HeaderHud
extends Control
## Persistent run header (doc's "Screen UI"): Relics top-left, and
## Timer / Layout Tab / Settings icons top-right, left to right in that
## order. Lives in HudLayer so it survives every screen swap.

const BAR_HEIGHT := 64.0
const EDGE_PAD := 22.0
const ICON_SIZE := 40.0
const BUTTON_SIZE := Vector2(46, 40)

## Screens outside an active run — the header has no business appearing on
## these even though Game.run may still be holding the just-finished run's
## data for their own summary text (patch 0.17).
const HIDDEN_SCREENS := [
	"res://scenes/screens/main_menu.tscn",
	"res://scenes/screens/game_over_screen.tscn",
	"res://scenes/screens/victory_screen.tscn",
]

var _bar: Control
var _relics_row: HBoxContainer
var _right_row: HBoxContainer
var _timer_label: Label
var _coins_label: Label
var _encounter_label: Label
var _last_relic_count := -1


## A distinct bolded bar behind the header content (patch 0.17 — "like in
## Slay the Spire"): a dark banded panel with a gold trim line along its
## bottom edge, instead of text floating directly on the scene art.
class Bar:
	extends Control

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.04, 0.05, 0.82))
		draw_rect(Rect2(Vector2(0, size.y - 3), Vector2(size.x, 3)),
			Color(0.83, 0.69, 0.22, 0.9))


static func attach(main_node: Node) -> HeaderHud:
	var hud := HeaderHud.new()
	main_node.get_node("HudLayer").add_child(hud)
	return hud


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_bar = Bar.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)

	# Both groups are laid out as rows of one common height and centred
	# against the bar, so nothing in the header sits at a different baseline
	# from its neighbours (patch 0.18).
	_relics_row = HBoxContainer.new()
	_relics_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_relics_row.add_theme_constant_override("separation", 10)
	add_child(_relics_row)

	_right_row = HBoxContainer.new()
	_right_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_right_row.add_theme_constant_override("separation", 16)
	add_child(_right_row)
	var right := _right_row

	# Gold and the encounter number belong on this row too (patch 0.18);
	# they used to float on their own line under the bar on the combat screen.
	_coins_label = _header_label("")
	_coins_label.tooltip_text = "Gold"
	right.add_child(_coins_label)

	_encounter_label = _header_label("")
	_encounter_label.tooltip_text = "Encounter"
	right.add_child(_encounter_label)

	_timer_label = _header_label("00:00")
	_timer_label.tooltip_text = "Run time"
	right.add_child(_timer_label)

	right.add_child(_header_button("🎰", "Layout", _open_layout_tab))
	right.add_child(_header_button("⚙", "Settings", _open_settings_tab))


static func _header_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"SubtitleLabel"
	label.add_theme_font_size_override("font_size", 24)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(0, BUTTON_SIZE.y)
	return label


static func _header_button(text: String, hint: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = hint
	button.custom_minimum_size = BUTTON_SIZE
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(action)
	return button


func _process(delta: float) -> void:
	visible = Game.run != null and not HIDDEN_SCREENS.has(Game.current_screen_path)
	if not visible:
		return
	if not Game.cinematic_playing:
		Game.run_elapsed_sec += delta
	var total := int(Game.run_elapsed_sec)
	_timer_label.text = "%02d:%02d" % [total / 60, total % 60]
	_coins_label.text = "🪙 %d" % Game.run.coins
	_encounter_label.text = "Encounter %d/10" % clampi(Game.run.history.size(), 1, 10)
	if Game.run.relic_ids.size() != _last_relic_count:
		_refresh_relics()
	var view_width := get_viewport_rect().size.x
	_bar.size = Vector2(view_width, BAR_HEIGHT)
	# Anchoring rows without a known content width fights Godot's anchor math
	# (it collapses to zero/negative width) — position them against their own
	# measured size instead, vertically centred in the bar.
	_relics_row.position = Vector2(EDGE_PAD,
		(BAR_HEIGHT - _relics_row.size.y) * 0.5)
	_right_row.position = Vector2(view_width - _right_row.size.x - EDGE_PAD,
		(BAR_HEIGHT - _right_row.size.y) * 0.5)


func _refresh_relics() -> void:
	_last_relic_count = Game.run.relic_ids.size()
	for child in _relics_row.get_children():
		child.queue_free()
	for relic_id in Game.run.relic_ids:
		var relic := Db.content.get_relic(relic_id)
		if relic == null:
			continue
		var icon := TextureRect.new()
		icon.texture = SuitAssets.relic_texture(relic_id)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
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
