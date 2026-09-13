extends ScreenBase
## Casino encounter: a rewards slot machine. One free spin per visit (doc
## v0.120 dropped the entry fee); collect every landed prize; three of a
## kind earns a free extra spin.

## Every face here has to be the icon the player already knows that prize by
## from the rest of the UI (patch 0.19) — a reel showing a different picture
## for the same thing reads as a different prize.
const PRIZE_TEXTURES := {
	&"coins": "res://assets/icons/coin.png",
	&"broken_coins": "res://assets/icons/icon_broken_coins.png",
	&"money_sack": "res://assets/props/treasure_chest.png",
	&"heart": "res://assets/icons/fx_heal.png",
	&"broken_heart": "res://assets/icons/status_vulnerable.png",
	&"sticker_spade": "res://assets/icons/suit_spade.png",
	&"sticker_heart": "res://assets/icons/suit_heart.png",
	&"sticker_club": "res://assets/icons/suit_club.png",
	&"sticker_diamond": "res://assets/icons/suit_diamond.png",
	&"relic": "res://assets/icons/relic_house_chip.png",
	&"extra_reel": "res://assets/props/slot_cabinet.png",
}

## Reel window and strip geometry. Each window is a clipped column of prize
## faces that scrolls past like a real drum; the landing face sits near the
## end of the strip so the reel visibly runs through the others first.
const WINDOW := Vector2(150, 170)
const FACE := 128.0
const STRIP_FACES := 18
## 0.0.111: "slower and more gradual, stopping one reel at a time" — the first
## reel runs this long, each later reel a full beat longer, so the eye has a
## moment on every stop before the next one lands.
const BASE_DURATION := 1.7
const STAGGER := 0.85

var _spin_used := false

var _status: Label
var _windows: Array[Control] = []
var _frames: Array[PanelContainer] = []
var _result: Label
var _spin_button: Button
var _leave_button: Button
var _free_spins := 0


func _ready() -> void:
	if Game.run == null and get_tree().current_scene == self:
		Game.run = RunState.new()  # standalone debug
		Game.run.coins = 100
		Game.rng = GameRng.new(randi())
	build_screen("The Casino", "res://assets/backgrounds/bg_casino_floor.png")
	_status = add_info_label("", 26)

	var strip := PanelContainer.new()
	strip.theme_type_variation = &"FeltPanel"
	strip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(strip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	strip.add_child(row)
	for i in 3:
		var frame := PanelContainer.new()
		frame.custom_minimum_size = WINDOW
		var window := StyleBoxFlat.new()
		window.bg_color = Color(0.96, 0.93, 0.85)
		window.border_color = Color(0.83, 0.69, 0.22)
		window.set_border_width_all(3)
		window.set_corner_radius_all(12)
		window.shadow_color = Color(0, 0, 0, 0.3)
		window.shadow_size = 3
		frame.add_theme_stylebox_override("panel", window)
		var clip := Control.new()
		clip.clip_contents = true
		clip.custom_minimum_size = WINDOW - Vector2(8, 8)
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(clip)
		row.add_child(frame)
		_frames.append(frame)
		_windows.append(clip)
		# Idle: a question-mark-free teaser — the coin face, centred.
		var idle := _populate(clip, &"coins")
		idle.strip.position.y = idle.land_y

	_result = add_info_label("Feeling lucky? The house is buying: one spin, on us.", 22)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 30)
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(buttons)
	_spin_button = Button.new()
	_spin_button.pressed.connect(_on_spin)
	buttons.add_child(_spin_button)
	_leave_button = Button.new()
	_leave_button.text = "Walk Away"
	_leave_button.pressed.connect(Game.encounter_finished)
	buttons.add_child(_leave_button)
	_refresh()
	# CB_DEBUG_AUTOSPIN=1: pull the lever after a second, so the staggered
	# reel stops can be screenshot mid-spin.
	if OS.get_environment("CB_DEBUG_AUTOSPIN") != "":
		await get_tree().create_timer(1.0).timeout
		_on_spin()


func _refresh() -> void:
	_status.text = "❤ %d / %d      🪙 %d" % [Game.run.hp, Game.run.max_hp, Game.run.coins]
	if _free_spins > 0:
		_spin_button.text = "FREE SPIN!"
		_spin_button.disabled = false
	elif _spin_used:
		# Doc: you play once (free re-spins from triples excepted).
		_spin_button.text = "House rules: one spin"
		_spin_button.disabled = true
	else:
		_spin_button.text = "Spin"
		_spin_button.disabled = false


