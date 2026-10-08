class_name TelemetrySpool
extends RefCounted
## The offline half of telemetry: an append-only NDJSON file under `user://`.
##
## The spool is the product; the network is best-effort. The game writes one
## JSON object per line and keeps writing whether or not anything is listening,
## so a session played on a plane is not lost — it ships on the next launch
## that sees the internet.
##
## NDJSON rather than a JSON array on purpose: an array needs a read-modify-
## write of the whole file per append, and a crash mid-rewrite destroys
## everything already spooled. A line append cannot damage anything but the
## line being written, and `read_lines()` drops a torn final line and counts it.
##
## Nothing here is allowed to throw. Every FileAccess result is checked, and a
## failure puts the spool into `degraded` for the rest of the session rather
## than retrying in a loop — `tools/verify.ps1` fails the build on the literal
## string "SCRIPT ERROR", and a telemetry fault must never be able to print it.

const DEFAULT_PATH := "user://telemetry/spool.ndjson"
## ~30 runs of offline backlog at the volume the filter produces.
const MAX_BYTES := 4 * 1024 * 1024
const MAX_LINE_BYTES := 8192
## Checking the file length every write would be a syscall per event.
const CHECK_EVERY := 200

var path: String
var degraded := false
var dropped_lines := 0
var malformed_lines := 0

var _file: FileAccess = null
var _writes_since_check := 0


func _init(spool_path: String = DEFAULT_PATH) -> void:
	path = spool_path


## Opens (creating the directory if needed) and seeks to the end. One handle is
## kept for the session: 60+ opens per fight is a lot of syscalls for nothing.
func open() -> bool:
	if degraded:
		return false
	if _file != null:
		return true
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if FileAccess.file_exists(path):
		_file = FileAccess.open(path, FileAccess.READ_WRITE)
		if _file != null:
			_file.seek_end()
	else:
		_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		degraded = true
		return false
	return true


func close() -> void:
	if _file != null:
		_file.flush()
		_file = null


## Appends one event. `flush()` after each line is what makes a `kill -9`
## survivable: it pushes the bytes to the OS, which outlives the process.
func append(event: Dictionary) -> bool:
	if degraded or not open():
		return false
	var line := JSON.stringify(event)
	if line.length() > MAX_LINE_BYTES:
		dropped_lines += 1
		return false
	_file.store_line(line)
	if _file.get_error() != OK:
		degraded = true
		close()
		return false
	_file.flush()
	_writes_since_check += 1
	if _writes_since_check >= CHECK_EVERY:
		_writes_since_check = 0
		_enforce_cap()
	return true


func size_bytes() -> int:
	if _file != null:
		return int(_file.get_length())
	if not FileAccess.file_exists(path):
		return 0
	var probe := FileAccess.open(path, FileAccess.READ)
	if probe == null:
		return 0
	return int(probe.get_length())


## How many lines are waiting. A raw count, NOT a parse: this used to run
## `read_lines(0)`, which JSON-parses every line of a spool that can hold 4 MB,
## once per accepted batch, on the main thread. A player with a backlog (a
## session or two played offline, then the first launch with the service
## reachable, whose cold start answers 10 to 20 seconds in) froze for as long
## as it took to drain, which is the "first action after a few seconds hangs"
## report of 0.122.
func line_count() -> int:
	return _raw_lines().size()


## Every parseable line, oldest first. `limit` of 0 means all of them.
## A line that does not parse is counted and skipped, never fatal — that is
## what makes a torn write at the tail a non-event.
func read_lines(limit: int = 0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	malformed_lines = 0
	if not FileAccess.file_exists(path):
		return out
	if _file != null:
		_file.flush()
	var reader := FileAccess.open(path, FileAccess.READ)
	if reader == null:
		return out
	while not reader.eof_reached():
		var line := reader.get_line()
		if line.strip_edges().is_empty():
			continue
		# A quiet parser: a torn tail line is expected, not an incident.
		# Named `parser`, not `reader` — `reader` is the open FileAccess here.
		var parser := JSON.new()
		if parser.parse(line) == OK and parser.data is Dictionary:
			out.append(parser.data)
			if limit > 0 and out.size() >= limit:
				break
		else:
			malformed_lines += 1
	return out


## Drops the first `count` lines, keeping the rest byte-for-byte. Called only
## after the server has taken them.
func truncate_head(count: int) -> bool:
	if count <= 0:
		return true
	if degraded:
		return false
	var kept := _tail_after(count)
	return _rewrite(kept)


## Everything goes: opting out, or a cap breach we could not repair.
func clear() -> void:
	close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	_writes_since_check = 0


## Over cap, drop the OLDEST half. A permanently offline machine would
## otherwise be pinned to its first ever session for good, and the recent
## session is the one worth keeping.
func _enforce_cap() -> void:
	if size_bytes() <= MAX_BYTES:
		return
	var lines := _raw_lines()
	var drop := int(lines.size() / 2.0)
	if drop <= 0:
		clear()
		return
	dropped_lines += drop
	var kept := lines.slice(drop)
	kept.insert(0, JSON.stringify({
		"t": "spool_truncated", "seq": -1, "d": {"dropped": drop}}))
	if not _rewrite(kept):
		clear()


func _raw_lines() -> PackedStringArray:
	var out := PackedStringArray()
	if not FileAccess.file_exists(path):
		return out
	if _file != null:
		_file.flush()
	# One native read and split instead of a GDScript get_line loop: a full spool
	# is ~14,000 lines and the loop cost ~200 ms, on the main thread, per batch.
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		if not line.strip_edges().is_empty():
			out.append(line)
	return out


func _tail_after(count: int) -> PackedStringArray:
	var lines := _raw_lines()
	return lines.slice(mini(count, lines.size()))


## write-tmp, swap, reopen. Any failure along the way degrades rather than
## leaving a half-written spool behind.
func _rewrite(lines: PackedStringArray) -> bool:
	close()
	var tmp := path + ".tmp"
	var out := FileAccess.open(tmp, FileAccess.WRITE)
	if out == null:
		degraded = true
		return false
	if not lines.is_empty():
		out.store_string("\n".join(lines) + "\n")
	out.flush()
	out = null
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if DirAccess.rename_absolute(tmp, path) != OK:
		degraded = true
		return false
	return open()
