class_name TelemetryIds
extends RefCounted
## UUIDs for telemetry, and the install identity that lives in `user://`.
##
## `Crypto.generate_random_bytes` on purpose, not `randi()`: the game reseeds
## the global RNG from a run seed, so two machines that happened to start the
## same seeded run would mint the same "unique" id.

const INSTALL_PATH := "user://telemetry/install.json"


## RFC 4122 version 4, lowercase, dashed.
static func uuid4() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0f) | 0x40          # version 4
	bytes[8] = (bytes[8] & 0x3f) | 0x80          # variant 10xx
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4),
		hex.substr(16, 4), hex.substr(20, 12)]


## The install id, made once and kept. A resettable random id on purpose —
## `OS.get_unique_id()` is a hardware fingerprint, which is exactly what this
## is meant not to be.
static func load_or_create_install(path: String = INSTALL_PATH) -> String:
	var existing := _read(path)
	if existing != "":
		return existing
	var minted := uuid4()
	_write(path, minted)
	return minted


## Forgets this install entirely (opting out). A later opt-in mints a fresh id
## that cannot be joined to the old one — which is the honest reading of
## "stop collecting", not a rename.
static func forget_install(path: String = INSTALL_PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


static func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	# JSON.parse_string() pushes an engine error on bad input; a corrupt file is
	# something we handle, not something to shout about in a player's log.
	var reader := JSON.new()
	if reader.parse(FileAccess.get_file_as_string(path)) != OK:
		return ""
	if not reader.data is Dictionary:
		return ""
	var id := str((reader.data as Dictionary).get("install_id", ""))
	return id if id.length() == 36 else ""


static func _write(path: String, install_id: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return                                    # telemetry never gets to throw
	file.store_string(JSON.stringify({
		"v": 1,
		"install_id": install_id,
		"created_utc": Time.get_datetime_string_from_system(true, true),
	}, "  "))
