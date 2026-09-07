extends ScreenBase
## Casino encounter: a rewards slot machine. Pay 10 coins per spin, collect
## every landed prize; three of a kind earns a free extra spin.

## Every face here has to be the icon the player already knows that prize by
## from the rest of the UI (patch 0.19) — a reel showing a different picture
## for the same thing reads as a different prize.
const PRIZE_TEXTURES := {
	&"coins": "res://assets/icons/coin.png",
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

var _paid_spin_used := false

var _status: Label
var _faces: Array[TextureRect] = []
var _result: Label
var _spin_button: Button
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
	row.add_theme_constant_override("separation", 14)
	strip.add_child(row)
	for i in 3:
		var frame := PanelContainer.new()
		frame.custom_minimum_size = Vector2(130, 150)
		var window := StyleBoxFlat.new()
		window.bg_color = Color(0.96, 0.93, 0.85)
		window.border_color = Color(0.83, 0.69, 0.22)
		window.set_border_width_all(3)
		window.set_corner_radius_all(12)
		frame.add_theme_stylebox_override("panel", window)
		var face := TextureRect.new()
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		face.custom_minimum_size = Vector2(100, 100)
		frame.add_child(face)
		row.add_child(frame)
		_faces.append(face)

	_result = add_info_label(
		"Feeling lucky? One spin: %d coins." % CasinoGame.spin_cost(Game.run), 22)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 30)
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(buttons)
	_spin_button = Button.new()
	_spin_button.pressed.connect(_on_spin)
	buttons.add_child(_spin_button)
	var leave := Button.new()
	leave.text = "Walk Away"
	leave.pressed.connect(Game.encounter_finished)
	buttons.add_child(leave)
	_refresh()


func _refresh() -> void:
	_status.text = "❤ %d / %d      🪙 %d" % [Game.run.hp, Game.run.max_hp, Game.run.coins]
	if _free_spins > 0:
		_spin_button.text = "FREE SPIN!"
		_spin_button.disabled = false
	elif _paid_spin_used:
		# Doc v0.13: you play once (free re-spins from triples excepted).
		_spin_button.text = "House rules: one spin"
		_spin_button.disabled = true
	else:
		var cost := CasinoGame.spin_cost(Game.run)
		_spin_button.text = "Spin  (🪙 %d)" % cost
		_spin_button.disabled = Game.run.coins < cost


func _on_spin() -> void:
	var free := _free_spins > 0
	if free:
		_free_spins -= 1
	var result := CasinoGame.spin(Db.content, Game.run,
		Game.rng.stream(&"rewards"), free)
	if result.is_empty():
		_refresh()
		return
	if not free:
		_paid_spin_used = true
	_spin_button.disabled = true
	await _animate(result.symbols, result.get("relics", []))
	if result.free_respin:
		_free_spins += 1
	_result.text = "\n".join(result.lines)
	_refresh()


func _animate(symbols: Array, relics: Array = []) -> void:
	var pool := CasinoGame.PRIZES.map(func(p: Dictionary) -> StringName: return p.id)
	for tick in 10:
		for face in _faces:
			_show(face, pool[randi() % pool.size()])
		await get_tree().create_timer(0.06).timeout
	for i in 3:
		_show(_faces[i], symbols[i], relics[i] if i < relics.size() else &"")
		_faces[i].scale = Vector2(1.35, 1.35)
		_faces[i].pivot_offset = _faces[i].size * 0.5
		_faces[i].create_tween().tween_property(_faces[i], "scale", Vector2.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		await get_tree().create_timer(0.2).timeout


## `relic_id` names the relic this reel actually landed, so each one shows its
## own art instead of every relic sharing the generic house chip (patch 0.19).
func _show(face: TextureRect, symbol: StringName, relic_id: StringName = &"") -> void:
	if symbol == &"relic" and relic_id != &"":
		face.texture = SuitAssets.relic_texture(relic_id)
		face.modulate = Color.WHITE
		return
	var path: String = PRIZE_TEXTURES.get(symbol, "")
	face.texture = load(path) if ResourceLoader.exists(path) else null
	face.modulate = Color.WHITE