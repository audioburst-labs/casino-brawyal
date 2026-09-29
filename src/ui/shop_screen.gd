extends ScreenBase
## Dreams Shop, laid out to the mock in the design doc: the player's loadout
## down the left (machine, six ability slots, a Trash slot below it), the four
## purchasable abilities in the middle, stickers and the Extra Reel on the
## right, and the three relics along the bottom.
##
## Abilities on the shelf may be new OR an upgrade of one already owned — the
## pool is shared with the reward screen (doc v0.19).

const LOADOUT_WIDTH := 404.0
## Patch 0.20: bigger shelf items — the 0.19 sizes left the lower third of the
## board empty.
const OFFER_SIZE := Vector2(286, 320)
const SMALL_OFFER := Vector2(192, 182)
const RELIC_SIZE := Vector2(202, 210)

var _stock: Dictionary
var _sold: Dictionary = {}            # offer key -> true
var _selected_sticker: StringName = &""

var _board: Control
var _loadout_slots: HBoxContainer
var _trash_slot: HBoxContainer
var _machine_box: VBoxContainer
var _ability_grid: GridContainer
var _sticker_grid: GridContainer
var _relic_row: HBoxContainer
var _reel_holder: VBoxContainer
var _hint: Label
var _preview: PanelContainer = null


func _ready() -> void:
	build_screen("Dreams Shop", "res://assets/backgrounds/bg_shop.png")
	if Game.run == null:
		Game.run = RunState.new()   # standalone debug
		Game.run.coins = 400
		Game.rng = GameRng.new(randi())
		for id in ["card_sling", "quick_maneuvers", "color_up", "bust"]:
			Game.run.acquire_ability(StringName(id))
		Game.run.acquire_ability(&"bust")   # a silver copy to look at
	# A visit interrupted by an exit to the main menu resumes with the same
	# shelf and the same SOLD stamps (0.0.111) — the stock rides in the run's
	# pending encounter rather than being re-rolled.
	var saved: Variant = Game.run.pending_encounter.get("stock")
	if saved is Dictionary:
		_stock = ShopStock.from_json(saved)
		for key in Game.run.pending_encounter.get("sold", []):
			_sold[str(key)] = true
	else:
		_stock = ShopStock.generate(Db.content, Game.run, Game.rng.stream(&"shop"))
		_store_stock()
	_build_board()
	_refresh()


func _store_stock() -> void:
	if Game.run.pending_encounter.is_empty():
		return   # standalone debug launch: nothing to resume into
	Game.run.pending_encounter["stock"] = ShopStock.to_json(_stock)
	Game.run.pending_encounter["sold"] = _sold.keys()


## The mock is a three-column board, not a centred column, so it replaces
## ScreenBase's content stack rather than living inside it.
func _build_board() -> void:
	# ScreenBase centres a title over a content column; the mock is a board, so
	# the whole stack is hidden and the title redrawn at the top of it.
	content.visible = false
	_title_label.get_parent().visible = false
	_board = Control.new()
	_board.set_anchors_preset(Control.PRESET_FULL_RECT)
	_board.offset_top = HeaderHud.BAR_HEIGHT + 8.0
	add_child(_board)

	var title := Label.new()
	title.text = "Dreams Shop"
	title.theme_type_variation = &"TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.22
	title.anchor_right = 0.78
	title.offset_top = 10.0
	title.offset_bottom = 74.0
	_board.add_child(title)

	_build_loadout_column()
	_build_ability_shelf()
	_build_right_column()

	var exit_button := Button.new()
	exit_button.text = "Exit Shop"
	exit_button.pressed.connect(Game.encounter_finished)
	exit_button.anchor_left = 0.86
	exit_button.anchor_right = 0.985
	exit_button.anchor_top = 0.01
	exit_button.anchor_bottom = 0.075
	_board.add_child(exit_button)


