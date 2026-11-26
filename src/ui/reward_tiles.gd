class_name RewardTiles
extends RefCounted
## The lit glass tiles the reward, rest and treasure screens show what you got in
## (build 1.30): a coin tile, a relic tile and a heal tile share one panel look.

const GOLD := Color(1.0, 0.79, 0.35)
const HEAL := Color(1.0, 0.44, 0.58)


## A lit glass tile: the reward's own panel, edged in `edge`.
static func tile(edge: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = NeonPalette.current().glass
	box.border_color = edge
	box.set_border_width_all(2)
	box.set_corner_radius_all(18)
	box.content_margin_left = 26
	box.content_margin_right = 34
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	box.shadow_color = Color(edge, 0.45)
	box.shadow_size = 16
	panel.add_theme_stylebox_override("panel", box)
	return panel


static func icon(texture: Texture2D, side: float) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(side, side)
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return rect


static func caption(text: String, colour: Color) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", colour)
	return label


static func big_number(text: String, colour: Color, size: int = 58) -> Label:
	var number := Label.new()
	number.text = text
	number.theme_type_variation = &"SubtitleLabel"
	number.add_theme_font_size_override("font_size", size)
	number.add_theme_color_override("font_color", colour)
	return number


static func coin_tile(coins: int, label: String = "Coins won") -> Control:
	var palette := NeonPalette.current()
	var panel := tile(palette.tube)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)
	if ResourceLoader.exists("res://assets/icons/coin.png"):
		row.add_child(icon(load("res://assets/icons/coin.png"), 72))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", -4)
	row.add_child(column)
	column.add_child(caption(label, palette.dim))
	column.add_child(big_number("+%d" % coins, GOLD))
	return panel


## A relic with its own art, name and full text.
static func relic_tile(relic: StringName, label: String) -> Control:
	var def := Db.content.get_relic(relic)
	var panel := tile(GOLD)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	panel.add_child(row)
	row.add_child(icon(SuitAssets.relic_texture(relic), 96))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	row.add_child(column)
	column.add_child(caption(label, GOLD))
	var name_label := Label.new()
	name_label.text = def.name
	name_label.theme_type_variation = &"SubtitleLabel"
	name_label.add_theme_font_size_override("font_size", 32)
	column.add_child(name_label)
	var text := Label.new()
	text.text = def.description
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(500, 0)
	text.add_theme_font_size_override("font_size", 21)
	column.add_child(text)
	return panel


## Healing: the heart, "+N HP" and the bar at its new level.
static func heal_tile(healed: int, hp: int, max_hp: int) -> Control:
	var panel := tile(HEAL)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	panel.add_child(row)
	var heart := NeonHeart.new()
	heart.custom_minimum_size = Vector2(100, 100)
	heart.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(heart)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(320, 0)
	column.add_theme_constant_override("separation", 2)
	row.add_child(column)
	column.add_child(caption("Healed", HEAL))
	column.add_child(big_number("+%d HP" % healed, HEAL, 64))
	var bar := HealBar.new()
	bar.setup(hp, 0, max_hp)
	column.add_child(bar)
	var reading := Label.new()
	reading.text = "%d / %d" % [hp, max_hp]
	reading.add_theme_font_size_override("font_size", 18)
	column.add_child(reading)
	return panel
