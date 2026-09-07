class_name LayoutTab
extends Control
## Layout Tab overlay (doc): Slot Machine reels+symbols, Relics collected,
## and Abilities split into Equipped / Unequipped / Trash for management —
## reachable any time via the header icon, without leaving the current screen.

var _zones := {}   # zone id -> slot container
var _held_sticker: StringName = &""   # the sticker awaiting a reel slot
var _machine_column: VBoxContainer


class AbilityChit:
	extends PanelContainer
	var ability_id: StringName = &""
	var zone: StringName = &""
	var screen: Node = null

	func _get_drag_data(_position: Vector2) -> Variant:
		var preview := Label.new()
		preview.text = String(ability_id).capitalize()
		preview.theme_type_variation = &"SubtitleLabel"
		set_drag_preview(preview)
		return {"ability": ability_id}

	func _can_drop_data(_position: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("ability") and data.ability != ability_id

	func _drop_data(_position: Vector2, data: Variant) -> void:
		screen._on_dropped(zone, data.ability)


class DropZone:
	extends PanelContainer
	var zone: StringName = &""
	var screen: Node = null

	func _can_drop_data(_position: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("ability")

	func _drop_data(_position: Vector2, data: Variant) -> void:
		screen._on_dropped(zone, data.ability)


func _ready() -> void:
	# See SettingsTab's _ready() for why this positions from the viewport
	# size directly rather than trusting anchors on a freshly-added Control.
	var vp := get_viewport_rect().size
	position = Vector2.ZERO
	size = vp
	z_index = 200

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.01, 0.02, 0.78)
	backdrop.position = Vector2.ZERO
	backdrop.size = vp
	backdrop.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_close())
	add_child(backdrop)

	var panel_size := Vector2(1080, minf(820, vp.y - 80))
	var panel := PanelContainer.new()
	panel.position = vp * 0.5 - panel_size * 0.5
	panel.size = panel_size
	add_child(panel)

	# The Abilities section can outgrow the panel on small viewports —
	# scroll rather than spill the Trash zone and Done button off-screen.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(scroll)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)

	var title := Label.new()
	title.text = "Layout"
	title.theme_type_variation = &"TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	_build_slot_machine_section(column)
	_build_relics_section(column)
	_build_abilities_section(column)

	var close_row := HBoxContainer.new()
	close_row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(close_row)
	var close_button := Button.new()
	close_button.text = "Done"
	close_button.pressed.connect(_close)
	close_row.add_child(close_button)


func _build_slot_machine_section(column: VBoxContainer) -> void:
	var header := Label.new()
	header.text = "Slot Machine"
	header.theme_type_variation = &"SubtitleLabel"
	column.add_child(header)

	_machine_column = VBoxContainer.new()
	_machine_column.add_theme_constant_override("separation", 10)
	column.add_child(_machine_column)
	_refresh_machine_section()


