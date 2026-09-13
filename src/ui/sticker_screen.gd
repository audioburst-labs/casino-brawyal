extends ScreenBase
## Sticker Applying Screen (doc): shown whenever the player holds stickers won
## outside the shop (the Casino, or one bought but never placed). The cursor
## becomes the held sticker; clicking any symbol on the machine replaces it.
## Extra stickers wait in their own tray and are equipped one after another
## at random; a Trash zone throws the held one away; Continue stays greyed
## until every sticker is placed or binned.

const SLOT_SIZE := Vector2(66, 66)

var _held: StringName = &""
var _machine_row: HBoxContainer
var _extra_panel: PanelContainer
var _extra_row: HBoxContainer
var _hint: Label
var _continue: Button
var _trash: Button


func _ready() -> void:
	if Game.run == null and get_tree().current_scene == self:
		Game.run = RunState.new()  # standalone debug: CB_DEBUG_STICKERS="spade,heart"
		Game.rng = GameRng.new(randi())
		for suit in OS.get_environment("CB_DEBUG_STICKERS").split(",", false):
			Game.run.sticker_inventory.append(StringName(suit))
		if Game.run.sticker_inventory.is_empty():
			Game.run.sticker_inventory.append(&"spade")
	build_screen("Sticker Time", "res://assets/backgrounds/bg_shop.png")
	_hint = add_info_label("", 24)

	var machine_panel := PanelContainer.new()
	machine_panel.theme_type_variation = &"FeltPanel"
	machine_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(machine_panel)
	var machine_column := VBoxContainer.new()
	machine_column.add_theme_constant_override("separation", 10)
	machine_panel.add_child(machine_column)
	var machine_title := Label.new()
	machine_title.text = "Your Slot Machine"
	machine_title.theme_type_variation = &"SubtitleLabel"
	machine_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	machine_column.add_child(machine_title)
	_machine_row = HBoxContainer.new()
	_machine_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_machine_row.add_theme_constant_override("separation", 18)
	machine_column.add_child(_machine_row)

	_extra_panel = PanelContainer.new()
	_extra_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(_extra_panel)
	var extra_column := VBoxContainer.new()
	_extra_panel.add_child(extra_column)
	var extra_title := Label.new()
	extra_title.text = "Extra Stickers"
	extra_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	extra_title.add_theme_font_size_override("font_size", 18)
	extra_column.add_child(extra_title)
	_extra_row = HBoxContainer.new()
	_extra_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_extra_row.add_theme_constant_override("separation", 12)
	_extra_row.custom_minimum_size = Vector2(240, 56)
	extra_column.add_child(_extra_row)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 30)
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(buttons)
	_trash = Button.new()
	_trash.text = "🗑  Trash this sticker"
	_trash.tooltip_text = "Throw the held sticker away for good"
	_trash.pressed.connect(_on_trash)
	buttons.add_child(_trash)
	_continue = Button.new()
	_continue.text = "Continue"
	_continue.pressed.connect(_on_continue)
	buttons.add_child(_continue)

	_equip_next()
	_refresh()


## The cursor "equips" a new random sticker from the tray after each
## placement (doc). Nothing left: the hand comes back.
func _equip_next() -> void:
	var inventory := Game.run.sticker_inventory
	if inventory.is_empty():
		_held = &""
	elif _held == &"" or not inventory.has(_held):
		_held = inventory[randi() % inventory.size()]
	Fx.set_cursor_sticker(SuitAssets.suit_texture(_held) if _held != &"" else null)


func _refresh() -> void:
	var inventory := Game.run.sticker_inventory
	var placing := _held != &""
	_hint.text = "Click a symbol on your machine to replace it with the %s sticker." \
		% String(_held).capitalize() if placing \
		else "Every sticker is placed. Your machine is ready."

	for child in _machine_row.get_children():
		_machine_row.remove_child(child)
		child.queue_free()
	for reel_index in Game.run.machine.reels.size():
		var reel: Reel = Game.run.machine.reels[reel_index]
		var reel_box := VBoxContainer.new()
		reel_box.add_theme_constant_override("separation", 6)
		_machine_row.add_child(reel_box)
		for slot_index in reel.symbols.size():
			var slot := LayoutTab._suit_button(reel.symbols[slot_index], SLOT_SIZE)
			slot.disabled = not placing
			slot.tooltip_text = "Replace %s with %s" % [String(reel.symbols[slot_index]).capitalize(),
				String(_held).capitalize()] if placing else String(reel.symbols[slot_index]).capitalize()
			slot.pressed.connect(_on_slot_clicked.bind(reel_index, slot_index))
			reel_box.add_child(slot)

	# The tray only exists for multi-sticker hauls (doc): the held one is on
	# the cursor, the rest wait here.
	for child in _extra_row.get_children():
		_extra_row.remove_child(child)
		child.queue_free()
	var waiting := 0
	var skipped_held := false
	for suit: StringName in inventory:
		if suit == _held and not skipped_held:
			skipped_held = true
			continue
		waiting += 1
		var icon := TextureRect.new()
		icon.texture = SuitAssets.suit_texture(suit)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(48, 48)
		icon.tooltip_text = "%s sticker, waiting" % String(suit).capitalize()
		_extra_row.add_child(icon)
	_extra_panel.visible = waiting > 0

	_trash.disabled = not placing
	_continue.disabled = placing
	_continue.tooltip_text = "Place or trash every sticker first" if placing else ""


func _on_slot_clicked(reel_index: int, slot_index: int) -> void:
	if _held == &"":
		return
	Game.run.machine.apply_sticker(reel_index, slot_index, _held)
	Game.run.sticker_inventory.erase(_held)
	_held = &""
	_equip_next()
	_refresh()


func _on_trash() -> void:
	if _held == &"":
		return
	Game.run.sticker_inventory.erase(_held)
	_held = &""
	_equip_next()
	_refresh()


func _on_continue() -> void:
	if not Game.run.sticker_inventory.is_empty():
		return
	Fx.set_cursor_sticker(null)
	Game.encounter_finished()


func _exit_tree() -> void:
	Fx.set_cursor_sticker(null)
