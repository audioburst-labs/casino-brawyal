extends Control
## Main menu. Uses the generated key art when it exists; Continue lands in M7.


func _ready() -> void:
	if ResourceLoader.exists("res://assets/backgrounds/bg_main_menu.png"):
		# The key art as a living night (0.119): rain, the wet street, the
		# spade and canopy breathing, searchlights on the clouds, lightning.
		var art := LivingBackdrop.night_exterior()
		add_child(art)
		move_child(art, 1)  # above the ColorRect, below the menu column
	$CenterContainer/VBox/Title.theme_type_variation = &"TitleLabel"
	# Codex (0.121): the rules in plain words, readable before the first run.
	var codex_button := Button.new()
	codex_button.text = "Codex"
	codex_button.add_theme_font_size_override("font_size", 40)
	codex_button.pressed.connect(func() -> void:
		var hud := get_tree().current_scene.get_node_or_null("HudLayer")
		(hud if hud != null else get_tree().current_scene).add_child(CodexTab.new()))
	$CenterContainer/VBox.add_child(codex_button)
	$CenterContainer/VBox.move_child(codex_button, $CenterContainer/VBox.get_child_count() - 2)
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
