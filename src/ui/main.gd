extends Control
## Root scene: hosts ScreenRoot (screens swap here), HudLayer, and FxLayer.


func _ready() -> void:
	Game.register_screen_root($ScreenRoot)
	Fx.set_shake_target($ScreenRoot)
	Fx.init_cursor()
	HeaderHud.attach(self)
	# CB_DEBUG_AUTORUN=1: skip the main menu straight into a fresh run
	# (header/settings/layout-tab review).
	if OS.get_environment("CB_DEBUG_AUTORUN") != "":
		Game.new_run(-1, true)
		# CB_DEBUG_OPEN_SETTINGS / CB_DEBUG_OPEN_LAYOUT=1: pop the matching
		# header overlay open for review.
		if OS.get_environment("CB_DEBUG_OPEN_SETTINGS") != "":
			await get_tree().create_timer(0.5).timeout
			$HudLayer.add_child(SettingsTab.new())
		if OS.get_environment("CB_DEBUG_OPEN_LAYOUT") != "":
			await get_tree().create_timer(0.5).timeout
			$HudLayer.add_child(LayoutTab.new())
	else:
		Game.goto_screen("res://scenes/screens/main_menu.tscn")
