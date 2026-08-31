extends ScreenBase
## Post-combat rewards: coins (auto-claimed), pick 1 of 2 abilities, and a
## relic after Hard Combat.

var _ability_row: HBoxContainer


func setup(args: Dictionary) -> void:
	build_screen("Winnings", "res://assets/backgrounds/bg_casino_floor.png")
	var reward_rng := Game.rng.stream(&"rewards")

	var coins := Rewards.roll_coins(
		int(args.get("gold_min", 0)), int(args.get("gold_max", 0)), reward_rng)
	Game.run.coins += coins
	add_info_label("🪙 +%d coins" % coins, 30)

	if args.get("hard", false):
		var relic := Rewards.random_unowned_relic(Db.content, Game.run, reward_rng)
		if relic != &"":
			Game.run.relic_ids.append(relic)
			var def := Db.content.get_relic(relic)
			add_info_label("Hard combat bonus — Relic: %s\n%s" % [def.name, def.description], 24)

	var choices := Rewards.ability_choices(Db.content, Game.run, reward_rng)
	if not choices.is_empty():
		add_info_label("Choose a new ability:", 24)
		_ability_row = HBoxContainer.new()
		_ability_row.alignment = BoxContainer.ALIGNMENT_CENTER
		_ability_row.add_theme_constant_override("separation", 30)
		content.add_child(_ability_row)
		for ability_id: StringName in choices:
			var def := Db.content.get_ability(ability_id)
			var cost_text := " ".join(def.cost.map(
				func(s: StringName) -> String: return String(s).left(1).to_upper()))
			_ability_row.add_child(_build_ability_card(def.name,
				"Cost: %s\n%s" % [cost_text, def.description], ability_id))

	add_continue_button("Skip / Continue", Game.encounter_finished)


## A Button's own text never wraps, so a long description could grow wider
## than its sibling card and crowd it off-screen (patch 0.17). This builds
## the button with an internal wrapped Label instead, capping its width so
## there's always room for both choices.
const CARD_WIDTH := 380.0


func _build_ability_card(title: String, body: String, ability_id: StringName) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(CARD_WIDTH, 170)
	card.pressed.connect(_pick_ability.bind(ability_id))
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)
	var title_label := Label.new()
	title_label.text = title
	title_label.theme_type_variation = &"SubtitleLabel"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(title_label)
	var body_label := Label.new()
	body_label.text = body
	body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	body_label.custom_minimum_size = Vector2(CARD_WIDTH - 24.0, 0)
	box.add_child(body_label)
	return card


func _pick_ability(ability_id: StringName) -> void:
	Game.run.acquire_ability(ability_id)
	Game.encounter_finished()
