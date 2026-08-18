extends ScreenBase
## Shop: Stock tab (reel upgrade, stickers, relics, abilities) and Layout tab
## (apply bought stickers onto machine reel slots).

var _stock: Dictionary
var _coins_label: Label
var _tabs: TabContainer
var _stock_list: VBoxContainer
var _layout_box: VBoxContainer
var _selected_sticker: StringName = &""
var _sold: Dictionary = {}   # offer key -> true


func _ready() -> void:
	build_screen("The Shop", "res://assets/backgrounds/bg_shop.png")
	_stock = ShopStock.generate(Db.content, Game.run, Game.rng.stream(&"shop"))

	_coins_label = Label.new()
	_coins_label.theme_type_variation = &"SubtitleLabel"
	_coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_coins_label)

	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(900, 520)
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_tabs)

	var stock_scroll := ScrollContainer.new()
	stock_scroll.name = "Stock"
	_tabs.add_child(stock_scroll)
	_stock_list = VBoxContainer.new()
	_stock_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stock_list.add_theme_constant_override("separation", 10)
	stock_scroll.add_child(_stock_list)

	var layout_scroll := ScrollContainer.new()
	layout_scroll.name = "Layout"
	_tabs.add_child(layout_scroll)
	_layout_box = VBoxContainer.new()
	_layout_box.add_theme_constant_override("separation", 10)
	layout_scroll.add_child(_layout_box)

	add_continue_button("Leave Shop", Game.encounter_finished)
	_refresh()


func _refresh() -> void:
	_coins_label.text = "🪙 %d" % Game.run.coins
	_refresh_stock()
	_refresh_layout()


func _refresh_stock() -> void:
	for child in _stock_list.get_children():
		child.queue_free()

	var reel: Dictionary = _stock.reel
	if reel.available:
		_stock_list.add_child(_offer_row("reel", "Extra Reel",
			"Adds a reel to your machine (%d/%d)" % [
				Game.run.machine.reels.size(), SlotMachine.MAX_REELS],
			int(reel.price), _buy_reel))

	for sticker: Dictionary in _stock.stickers:
		var suit: StringName = sticker.suit
		_stock_list.add_child(_offer_row("sticker_%s" % suit,
			"%s Sticker" % String(suit).capitalize(),
			"Replace a reel symbol with a %s (apply in Layout tab)" % suit,
			int(sticker.price), _buy_sticker.bind(suit)))

	for offer: Dictionary in _stock.relics:
		var relic := Db.content.get_relic(offer.id)
		_stock_list.add_child(_offer_row("relic_%s" % offer.id,
			"Relic: %s" % relic.name, relic.description,
			int(offer.price), _buy_relic.bind(offer.id)))

	for offer: Dictionary in _stock.abilities:
		var ability := Db.content.get_ability(offer.id)
		_stock_list.add_child(_offer_row("ability_%s" % offer.id,
			"Ability: %s" % ability.name, ability.description,
			int(offer.price), _buy_ability.bind(offer.id)))


func _offer_row(key: String, title: String, description: String,
		price: int, on_buy: Callable) -> Control:
	var panel := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_box)
	var name_label := Label.new()
	name_label.text = title
	name_label.theme_type_variation = &"SubtitleLabel"
	name_label.add_theme_font_size_override("font_size", 24)
	text_box.add_child(name_label)
	var desc_label := Label.new()
	desc_label.text = description
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", 18)
	text_box.add_child(desc_label)

	var buy := Button.new()
	if _sold.get(key, false):
		buy.text = "SOLD"
		buy.disabled = true
	else:
		buy.text = "🪙 %d" % price
		buy.disabled = Game.run.coins < price
		buy.pressed.connect(func() -> void:
			if Game.run.spend(price):
				_sold[key] = true
				on_buy.call()
				_refresh())
	row.add_child(buy)
	return panel


func _buy_reel() -> void:
	Game.run.machine.add_reel()
	# Reel price scales per purchase: regenerate just the reel offer.
	_stock.reel = {
		"price": 100 + 50 * (Game.run.machine.reels.size() - SlotMachine.START_REELS),
		"available": Game.run.machine.reels.size() < SlotMachine.MAX_REELS,
	}
	_sold.erase("reel")


func _buy_sticker(suit: StringName) -> void:
	Game.run.sticker_inventory.append(suit)
	_tabs.current_tab = 1


func _buy_relic(relic_id: StringName) -> void:
	Game.run.relic_ids.append(relic_id)


func _buy_ability(ability_id: StringName) -> void:
	Game.run.ability_ids.append(ability_id)


func _refresh_layout() -> void:
	for child in _layout_box.get_children():
		child.queue_free()

	var inventory_row := HBoxContainer.new()
	inventory_row.add_theme_constant_override("separation", 10)
	_layout_box.add_child(inventory_row)
	var inventory_label := Label.new()
	inventory_label.text = "Stickers: " if not Game.run.sticker_inventory.is_empty() \
		else "No stickers owned — buy them in the Stock tab."
	inventory_row.add_child(inventory_label)
	for index in Game.run.sticker_inventory.size():
		var suit := Game.run.sticker_inventory[index]
		var sticker_button := Button.new()
		sticker_button.text = String(suit).capitalize()
		var icon := SuitAssets.suit_texture(suit)
		if icon != null:
			sticker_button.icon = icon
			sticker_button.expand_icon = true
			sticker_button.custom_minimum_size = Vector2(120, 56)
		if _selected_sticker == suit:
			sticker_button.modulate = Color(1.3, 1.25, 0.8)
		sticker_button.pressed.connect(func() -> void:
			_selected_sticker = suit if _selected_sticker != suit else &""
			_refresh_layout())
		inventory_row.add_child(sticker_button)

	var hint := Label.new()
	hint.text = "Select a sticker, then click a reel slot to replace that symbol." \
		if _selected_sticker != &"" else "Your machine:"
	hint.add_theme_font_size_override("font_size", 18)
	_layout_box.add_child(hint)

	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 14)
	_layout_box.add_child(grid)
	for reel_index in Game.run.machine.reels.size():
		var reel := Game.run.machine.reels[reel_index]
		var reel_column := VBoxContainer.new()
		reel_column.add_theme_constant_override("separation", 6)
		var header := Label.new()
		header.text = "Reel %d" % (reel_index + 1)
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.add_theme_font_size_override("font_size", 18)
		reel_column.add_child(header)
		for slot_index in reel.symbols.size():
			var suit := reel.symbols[slot_index]
			var slot_button := Button.new()
			slot_button.custom_minimum_size = Vector2(84, 64)
			var icon := SuitAssets.suit_texture(suit)
			if icon != null:
				slot_button.icon = icon
				slot_button.expand_icon = true
			else:
				slot_button.text = String(suit).left(1).to_upper()
			slot_button.disabled = _selected_sticker == &""
			slot_button.pressed.connect(
				_apply_sticker.bind(reel_index, slot_index))
			reel_column.add_child(slot_button)
		grid.add_child(reel_column)


func _apply_sticker(reel_index: int, slot_index: int) -> void:
	if _selected_sticker == &"":
		return
	Game.run.machine.apply_sticker(reel_index, slot_index, _selected_sticker)
	Game.run.sticker_inventory.erase(_selected_sticker)
	_selected_sticker = &""
	_refresh_layout()
