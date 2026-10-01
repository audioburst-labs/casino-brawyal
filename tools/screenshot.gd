extends SceneTree
## Renders a scene for N frames, saves a PNG, and quits — the agent's eyes.
## Needs a window (not --headless).
##
## Usage: godot --path . -s tools/screenshot.gd -- <res://scene.tscn> <frames> <out.png>
##
## Frame sequences (0.121, for the Steam page GIFs): with
## CB_CAPTURE_EVERY=K set, every K-th frame from CB_CAPTURE_FROM (default 1)
## up to <frames> is saved as <out>_0001.png, <out>_0002.png... and
## tools/capture_gif.ps1 turns the folder into a GIF with ffmpeg.

var _frames := 0
var _target_frames := 60
var _out_path := "screenshot.png"
var _every := 0
var _from := 1
var _saved := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("usage: -s tools/screenshot.gd -- <scene> <frames> <out.png>")
		quit(1)
		return
	_target_frames = int(args[1])
	_out_path = args[2]
	_every = OS.get_environment("CB_CAPTURE_EVERY").to_int()
	_from = maxi(1, OS.get_environment("CB_CAPTURE_FROM").to_int())
	change_scene_to_file.call_deferred(args[0])
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frames += 1
	if _every > 0:
		if _frames >= _from and (_frames - _from) % _every == 0:
			_saved += 1
			var path := "%s_%04d.png" % [_out_path.get_basename(), _saved]
			root.get_texture().get_image().save_png(path)
		if _frames < _target_frames:
			return
		process_frame.disconnect(_on_frame)
		print("sequence saved: %d frames as %s_NNNN.png" % [_saved, _out_path.get_basename()])
		quit(0)
		return
	if _frames < _target_frames:
		return
	process_frame.disconnect(_on_frame)
	var image := root.get_texture().get_image()
	image.save_png(_out_path)
	print("screenshot saved: " + _out_path)
	quit(0)
