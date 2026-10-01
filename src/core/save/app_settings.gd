class_name AppSettings
extends RefCounted
## The project's first settings file: `user://settings.json`.
##
## Until 0.115 nothing was persisted — `SettingsTab` pushed volume and display
## mode straight at the engine and forgot them on quit. Telemetry needs a home
## for its consent flag that survives a restart, and that flag must live
## OUTSIDE `user://telemetry/`: wiping the telemetry directory must never
## silently re-enable collection.
##
## Same discipline as `RunSave`, plus the null and type checks it is missing —
## a settings file that throws would take the main menu down with it.

const DEFAULT_PATH := "user://settings.json"
## Telemetry ships on. The first-launch notice says so, and the Settings tab
## turns it off. Flip this one constant for an opt-in build.
const DEFAULT_TELEMETRY := true

var telemetry_enabled := DEFAULT_TELEMETRY
var telemetry_notice_seen := false
var volume_pct := 80.0
var muted := false
## Patch 0.120: the Music and Sfx buses get their own levels. Music sits a
## notch under the effects by default so a hit still lands over the band.
var music_pct := 80.0
var sfx_pct := 100.0
var fullscreen := false
var max_fps := 60
## Combat animation speed, one of `SpeedRules.ALLOWED` (phase 0 roadmap).
var combat_speed := 1.0
## Anything a newer build wrote that this one does not know about, kept so a
## downgrade does not silently drop the player's other preferences.
var _unknown: Dictionary = {}


static func load_settings(path: String = DEFAULT_PATH) -> AppSettings:
	var settings := AppSettings.new()
	if not FileAccess.file_exists(path):
		return settings
	# A quiet parser: a corrupt settings file falls back to defaults without
	# pushing an engine error into the log.
	var reader := JSON.new()
	if reader.parse(FileAccess.get_file_as_string(path)) != OK:
		return settings
	if not reader.data is Dictionary:
		return settings                        # corrupt: defaults, not a crash
	var data: Dictionary = reader.data
	var telemetry: Dictionary = data.get("telemetry", {}) if data.get("telemetry") is Dictionary else {}
	settings.telemetry_enabled = bool(telemetry.get("enabled", DEFAULT_TELEMETRY))
	settings.telemetry_notice_seen = bool(telemetry.get("notice_seen", false))
	var audio: Dictionary = data.get("audio", {}) if data.get("audio") is Dictionary else {}
	settings.volume_pct = clampf(float(audio.get("volume_pct", 80.0)), 0.0, 100.0)
	settings.muted = bool(audio.get("muted", false))
	settings.music_pct = clampf(float(audio.get("music_pct", 80.0)), 0.0, 100.0)
	settings.sfx_pct = clampf(float(audio.get("sfx_pct", 100.0)), 0.0, 100.0)
	var display: Dictionary = data.get("display", {}) if data.get("display") is Dictionary else {}
	settings.fullscreen = bool(display.get("fullscreen", false))
	settings.max_fps = int(display.get("max_fps", 60))
	var gameplay: Dictionary = data.get("gameplay", {}) if data.get("gameplay") is Dictionary else {}
	settings.combat_speed = SpeedRules.clamp_speed(float(gameplay.get("combat_speed", 1.0)))
	for key: String in data:
		if not ["v", "telemetry", "audio", "display", "gameplay"].has(key):
			settings._unknown[key] = data[key]
	return settings


func save(path: String = DEFAULT_PATH) -> bool:
	var data := {
		"v": 1,
		"telemetry": {
			"enabled": telemetry_enabled,
			"notice_seen": telemetry_notice_seen,
		},
		"audio": {"volume_pct": volume_pct, "muted": muted,
			"music_pct": music_pct, "sfx_pct": sfx_pct},
		"display": {"fullscreen": fullscreen, "max_fps": max_fps},
		"gameplay": {"combat_speed": combat_speed},
	}
	for key: String in _unknown:
		data[key] = _unknown[key]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false                           # read-only disk: never fatal
	file.store_string(JSON.stringify(data, "  "))
	return true
