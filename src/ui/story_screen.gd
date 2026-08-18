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
	var lines := RunEffects.apply(choice.get("effects", []),
		Db.content, Game.run, Game.rng.stream(&"rewards"))
	_choice_row.queue_free()
	if lines.is_empty():
		lines.append("You move on.")
	add_info_label("\n".join(lines), 28)
	add_continue_button()
