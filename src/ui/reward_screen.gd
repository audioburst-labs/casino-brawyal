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
	if int(args.get("healed", 0)) > 0:
		add_info_label("❤ Hard combat won — recovered %d HP" % int(args.healed), 24)

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
			var card := make_card(def.name,
				["Cost: %s" % cost_text, def.description] as Array[String],
				_pick_ability.bind(ability_id))
			card.custom_minimum_size = Vector2(380, 170)
			_ability_row.add_child(card)

	add_continue_button("Skip / Continue", Game.encounter_finished)


func _pick_ability(ability_id: StringName) -> void:
	Game.run.acquire_ability(ability_id)
	Game.encounter_finished()
