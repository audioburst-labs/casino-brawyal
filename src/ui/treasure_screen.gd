class_name TreasureScreen
extends ScreenBase
## Treasure node (build 1.30, from the designer's mock): the chest glows, and the one
## unowned relic it holds arrives in a gold tile. When every relic is owned it pays
## coins instead.


func _ready() -> void:
	build_screen("Treasure!", "res://assets/backgrounds/bg_casino_floor.png")
	_title_label.add_theme_font_size_override("font_size", 80)
	_title_label.get_parent().add_theme_constant_override("separation", 6)
	content.add_theme_constant_override("separation", 12)
	add_eyebrow("Treasure").add_theme_color_override("font_color", NeonPalette.current().tube_hi)

	content.add_child(_chest())

	Game.commit_encounter()   # the chest opens on arrival; nothing to replay
	Audio.play_sfx(&"treasure_open")
	var reward_rng := Game.rng.stream(&"rewards")
	var tile_row := HBoxContainer.new()
	tile_row.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(tile_row)
	var relic := Rewards.random_unowned_relic(Db.content, Game.run, reward_rng)
	if relic != &"":
		Game.run.relic_ids.append(relic)
		tile_row.add_child(RewardTiles.relic_tile(relic, "Relic"))
	else:
		var before := Game.run.coins
		RunEffects.apply([{"op": "gain_coins", "min": 40, "max": 70}],
			Db.content, Game.run, reward_rng)
		tile_row.add_child(RewardTiles.coin_tile(Game.run.coins - before, "Coins found"))
		var line := Label.new()
		line.text = "The chest is nearly empty."
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.add_theme_font_size_override("font_size", 26)
		line.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		line.add_theme_constant_override("outline_size", 6)
		content.add_child(line)

	add_continue_button()


## The chest on a warm glow.
func _chest() -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 320)
	var glow := GradientTexture2D.new()
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5, 0.5)
	glow.fill_to = Vector2(1.0, 0.5)
	glow.width = 512
	glow.height = 512
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.79, 0.35, 0.5))
	gradient.set_color(1, Color(1.0, 0.79, 0.35, 0.0))
	glow.gradient = gradient
	var halo := TextureRect.new()
	halo.texture = glow
	halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	halo.set_anchors_preset(Control.PRESET_CENTER)
	halo.offset_left = -330.0
	halo.offset_right = 330.0
	halo.offset_top = -330.0
	halo.offset_bottom = 330.0
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(halo)
	if ResourceLoader.exists("res://assets/props/treasure_chest.png"):
		var chest := TextureRect.new()
		chest.texture = load("res://assets/props/treasure_chest.png")
		chest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		chest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		chest.set_anchors_preset(Control.PRESET_FULL_RECT)
		chest.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(chest)
	return holder
