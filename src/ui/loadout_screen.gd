extends ScreenBase
## Ability Choosing Screen (doc v0.11): drag abilities between the Equipped
## area (6 battle slots), Storage (6 slots), and the Trash slot (its occupant
## is deleted for good when the next combat begins).

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

	# Dropping anywhere in a zone works — including on top of another chit
	# (patch 0.12): forward the drop to the zone this chit lives in.
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
	if Game.run == null and get_tree().current_scene == self:
		Game.run = RunState.new()  # standalone debug: a well-stocked run
		for id in Db.content.all_ability_ids().slice(0, 9):
			Game.run.acquire_ability(id)
	build_screen("Choose Your Hand", "res://assets/backgrounds/bg_rest.png")
	add_info_label("Drag abilities between zones. Only Equipped abilities are usable in combat.\nWhatever sits in the Trash is destroyed when the next combat begins.", 18)
	for config in [
		[&"equipped", "Equipped (max %d)" % RunState.EQUIP_CAP],
		[&"storage", "Storage (max %d)" % RunState.STORAGE_CAP],
		[&"trash", "Trash"],
	]:
		var zone := DropZone.new()
		zone.zone = config[0]
		zone.screen = self
		zone.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		# The whole area square is a drop target (patch 0.12).
		zone.custom_minimum_size = Vector2(170, 150) if config[0] == &"trash" \
			else Vector2(840, 150)
		var box := VBoxContainer.new()
		zone.add_child(box)
		var header := Label.new()
		header.text = config[1]
		header.theme_type_variation = &"SubtitleLabel"
		header.add_theme_font_size_override("font_size", 22)
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(header)
		var slots := HBoxContainer.new()
		slots.alignment = BoxContainer.ALIGNMENT_CENTER
		slots.add_theme_constant_override("separation", 10)
		slots.custom_minimum_size = Vector2(0, 96)
		box.add_child(slots)
		content.add_child(zone)
		_zones[config[0]] = slots
	add_continue_button("Done", func() -> void: Game.show_map())
	_refresh()


func _refresh() -> void:
	_fill_zone(&"equipped", Game.run.equipped_ids)
	_fill_zone(&"storage", Game.run.stored_ids())
	var trash: Array[StringName] = []
	if Game.run.trash_id != &"":
		trash.append(Game.run.trash_id)
	_fill_zone(&"trash", trash)


func _fill_zone(zone: StringName, ids: Array) -> void:
	var slots: HBoxContainer = _zones[zone]
	for child in slots.get_children():
		child.queue_free()
	for id: StringName in ids:
		slots.add_child(_build_chit(id, zone))
	var capacity: int = RunState.EQUIP_CAP if zone == &"equipped" \
		else (RunState.STORAGE_CAP if zone == &"storage" else 1)
	for i in capacity - ids.size():
		var empty := Panel.new()
		empty.custom_minimum_size = Vector2(120, 84)
		empty.modulate.a = 0.35
		# Let drops fall through to the DropZone panel behind (patch 0.12).
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slots.add_child(empty)


func _build_chit(id: StringName, zone: StringName) -> Control:
	var chit := AbilityChit.new()
	chit.ability_id = id
	chit.zone = zone
	chit.screen = self
	chit.custom_minimum_size = Vector2(120, 84)
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
		icon.custom_minimum_size = Vector2(40, 40)
		box.add_child(icon)
	var name_label := Label.new()
	name_label.text = def.name if def else String(id)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_label.add_theme_font_size_override("font_size", 14)
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
