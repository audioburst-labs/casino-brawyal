class_name AbilityCard
extends PanelContainer
## One ability on the bar: icon, name, description text, and cost sockets.
## All cards share one fixed size. Chips arrive by click (select chip, click
## socket) or drag-and-drop. Hovering shows keyword bubbles above the card
## immediately (patch 0.1).

signal socket_clicked(ability_index: int, slot_index: int)
signal chip_dropped(ability_index: int, slot_index: int, suit: StringName)

## Patch 0.18: a taller, slightly wider constant frame, and a description
## band of a FIXED height whose font shrinks to fit — the old card clipped
## longer ability text against its own border.
const CARD_SIZE := Vector2(190, 300)
const SOCKET_SIZE := 46.0
const DESC_HEIGHT := 64.0
const DESC_FONT_MAX := 17
const DESC_FONT_MIN := 11

var ability_index := -1

var _state: AbilityState
var _sim: CombatSim = null
var _sockets: Array[Button] = []
var _socket_faces: Array[TextureRect] = []
var _socket_labels: Array[Label] = []
var _description: RichTextLabel
var _highlight_suit: StringName = &""
var _keyword_panel: PanelContainer = null
var _glowing := false
var _glow_phase := 0.0


class SocketButton:
	extends Button
	var card: AbilityCard
	var slot := 0

	## A socket is heard through `chip_assigned`, not as a button click.
	func _init() -> void:
		set_meta(&"silent", true)

	func _can_drop_data(_position: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("suit") \
			and card.accepts_chip(slot, data.suit)

	func _drop_data(_position: Vector2, data: Variant) -> void:
		card.chip_dropped.emit(card.ability_index, slot, data.suit)


func accepts_chip(slot: int, suit: StringName) -> bool:
	return not _state.exhausted() and _state.can_accept(slot, suit)


## Doc "Chip Placement on Abilities" (0.117): a chip dropped on the CARD, not
## on a socket, goes to the slot that asks for its suit first, else the
## leftmost open generic slot. The socket buttons keep their own exact-slot
## drop, so aiming still works; this is the forgiving path around them.
func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary and data.has("suit")) or _state == null:
		return false
	return not _state.exhausted() and _state.placement_slot(data.suit) >= 0


func _drop_data(_position: Vector2, data: Variant) -> void:
	var slot := _state.placement_slot(data.suit)
	if slot >= 0:
		chip_dropped.emit(ability_index, slot, data.suit)


