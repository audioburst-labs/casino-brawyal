extends SceneTree
## Renders a scene for N frames, saves a PNG, and quits — the agent's eyes.
## Needs a window (not --headless).
##
## Usage: godot --path . -s tools/screenshot.gd -- <res://scene.tscn> <frames> <out.png>

var _frames := 0
var _target_frames := 60
var _out_path := "screenshot.png"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("usage: -s tools/screenshot.gd -- <scene> <frames> <out.png>")
		quit(1)
		return
	_target_frames = int(args[1])
	_out_path = args[2]
	change_scene_to_file.call_deferred(args[0])
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frames += 1
	if _frames < _target_frames:
		return
	process_frame.disconnect(_on_frame)
	var image := root.get_texture().get_image()
	image.save_png(_out_path)
	print("screenshot saved: " + _out_path)
	quit(0)