func _on_spin() -> void:
	var free := _free_spins > 0
	if free:
		_free_spins -= 1
	var result := CasinoGame.spin(Db.content, Game.run, Game.rng.stream(&"rewards"))
	if result.is_empty():
		_refresh()
		return
	_spin_used = true
	# The winnings are banked the moment the reels are rolled: leaving for the
	# main menu now resumes at the map, not at a second free spin (0.0.111).
	Game.commit_encounter()
	_spin_button.disabled = true
	_leave_button.disabled = true
	await _animate(result.symbols, result.get("relics", []))
	_leave_button.disabled = false
	if result.free_respin:
		_free_spins += 1
	_result.text = "\n".join(result.lines)
	_refresh()


## Fills a reel window with a fresh strip whose landing cell shows `final`.
## Returns {strip, land_y, landing_index}.
func _populate(clip: Control, final: StringName, relic_id: StringName = &"") -> Dictionary:
	for child in clip.get_children():
		clip.remove_child(child)
		child.queue_free()
	var strip := VBoxContainer.new()
	strip.add_theme_constant_override("separation", 0)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(strip)
	var pool := CasinoGame.PRIZES.map(func(p: Dictionary) -> StringName: return p.id)
	var landing_index := STRIP_FACES - 2
	var previous: StringName = &""
	for face_index in STRIP_FACES:
		var cell := CenterContainer.new()
		cell.custom_minimum_size = Vector2(WINDOW.x - 8, FACE)
		var symbol: StringName = final
		if face_index != landing_index:
			symbol = pool[randi() % pool.size()]
			while symbol == previous:   # no doubled face while it rolls past
				symbol = pool[randi() % pool.size()]
		previous = symbol
		var face := TextureRect.new()
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		face.custom_minimum_size = Vector2(104, 104)
		face.pivot_offset = Vector2(52, 52)
		face.texture = _texture_for(symbol, relic_id if face_index == landing_index else &"")
		cell.add_child(face)
		strip.add_child(cell)
	strip.position.y = 0.0
	var land_y := -(FACE * landing_index) + (clip.custom_minimum_size.y - FACE) * 0.5
	return {"strip": strip, "land_y": land_y, "landing_index": landing_index}


## Spins the three reels as real drums: every reel starts together, then they
## decelerate and stop one at a time, left to right, each with an overshoot
## and spring-back, a flash on its frame and a pop on the landed face.
func _animate(symbols: Array, relics: Array = []) -> void:
	var spins: Array[Dictionary] = []
	for i in 3:
		spins.append(_populate(_windows[i], symbols[i], relics[i] if i < relics.size() else &""))
	var last_tween: Tween = null
	for i in spins.size():
		var strip: VBoxContainer = spins[i].strip
		var land_y: float = spins[i].land_y
		var duration: float = BASE_DURATION + i * STAGGER
		var tween := create_tween()
		# A long decelerating scroll down the whole strip...
		tween.tween_property(strip, "position:y", land_y - 22.0, duration) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		# ...past the mark, then the classic reel spring-back.
		tween.tween_property(strip, "position:y", land_y, 0.3) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_callback(_stopped.bind(i, strip, int(spins[i].landing_index)))
		last_tween = tween
	if last_tween != null:
		await last_tween.finished
	await get_tree().create_timer(0.25).timeout


## The beat of one reel stopping: its frame flashes gold and the landed face
## pops — so three stops read as three separate events, not one blur.
func _stopped(index: int, strip: VBoxContainer, landing_index: int) -> void:
	var frame := _frames[index]
	var style: StyleBoxFlat = frame.get_theme_stylebox("panel").duplicate()
	frame.add_theme_stylebox_override("panel", style)
	var flash := create_tween()
	flash.tween_method(func(t: float) -> void:
		style.bg_color = Color(0.96, 0.93, 0.85).lerp(Color(1.0, 0.95, 0.6), 1.0 - t)
		style.border_color = Color(0.83, 0.69, 0.22).lerp(Color(1.0, 0.9, 0.4), 1.0 - t),
		0.0, 1.0, 0.45)
	frame.pivot_offset = frame.size * 0.5
	var kick := frame.create_tween()
	kick.tween_property(frame, "scale", Vector2(1.06, 0.96), 0.06)
	kick.tween_property(frame, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if landing_index >= strip.get_child_count():
		return
	var cell: CenterContainer = strip.get_child(landing_index)
	if cell.get_child_count() == 0:
		return
	var face: TextureRect = cell.get_child(0)
	face.scale = Vector2(1.35, 1.35)
	var pop := face.create_tween()
	pop.tween_property(face, "scale", Vector2.ONE, 0.32) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## `relic_id` names the relic this reel actually landed, so each one shows its
## own art instead of every relic sharing the generic house chip (patch 0.19).
func _texture_for(symbol: StringName, relic_id: StringName = &"") -> Texture2D:
	if symbol == &"relic" and relic_id != &"":
		return SuitAssets.relic_texture(relic_id)
	var path: String = PRIZE_TEXTURES.get(symbol, "")
	return load(path) if ResourceLoader.exists(path) else null