## The cost as suit ART rather than letters (designer, 0.117: "show the Heart
## symbol itself, not the letter H"). Shared by the reward screen, the shop
## and the loadout so every list agrees with the card.
static func cost_row(def: Defs.AbilityDef, side := 26.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for suit: StringName in def.cost:
		var face := TextureRect.new()
		face.custom_minimum_size = Vector2(side, side)
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# The same ghost art the combat card's empty socket wears, so "any"
		# is the four-suit cluster here as well.
		face.texture = SuitAssets.suit_texture(suit)
		if face.texture == null:
			# No art for this suit: a small labelled disc rather than nothing.
			var label := Label.new()
			label.text = "?" if suit == &"any" else String(suit).left(1).to_upper()
			label.add_theme_font_size_override("font_size", int(side * 0.6))
			label.custom_minimum_size = Vector2(side, side)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			row.add_child(label)
			continue
		face.tooltip_text = "Any suit" if suit == &"any" else String(suit).capitalize()
		row.add_child(face)
	return row


## The use-limit pills, for lists outside combat (designer, 0.117: "all
## appearances of abilities should show whether they are once per turn or
## once per fight"). Empty when the ability has no limit.
static func limits_row(def: Defs.AbilityDef) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if def.per_turn > 0:
		row.add_child(_limit_pill("%d Per Turn" % def.per_turn, PER_TURN_FILL,
			"Usable %d time(s) each turn." % def.per_turn))
	if def.per_combat > 0:
		row.add_child(_limit_pill("%d Per Fight" % def.per_combat, PER_FIGHT_FILL,
			"Usable %d time(s) this fight, and never refreshed between turns."
			% def.per_combat))
	return row


## The doc's two indicator colours: lavender for a per-turn cap, peach for a
## per-fight one, both with dark text so they read against the card art.
const PER_TURN_FILL := Color(0.63, 0.51, 0.81)
const PER_FIGHT_FILL := Color(0.96, 0.79, 0.63)
const PILL_TEXT := Color(0.13, 0.09, 0.15)


static func _limit_pill(text: String, fill: Color, hint: String) -> PanelContainer:
	var pill := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	# Rounded everywhere except where it meets the card's own top-right corner.
	box.corner_radius_top_left = 9
	box.corner_radius_bottom_left = 9
	box.corner_radius_bottom_right = 9
	box.corner_radius_top_right = 11
	box.content_margin_left = 9.0
	box.content_margin_right = 9.0
	box.content_margin_top = 2.0
	box.content_margin_bottom = 3.0
	pill.add_theme_stylebox_override("panel", box)
	pill.tooltip_text = hint
	pill.mouse_filter = Control.MOUSE_FILTER_PASS
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", PILL_TEXT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(label)
	return pill


func setup(state: AbilityState, index: int, sim: CombatSim = null) -> void:
	_state = state
	_sim = sim
	ability_index = index
	custom_minimum_size = CARD_SIZE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pivot_offset = Vector2(CARD_SIZE.x * 0.5, CARD_SIZE.y)
	mouse_entered.connect(_on_hover_entered)
	mouse_exited.connect(_on_hover_exited)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	var icon_holder := CenterContainer.new()
	icon_holder.custom_minimum_size = Vector2(0, 58)
	box.add_child(icon_holder)
	var icon_texture := SuitAssets.ability_texture(_state.def.id)
	if icon_texture != null:
		var icon := TextureRect.new()
		icon.texture = icon_texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(70, 70)
		icon_holder.add_child(icon)

	var name_label := Label.new()
	name_label.text = _state.def.name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_label.theme_type_variation = &"SubtitleLabel"
	name_label.add_theme_font_size_override("font_size", 22)
	box.add_child(name_label)

	_description = RichTextLabel.new()
	_description.bbcode_enabled = true
	_description.fit_content = false
	_description.scroll_active = false
	_description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_description.add_theme_font_size_override("normal_font_size", DESC_FONT_MAX)
	_description.add_theme_color_override("default_color", Color(0.9, 0.86, 0.78))
	_description.custom_minimum_size = Vector2(0, DESC_HEIGHT)
	_description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_description)

	# Upgrade tier (v0.19): the card re-trims silver or gold and carries a pip.
	# The tier comes from the def the sim resolved, so the card cannot disagree
	# with what the ability actually does this combat.
	if _state.def.tier > 0:
		add_theme_stylebox_override("panel", TierStyle.panel(_state.def.tier))
		var pip := Label.new()
		pip.text = TierStyle.pips(_state.def.tier)
		pip.add_theme_font_size_override("font_size", 15)
		pip.add_theme_color_override("font_color", TierStyle.color(_state.def.tier))
		pip.tooltip_text = "%s tier" % TierStyle.label(_state.def.tier)
		pip.mouse_filter = Control.MOUSE_FILTER_PASS
		pip.position = Vector2(9, 5)
		var pip_overlay := Control.new()
		pip_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(pip_overlay)
		pip_overlay.add_child(pip)

	# Use limits (doc "Per Turn & Per Combat", patch 0.113): a pill in the
	# card's top-right corner naming the limit and how many uses it allows,
	# stacked when an ability is capped both ways. It replaces the 0.13 icon
	# badge, which said "limited" without saying limited to WHAT, and showed
	# nothing at all for the per-fight abilities (House Edge, Face Reader).
	if _state.def.per_turn > 0 or _state.def.per_combat > 0:
		var limits := Control.new()
		limits.set_anchors_preset(Control.PRESET_FULL_RECT)
		limits.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(limits)
		var pills := VBoxContainer.new()
		pills.add_theme_constant_override("separation", 3)
		pills.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		# Flush with the card's right edge, growing leftward and downward, so a
		# long reading can never push the pill off the card.
		pills.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		pills.mouse_filter = Control.MOUSE_FILTER_IGNORE
		limits.add_child(pills)
		if _state.def.per_turn > 0:
			pills.add_child(_limit_pill(
				"%d Per Turn" % _state.def.per_turn, PER_TURN_FILL,
				"Usable %d time(s) each turn." % _state.def.per_turn))
		if _state.def.per_combat > 0:
			pills.add_child(_limit_pill(
				"%d Per Fight" % _state.def.per_combat, PER_FIGHT_FILL,
				"Usable %d time(s) this fight, and never refreshed between turns."
				% _state.def.per_combat))

	# Socket rows: odd costs of 5+ put 2 on top, the rest in rows of 3
	# (patch 0.13); otherwise up to 3 per centered row.
	var socket_box := VBoxContainer.new()
	socket_box.alignment = BoxContainer.ALIGNMENT_CENTER
	socket_box.add_theme_constant_override("separation", 5)
	box.add_child(socket_box)
	var rows := _socket_rows(_state.def.cost.size())
	var socket_rows: Array[HBoxContainer] = []
	for row_size in rows:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 5)
		socket_box.add_child(row)
		socket_rows.append(row)
	var row_index := 0
	var placed_in_row := 0
	var socket_row: HBoxContainer = socket_rows[0]
	var socket_style := StyleBoxFlat.new()
	socket_style.bg_color = Color(0.94, 0.9, 0.8)
	socket_style.border_color = Color(0.83, 0.69, 0.22)
	socket_style.set_border_width_all(2)
	socket_style.set_corner_radius_all(10)
	for slot in _state.def.cost.size():
		if placed_in_row >= int(rows[row_index]):
			row_index += 1
			placed_in_row = 0
			socket_row = socket_rows[row_index]
		placed_in_row += 1
		var socket := SocketButton.new()
		socket.card = self
		socket.slot = slot
		socket.custom_minimum_size = Vector2(SOCKET_SIZE, SOCKET_SIZE)
		for style_name in ["normal", "hover", "pressed", "disabled"]:
			socket.add_theme_stylebox_override(style_name, socket_style)
		socket.pressed.connect(_on_socket_pressed.bind(slot))
		socket_row.add_child(socket)
		_sockets.append(socket)
		var face := TextureRect.new()
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		face.set_anchors_preset(Control.PRESET_FULL_RECT)
		face.offset_left = 6
		face.offset_top = 6
		face.offset_right = -6
		face.offset_bottom = -6
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		socket.add_child(face)
		_socket_faces.append(face)
		var fallback := Label.new()
		fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.add_theme_color_override("font_color", Color(0.35, 0.25, 0.2))
		fallback.add_theme_font_size_override("font_size", 22)
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		socket.add_child(fallback)
		_socket_labels.append(fallback)
	refresh()


