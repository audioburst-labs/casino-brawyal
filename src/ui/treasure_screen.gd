extends ScreenBase
## Treasure node: one random unowned relic, no choice.


func _ready() -> void:
	build_screen("Treasure!", "res://assets/backgrounds/bg_casino_floor.png")

	if ResourceLoader.exists("res://assets/props/treasure_chest.png"):
		var chest := TextureRect.new()
		chest.texture = load("res://assets/props/treasure_chest.png")
		chest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		chest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		chest.custom_minimum_size = Vector2(320, 320)
		var holder := CenterContainer.new()
		holder.add_child(chest)
		content.add_child(holder)

	Game.commit_encounter()   # the chest opens on arrival; nothing to replay
	var relic := Rewards.random_unowned_relic(Db.content, Game.run,
		Game.rng.stream(&"rewards"))
	if relic != &"":
		Game.run.relic_ids.append(relic)
		var def := Db.content.get_relic(relic)
		add_info_label("Relic: %s\n%s" % [def.name, def.description], 28)
	else:
		var lines := RunEffects.apply([{"op": "gain_coins", "min": 40, "max": 70}],
			Db.content, Game.run, Game.rng.stream(&"rewards"))
		add_info_label("The chest is nearly empty...\n%s" % "\n".join(lines), 28)

	add_continue_button()