func _build_loadout_column() -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"FeltPanel"
	panel.anchor_left = 0.012
	panel.anchor_top = 0.01
	panel.anchor_bottom = 0.80
	panel.offset_right = LOADOUT_WIDTH
	panel.offset_left = 0.012 * 1920.0
	_board.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE)
	panel.position = Vector2(24, 8)
	panel.custom_minimum_size = Vector2(LOADOUT_WIDTH, 0)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	var header := Label.new()
	header.text = "Player Loadout"
	header.theme_type_variation = &"SubtitleLabel"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(header)

	_machine_box = VBoxContainer.new()
	_machine_box.add_theme_constant_override("separation", 6)
	column.add_child(_machine_box)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(LOADOUT_WIDTH - 40.0, 0)
	_hint.add_theme_font_size_override("font_size", 15)
	column.add_child(_hint)

	var equipped_label := Label.new()
	equipped_label.text = "Equipped (max %d)" % RunState.EQUIP_CAP
	equipped_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	equipped_label.add_theme_font_size_override("font_size", 16)
	column.add_child(equipped_label)

	# Six slots in two rows of three, as the mock draws them.
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(grid)
	_loadout_slots = HBoxContainer.new()   # holder; the grid is filled directly
	_loadout_slots.visible = false
	column.add_child(_loadout_slots)
	_loadout_slots.set_meta("grid", grid)

	var trash_panel := PanelContainer.new()
	trash_panel.theme_type_variation = &"FeltPanel"
	column.add_child(trash_panel)
	var trash_column := VBoxContainer.new()
	trash_panel.add_child(trash_column)
	var trash_label := Label.new()
	trash_label.text = "Trash Ability"
	trash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trash_label.add_theme_font_size_override("font_size", 16)
	trash_column.add_child(trash_label)
	var trash_zone := LayoutTab.DropZone.new()
	trash_zone.zone = &"trash"
	trash_zone.screen = self
	trash_zone.custom_minimum_size = Vector2(LOADOUT_WIDTH - 60.0, 76)
	trash_column.add_child(trash_zone)
	_trash_slot = HBoxContainer.new()
	_trash_slot.alignment = BoxContainer.ALIGNMENT_CENTER
	trash_zone.add_child(_trash_slot)


func _build_ability_shelf() -> void:
	_ability_grid = GridContainer.new()
	_ability_grid.columns = 2
	_ability_grid.add_theme_constant_override("h_separation", 16)
	_ability_grid.add_theme_constant_override("v_separation", 16)
	_ability_grid.position = Vector2(452, 92)
	_board.add_child(_ability_grid)


func _build_right_column() -> void:
	_sticker_grid = GridContainer.new()
	_sticker_grid.columns = 2
	_sticker_grid.add_theme_constant_override("h_separation", 14)
	_sticker_grid.add_theme_constant_override("v_separation", 14)
	_sticker_grid.position = Vector2(1046, 92)
	_board.add_child(_sticker_grid)

	_reel_holder = VBoxContainer.new()
	_reel_holder.position = Vector2(1452, 92)
	_board.add_child(_reel_holder)

	_relic_row = HBoxContainer.new()
	_relic_row.add_theme_constant_override("separation", 14)
	_relic_row.position = Vector2(1046, 580)
	_board.add_child(_relic_row)


func _refresh() -> void:
	_refresh_offers()
	_refresh_loadout()
	_refresh_machine()


# ---- the shelves -------------------------------------------------------