## Doc "Sticker Applying Screen": stickers won outside the shop are held until
## the player clicks the reel symbol they should replace. Without this they had
## nowhere to go but the shop, so a Casino-won sticker was a dead reward
## (patch 0.18).
func _refresh_machine_section() -> void:
	for child in _machine_column.get_children():
		_machine_column.remove_child(child)
		child.queue_free()
	if Game.run == null:
		return

	if not Game.run.sticker_inventory.is_empty():
		var tray := HBoxContainer.new()
		tray.alignment = BoxContainer.ALIGNMENT_CENTER
		tray.add_theme_constant_override("separation", 10)
		_machine_column.add_child(tray)
		var hint := Label.new()
		var placing_now := _held_sticker != &""
		hint.text = "Click a reel symbol to place it:" if placing_now else "Pick a sticker, then a symbol:"
		tray.add_child(hint)
		for index in Game.run.sticker_inventory.size():
			var suit: StringName = Game.run.sticker_inventory[index]
			var chip := _suit_button(suit, Vector2(44, 44))
			chip.tooltip_text = "%s sticker" % String(suit).capitalize()
			chip.toggle_mode = true
			chip.button_pressed = suit == _held_sticker
			chip.pressed.connect(_on_sticker_picked.bind(suit))
			tray.add_child(chip)
		var discard := Button.new()
		discard.focus_mode = Control.FOCUS_NONE
		discard.text = "🗑"
		discard.tooltip_text = "Throw the held sticker away"
		discard.disabled = _held_sticker == &""
		discard.pressed.connect(_on_sticker_discarded)
		tray.add_child(discard)

	var reels_row := HBoxContainer.new()
	reels_row.alignment = BoxContainer.ALIGNMENT_CENTER
	reels_row.add_theme_constant_override("separation", 10)
	_machine_column.add_child(reels_row)
	var placing := _held_sticker != &""
	for reel_index in Game.run.machine.reels.size():
		var reel: Reel = Game.run.machine.reels[reel_index]
		var reel_box := VBoxContainer.new()
		reel_box.add_theme_constant_override("separation", 4)
		reels_row.add_child(reel_box)
		for slot_index in reel.symbols.size():
			var suit: StringName = reel.symbols[slot_index]
			var slot := _suit_button(suit, Vector2(40, 40))
			slot.flat = not placing
			slot.disabled = not placing
			slot.focus_mode = Control.FOCUS_NONE
			slot.tooltip_text = String(suit).capitalize()
			slot.pressed.connect(_on_reel_slot_clicked.bind(reel_index, slot_index))
			reel_box.add_child(slot)


## A square suit button. The art is 1024px square, so it rides as an inset
## child TextureRect (the ability card's socket pattern) rather than as
## Button.icon, which would draw it at native size.
static func _suit_button(suit: StringName, box: Vector2) -> Button:
	var button := Button.new()
	button.custom_minimum_size = box
	# Focusable buttons make the ScrollContainer jump to whichever one grabs
	# focus the moment the tab opens; nothing here needs keyboard focus.
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var face := TextureRect.new()
	face.texture = SuitAssets.suit_texture(suit)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.set_anchors_preset(Control.PRESET_FULL_RECT)
	face.offset_left = 5
	face.offset_top = 5
	face.offset_right = -5
	face.offset_bottom = -5
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(face)
	return button


func _on_sticker_picked(suit: StringName) -> void:
	_held_sticker = &"" if _held_sticker == suit else suit
	_refresh_machine_section()


func _on_sticker_discarded() -> void:
	Game.run.sticker_inventory.erase(_held_sticker)
	_held_sticker = &""
	_refresh_machine_section()


func _on_reel_slot_clicked(reel_index: int, slot_index: int) -> void:
	if _held_sticker == &"":
		return
	Game.run.machine.apply_sticker(reel_index, slot_index, _held_sticker)
	Game.run.sticker_inventory.erase(_held_sticker)
	_held_sticker = &""
	_refresh_machine_section()


func _build_relics_section(column: VBoxContainer) -> void:
	var header := Label.new()
	header.text = "Relics"
	header.theme_type_variation = &"SubtitleLabel"
	column.add_child(header)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.custom_minimum_size = Vector2(0, 60)
	column.add_child(row)
	if Game.run == null:
		return
	if Game.run.relic_ids.is_empty():
		var empty := Label.new()
		empty.text = "No relics yet."
		row.add_child(empty)
		return
	for relic_id in Game.run.relic_ids:
		var relic := Db.content.get_relic(relic_id)
		if relic == null:
			continue
		var icon := TextureRect.new()
		icon.texture = SuitAssets.relic_texture(relic_id)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(52, 52)
		icon.tooltip_text = "%s — %s" % [relic.name, relic.description]
		row.add_child(icon)


