extends ScreenBase
## Mr. Moneyman is beaten — the run is complete.


func _ready() -> void:
	build_screen("MR. MONEYMAN DEFEATED!", "res://assets/backgrounds/bg_main_menu.png")
	add_info_label("Ace settled the score.\nCoins gathered: %d    Relics: %d\nSeed: %d" % [
		Game.run.coins, Game.run.relic_ids.size(), Game.run.seed_value], 28)
	add_continue_button("Return to Menu",
		func() -> void: Game.goto_screen("res://scenes/screens/main_menu.tscn"))
