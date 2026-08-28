class_name LayoutTab
extends Control
## Layout Tab overlay (doc): Slot Machine reels+symbols, Relics collected,
## and Abilities split into Equipped / Unequipped / Trash for management —
## reachable any time via the header icon, without leaving the current screen.

var _zones := {}   # zone id -> slot container


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
			queue_free())
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
	close_button.pressed.connect(queue_free)
	close_row.add_child(close_button)


func _build_slot_machine_section(column: VBoxContainer) -> void:
	var header := Label.new()
	header.text = "Slot Machine"
	header.theme_type_variation = &"SubtitleLabel"
	column.add_child(header)

	var reels_row := HBoxContainer.new()
	reels_row.alignment = BoxContainer.ALIGNMENT_CENTER
	reels_row.add_theme_constant_override("separation", 10)
	column.add_child(reels_row)
	if Game.run == null:
		return
	for reel: Reel in Game.run.machine.reels:
		var reel_box := VBoxContainer.new()
		reel_box.add_theme_constant_override("separation", 4)
		reels_row.add_child(reel_box)
		for suit: StringName in reel.symbols:
			var icon := TextureRect.new()
			var texture := SuitAssets.suit_texture(suit)
			if texture != null:
				icon.texture = texture
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(32, 32)
			reel_box.add_child(icon)


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
		var icon_path := "res://assets/icons/relic_%s.png" % relic_id
		if ResourceLoader.exists(icon_path):
			var icon := TextureRect.new()
			icon.texture = load(icon_path)
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
	var def := Db.content.get_ability(id)
	chit.tooltip_text = "%s\n%s" % [def.name, def.description] if def else String(id)
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