## Whether this ability's condition is live right now (doc "Glow"):
##   - Cash In, while any enemy carries the Mark
##   - a Weak-synergy skill, while an eligible Weak target exists
## "Knights" is in the doc's list too, but no Knight exists in the game yet.
static func wants_glow(def: Defs.AbilityDef, sim: CombatSim) -> bool:
	if def == null or sim == null:
		return false
	var marked := false
	var weakened := false
	for enemy in sim.enemies:
		if not enemy.is_alive():
			continue
		marked = marked or enemy.has_status(&"mark")
		weakened = weakened or enemy.has_status(&"weak")
	if marked and _mentions(def, ["cash_in"], []):
		return true
	if weakened and _mentions(def, [], ["target_weak", "any_enemy_weak"]):
		return true
	return false


## Walks the whole effect tree - a Cash In can sit nested inside another op,
## and a condition can sit on any leaf.
static func _mentions(def: Defs.AbilityDef, ops: Array, conditions: Array) -> bool:
	var stacks: Array[Array] = [def.effects, def.bonus_effects, def.active_effects]
	for effects: Array in stacks:
		if _walk(effects, ops, conditions):
			return true
	return false


static func _walk(effects: Array, ops: Array, conditions: Array) -> bool:
	for effect: Dictionary in effects:
		if ops.has(str(effect.get("op", ""))):
			return true
		if conditions.has(str(effect.get("condition", ""))):
			return true
		for nested: String in ["effects", "else_effects"]:
			if effect.has(nested) and _walk(effect[nested], ops, conditions):
				return true
	return false


## Socket `i`'s button, for the debug driver that drops through the real GUI.
func socket_button(i: int) -> Button:
	return _sockets[i] if i >= 0 and i < _sockets.size() else null


## The def this card is showing, for callers that need to ask about it.
func ability_def() -> Defs.AbilityDef:
	return _state.def if _state != null else null