func _refresh_offers() -> void:
	for holder in [_ability_grid, _sticker_grid, _relic_row, _reel_holder]:
		for child in holder.get_children():
			holder.remove_child(child)
			child.queue_free()

	for offer: Dictionary in _stock.abilities:
		_ability_grid.add_child(_ability_offer(offer))

	for offer: Dictionary in _stock.stickers:
		var suit: StringName = offer.suit
		_sticker_grid.add_child(_offer_tile(
			"sticker_%s" % suit, "%s Sticker" % String(suit).capitalize(),
			SuitAssets.suit_texture(suit), int(offer.price), SMALL_OFFER,
			_buy_sticker.bind(suit)))

	for offer: Dictionary in _stock.relics:
		var relic := Db.content.get_relic(offer.id)
		var tile := _offer_tile("relic_%s" % offer.id, relic.name,
			SuitAssets.relic_texture(offer.id), int(offer.price), RELIC_SIZE,
			_buy_relic.bind(offer.id))
		tile.tooltip_text = "%s: %s" % [relic.name, relic.description]
		tile.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		_relic_row.add_child(tile)

	var reel: Dictionary = _stock.reel
	if reel.available:
		var reel_tile := _offer_tile("reel", "Extra Reel",
			_load_texture("res://assets/props/slot_cabinet.png"),
			int(reel.price), Vector2(256, 470), _buy_reel)
		reel_tile.tooltip_text = "Adds a reel with one of each suit (max %d)." \
			% SlotMachine.MAX_REELS
		_reel_holder.add_child(reel_tile)


## The four purchasable abilities. An upgrade shows what it would become and
## carries the doc's glowing border and UPGRADE! flag.
func _ability_offer(offer: Dictionary) -> Control:
	var id: StringName = offer.id
	var upgrade := bool(offer.get("upgrade", false))
	var shown_tier := int(offer.get("tier", 0)) + 1 if upgrade else 0
	var def := Db.content.get_ability(id, shown_tier)
	var key := "ability_%s" % id

	var tile := Button.new()
	tile.custom_minimum_size = OFFER_SIZE
	for state in ["normal", "hover", "pressed", "focus"]:
		tile.add_theme_stylebox_override(state,
			TierStyle.upgrade_panel() if upgrade else TierStyle.panel(0))

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)
	tile.add_child(column)

	var icon_holder := CenterContainer.new()
	var icon := TextureRect.new()
	icon.texture = SuitAssets.ability_texture(id)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(46, 46)
	icon_holder.add_child(icon)
	column.add_child(icon_holder)

	var name_label := Label.new()
	name_label.text = def.name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_label.add_theme_font_size_override("font_size", 18)
	if shown_tier > 0:
		name_label.add_theme_color_override("font_color", TierStyle.color(shown_tier))
	column.add_child(name_label)

	column.add_child(AbilityCard.cost_row(def, 22.0))
	var limits := AbilityCard.limits_row(def)
	if limits.get_child_count() > 0:
		column.add_child(limits)
	var text := Label.new()
	text.text = def.description
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD
	text.custom_minimum_size = Vector2(OFFER_SIZE.x - 26.0, 0)
	text.add_theme_font_size_override("font_size", 13)
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(text)

	var price := _price_button(key, int(offer.price), _buy_ability.bind(id))
	column.add_child(price)

	if upgrade:
		var overlay := Control.new()
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(overlay)
		var badge := TierStyle.upgrade_badge(shown_tier)
		badge.position = Vector2(OFFER_SIZE.x - 104.0, 6.0)
		overlay.add_child(badge)
	return tile


## Everything else on the shelf: an icon, a name and a price button.
func _offer_tile(key: String, title: String, art: Texture2D, price: int,
		box: Vector2, on_buy: Callable) -> Control:
	var tile := PanelContainer.new()
	tile.custom_minimum_size = box
	tile.add_theme_stylebox_override("panel", TierStyle.panel(0))

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	tile.add_child(column)

	var icon_holder := CenterContainer.new()
	icon_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var icon := TextureRect.new()
	icon.texture = art
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(box.x * 0.42, box.x * 0.42)
	icon_holder.add_child(icon)
	column.add_child(icon_holder)

	var name_label := Label.new()
	name_label.text = title
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(name_label)

	column.add_child(_price_button(key, price, on_buy))
	return tile


