extends Control
## Root scene: hosts ScreenRoot (screens swap here), HudLayer, and FxLayer.


func _ready() -> void:
	Game.register_screen_root($ScreenRoot)
	Fx.set_shake_target($ScreenRoot)
	Fx.init_cursor()
	_ready_freeze_probe()
	HeaderHud.attach(self)
	_attach_curtain()
	_restore_window_mode()
	# CB_DEBUG_AUTORUN=1: skip the main menu straight into a fresh run
	# (header/settings/layout-tab review).
	if OS.get_environment("CB_DEBUG_AUTORUN") != "":
		Game.new_run(-1, true)
		# CB_DEBUG_STICKERS="spade,heart": start holding unplaced stickers, so
		# the Layout Tab's sticker-placing flow can be reviewed.
		for suit in OS.get_environment("CB_DEBUG_STICKERS").split(",", false):
			Game.run.sticker_inventory.append(StringName(suit))
		# CB_DEBUG_RELICS="gamblers_confidence,winners_aura": start holding
		# relics, to review the relic strip and the Layout Tab.
		for relic in OS.get_environment("CB_DEBUG_RELICS").split(",", false):
			Game.run.relic_ids.append(StringName(relic))
		# CB_DEBUG_OPEN_SETTINGS / CB_DEBUG_OPEN_LAYOUT=1: pop the matching
		# header overlay open for review.
		if OS.get_environment("CB_DEBUG_OPEN_SETTINGS") != "":
			await get_tree().create_timer(0.5).timeout
			$HudLayer.add_child(SettingsTab.new())
		if OS.get_environment("CB_DEBUG_OPEN_LAYOUT") != "":
			await get_tree().create_timer(0.5).timeout
			$HudLayer.add_child(LayoutTab.new())
		if OS.get_environment("CB_DEBUG_OPEN_CODEX") != "":
			await get_tree().create_timer(0.5).timeout
			$HudLayer.add_child(CodexTab.new())
	else:
		Game.goto_screen("res://scenes/screens/main_menu.tscn")
		if TelemetryNotice.should_show():
			$HudLayer.add_child(TelemetryNotice.new())


## The window opens the way it was last left: fullscreen the first time, then
## whatever the player chose (patch 0.125). Not applied headless, nor when the
## command line names a window itself (`--windowed`, `--fullscreen`,
## `--resolution`, which is how the screenshot tool runs).
func _restore_window_mode() -> void:
	if DisplayServer.get_name() == "headless" or Telemetry.settings == null:
		return
	for arg in OS.get_cmdline_args():
		if arg in ["--windowed", "--fullscreen", "--resolution", "--position"]:
			return
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if Telemetry.settings.fullscreen \
		else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)
	_window_watch_on = true


## Whatever puts the window in or out of fullscreen (the Settings button, the
## OS shortcut) is remembered, so the next launch matches. Polled twice a
## second; a mode change is rare and this costs one comparison.
var _window_watch_on := false
var _window_check := 0.0


func _watch_window_mode(delta: float) -> void:
	if not _window_watch_on:
		return
	_window_check += delta
	if _window_check < 0.5:
		return
	_window_check = 0.0
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_MINIMIZED:
		return
	var fullscreen := mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
		or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if fullscreen != Telemetry.settings.fullscreen:
		Telemetry.settings.fullscreen = fullscreen
		Telemetry.settings.save(Telemetry.SETTINGS_PATH)


## The theatre curtain between screens (patch 0.125). Its own layer, one below
## the header so HP and gold stay readable while it closes. Not built headless
## (tests and bots swap synchronously) nor with CB_CURTAINS=0.
func _attach_curtain() -> void:
	if DisplayServer.get_name() == "headless" or OS.get_environment("CB_CURTAINS") == "0":
		return
	var layer := CanvasLayer.new()
	layer.layer = 9
	add_child(layer)
	var curtain := CurtainTransition.new()
	layer.add_child(curtain)
	Game.register_curtain(curtain)
	# CB_DEBUG_CURTAIN=1: bounce between two screens so the act can be filmed.
	if OS.get_environment("CB_DEBUG_CURTAIN") != "":
		_debug_curtain_loop()
	# CB_DEBUG_CURTAIN_POSE=0.5: hold the curtain at that progress for a still.
	var pose := OS.get_environment("CB_DEBUG_CURTAIN_POSE")
	if pose != "":
		# CB_DEBUG_CURTAIN_SCREEN=rest: first walk to that screen (through the real
		# transition), so the pose can be compared with a ScreenBase screen.
		var target := OS.get_environment("CB_DEBUG_CURTAIN_SCREEN")
		if target != "":
			await get_tree().create_timer(1.0).timeout
			Game.goto_screen("res://scenes/screens/%s_screen.tscn" % target)
			await get_tree().create_timer(3.0).timeout
		await get_tree().create_timer(1.0).timeout
		if pose.to_float() >= 0.0:
			curtain.debug_pose(pose.to_float())


func _debug_curtain_loop() -> void:
	await get_tree().create_timer(1.5).timeout
	Game.goto_screen("res://scenes/screens/rest_screen.tscn")
	await get_tree().create_timer(4.0).timeout
	Game.goto_screen("res://scenes/screens/map_screen.tscn")


## Any frame that took a quarter of a second or more is written to godot.log
## with the time since launch and the screen it happened on. The reports of the
## game "getting stuck" a few seconds after opening had nothing to go on; this
## is what a log will show next time. Costs one comparison per frame.
const HITCH_MS := 250.0


var _last_frame_ms := 0


## Wall-clock time between frames, not `delta`: the engine smooths and clamps
## delta, which hid a deliberate 700 ms block when this was first tried.
func _process(delta: float) -> void:
	_watch_window_mode(delta)
	var now := Time.get_ticks_msec()
	if _last_frame_ms > 0 and now - _last_frame_ms >= HITCH_MS:
		print("[CB hitch] %d ms between frames at %.1f s since launch, screen=%s" % [
			now - _last_frame_ms, now / 1000.0, Game.current_screen_path])
	_last_frame_ms = now


## CB_DEBUG_FREEZE_MS=N: block the main thread for N ms two seconds after
## launch, to prove the hitch logger above reports what it should.
func _ready_freeze_probe() -> void:
	var ms := OS.get_environment("CB_DEBUG_FREEZE_MS").to_int()
	if ms <= 0:
		return
	await get_tree().create_timer(2.0).timeout
	OS.delay_msec(ms)