## Turns the aura on or off. Cheap to call on every refresh: it only flips a
## flag and starts or stops the idle tick.
##
## Patch 0.116: the aura is drawn by the card ITSELF, not by a child node.
## `AbilityCard` is a `PanelContainer`, and a container lays out every child
## into its inner content rect, so the 0.115 `GlowRing` was clamped inside the
## card and then hidden outright behind the panel's own opaque background by
## `show_behind_parent`. It was built correctly on every qualifying card and
## painted where nothing could see it. Drawing it here sidesteps the layout
## entirely: a Control's `_draw` is not clipped to its own rect, so rings drawn
## outside `size` land in the gap between cards.
func set_glowing(on: bool) -> void:
	if on == _glowing:
		return
	_glowing = on
	set_process(on)
	queue_redraw()


func _process(delta: float) -> void:
	_glow_phase = fposmod(_glow_phase + delta * 1.8, TAU)
	queue_redraw()


func _draw() -> void:
	if not _glowing:
		return
	var breath := 0.5 + 0.5 * sin(_glow_phase)
	var rect := Rect2(Vector2.ZERO, size)
	# Three rings, widest and faintest outermost, so the edge glows rather
	# than gaining a hard second border. They stay inside the row's card gap.
	for i in 3:
		var grow := 1.0 + float(i) * 3.0
		var alpha := (0.95 - float(i) * 0.26) * (0.6 + 0.4 * breath)
		_draw_ring(rect.grow(grow), Color(1.0, 0.84, 0.35, alpha), 3.0 + float(i))


func _draw_ring(rect: Rect2, tint: Color, width: float) -> void:
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.set_corner_radius_all(14)
	box.set_border_width_all(int(width))
	box.border_color = tint
	draw_style_box(box, rect)


func refresh(highlight_suit: StringName = &"") -> void:
	set_glowing(wants_glow(_state.def, _sim))
	_highlight_suit = highlight_suit
	modulate = Color(0.6, 0.58, 0.55) if _state.exhausted() else Color.WHITE
	for slot in _sockets.size():
		_render_socket(slot, _state.filled[slot])
	_refresh_description()


## Row layout for cost sockets: <=3 one row; 4 = 2+2; odd 5+ = 2 on top then
## rows of 3 (patch 0.13); even 6+ = rows of 3.
static func _socket_rows(count: int) -> Array:
	if count <= 3:
		return [count]
	if count == 4:
		return [2, 2]
	var rows := []
	var remaining := count
	if count % 2 == 1:
		rows.append(2)
		remaining -= 2
	while remaining > 0:
		rows.append(mini(3, remaining))
		remaining -= 3
	return rows


## Every damage figure an ability can print, in the order it prints them.
##
## Since the v0.19 Cash In rework a damage op can sit NESTED inside `cash_in`
## (its payoff and its "instead" fallback), and a suit bonus keeps its own copy
## in `bonus_effects` — Double Down, Bust and On a Roll live entirely in those
## branches, so a top-level-only walk previewed nothing for them (patch 0.20).
static func damage_amounts(def: Defs.AbilityDef) -> Array[int]:
	var amounts: Array[int] = []
	_collect_damage(def.effects, amounts)
	_collect_damage(def.bonus_effects, amounts)
	_collect_damage(def.active_effects, amounts)
	return amounts


static func _collect_damage(effects: Array, into: Array[int]) -> void:
	for effect: Dictionary in effects:
		match str(effect.get("op", "")):
			# `damage_per_ability` too (0.118): The River's "deal 10" is a per-
			# ability base that Weak, Strength and All In all move, and it was
			# the one figure on the bar that stayed put under Weak. Not
			# `damage_missing_pct`: that op bypasses the attacker's modifiers
			# on purpose, so its number is correct as printed.
			"damage", "damage_per_ability":
				var amount := int(effect.get("amount", 0))
				if amount > 0 and not into.has(amount):
					into.append(amount)
			"cash_in":
				_collect_damage(effect.get("effects", []), into)
				_collect_damage(effect.get("else_effects", []), into)


