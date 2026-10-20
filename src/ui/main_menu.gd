extends Control
## Title screen (doc "Title Screen", redesigned in patch 0.125 from the
## designer's mock): the Dreams Casino in the rain filling the screen, with the
## neon Casino Brawyal menu on the left. The scene and the panel are their own
## classes under src/ui/title/; this only wires the buttons.
##
## Continue appears only when there is a saved run. The Play Tutorial toggle is
## the old test switch (AppSettings.play_tutorial): while it is on, every new run
## opens with the tutorial whether or not it was completed before.

var _panel: TitlePanel


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var backdrop := TitleBackdrop.new()
	add_child(backdrop)
	_panel = TitlePanel.new()
	add_child(_panel)
	_panel.setup(RunSave.has_save(), Telemetry.settings != null and Telemetry.settings.play_tutorial)
	_panel.play_pressed.connect(_on_play_pressed)
	_panel.continue_pressed.connect(func() -> void: Game.continue_run())
	_panel.settings_pressed.connect(func() -> void: _open_overlay(SettingsTab.new()))
	_panel.codex_pressed.connect(func() -> void: _open_overlay(CodexTab.new()))
	_panel.quit_pressed.connect(_on_quit_pressed)
	_panel.tutorial_toggled.connect(func(on: bool) -> void: SettingsTab.persist("play_tutorial", on))


## Settings and the Codex are full-screen overlays that live in the header's layer.
func _open_overlay(tab: Control) -> void:
	var hud := get_tree().current_scene.get_node_or_null("HudLayer")
	(hud if hud != null else get_tree().current_scene).add_child(tab)


func _on_play_pressed() -> void:
	Game.new_run()


func _on_quit_pressed() -> void:
	get_tree().quit()
