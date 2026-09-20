extends Node
## Autoload: play telemetry. Spools locally, ships when it can.
##
## Three rules this file exists to keep:
##
## 1. **The spool is the product, the network is best-effort.** Nothing here
##    ever blocks a frame, a fight or a quit. A flush that dies mid-flight is
##    resent next launch; the server dedups.
## 2. **Every decision lives in `src/core/telemetry/`.** What to keep, how big
##    a batch is, when to retry — all pure and unit-tested. This file holds an
##    HTTPRequest, a Timer and a file handle.
## 3. **It never references another autoload.** Callers push into it. That
##    makes load order irrelevant, including at shutdown, where teardown order
##    is not a contract — the naive "read Game.run in _exit_tree" design is a
##    SCRIPT ERROR waiting for the day that order flips.
##
## Inertness: `_live` is false under `--headless`, in the editor, without an
## endpoint, or when the player has opted out. When it is false this node
## creates no HTTPRequest, no Timer, no directory and no file, and every public
## method returns on its first line. That single check is what keeps all three
## steps of `tools/verify.ps1` silent and fast, and the 40-run balance bot
## cannot reach this file at all — `RunBot` never builds a presenter.

const SETTINGS_PATH := AppSettings.DEFAULT_PATH
const CONFIG_PATH := "res://telemetry_config.json"
const KEY_PATH := "res://telemetry_key.json"
const FLUSH_INTERVAL := 30.0
const HEARTBEAT_SEC := 60.0
const REQUEST_TIMEOUT := 10.0

var settings: AppSettings

var _live := false
var _endpoint := ""
var _api_key := ""
var _install_id := ""
var _session_id := ""
var _spool: TelemetrySpool = null
var _http: HTTPRequest = null
var _timer: Timer = null
var _seq := 0
var _inflight := 0                 # lines the server is being offered
var _sending := false
var _failures := 0
var _stopped := false              # a bad key: stop asking until next launch
var _session_start_ms := 0
var _active_sec := 0.0
var _focused := true
var _last_heartbeat := 0.0
var _session_closed := false
var _run_id := ""
var _runs_started := 0
var _runs_won := 0
var _runs_lost := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	settings = AppSettings.load_settings(SETTINGS_PATH)
	_session_start_ms = Time.get_ticks_msec()
	_live = _resolve_live()
	if not _live:
		set_process(false)
		return
	_install_id = TelemetryIds.load_or_create_install()
	_session_id = TelemetryIds.uuid4()
	_spool = TelemetrySpool.new()
	_spool.open()

	_http = HTTPRequest.new()
	_http.timeout = REQUEST_TIMEOUT
	_http.use_threads = true
	_http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

	_timer = Timer.new()
	_timer.wait_time = FLUSH_INTERVAL
	_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_timer)
	_timer.timeout.connect(_on_flush_tick)
	_timer.start()

	record(&"session_started", {
		"app": _app_version(), "os": OS.get_name(),
		"locale": OS.get_locale(), "first_launch": not settings.telemetry_notice_seen,
	})
	# Jittered, so a thousand players relaunching after a patch do not arrive
	# together.
	await get_tree().create_timer(randf_range(2.0, 5.0)).timeout
	flush()


## Live only when there is somewhere to send, someone to send about, and a
## real player at the keyboard.
func _resolve_live() -> bool:
	if DisplayServer.get_name() == "headless":
		return false                       # the house idiom (game.gd:225)
	if Engine.is_editor_hint():
		return false
	if OS.get_environment("CB_TELEMETRY") == "0":
		return false
	if not settings.telemetry_enabled:
		return false
	_endpoint = _setting("CB_TELEMETRY_URL", CONFIG_PATH, "url")
	_api_key = _setting("CB_TELEMETRY_KEY", KEY_PATH, "key")
	return _endpoint.begins_with("https://") or _endpoint.begins_with("http://127.0.0.1")


