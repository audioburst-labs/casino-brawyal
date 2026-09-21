extends GutTest
## Copy style lint (patch 0.116).
##
## The designer's rule: no long dashes anywhere a player can read them. They
## were all over the story events, the tooltips and the first-launch notice.
## A rule nobody can see being broken gets broken again in a month, so this
## scans the shipped text instead of trusting a search-and-replace to hold.
##
## Scope is deliberately what the player SEES: `data/` (story prose, ability
## and relic descriptions) and `src/ui/` (labels, tooltips, glossary text).
## Source comments are ours, not theirs, and are left alone.

const LONG_DASHES := {
	"—": "em dash",
	"–": "en dash",
	"―": "horizontal bar",
	"−": "minus sign",
}

const SCANNED := [
	{"dir": "res://data", "ext": "json"},
	{"dir": "res://src/ui", "ext": "gd"},
]


func test_no_long_dashes_in_player_facing_text() -> void:
	var offences: Array[String] = []
	for target: Dictionary in SCANNED:
		for path in _walk(target.dir, target.ext):
			_scan(path, offences)
	assert_eq(offences, [] as Array[String],
		"Long dashes reach the player in %d place(s). Use a comma, a colon or " % offences.size()
		+ "a full stop instead:\n  " + "\n  ".join(offences))


## A `#` line is a comment; anything else in a .gd file may end up on screen.
## Crude on purpose: a false positive costs one keystroke, a miss ships.
func _scan(path: String, offences: Array[String]) -> void:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return
	var line_no := 0
	for line in text.split("\n"):
		line_no += 1
		if line.strip_edges().begins_with("#"):
			continue
		for dash: String in LONG_DASHES:
			if line.contains(dash):
				offences.append("%s:%d (%s)" % [path, line_no, LONG_DASHES[dash]])
				break


func _walk(dir_path: String, ext: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			found.append_array(_walk(full, ext))
		elif entry.get_extension() == ext:
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return found
