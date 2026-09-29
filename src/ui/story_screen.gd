extends ScreenBase
## Story encounter: illustration, narrative text, 2-4 choices, outcome.

var _event: Defs.StoryEventDef
var _choice_row: HBoxContainer


func setup(args: Dictionary) -> void:
	_event = Db.content.get_story_event(args.get("event"))
	build_screen(_event.title, "res://assets/backgrounds/bg_map.png")

	if ResourceLoader.exists(_event.image):
		var illustration := TextureRect.new()
		illustration.texture = load(_event.image)
		illustration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		illustration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		illustration.custom_minimum_size = Vector2(720, 400)
		var holder := CenterContainer.new()
		holder.add_child(illustration)
		content.add_child(holder)

	var panel := PanelContainer.new()
	content.add_child(panel)
	var body := Label.new()
	body.text = _event.description
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(760, 0)
	panel.add_child(body)

	_choice_row = HBoxContainer.new()
	_choice_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_choice_row.add_theme_constant_override("separation", 24)
	content.add_child(_choice_row)
	for choice: Dictionary in _event.choices:
		var card := make_card(choice.get("label", "?"),
			[str(choice.get("summary", ""))] as Array[String], _pick.bind(choice))
		card.custom_minimum_size = Vector2(300, 130)
		_choice_row.add_child(card)


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
