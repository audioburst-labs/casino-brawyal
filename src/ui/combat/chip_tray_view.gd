class_name ChipTrayView
extends PanelContainer
## The chip tray: one stack per suit with a count badge. Chips move to
## ability sockets by drag-and-drop only (patch 0.11), with the drag preview
## centered on the cursor.

var _tray: ChipTray
var _row: HBoxContainer
## What the player has actually been SHOWN, which is not always what the tray
## holds. The sim resolves an ability the instant its last socket fills, so a
## Go Again's new chips are already in `_tray` before the reels are seen to
## spin for them — the tray would jump ahead of its own animation (patch 0.20).
## `spend()` steps this down as chips leave; `refresh()` re-syncs it, and the
## presenter only calls that once a payout has been animated.
var _shown: Dictionary = {}

## One chip button's footprint (patch 0.22: 96 -> 80, see _ready).
const CHIP_SIZE := 80
## Inside the slot machine's drawer the cabinet art IS the frame, so the tray
## draws nothing of its own (patch 0.22).
##
## Patch 0.114: 0.113's brown well is gone. It was added to replace the frame
## per chip, but the drawer art already has a wooden plank painted on it, and
## the well simply covered it up. The chips now lie straight on that plank —
## one background for all of them, which is what the note asked for, drawn by
## the cabinet rather than by the tray.
var framed := true


static func _well_style(_bevelled: bool) -> StyleBoxEmpty:
	# Deliberately empty: the drawer's own art is the background.
	return StyleBoxEmpty.new()


class ChipButton:
	extends Button
	var suit: StringName = &""
	var art: Control = null

	## With the per-chip frame gone the chip itself has to answer the mouse, so
	## it lifts and brightens under the cursor (patch 0.113).
	func _ready() -> void:
		mouse_entered.connect(func() -> void: _hover(true))
		mouse_exited.connect(func() -> void: _hover(false))

	func _hover(on: bool) -> void:
		if art == null or not is_instance_valid(art):
			return
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(art, "position:y", -5.0 if on else 0.0, 0.12) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(art, "modulate",
			Color(1.18, 1.14, 1.05) if on else Color.WHITE, 0.12)

	func _get_drag_data(_position: Vector2) -> Variant:
		var preview_texture := SuitAssets.chip_texture(suit)
		if preview_texture != null:
			# Wrap so the chip is centered on the mouse (patch 0.11).
			var wrapper := Control.new()
			var image := TextureRect.new()
			image.texture = preview_texture
			image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			image.custom_minimum_size = Vector2(64, 64)
			image.size = Vector2(64, 64)
			image.position = Vector2(-32, -32)
			image.modulate.a = 0.9
			wrapper.add_child(image)
			set_drag_preview(wrapper)
		# Doc's Mouse spec: selecting a chip triggers a brief grabbing gesture.
		Fx.set_cursor_grabbing(true)
		return {"suit": suit}

	## NOTIFICATION_DRAG_END fires on the control that started the drag,
	## whether or not the drop succeeded — the cue to revert the cursor.
	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_END:
			Fx.set_cursor_grabbing(false)


func _ready() -> void:
	add_theme_stylebox_override("panel", _well_style(framed))
	# Constant footprint whether the tray holds 0 or 4 suits (patch 0.12).
	# Patch 0.22: a little slimmer, because the tray is the slot machine's
	# drawer now and the whole cabinet has to fit one band of the screen.
	custom_minimum_size = Vector2(4 * CHIP_SIZE + 3 * 12 + 24, CHIP_SIZE + 16)
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 18)
	add_child(_row)


## The first live chip button showing `suit` (any suit when &""), for the
## debug driver that dispatches a REAL drag through the GUI (0.118).
func chip_button(suit: StringName = &"") -> Button:
	for stack in _row.get_children():
		var found := _find_chip(stack, suit)
		if found != null:
			return found
	return null


func _find_chip(node: Node, suit: StringName) -> Button:
	if node is ChipButton and (suit == &"" or (node as ChipButton).suit == suit):
		return node
	for child in node.get_children():
		var found := _find_chip(child, suit)
		if found != null:
			return found
	return null


func bind(tray: ChipTray) -> void:
	_tray = tray
	refresh()


## Catches the display up with the tray. Called when a payout has finished
## animating, and after discards and un-assignments.
func refresh() -> void:
	if _tray == null:
		return
	_shown.clear()
	for suit: StringName in ContentDB.SUITS:
		_shown[suit] = _tray.count(suit)
	_redraw()


## One chip of `suit` has left the tray for a socket. Stepping the display
## down directly, rather than re-reading the tray, is what keeps a Go Again's
## winnings hidden until the reels have shown them arriving.
## Shows ONE more chip of `suit` (0.117). The sim resolves a whole round
## before the first frame of it is drawn, so `refresh()` after the payout
## flourish also exposed every gift and Earn chip that had already landed in
## the live tray. Arrivals now step the shown count up one animation at a
## time, and `refresh()` is for the discard/unassign paths that re-sync.
func reveal(suit: StringName, count := 1) -> void:
	if _tray == null:
		return
	var shown := int(_shown.get(suit, 0)) + count
	_shown[suit] = mini(shown, _tray.count(suit))
	_redraw()


func spend(suit: StringName) -> void:
	_shown[suit] = maxi(0, int(_shown.get(suit, 0)) - 1)
	_redraw()


func _redraw() -> void:
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	for suit: StringName in ContentDB.SUITS:
		var count := int(_shown.get(suit, 0))
		if count > 0:
			_row.add_child(_build_stack(suit, count))


## A frameless chip. Every button state is an empty box (patch 0.113) —
## hover and press are carried by the chip art's own scale and tint instead,
## so nothing draws a second square inside the drawer's one brown well.
static func _strip_button_frames(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())


func _build_stack(suit: StringName, count: int) -> Control:
	var button := ChipButton.new()
	button.suit = suit
	_strip_button_frames(button)
	button.custom_minimum_size = Vector2(CHIP_SIZE, CHIP_SIZE)
	button.tooltip_text = "%s chips: %d. Drag onto an ability socket." % [suit, count]
	var texture := SuitAssets.chip_texture(suit)
	if texture != null:
		var chip := TextureRect.new()
		chip.texture = texture
		chip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		chip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		chip.set_anchors_preset(Control.PRESET_FULL_RECT)
		chip.offset_left = 8
		chip.offset_top = 8
		chip.offset_right = -8
		chip.offset_bottom = -8
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(chip)
		button.art = chip
		var badge := Label.new()
		badge.text = "x%d" % count
		badge.theme_type_variation = &"SubtitleLabel"
		badge.add_theme_font_size_override("font_size", 22)
		badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		badge.offset_left = -44
		badge.offset_top = -30
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(badge)
	else:
		button.text = "%s x%d" % [String(suit).left(1).to_upper(), count]
		button.add_theme_color_override("font_color", SuitAssets.suit_color(suit).lightened(0.5))
	return button
