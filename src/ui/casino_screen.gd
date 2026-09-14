extends ScreenBase
## Casino encounter: a rewards slot machine. One free spin per visit (doc
## v0.120 dropped the entry fee); collect every landed prize; three of a
## kind earns a free extra spin.
##
## Patch 0.22: the reels are the shared `ReelStrip` inside a real `SlotCabinet`
## (the doc's golden machine with a chip drawer), and they scroll DOWNWARD like
## the combat machine — "exactly the same, but downwards instead of upwards".

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

## Bigger windows than the combat machine, and a much slower, more staggered
## spin: "the slot machine animation should be slower and more gradual,
## stopping one reel at a time" (patch 0.0.111).
const WINDOW := Vector2(150, 170)
const FACE := 128.0
const STRIP_FACES := 18
const BASE_DURATION := 1.7
const STAGGER := 0.85

var _spin_used := false

var _status: Label
var _reels: ReelStrip
var _cabinet: SlotCabinet
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

	_reels = ReelStrip.new()
	_reels.framed = false
	_reels.shrink_to_fit = false
	_reels.window_size = WINDOW
	_reels.face_height = FACE
	_reels.face_icon = 104.0
	_reels.strip_faces = STRIP_FACES
	_reels.base_duration = BASE_DURATION
	_reels.stagger = STAGGER
	_reels.overshoot = 22.0
	_reels.stop_flash = true
	_reels.face_provider = _texture_for
	_reels.filler_pool = CasinoGame.PRIZES.map(
		func(prize: Dictionary) -> StringName: return prize.id)

	# The result line lives in the machine's drawer, where the winnings land.
	_result = Label.new()
	_result.text = "Feeling lucky? The house is buying: one spin, on us."
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.custom_minimum_size = Vector2(560, 86)
	_result.add_theme_font_size_override("font_size", 20)

	_cabinet = SlotCabinet.new()
	var holder := CenterContainer.new()
	content.add_child(holder)
	holder.add_child(_cabinet)
	_cabinet.setup(SlotCabinet.Mode.CASINO, _reels, _result)
	_reels.set_reel_count(3)
	_cabinet.refresh_layout()

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
	if _free_spins > 0:
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
	var relics: Array = result.get("relics", [])
	var landing: Array = []
	for i in result.symbols.size():
		var relic_id: StringName = relics[i] if i < relics.size() else &""
		landing.append(SuitAssets.relic_texture(relic_id) if relic_id != &"" else null)
	await _reels.spin_to(result.symbols, landing)
	_leave_button.disabled = false
	if result.free_respin:
		_free_spins += 1
	_result.text = "\n".join(result.lines)
	_refresh()


func _texture_for(symbol: StringName) -> Texture2D:
	var path: String = PRIZE_TEXTURES.get(symbol, "")
	return load(path) if ResourceLoader.exists(path) else null