## env > user:// override > res:// config. The override file is how a tester
## points a shipped build at a staging endpoint without a rebuild.
func _setting(env_name: String, res_path: String, field: String) -> String:
	var from_env := OS.get_environment(env_name)
	if from_env != "":
		return from_env
	for path in ["user://telemetry_override.json", res_path]:
		if not FileAccess.file_exists(path):
			continue
		var reader := JSON.new()
		if reader.parse(FileAccess.get_file_as_string(path)) != OK:
			continue
		if reader.data is Dictionary and (reader.data as Dictionary).has(field):
			var value := str((reader.data as Dictionary)[field])
			if value != "":
				return value
	return ""


func _app_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


# ---------------------------------------------------------------- recording

## One spooled event. `data` is the row payload; the run and combat ids are
## whatever the caller last told us about.
func record(type: StringName, data: Dictionary = {}, combat_id: String = "",
		encounter: int = 0, round_number: int = 0) -> void:
	if not _live or _spool == null:
		return
	_seq += 1
	var line := {
		"t": String(type),
		"id": TelemetryIds.uuid4(),
		"seq": _seq,
		"ts": Time.get_datetime_string_from_system(true, true),
		"mono": snappedf((Time.get_ticks_msec() - _session_start_ms) / 1000.0, 0.01),
		"sess": _session_id,
		"d": data,
	}
	if _run_id != "":
		line["run"] = _run_id
	if combat_id != "":
		line["combat"] = combat_id
	if encounter > 0:
		line["enc"] = encounter
	if round_number > 0:
		line["rnd"] = round_number
	_spool.append(line)


## The presenter tells us which run is current; nothing here reads `Game`.
func set_run(run_id: String) -> void:
	_run_id = run_id


func run_started(run_id: String, data: Dictionary) -> void:
	if not _live:
		return
	_run_id = run_id
	_runs_started += 1
	record(&"run_started", data)
	flush()


func run_ended(data: Dictionary) -> void:
	if not _live:
		return
	if str(data.get("outcome", "")) == "victory":
		_runs_won += 1
	else:
		_runs_lost += 1
	record(&"run_ended", data)
	_run_id = ""
	flush()


# ------------------------------------------------------------------- session

func _process(delta: float) -> void:
	if not _live:
		return
	if _focused:
		_active_sec += delta
	var now := (Time.get_ticks_msec() - _session_start_ms) / 1000.0
	if now - _last_heartbeat >= HEARTBEAT_SEC:
		_last_heartbeat = now
		# The heartbeat is the crash story: a killed process writes no ending,
		# so the server prices the session from the last one it received.
		record(&"session_heartbeat", {
			"duration_sec": int(now), "active_sec": int(_active_sec)})


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_focused = true
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_focused = false
			flush()
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_PREDELETE:
			session_ended("window_closed")


## Idempotent, and it touches nothing but our own memory and file — teardown
## order across autoloads is not something to depend on.
func session_ended(reason: String) -> void:
	if not _live or _session_closed:
		return
	_session_closed = true
	var seconds := (Time.get_ticks_msec() - _session_start_ms) / 1000.0
	record(&"session_ended", {
		"reason": reason,
		"duration_sec": int(seconds),
		"active_sec": int(_active_sec),
		"runs_started": _runs_started,
		"runs_won": _runs_won,
		"runs_lost": _runs_lost,
	})
	if _spool != null:
		_spool.close()
	# Deliberately no await: quitting must never hang on a dead socket. What
	# is on disk ships next launch, which is the whole point of the spool.


# --------------------------------------------------------------------- flush

func _on_flush_tick() -> void:
	flush()


