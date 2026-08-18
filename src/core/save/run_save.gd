class_name RunSave
extends RefCounted
## Checkpoint save: one JSON snapshot of the RunState, written at the map
## screen. No mid-combat saves in v0.1.

const DEFAULT_PATH := "user://run_save.json"


static func save_run(run: RunState, path: String = DEFAULT_PATH) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(run.to_dict(), "  "))


static func has_save(path: String = DEFAULT_PATH) -> bool:
	return FileAccess.file_exists(path)


static func load_run(path: String = DEFAULT_PATH) -> RunState:
	if not FileAccess.file_exists(path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return null
	return RunState.from_dict(parsed)


static func clear(path: String = DEFAULT_PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
