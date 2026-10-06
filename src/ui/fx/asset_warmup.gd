class_name AssetWarmup
extends RefCounted
## Loads the art the first fight needs while the player is still on the title
## screen (designer, 0.121: "the game freezes for a few seconds the first time
## you try to make a move after starting a run").
##
## Every status, effect, chip and card icon is a 1024 px PNG that used to be
## `load()`ed on the main thread the first time something drew it: the intent
## row, the first spin, the first card flying at an enemy. On a cold disk or
## under a virus scanner each of those costs real time, and the first move of a
## run asks for all of them at once. Requesting them on the loader threads up
## front fills the resource cache, so the later `load()` is a dictionary hit.
## Failure is silent: a path that does not load simply loads late, as before.

const ICON_PREFIXES: Array[String] = ["status_", "fx_", "passive_", "intent_",
	"ability_card_", "chip_", "suit_", "ability_"]
const CHARACTER_PREFIXES: Array[String] = ["ace_"]

static var _started := false


static func start() -> void:
	if _started or DisplayServer.get_name() == "headless":
		return
	_started = true
	for path in paths():
		ResourceLoader.load_threaded_request(path, "Texture2D", false)


## The files worth warming. Exported builds list `x.png.import` (or `.remap`)
## rather than `x.png`, so the suffix is stripped to get the loadable path.
static func paths() -> Array[String]:
	var out: Array[String] = []
	_collect("res://assets/icons", ICON_PREFIXES, out)
	_collect("res://assets/characters", CHARACTER_PREFIXES, out)
	return out


static func _collect(directory: String, prefixes: Array[String], into: Array[String]) -> void:
	for file in DirAccess.get_files_at(directory):
		var name := file.trim_suffix(".import").trim_suffix(".remap")
		if not name.ends_with(".png"):
			continue
		for prefix in prefixes:
			if name.begins_with(prefix):
				var path := "%s/%s" % [directory, name]
				if not into.has(path):
					into.append(path)
				break