## The mock's "Price" selector: one per item, showing its gold price, stamped
## SOLD once bought and greyed when it is out of reach.
func _price_button(key: String, price: int, on_buy: Callable) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 34)
	if _sold.get(key, false):
		button.text = "SOLD"
		button.disabled = true
		return button
	button.text = "🪙 %d" % price
	button.disabled = Game.run.coins < price
	button.pressed.connect(func() -> void:
		if not Game.run.spend(price):
			return
		_sold[key] = true
		on_buy.call()
		_store_stock()
		_refresh())
	return button


# ---- the player's own loadout ------------------------------------------

func _refresh_loadout() -> void:
	var grid: GridContainer = _loadout_slots.get_meta("grid")
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	for index in RunState.EQUIP_CAP:
		if index < Game.run.equipped_ids.size():
			grid.add_child(_loadout_chit(Game.run.equipped_ids[index]))
		else:
			grid.add_child(_empty_slot())

	for child in _trash_slot.get_children():
		_trash_slot.remove_child(child)
		child.queue_free()
	if Game.run.trash_id != &"":
		_trash_slot.add_child(_loadout_chit(Game.run.trash_id, &"trash"))


## Doc: loadout abilities are "icon and ability name only. When hovered over,
## they are enlarged to their full ability look."
func _loadout_chit(id: StringName, zone: StringName = &"equipped") -> Control:
	var tier := Game.run.ability_tier(id)
	var def := Db.content.get_ability(id, tier)
	var chit := LayoutTab.AbilityChit.new()
	chit.ability_id = id
	chit.zone = zone
	chit.screen = self
	chit.custom_minimum_size = Vector2(102, 92)
	chit.add_theme_stylebox_override("panel", TierStyle.panel(tier, 2))
	chit.mouse_entered.connect(_show_preview.bind(chit, id, tier))
	chit.mouse_exited.connect(_hide_preview)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 2)
	chit.add_child(column)

	var icon_holder := CenterContainer.new()
	var icon := TextureRect.new()
	icon.texture = SuitAssets.ability_texture(id)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(38, 38)
	icon_holder.add_child(icon)
	column.add_child(icon_holder)

	var name_label := Label.new()
	name_label.text = def.name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_label.add_theme_font_size_override("font_size", 12)
	if tier > 0:
		name_label.add_theme_color_override("font_color", TierStyle.color(tier))
	column.add_child(name_label)
	return chit


func _empty_slot() -> Control:
	var slot := LayoutTab.DropZone.new()
	slot.zone = &"equipped"
	slot.screen = self
	slot.custom_minimum_size = Vector2(102, 92)
	slot.modulate.a = 0.35
	return slot


## The "enlarged to their full ability look" popup.
func _show_preview(anchor: Control, id: StringName, tier: int) -> void:
	_hide_preview()
	var def := Db.content.get_ability(id, tier)
	_preview = PanelContainer.new()
	_preview.top_level = true
	_preview.z_index = 220
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.add_theme_stylebox_override("panel", TierStyle.panel(tier))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_preview.add_child(column)

	var title := Label.new()
	title.text = def.name if tier == 0 else "%s (%s)" % [def.name, TierStyle.label(tier)]
	title.theme_type_variation = &"SubtitleLabel"
	title.add_theme_font_size_override("font_size", 22)
	if tier > 0:
		title.add_theme_color_override("font_color", TierStyle.color(tier))
	column.add_child(title)

	column.add_child(AbilityCard.cost_row(def))
	var limits := AbilityCard.limits_row(def)
	if limits.get_child_count() > 0:
		column.add_child(limits)
	var text := Label.new()
	text.text = def.description
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(280, 0)
	text.add_theme_font_size_override("font_size", 16)
	column.add_child(text)

	add_child(_preview)
	await get_tree().process_frame
	if _preview == null:
		return
	var box := _preview.get_combined_minimum_size()
	var at := anchor.global_position + Vector2(anchor.size.x + 12.0, 0)
	at.x = minf(at.x, get_viewport_rect().size.x - box.x - 12.0)
	at.y = clampf(at.y, 12.0, get_viewport_rect().size.y - box.y - 12.0)
	_preview.global_position = at


