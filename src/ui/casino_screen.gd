extends ScreenBase
## The Casino encounter (doc v0.120): "Choose and play once in one of the
## casino's available games." The screen is a hub — three game cards, then the
## game the player picked, then what they won (patch 0.22).
##
## The games themselves live in src/ui/casino/ and are pure presentation over
## pure logic (`CasinoGame`, `DiceGame`, `RelicHunt`).

const GAMES := [
	{
		"id": &"slots", "title": "Slot Machine",
		"rules": "One free spin on the house.\nThree of a kind spins again.",
		"icon": "res://assets/props/slot_cabinet.png",
	},
	{
		"id": &"dice", "title": "Dice Game",
		"rules": "Roll toward exactly ten.\nGo past it and you win nothing.",
		"icon": "res://assets/icons/ability_loaded_dice.png",
	},
	{
		"id": &"hunt", "title": "Find the Relic",
		"rules": "Five cards, one relic.\nShuffle, then pick one.",
		"icon": "res://assets/icons/relic_house_chip.png",
	},
]

var _status: Label
var _choice_row: HBoxContainer
var _view: Control = null


func _ready() -> void:
	if Game.run == null and get_tree().current_scene == self:
		Game.run = RunState.new()  # standalone debug
		Game.run.coins = 100
		Game.rng = GameRng.new(randi())
	build_screen("The Casino", "res://assets/backgrounds/bg_casino_floor.png")
	_status = add_info_label("", 26)
	_refresh_status()
	_show_choice()


func _refresh_status() -> void:
	_status.text = "❤ %d / %d      🪙 %d" % [Game.run.hp, Game.run.max_hp, Game.run.coins]


func _show_choice() -> void:
	var prompt := add_info_label("Choose your game. You play one.", 22)
	_choice_row = HBoxContainer.new()
	_choice_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_choice_row.add_theme_constant_override("separation", 34)
	content.add_child(_choice_row)
	for game: Dictionary in GAMES:
		_choice_row.add_child(_game_card(game))
	add_continue_button("Walk Away", Game.encounter_finished)

	# CB_DEBUG_CASINO=slots|dice|hunt opens one game straight away.
	var forced := OS.get_environment("CB_DEBUG_CASINO")
	if forced != "":
		await get_tree().process_frame
		_play(StringName(forced), prompt)


func _game_card(game: Dictionary) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(300, 250)
	card.pressed.connect(_play.bind(game.id, null))
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)

	var icon_holder := CenterContainer.new()
	icon_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var icon := TextureRect.new()
	icon.texture = load(game.icon) if ResourceLoader.exists(game.icon) else null
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(110, 110)
	icon_holder.add_child(icon)
	box.add_child(icon_holder)

	var title := Label.new()
	title.text = game.title
	title.theme_type_variation = &"SubtitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var rules := Label.new()
	rules.text = game.rules
	rules.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.add_theme_font_size_override("font_size", 17)
	rules.custom_minimum_size = Vector2(0, 56)
	box.add_child(rules)
	return card


func _play(game_id: StringName, prompt: Label) -> void:
	if _view != null:
		return
	_choice_row.queue_free()
	_choice_row = null
	if prompt != null and is_instance_valid(prompt):
		prompt.queue_free()
	for child in content.get_children():
		# The "Walk Away" row goes with the choice; each game offers its own
		# way out once it has started.
		if child is HBoxContainer:
			child.queue_free()

	match game_id:
		&"dice":
			set_title("Dice Game")
			_view = DiceGameView.new()
		&"hunt":
			set_title("Find the Relic")
			_view = RelicHuntView.new()
		_:
			set_title("Slot Machine")
			_view = SlotGameView.new()
	content.add_child(_view)
	_view.finished.connect(_on_finished)
	_view.start(Game.rng.stream(&"rewards"))


## Every game ends the same way: what you won, with the relic's own art if you
## won one, and a way back to the map.
func _on_finished(lines: Array, relic_id: StringName) -> void:
	if _view != null:
		_view.queue_free()
		_view = null
	Game.commit_encounter()
	_refresh_status()
	if relic_id != &"":
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 16)
		row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		content.add_child(row)
		var icon := TextureRect.new()
		icon.texture = SuitAssets.relic_texture(relic_id)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(96, 96)
		var def := Db.content.get_relic(relic_id)
		icon.tooltip_text = "%s — %s" % [def.name, def.description] if def else String(relic_id)
		row.add_child(icon)
	var text: Array[String] = []
	for line in lines:
		text.append(str(line))
	add_info_label("\n".join(text) if not text.is_empty() else "You walk away empty-handed.", 28)
	add_continue_button("Continue", Game.encounter_finished)
