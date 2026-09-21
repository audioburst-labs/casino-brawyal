extends ScreenBase
## The Choice screen (doc "Choice", rebuilt patch 0.116).
##
## Header, the offered encounters as framed cards with an icon, a name and a
## description, and the path to the boss underneath. #1 is always a combat and
## #10 is always the boss, so those arrive as a single option.
##
## HP and coins are NOT drawn here: `HeaderHud` has owned both since patch
## 0.18 and this screen used to print a second, quietly different copy.

const TYPE_LABELS := {
	&"combat": "Combat",
	&"elite": "Elite",
	&"story": "Story",
	&"rest": "Rest",
	&"treasure": "Treasure",
	&"casino": "Casino",
	&"shop": "Shop",
	&"boss": "BOSS: Mr. Moneybags",
}
const TYPE_FLAVOR := {
	&"combat": "The house always sends someone.",
	&"elite": "A mini-boss with its own tricks. Beat it for a relic.",
	&"story": "Something is happening here...",
	&"rest": "A quiet corner to catch your breath.",
	&"treasure": "Something glitters in the dark.",
	&"casino": "Try your luck at the tables.",
	&"shop": "Spend your winnings.",
	&"boss": "Time to settle the score.",
}

const CARD_SIZE := Vector2(380, 250)


func _ready() -> void:
	_debug_standalone_run()
	build_screen("Encounter %d of 10" % Game.run.encounter_number(),
		"res://assets/backgrounds/bg_map.png")

	var options := Game.map_options()

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)
	content.add_child(row)
	for option: Dictionary in options:
		row.add_child(_option_card(option))

	# The road so far, the fork here, and the boss at the end.
	var ribbon := PathRibbon.new()
	ribbon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(ribbon)
	var offered: Array[StringName] = []
	for option: Dictionary in options:
		offered.append(StringName(option.type))
	ribbon.show_path(Game.run.history, offered)

	var loadout_row := HBoxContainer.new()
	loadout_row.alignment = BoxContainer.ALIGNMENT_CENTER
	loadout_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(loadout_row)
	var loadout_button := Button.new()
	loadout_button.text = "Abilities (%d equipped)" % Game.run.equipped_ids.size()
	loadout_button.pressed.connect(Game.show_loadout)
	loadout_row.add_child(loadout_button)


## The doc's four parts: frame, icon, name, description. Built as a Button
## with an inset column rather than `Button.icon`, which would draw the
## 1024 px source at its native size.
func _option_card(option: Dictionary) -> Button:
	var type := StringName(option.type)
	var button := Button.new()
	button.custom_minimum_size = CARD_SIZE
	button.pressed.connect(func() -> void: Game.choose_encounter(option))

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 8)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(column)

	var art := "res://assets/icons/encounter_%s.png" % String(type)
	if ResourceLoader.exists(art):
		var holder := CenterContainer.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := TextureRect.new()
		icon.texture = load(art)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(96, 96)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(icon)
		column.add_child(holder)

	var name_label := Label.new()
	name_label.text = TYPE_LABELS.get(type, String(type))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.theme_type_variation = &"SubtitleLabel"
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(name_label)

	var description := Label.new()
	var text: String = TYPE_FLAVOR.get(type, "")
	if option.has("variant"):
		text = "%s\nVariant: %s" % [text, option.variant]
	description.text = text
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size = Vector2(CARD_SIZE.x - 44, 0)
	description.add_theme_color_override("font_color", Color(0.86, 0.82, 0.74))
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(description)

	return button


## CB_DEBUG_MAP="combat,story,rest": open this screen on its own with that
## history already behind the player, so the path ribbon can be reviewed at
## any depth without playing seven encounters to get there. Does nothing
## inside a real run, where `Game.run` is already set.
func _debug_standalone_run() -> void:
	if Game.run != null:
		return
	var history := OS.get_environment("CB_DEBUG_MAP")
	Game.rng = GameRng.new(12345)
	Game.run = RunState.new()
	Game.run.max_hp = 80
	Game.run.hp = 62
	Game.run.coins = 140
	for type in history.split(",", false):
		Game.run.history.append(StringName(type.strip_edges()))
