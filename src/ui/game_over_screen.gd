extends ScreenBase
## Run over. Show a summary and return to the menu.


func _ready() -> void:
	build_screen("THE HOUSE WINS", "res://assets/backgrounds/bg_main_menu.png")
	add_info_label("Ace fell at encounter %d of 10.\nCoins gathered: %d\nSeed: %d" % [
		Game.run.history.size(), Game.run.coins, Game.run.seed_value], 26)
	add_continue_button("Return to Menu",
		func() -> void: Game.goto_screen("res://scenes/screens/main_menu.tscn"))