func flush() -> void:
	if not _live or _sending or _stopped or _spool == null:
		return
	var lines := _spool.read_lines(TelemetryBatch.MAX_EVENTS)
	if lines.is_empty():
		return
	var built := TelemetryBatch.build(lines, {
		"install_id": _install_id,
		"app_version": _app_version(),
		"os_name": OS.get_name(),
		"os_version": OS.get_version(),
		"cpu_name": OS.get_processor_name(),
		"cpu_count": OS.get_processor_count(),
		"gpu_name": RenderingServer.get_video_adapter_name(),
		"screen": "%dx%d" % [DisplayServer.screen_get_size().x,
			DisplayServer.screen_get_size().y],
		"locale": OS.get_locale(),
		"malformed": _spool.malformed_lines,
	})
	if built.is_empty():
		return
	var headers := PackedStringArray(["Content-Type: application/json"])
	if _api_key != "":
		headers.append("X-Api-Key: " + _api_key)
	_inflight = int(built.count)
	_sending = true
	# The lines stay in the spool until a 2xx: a crash here simply resends.
	var err := _http.request(_endpoint, headers, HTTPClient.METHOD_POST,
		JSON.stringify(built.batch))
	if err != OK:
		# Ignoring this would wedge `_sending` forever and stop all telemetry.
		_sending = false
		_inflight = 0
		_schedule_retry()


func _on_request_completed(result: int, code: int, _headers: PackedStringArray,
		_body: PackedByteArray) -> void:
	# Take the count and clear the field FIRST. This handler can start another
	# flush, and that nested call sets `_inflight` for its own request - if the
	# outer frame then reset it on the way out, the next response would
	# truncate nothing, find the spool still full, and flush again for ever.
	# (Exactly what happened: four events resent 58 times in one session.)
	var sent := _inflight
	_inflight = 0
	_sending = false
	match TelemetryBatch.classify(result, code):
		TelemetryBatch.Verdict.OK:
			_after_accepted(sent)
		TelemetryBatch.Verdict.DROP:
			# The server refused these exact bytes; retrying is guaranteed to
			# fail forever, so drop them rather than block the queue on a
			# poison pill.
			_after_accepted(sent)
		TelemetryBatch.Verdict.STOP:
			# A bad key will not fix itself, and hammering it is how an egress
			# IP gets blackholed. Stop until the next launch.
			_stopped = true
			_timer.stop()
		_:
			_schedule_retry()


## The spool has given up `sent` lines. Drop them, and if more are waiting keep
## going - deferred, never recursively, so this function can never re-enter
## itself through `flush()`.
func _after_accepted(sent: int) -> void:
	_failures = 0
	if _timer != null:
		_timer.wait_time = FLUSH_INTERVAL
		_timer.start()
	if sent <= 0:
		return
	if not _spool.truncate_head(sent):
		# The spool could not drop what the server already has. Resending it
		# would duplicate nothing (the server dedups) but would loop forever,
		# so let the spool go instead - the data is safely delivered.
		_spool.clear()
		return
	if _spool.line_count() > 0:
		flush.call_deferred()


func _schedule_retry() -> void:
	_failures += 1
	_timer.wait_time = TelemetryBatch.next_delay(_failures)
	_timer.start()


# ------------------------------------------------------------------- consent

func is_live() -> bool:
	return _live


func notice_seen() -> bool:
	return settings != null and settings.telemetry_notice_seen


func mark_notice_seen() -> void:
	if settings == null:
		return
	settings.telemetry_notice_seen = true
	settings.save(SETTINGS_PATH)


func is_enabled() -> bool:
	return settings != null and settings.telemetry_enabled


## The Settings toggle. Opting out stops collection AND deletes what is on
## disk, including the install id — a later opt-in mints a fresh one that
## cannot be joined to the old. Nothing is sent on the way out: a parting
## "they opted out" row is exactly what a privacy-minded player would check
## for, and finding one would be a small betrayal.
func set_enabled(enabled: bool) -> void:
	if settings == null:
		return
	settings.telemetry_enabled = enabled
	settings.telemetry_notice_seen = true
	settings.save(SETTINGS_PATH)
	if enabled:
		if not _live:
			_live = _resolve_live()
			if _live:
				_install_id = TelemetryIds.load_or_create_install()
				_session_id = TelemetryIds.uuid4()
				_spool = TelemetrySpool.new()
				_spool.open()
				set_process(true)
				if _timer != null:
					_timer.start()
	else:
		_live = false
		set_process(false)
		if _timer != null:
			_timer.stop()
		if _spool != null:
			_spool.clear()
			_spool = null
		TelemetryIds.forget_install()