func _hide_preview() -> void:
	if _preview != null:
		_preview.queue_free()
		_preview = null


func _exit_tree() -> void:
	_hide_preview()


## Drag targets, shared with the Layout tab's chit classes.
func _on_swapped(dragged: StringName, onto: StringName) -> void:
	if not Game.run.swap_abilities(dragged, onto):
		_on_dropped(&"trash" if onto == Game.run.trash_id else &"equipped", dragged)
		return
	_refresh()


func _on_dropped(zone: StringName, id: StringName) -> void:
	match zone:
		&"equipped":
			if id == Game.run.trash_id:
				Game.run.restore_from_trash()
			else:
				Game.run.equip(id)
		&"trash":
			Game.run.move_to_trash(id)
	_refresh()


# ---- the machine, and applying a bought sticker ------------------------

func _refresh_machine() -> void:
	for child in _machine_box.get_children():
		_machine_box.remove_child(child)
		child.queue_free()
	var placing := _selected_sticker != &""
	_hint.text = "Click a reel symbol to place your %s sticker." \
		% String(_selected_sticker).capitalize() if placing \
		else "Buy a sticker to replace a symbol on your machine."

	# The player's machine is the same cabinet they play on (patch 0.22), at a
	# size that fits the loadout column.
	var reels_row := HBoxContainer.new()
	reels_row.alignment = BoxContainer.ALIGNMENT_CENTER
	reels_row.add_theme_constant_override("separation", 8)
	var cabinet := SlotCabinet.new()
	cabinet.art_scale = 0.55
	cabinet.marquee_text = ""
	var holder := CenterContainer.new()
	_machine_box.add_child(holder)
	holder.add_child(cabinet)
	cabinet.setup(SlotCabinet.Mode.GRID, reels_row)
	for reel_index in Game.run.machine.reels.size():
		var reel: Reel = Game.run.machine.reels[reel_index]
		var reel_column := VBoxContainer.new()
		reel_column.add_theme_constant_override("separation", 3)
		reels_row.add_child(reel_column)
		for slot_index in reel.symbols.size():
			var slot := LayoutTab._suit_button(reel.symbols[slot_index], Vector2(34, 34))
			slot.flat = not placing
			slot.disabled = not placing
			slot.pressed.connect(_apply_sticker.bind(reel_index, slot_index))
			reel_column.add_child(slot)
	cabinet.refresh_layout.call_deferred()


func _buy_reel() -> void:
	Audio.play_sfx(&"shop_buy")
	Game.run.machine.add_reel()
	# ONLY the reel is re-priced. Regenerating the whole stock here re-rolled
	# the abilities, the relics and the sticker prices too, so buying a reel
	# silently reset the shop (patch 0.20).
	_stock.reel = ShopStock.reel_offer(Game.run)
	_sold.erase("reel")


func _buy_sticker(suit: StringName) -> void:
	Audio.play_sfx(&"shop_buy")
	Game.run.sticker_inventory.append(suit)
	_selected_sticker = suit


func _buy_relic(relic_id: StringName) -> void:
	Audio.play_sfx(&"shop_buy")
	Game.run.relic_ids.append(relic_id)


func _buy_ability(ability_id: StringName) -> void:
	Audio.play_sfx(&"shop_buy")
	Game.run.acquire_ability(ability_id)


func _apply_sticker(reel_index: int, slot_index: int) -> void:
	if _selected_sticker == &"":
		return
	Audio.play_sfx(&"sticker_place")
	Game.run.machine.apply_sticker(reel_index, slot_index, _selected_sticker)
	Game.run.sticker_inventory.erase(_selected_sticker)
	_selected_sticker = &""
	_refresh()


func _load_texture(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null
