extends Control
## Root scene: hosts ScreenRoot (screens swap here), HudLayer, and FxLayer.


func _ready() -> void:
	Game.register_screen_root($ScreenRoot)
	Fx.set_shake_target($ScreenRoot)
	Fx.init_cursor()
	_ready_freeze_probe()
	HeaderHud.attach(self)
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


## Any frame that took a quarter of a second or more is written to godot.log
## with the time since launch and the screen it happened on. The reports of the
## game "getting stuck" a few seconds after opening had nothing to go on; this
## is what a log will show next time. Costs one comparison per frame.
const HITCH_MS := 250.0


var _last_frame_ms := 0


## Wall-clock time between frames, not `delta`: the engine smooths and clamps
## delta, which hid a deliberate 700 ms block when this was first tried.
func _process(_delta: float) -> void:
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
