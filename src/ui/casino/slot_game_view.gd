class_name SlotGameView
extends VBoxContainer
## The Casino's slot machine (doc v0.120): one free spin, every landed prize
## collected, three of a kind earns another. The reels are the shared
## `ReelStrip` inside the same `SlotCabinet` the player fights on, scrolling
## downward like the combat machine (patch 0.22).

signal finished(lines: Array, relic_id: StringName)

## Every face has to be the icon the player already knows that prize by from
## the rest of the UI (patch 0.19) — a reel showing a different picture for the
## same thing reads as a different prize.
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
## spin: "slower and more gradual, stopping one reel at a time" (0.0.111).
const WINDOW := Vector2(150, 170)
const FACE := 128.0
const STRIP_FACES := 18
const BASE_DURATION := 1.7
const STAGGER := 0.85

var _rng: RandomNumberGenerator
var _reels: ReelStrip
var _cabinet: SlotCabinet
var _result: Label
var _spin_button: Button
var _done_button: Button
var _free_spins := 0
var _spin_used := false
var _lines: Array = []
var _relic_won: StringName = &""


func start(rng: RandomNumberGenerator) -> void:
	_rng = rng
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 18)

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

	# The winnings read out of the machine's drawer, where the chips fall.
	_result = Label.new()
	_result.text = "Feeling lucky? The house is buying: one spin, on us."
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.custom_minimum_size = Vector2(560, 92)
	_result.add_theme_font_size_override("font_size", 20)

	_cabinet = SlotCabinet.new()
	var holder := CenterContainer.new()
	add_child(holder)
	holder.add_child(_cabinet)
	_cabinet.setup(SlotCabinet.Mode.CASINO, _reels, _result)
	_reels.set_reel_count(3)
	_cabinet.refresh_layout()

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 30)
	add_child(buttons)
	_spin_button = Button.new()
	_spin_button.pressed.connect(_on_spin)
	buttons.add_child(_spin_button)
	_done_button = Button.new()
	_done_button.text = "Collect"
	_done_button.disabled = true
	_done_button.pressed.connect(func() -> void: finished.emit(_lines, _relic_won))
	buttons.add_child(_done_button)
	_refresh()

	if OS.get_environment("CB_DEBUG_AUTOSPIN") != "":
		await get_tree().create_timer(1.0).timeout
		_on_spin()


func _refresh() -> void:
	if _free_spins > 0:
		_spin_button.text = "FREE SPIN!"
		_spin_button.disabled = false
	elif _spin_used:
		_spin_button.text = "House rules: one spin"
		_spin_button.disabled = true
	else:
		_spin_button.text = "Spin"
		_spin_button.disabled = false
	_done_button.disabled = not _spin_used or _free_spins > 0


func _on_spin() -> void:
	if _free_spins > 0:
		_free_spins -= 1
	var result := CasinoGame.spin(Db.content, Game.run, _rng)
	if result.is_empty():
		_refresh()
		return
	_spin_used = true
	# The winnings are banked the moment the reels roll (0.0.111).
	Game.commit_encounter()
	_spin_button.disabled = true
	_done_button.disabled = true
	var relics: Array = result.get("relics", [])
	var landing: Array = []
	for i in result.symbols.size():
		var relic_id: StringName = relics[i] if i < relics.size() else &""
		if relic_id != &"":
			_relic_won = relic_id
		landing.append(SuitAssets.relic_texture(relic_id) if relic_id != &"" else null)
	await _reels.spin_to(result.symbols, landing)
	if result.free_respin:
		_free_spins += 1
	_lines = result.lines
	_result.text = "\n".join(result.lines)
	_refresh()


func _texture_for(symbol: StringName) -> Texture2D:
	var path: String = PRIZE_TEXTURES.get(symbol, "")
	return load(path) if ResourceLoader.exists(path) else null
