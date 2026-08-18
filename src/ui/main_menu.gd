extends Control
## Main menu. Uses the generated key art when it exists; Continue lands in M7.


func _ready() -> void:
	if ResourceLoader.exists("res://assets/backgrounds/bg_main_menu.png"):
		var art := TextureRect.new()
		art.texture = load("res://assets/backgrounds/bg_main_menu.png")
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		add_child(art)
		move_child(art, 1)  # above the ColorRect, below the menu column
	$CenterContainer/VBox/Title.theme_type_variation = &"TitleLabel"
	if RunSave.has_save():
		var continue_button := Button.new()
		continue_button.text = "Continue"
		continue_button.add_theme_font_size_override("font_size", 40)
		continue_button.pressed.connect(func() -> void: Game.continue_run())
		var vbox := $CenterContainer/VBox
		vbox.add_child(continue_button)
		vbox.move_child(continue_button, 1)  # right under the title


func _on_play_pressed() -> void:
	Game.new_run()


func _on_quit_pressed() -> void:
	get_tree().quit()
