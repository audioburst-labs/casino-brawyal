extends Control
## Root scene: hosts ScreenRoot (screens swap here), HudLayer, and FxLayer.


func _ready() -> void:
	Game.register_screen_root($ScreenRoot)
	Fx.set_shake_target($ScreenRoot)
	_set_custom_cursor()
	Game.goto_screen("res://scenes/screens/main_menu.tscn")


## The dealer's-glove mouse cursor (patch 0.13).
func _set_custom_cursor() -> void:
	if not ResourceLoader.exists("res://assets/icons/cursor_glove.png"):
		return
	var image: Image = (load("res://assets/icons/cursor_glove.png") as Texture2D).get_image()
	image.resize(48, 48, Image.INTERPOLATE_LANCZOS)
	Input.set_custom_mouse_cursor(ImageTexture.create_from_image(image),
		Input.CURSOR_ARROW, Vector2(8, 4))