## Every Block figure an ability can print (patch 0.22: "Block numbers on
## abilities should be affected by buffs/debuffs and show the correct numbers
## when used"). Walked exactly like the damage figures, nested branches and
## all — Bad Beat's Block lives inside its Cash In, and Quick Maneuvers keeps
## its Diamond value in `bonus_effects`.
##
## `block_per_enemy` / `block_per_chip` print their PER-UNIT amount ("2 Block
## per enemy"), which is the number on the card and the number Frail taxes.
static func block_amounts(def: Defs.AbilityDef) -> Array[int]:
	var amounts: Array[int] = []
	_collect_block(def.effects, amounts)
	_collect_block(def.bonus_effects, amounts)
	return amounts


static func _collect_block(effects: Array, into: Array[int]) -> void:
	for effect: Dictionary in effects:
		match str(effect.get("op", "")):
			"gain_block", "block_per_enemy", "block_per_chip":
				var amount := int(effect.get("amount", 0))
				if amount > 0 and not into.has(amount):
					into.append(amount)
			"cash_in":
				_collect_block(effect.get("effects", []), into)
				_collect_block(effect.get("else_effects", []), into)


## Live numbers (patch 0.12): damage figures reflect the hero's current
## Strength/Weak modifiers, colored red when lowered and green when raised
## (patch 0.17). Keyword icons render on enemy intents instead — inline
## icons here were on the wrong text (patch 0.17).
func _refresh_description() -> void:
	var text := _state.def.description
	if _sim != null:
		# Largest first: replacing "10" before "100" would corrupt the longer
		# number, and every match is bounded to a whole number so a figure
		# already wrapped in a colour tag is never re-matched.
		#
		# Damage and Block are collected together and sorted as one list: an
		# ability can print both (HeartSteal), and doing them in two passes
		# would let the second pass re-match a digit the first had already
		# wrapped in a colour tag.
		var previews := {}   # base figure -> modified figure
		for base: int in damage_amounts(_state.def):
			previews[base] = _sim.preview_damage(base, _state)
		for base: int in block_amounts(_state.def):
			if not previews.has(base):
				previews[base] = _sim.preview_block(base)
		var amounts: Array[int] = []
		for base: int in previews:
			amounts.append(base)
		amounts.sort()
		amounts.reverse()
		for base: int in amounts:
			var modified: int = previews[base]
			if modified == base:
				continue
			var tint := "#6ee06e" if modified > base else "#e06e6e"
			text = _replace_number(text, base, "[color=%s]%d[/color]" % [tint, modified])
	# Measured against what actually renders: a buffed figure can be a glyph
	# wider than the plain one and overflow the fixed band (patch 0.20).
	_fit_description_font(_plain_text(text))
	_description.text = "[center]%s[/center]" % text


## Swaps whole numbers only, so "10" never matches inside "100" and never
## touches digits that are already part of a colour tag.
static func _replace_number(text: String, number: int, with: String) -> String:
	var needle := str(number)
	var out := ""
	var i := 0
	while i < text.length():
		if text.substr(i, needle.length()) == needle \
				and not _is_digit(text, i - 1) and not _is_digit(text, i + needle.length()):
			out += with
			i += needle.length()
		else:
			out += text[i]
			i += 1
	return out


static func _is_digit(text: String, index: int) -> bool:
	if index < 0 or index >= text.length():
		return false
	return text[index] >= "0" and text[index] <= "9"


## The description as the player reads it, with the bbcode stripped back out.
static func _plain_text(text: String) -> String:
	var out := ""
	var inside := false
	for i in text.length():
		var glyph := text[i]
		if glyph == "[":
			inside = true
		elif glyph == "]":
			inside = false
		elif not inside:
			out += glyph
	return out


## Picks the largest font size at which the whole description still fits the
## card's fixed description band, measuring the real theme font rather than
## waiting a frame and reading a laid-out height (patch 0.18). Text that will
## not fit even at the floor size is still readable in full on hover.
func _fit_description_font(plain: String) -> void:
	var font := _description.get_theme_font("normal_font")
	if font == null:
		return
	var width := CARD_SIZE.x - 26.0
	for font_size in range(DESC_FONT_MAX, DESC_FONT_MIN - 1, -1):
		var measured := font.get_multiline_string_size(
			plain, HORIZONTAL_ALIGNMENT_CENTER, width, font_size)
		if measured.y <= DESC_HEIGHT:
			_description.add_theme_font_size_override("normal_font_size", font_size)
			return
	_description.add_theme_font_size_override("normal_font_size", DESC_FONT_MIN)