func _build_abilities_section(column: VBoxContainer) -> void:
	var header := Label.new()
	header.text = "Abilities"
	header.theme_type_variation = &"SubtitleLabel"
	column.add_child(header)

	if Game.run == null:
		var empty := Label.new()
		empty.text = "No run in progress."
		column.add_child(empty)
		return

	for config in [
		[&"equipped", "Equipped (max %d)" % RunState.EQUIP_CAP],
		[&"storage", "Unequipped (max %d)" % RunState.STORAGE_CAP],
		[&"trash", "Trash"],
	]:
		var zone := DropZone.new()
		zone.zone = config[0]
		zone.screen = self
		zone.custom_minimum_size = Vector2(140, 110) if config[0] == &"trash" else Vector2(760, 110)
		zone.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var box := VBoxContainer.new()
		zone.add_child(box)
		var zone_header := Label.new()
		zone_header.text = config[1]
		zone_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		zone_header.add_theme_font_size_override("font_size", 16)
		box.add_child(zone_header)
		var slots := HBoxContainer.new()
		slots.alignment = BoxContainer.ALIGNMENT_CENTER
		slots.add_theme_constant_override("separation", 8)
		slots.custom_minimum_size = Vector2(0, 76)
		box.add_child(slots)
		column.add_child(zone)
		_zones[config[0]] = slots
	_refresh()


func _refresh() -> void:
	var run: RunState = Game.run
	_fill_zone(&"equipped", run.equipped_ids)
	_fill_zone(&"storage", run.stored_ids())
	var trash: Array[StringName] = []
	if run.trash_id != &"":
		trash.append(run.trash_id)
	_fill_zone(&"trash", trash)


func _fill_zone(zone: StringName, ids: Array) -> void:
	var slots: HBoxContainer = _zones[zone]
	for child in slots.get_children():
		child.queue_free()
	for id: StringName in ids:
		slots.add_child(_build_chit(id))
	var capacity: int = RunState.EQUIP_CAP if zone == &"equipped" \
		else (RunState.STORAGE_CAP if zone == &"storage" else 1)
	for i in capacity - ids.size():
		var empty := Panel.new()
		empty.custom_minimum_size = Vector2(90, 66)
		empty.modulate.a = 0.35
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slots.add_child(empty)


func _build_chit(id: StringName) -> Control:
	var chit := AbilityChit.new()
	chit.ability_id = id
	chit.screen = self
	chit.custom_minimum_size = Vector2(90, 66)
	# Drawn at the tier the run owns, so a chit matches the card it becomes
	# in combat (v0.19).
	var tier := Game.run.ability_tier(id) if Game.run != null else 0
	var def := Db.content.get_ability(id, tier)
	chit.tooltip_text = "%s%s\n%s" % [def.name,
		" — %s" % TierStyle.label(tier) if tier > 0 else "",
		def.description] if def else String(id)
	if tier > 0:
		chit.add_theme_stylebox_override("panel", TierStyle.panel(tier, 2))
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	chit.add_child(box)
	var icon_texture := SuitAssets.ability_texture(id)
	if icon_texture != null:
		var icon := TextureRect.new()
		icon.texture = icon_texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(30, 30)
		box.add_child(icon)
	var name_label := Label.new()
	name_label.text = def.name if def else String(id)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_label.add_theme_font_size_override("font_size", 11)
	box.add_child(name_label)
	return chit


func _on_dropped(zone: StringName, id: StringName) -> void:
	var run: RunState = Game.run
	match zone:
		&"equipped":
			if id == run.trash_id:
				run.restore_from_trash()
			else:
				run.equip(id)
		&"storage":
			if id == run.trash_id:
				run.restore_from_trash()
			else:
				run.unequip(id)
		&"trash":
			run.move_to_trash(id)
	_refresh()


func _close() -> void:
	queue_free()


## Esc closes the tab (patch 0.19). Handled as *unhandled* input and marked
## consumed, so with both overlays somehow open only the topmost one closes,
## and Esc never leaks through to the screen underneath.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()
