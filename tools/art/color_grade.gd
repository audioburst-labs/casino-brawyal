extends SceneTree
## One-shot colour grade for character sprites, in place. The generated art
## carries the casino's warm lighting baked in — every sprite averaged far
## more red than blue — and the designer read it as "a red hue on all
## characters" (0.0.111). This cools the balance and pulls a little saturation
## out, with ONE shared curve so idle art and its pose frames stay identical.
##
## Usage: godot --headless -s tools/art/color_grade.gd -- <abs_path.png> [...]
## NOT idempotent: run it once per file. Pose frames generated later from an
## already-graded base inherit the look and must not be graded again.

const GAIN := Vector3(0.89, 1.0, 1.13)
const DESATURATE := 0.10


func _init() -> void:
	var failed := false
	for path in OS.get_cmdline_user_args():
		if not _grade_file(path):
			failed = true
	await process_frame
	quit(1 if failed else 0)


func _grade_file(path: String) -> bool:
	var img := Image.load_from_file(path)
	if img == null:
		push_error("cannot load: " + path)
		return false
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var r := clampf(c.r * GAIN.x, 0.0, 1.0)
			var g := clampf(c.g * GAIN.y, 0.0, 1.0)
			var b := clampf(c.b * GAIN.z, 0.0, 1.0)
			var lum := 0.299 * r + 0.587 * g + 0.114 * b
			img.set_pixel(x, y, Color(
				lerpf(r, lum, DESATURATE), lerpf(g, lum, DESATURATE),
				lerpf(b, lum, DESATURATE), c.a))
	img.save_png(path)
	print("graded %s" % path.get_file())
	return true