## Immediately paints a chip into a socket, even if the sim already cleared
## the ability (patch 0.1: the final chip must be visible before firing).
func show_chip(slot: int, suit: StringName) -> void:
	_render_socket(slot, suit)


func _render_socket(slot: int, filled: StringName) -> void:
	var socket := _sockets[slot]
	var face := _socket_faces[slot]
	var fallback := _socket_labels[slot]
	var required := _state.def.cost[slot]
	if filled != &"":
		var chip := SuitAssets.chip_texture(filled)
		face.texture = chip
		face.modulate = Color.WHITE
		fallback.text = "" if chip != null else String(filled).left(1).to_upper()
		socket.modulate = Color.WHITE
		socket.tooltip_text = "%s chip socketed (click to return)" % filled
	else:
		var ghost := SuitAssets.suit_texture(required)
		face.texture = ghost
		face.modulate = Color(1, 1, 1, 0.45)
		fallback.text = "" if ghost != null else \
			("?" if required == &"any" else String(required).left(1).to_upper())
		socket.tooltip_text = "needs: any suit" if required == &"any" else "needs: %s" % required
		var eligible := _highlight_suit != &"" and accepts_chip(slot, _highlight_suit)
		if eligible:
			socket.modulate = Color(1.25, 1.2, 0.75)
			face.modulate = Color(1, 1, 1, 0.85)
		else:
			socket.modulate = Color.WHITE


func flash_fire() -> void:
	var tween := create_tween()
	modulate = Color(1.8, 1.6, 1.0)
	scale = Vector2(1.08, 1.08)
	pivot_offset = size * 0.5
	tween.tween_property(self, "modulate", Color.WHITE, 0.35)
	tween.parallel().tween_property(self, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Balatro-style hover: the card leans up at you and settles back springily.
func _on_hover_entered() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.06, 1.06), 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_show_keywords()


func _on_hover_exited() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ONE, 0.14) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hide_keywords()


func _show_keywords() -> void:
	if (_state.def.keywords.is_empty() and _state.def.per_turn == 0
		and _state.def.per_combat == 0) or _keyword_panel != null:
		return
	_keyword_panel = PanelContainer.new()
	_keyword_panel.top_level = true
	_keyword_panel.z_index = 200
	_keyword_panel.theme_type_variation = &"TooltipPanel"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_keyword_panel.add_child(box)
	# Keywords only (0.0.111): the card already shows its full description,
	# so the hover panel no longer repeats it.
	for keyword_id: StringName in _state.def.keywords:
		var keyword := Db.content.get_keyword(keyword_id)
		if keyword == null:
			continue
		var entry := PanelContainer.new()
		var label := Label.new()
		label.text = "%s: %s" % [keyword.name, keyword.text]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(280, 0)
		label.add_theme_font_size_override("font_size", 15)
		entry.add_child(label)
		box.add_child(entry)
	if _state.def.per_turn > 0:
		box.add_child(_hover_entry(
			"Per Turn: usable %d time(s) each turn." % _state.def.per_turn))
	if _state.def.per_combat > 0:
		box.add_child(_hover_entry(
			"Per Fight: usable %d time(s) this fight, and never refreshed."
			% _state.def.per_combat))
	add_child(_keyword_panel)
	# Above the card, clamped to the screen.
	await get_tree().process_frame
	if _keyword_panel == null:
		return
	var panel_size := _keyword_panel.get_combined_minimum_size()
	var pos := global_position + Vector2((size.x - panel_size.x) * 0.5, -panel_size.y - 8)
	pos.x = clampf(pos.x, 8, get_viewport_rect().size.x - panel_size.x - 8)
	pos.y = maxf(pos.y, 8)
	_keyword_panel.global_position = pos


## One line of the hover panel, boxed like the keyword entries above it.
static func _hover_entry(text: String) -> PanelContainer:
	var entry := PanelContainer.new()
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(280, 0)
	label.add_theme_font_size_override("font_size", 15)
	entry.add_child(label)
	return entry


func _hide_keywords() -> void:
	if _keyword_panel != null:
		_keyword_panel.queue_free()
		_keyword_panel = null


func _exit_tree() -> void:
	_hide_keywords()


func _on_socket_pressed(slot: int) -> void:
	socket_clicked.emit(ability_index, slot)
