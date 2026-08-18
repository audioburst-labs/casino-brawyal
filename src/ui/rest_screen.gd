extends ScreenBase
## Rest node: heal 30% of max HP, or take a random reward instead.

var _choice_row: HBoxContainer


func _ready() -> void:
	build_screen("A Quiet Corner", "res://assets/backgrounds/bg_rest.png")
	add_info_label("❤ %d / %d    🪙 %d" % [Game.run.hp, Game.run.max_hp, Game.run.coins], 26)

	_choice_row = HBoxContainer.new()
	_choice_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_choice_row.add_theme_constant_override("separation", 40)
	content.add_child(_choice_row)

	var heal := int(ceil(Game.run.max_hp * 0.3))
	_choice_row.add_child(make_card("Rest",
		["Restore %d HP (30%% of max)" % heal] as Array[String], _on_rest))
	_choice_row.add_child(make_card("Scrounge",
		["Take a random reward instead"] as Array[String], _on_reward))


func _on_rest() -> void:
	var healed: int = mini(int(ceil(Game.run.max_hp * 0.3)), Game.run.max_hp - Game.run.hp)
	Game.run.hp += healed
	_finish("You rest by the fire.\n+%d HP" % healed)


func _on_reward() -> void:
	var reward_rng := Game.rng.stream(&"rewards")
	var lines: Array[String]
	var relic := Rewards.random_unowned_relic(Db.content, Game.run, reward_rng)
	if relic != &"" and reward_rng.randi_range(0, 1) == 0:
		Game.run.relic_ids.append(relic)
		lines = ["You find something tucked under the cushions.",
			"Relic: %s" % Db.content.get_relic(relic).name]
	else:
		lines = RunEffects.apply([{"op": "gain_coins",
			"min": Game.run.encounter_number() * 6,
			"max": Game.run.encounter_number() * 10}], Db.content, Game.run, reward_rng)
		lines.push_front("Loose change in the sofa. Jackpot... sort of.")
	_finish("\n".join(lines))


func _finish(message: String) -> void:
	_choice_row.queue_free()
	add_info_label(message, 28)
	add_continue_button()
