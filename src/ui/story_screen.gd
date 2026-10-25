extends ScreenBase
## Story encounter: illustration, narrative text, 2-4 choices, outcome.

var _event: Defs.StoryEventDef
var _choice_row: BoxContainer


func setup(args: Dictionary) -> void:
	_event = Db.content.get_story_event(args.get("event"))
	build_screen(_event.title, "res://assets/backgrounds/bg_map.png")

	add_eyebrow("Story")
	# Illustration on the left, the telling and the choices on the right (0.126).
	var body_row := HBoxContainer.new()
	body_row.alignment = BoxContainer.ALIGNMENT_CENTER
	body_row.add_theme_constant_override("separation", 36)
	content.add_child(body_row)

	if ResourceLoader.exists(_event.image):
		var frame := PanelContainer.new()
		var illustration := TextureRect.new()
		illustration.texture = load(_event.image)
		illustration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		illustration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		illustration.custom_minimum_size = Vector2(560, 440)
		frame.add_child(illustration)
		body_row.add_child(frame)

	# The telling and the choices share one framed panel (0.126, the mock's).
	var frame_panel := PanelContainer.new()
	body_row.add_child(frame_panel)
	var text_column := VBoxContainer.new()
	text_column.add_theme_constant_override("separation", 14)
	text_column.custom_minimum_size = Vector2(640, 0)
	frame_panel.add_child(text_column)

	var panel := Control.new()
	panel.visible = false   # placeholder so the description label below keeps its parent
	text_column.add_child(panel)
	var body := Label.new()
	body.text = _event.description
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(600, 0)
	body.add_theme_font_override("font", AbilityCard.body_font())
	body.add_theme_font_size_override("font_size", 22)
	text_column.add_child(body)

	_choice_row = VBoxContainer.new()
	_choice_row.add_theme_constant_override("separation", 10)
	text_column.add_child(_choice_row)
	for choice: Dictionary in _event.choices:
		_choice_row.add_child(_option_button(_choice_row.get_child_count() + 1, choice))


const OPTION_ICONS := [
	["grant_relic", "res://assets/icons/relic_house_chip.png"],
	["casino_spin", "res://assets/icons/suit_any.png"],
	["grant_sticker", "res://assets/icons/suit_any.png"],
	["gain_coins", "res://assets/icons/coin.png"],
	["heal_pct", "res://assets/icons/icon_health.png"],
	["lose_hp", "res://assets/icons/icon_health.png"],
]


## One choice, the mock's way: a round icon, a bold title with what it does under
## it, and its number at the right, all inside the lit frame.
func _option_button(number: int, choice: Dictionary) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(640, 96)
	button.pressed.connect(_pick.bind(choice))
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 14
	row.offset_right = -18
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)

	var disc := PanelContainer.new()
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ring := StyleBoxFlat.new()
	ring.bg_color = NeonPalette.current().glass_deep
	ring.border_color = NeonPalette.current().tube
	ring.set_border_width_all(2)
	ring.set_corner_radius_all(34)
	ring.shadow_color = NeonPalette.alpha(NeonPalette.current().tube, 0.5)
	ring.shadow_size = 8
	ring.set_content_margin_all(10)
	disc.add_theme_stylebox_override("panel", ring)
	var icon := TextureRect.new()
	icon.texture = _option_icon(choice)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(48, 48)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.add_child(icon)
	row.add_child(disc)

	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 2)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(words)
	var title := Label.new()
	title.text = str(choice.get("label", "?"))
	title.theme_type_variation = &"SubtitleLabel"
	title.add_theme_font_size_override("font_size", 28)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(title)
	var summary := Label.new()
	summary.text = RunEffects.summary_text(choice, Game.run)
	summary.add_theme_font_override("font", AbilityCard.body_font())
	summary.add_theme_font_size_override("font_size", 19)
	summary.add_theme_color_override("font_color", NeonPalette.current().dim)
	summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(summary)

	var index := Label.new()
	index.text = str(number)
	index.theme_type_variation = &"SubtitleLabel"
	index.add_theme_font_size_override("font_size", 26)
	index.add_theme_color_override("font_color", NeonPalette.current().tube_hi)
	index.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(index)
	return button


static func _option_icon(choice: Dictionary) -> Texture2D:
	var ops: Array[String] = []
	for effect: Dictionary in choice.get("effects", []):
		ops.append(str(effect.get("op", "")))
	for pair: Array in OPTION_ICONS:
		if ops.has(pair[0]) and ResourceLoader.exists(pair[1]):
			return load(pair[1])
	return load("res://assets/icons/encounter_story.png") if ResourceLoader.exists("res://assets/icons/encounter_story.png") else null


func _pick(choice: Dictionary) -> void:
	Audio.play_sfx(&"ui_confirm")
	Game.commit_encounter()   # the choice is made; nothing left to replay
	var lines := RunEffects.apply(choice.get("effects", []),
		Db.content, Game.run, Game.rng.stream(&"rewards"))
	_choice_row.queue_free()
	# Patch 0.1: describe what happened with the chosen result, not just numbers.
	var outcome := str(choice.get("outcome", ""))
	if outcome == "" and lines.is_empty():
		outcome = "You move on."
	add_info_label(outcome, 24)
	if not lines.is_empty():
		add_info_label("\n".join(lines), 28)
	# Some choices pick a fight rather than paying out (the sheet's Guarded
	# Treasure). The prize rides on the run and is paid only if it is won, so
	# there is no Continue here: the button walks into the combat instead.
	if str(choice.get("then", "")) == "combat":
		add_continue_button("Fight", func() -> void:
			Game.story_started_a_fight(choice.get("bonus_rewards", [])))
		return
	add_continue_button()


## CB_DEBUG_STORY="cheap_tricks": open this screen on its own with that event,
## for reviewing the illustration and the choice cards without walking a run
## into a story node. Does nothing once `setup` has run for real.
func _ready() -> void:
	var forced := OS.get_environment("CB_DEBUG_STORY")
	if forced == "" or _event != null:
		return
	if Game.run == null:
		Game.rng = GameRng.new(4242)
		Game.run = RunState.new()
		Game.run.max_hp = 80
		Game.run.hp = 55
		Game.run.coins = 120
	setup({"event": StringName(forced)})
