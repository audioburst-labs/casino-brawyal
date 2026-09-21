class_name HeaderHud
extends Control
## Persistent run header (doc's "Screen UI"): Ace's portrait and HP, then
## Relics, top-left (the Slay the Spire reference bar, 0.0.111); Gold /
## Encounter / Timer / Layout Tab / Settings top-right, left to right in that
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
var _hp_label: Label
var _last_relic_count := -1


## Ace's face in a gold-rimmed medallion: the portrait art drawn through a
## circular polygon with UVs cropped to the face, so no mask shader is needed.
class Portrait:
	extends Control
	const SEGMENTS := 48
	const UV_CENTRE := Vector2(0.5, 0.40)   # where the face sits in the portrait
	const UV_RADIUS := 0.30
	var texture: Texture2D = null

	func _draw() -> void:
		var centre := size * 0.5
		var radius := minf(size.x, size.y) * 0.5 - 2.0
		if texture != null:
			var points := PackedVector2Array()
			var uvs := PackedVector2Array()
			var colors := PackedColorArray()
			for i in SEGMENTS:
				var angle := TAU * float(i) / SEGMENTS
				var dir := Vector2(cos(angle), sin(angle))
				points.append(centre + dir * radius)
				uvs.append(UV_CENTRE + dir * UV_RADIUS)
				colors.append(Color.WHITE)
			draw_polygon(points, colors, uvs, texture)
		else:
			draw_circle(centre, radius, Color(0.25, 0.1, 0.12))
		draw_arc(centre, radius + 0.5, 0, TAU, SEGMENTS, Color(0.83, 0.69, 0.22, 0.95), 3.0, true)


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

	# Portrait and health lead the left group (0.0.111): health used to be
	# invisible everywhere outside a fight.
	var portrait := Portrait.new()
	portrait.custom_minimum_size = Vector2(46, 46)
	portrait.tooltip_text = "Ace"
	var portrait_path := "res://assets/characters/ace_portrait.png"
	if ResourceLoader.exists(portrait_path):
		portrait.texture = load(portrait_path)
	_relics_row.add_child(portrait)
	# The heart and its number are one unit with a tight gap of their own
	# (patch 0.113: "HP numbers should sit adjacent to the heart icon"), not
	# two items separated by the row's 10 px.
	var health_box := HBoxContainer.new()
	health_box.add_theme_constant_override("separation", 5)
	health_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_relics_row.add_child(health_box)
	var heart := TextureRect.new()
	var heart_path := "res://assets/icons/icon_health.png"
	if ResourceLoader.exists(heart_path):
		heart.texture = load(heart_path)
	heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	heart.custom_minimum_size = Vector2(30, 30)
	heart.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heart.tooltip_text = "Health"
	health_box.add_child(heart)
	_hp_label = _header_label("")
	_hp_label.tooltip_text = "Health"
	_hp_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55))
	health_box.add_child(_hp_label)
	var divider := VSeparator.new()
	divider.custom_minimum_size = Vector2(4, 34)
	divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_relics_row.add_child(divider)
	_relics_row.set_meta("fixed_children", _relics_row.get_child_count())

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

	_reserve_number_widths.call_deferred()


static func _header_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"SubtitleLabel"
	label.add_theme_font_size_override("font_size", 24)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(0, BUTTON_SIZE.y)
	return label


## Every number in the header gets a FIXED column wide enough for its widest
## reading, right-aligned inside it (patch 0.22: "UI elements slightly shift
## due to the numbers on the timer ticking"). The display font is Alfa Slab
## One, whose digits are proportional - "1" is narrower than "0" - and both
## header rows are positioned every frame from their own measured width, so
## 00:01 -> 00:11 used to drag every sibling sideways once a second.
##
## Deferred because a Label only resolves its theme font once it is inside the
## tree; measured off an orphan it returns the plain default (patch 0.18).
func _reserve_number_widths() -> void:
	var digit := _widest_digit(_timer_label)
	_reserve(_timer_label, "%s%s:%s%s" % [digit, digit, digit, digit])
	_reserve(_coins_label, "🪙 %s" % digit.repeat(4))
	_reserve(_encounter_label, "Encounter %s%s/10" % [digit, digit])
	# Left-aligned: right-aligning it inside a "999/999" column parked a
	# two-digit reading at the far end, a thumb's width from the heart.
	_reserve(_hp_label, "%s/%s" % [digit.repeat(3), digit.repeat(3)],
		HORIZONTAL_ALIGNMENT_LEFT)


## Alfa Slab One has no tabular figures, so the widest glyph is measured
## rather than assumed.
static func _widest_digit(label: Label) -> String:
	var font := label.get_theme_font("font")
	if font == null:
		return "0"
	var size := label.get_theme_font_size("font_size")
	var widest := "0"
	var best := 0.0
	for value in 10:
		var glyph := str(value)
		var width := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		if width > best:
			best = width
			widest = glyph
	return widest


static func _reserve(label: Label, widest: String,
		align := HORIZONTAL_ALIGNMENT_RIGHT) -> void:
	label.horizontal_alignment = align
	var font := label.get_theme_font("font")
	if font == null:
		return
	var size := label.get_theme_font_size("font_size")
	label.custom_minimum_size.x = ceilf(
		font.get_string_size(widest, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x) + 2.0


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
	# During a fight the combat screen publishes what Ace's own panel shows,
	# because run.hp is only written back when the fight ends.
	var hp := Game.live_hp if Game.live_hp >= 0 else Game.run.hp
	_hp_label.text = "%d/%d" % [hp, Game.run.max_hp]
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
	# The portrait, heart, HP and divider lead the row and stay put; only the
	# relic icons after them are rebuilt.
	var fixed: int = _relics_row.get_meta("fixed_children", 0)
	var children := _relics_row.get_children()
	for index in range(fixed, children.size()):
		_relics_row.remove_child(children[index])
		children[index].queue_free()
	for relic_id in Game.run.relic_ids:
		var relic := Db.content.get_relic(relic_id)
		if relic == null:
			continue
		var icon := TextureRect.new()
		icon.texture = SuitAssets.relic_texture(relic_id)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		icon.tooltip_text = "%s: %s" % [relic.name, relic.description]
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
