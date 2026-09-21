extends ScreenBase
## The boss is beaten, and the run is complete.
##
## The name comes from the enemy def rather than a literal (patch 0.116): the
## data calls him Mr. Moneybags and this screen used to shout "MR. MONEYMAN
## DEFEATED", so whoever actually beat him was congratulated on killing
## somebody else. The doc and the sheet still disagree about his name; reading
## it from the def means the game at least agrees with itself either way.

const BOSS_ID := &"mr_moneybags"


func _ready() -> void:
	var boss := Db.content.get_enemy(BOSS_ID)
	var name := boss.name if boss != null else "The boss"
	build_screen("%s DEFEATED!" % name.to_upper(),
		"res://assets/backgrounds/bg_main_menu.png")
	add_info_label("Ace settled the score.\nCoins gathered: %d    Relics: %d\nSeed: %d" % [
		Game.run.coins, Game.run.relic_ids.size(), Game.run.seed_value], 28)
	add_continue_button("Return to Menu",
		func() -> void: Game.goto_screen("res://scenes/screens/main_menu.tscn"))
