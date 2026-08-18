extends SceneTree
## Removes a flat magenta (#FF00FF) background from generated PNGs, in place.
## gpt-image-2 can't output true transparency, so sprites are generated on a
## magenta screen and keyed out here.
##
## Usage: godot --headless -s tools/art/chroma_key.gd -- <abs_path.png> [...]
##
## Keying: magenta-ness m = min(r, b) - g. m >= HARD -> fully transparent;
## SOFT..HARD -> partial alpha with the magenta cast neutralized (edge pixels).

const HARD := 0.55
const SOFT := 0.18


func _init() -> void:
	var failed := false
	for path in OS.get_cmdline_user_args():
		if not _key_file(path):
			failed = true
	await process_frame
	quit(1 if failed else 0)


func _key_file(path: String) -> bool:
	var img := Image.load_from_file(path)
	if img == null:
		push_error("cannot load: " + path)
		return false
	img.convert(Image.FORMAT_RGBA8)
	var cleared := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var m := minf(c.r, c.b) - c.g
			if m >= HARD:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				cleared += 1
			elif m > SOFT:
				var alpha := 1.0 - (m - SOFT) / (HARD - SOFT)
				var detinted := Color(c.g, c.g, c.g, c.a * alpha)
				img.set_pixel(x, y, detinted)
	img.save_png(path)
	print("keyed %s (%d px cleared)" % [path.get_file(), cleared])
	return true
