extends GutTest
## Telemetry must be completely inert in tests, in CI and in the balance bot.
##
## This is the direct regression test for that. GUT runs inside the tree, so it
## can reach the autoload and check what it actually did on boot — which is the
## only way to catch "somebody made telemetry start doing work under
## --headless" before it shows up as a slow, chatty, or failing verify.

func test_telemetry_is_not_live_under_headless() -> void:
	assert_eq(DisplayServer.get_name(), "headless", "the suite runs headless")
	assert_false(Telemetry.is_live(),
		"telemetry must be dead in tests, CI and the smoke boot")


## The assertion that matters is that THIS run wrote nothing — not that the
## directory has never existed. A developer who played the windowed build on
## the same machine leaves a real spool behind, and that is not a failure.
func test_this_run_wrote_no_telemetry() -> void:
	assert_eq(_spool_fingerprint(), _fingerprint_at_start,
		"an inert build neither creates nor grows the spool")


const SPOOL := "user://telemetry/spool.ndjson"
var _fingerprint_at_start := ""


func before_all() -> void:
	_fingerprint_at_start = _spool_fingerprint()


## "absent", or the byte length — enough to catch a write.
func _spool_fingerprint() -> String:
	if not FileAccess.file_exists(SPOOL):
		return "absent"
	var file := FileAccess.open(SPOOL, FileAccess.READ)
	return "absent" if file == null else str(file.get_length())


func test_every_public_method_is_a_no_op() -> void:
	# None of these may throw, and none may leave anything behind.
	Telemetry.set_run("11111111-1111-4111-8111-111111111111")
	Telemetry.record(&"combat_started", {"lineup": "door_duty"})
	Telemetry.record(&"ability_fired", {"ability": "card_sling"}, "c", 3, 2)
	Telemetry.run_started("22222222-2222-4222-8222-222222222222", {"seed": 7})
	Telemetry.run_ended({"outcome": "defeat"})
	Telemetry.flush()
	Telemetry.session_ended("test")
	assert_eq(_spool_fingerprint(), _fingerprint_at_start,
		"every entry point called, and not one byte written")
	assert_true(true, "and nothing threw")


## The balance bot is pure RefCounted and never builds a presenter, so the
## capture tap is unreachable from it by construction rather than by a flag.
## This pins that: RunBot must not reference the autoload at all.
func test_the_balance_bot_cannot_reach_telemetry() -> void:
	for path in ["res://src/core/bot/run_bot.gd", "res://src/core/bot/greedy_bot.gd"]:
		var source := FileAccess.get_file_as_string(path)
		assert_false(source.contains("Telemetry"),
			"%s must not reference the Telemetry autoload" % path)


## The architecture rule, checked rather than trusted: nothing under
## `src/core/` may reach for an autoload.
func test_the_pure_layer_references_no_autoload() -> void:
	var offenders: Array[String] = []
	_scan("res://src/core", offenders)
	assert_eq(offenders, [] as Array[String],
		"src/core must stay free of autoloads: %s" % [offenders])


func _scan(dir_path: String, offenders: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path + "/" + entry
		if dir.current_is_dir():
			_scan(full, offenders)
		elif entry.ends_with(".gd"):
			_check_file(full, offenders)
		entry = dir.get_next()


## A word boundary matters: `CasinoGame.spin()` and `DiceGame.TARGET` both
## contain the substring "Game." and neither is an autoload reference.
func _check_file(path: String, offenders: Array[String]) -> void:
	var pattern := RegEx.create_from_string("\\b(Telemetry|Game|Db|Fx)\\.")
	var source := FileAccess.get_file_as_string(path)
	for line in source.split("\n"):
		var code := line.strip_edges()
		if code.begins_with("#"):
			continue
		var hit := pattern.search(code)
		if hit != null:
			offenders.append("%s -> %s" % [path, hit.get_string()])
			return
