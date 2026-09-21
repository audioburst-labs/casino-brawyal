class_name DiceGameView
extends VBoxContainer
## The Casino's Dice Game (doc v0.120). Roll one die at a time toward exactly
## ten; the running count sits under the dice. Past ten you bust and the only
## option left is to leave; on ten the count glows gold, rolling closes and
## Cash Out lights up.

signal finished(lines: Array, relic_id: StringName)

const DIE_SIZE := 104.0

var _game := DiceGame.new()
var _rng: RandomNumberGenerator
var _dice_row: HFlowContainer
var _total_label: Label
var _hint: Label
var _roll_button: Button
var _cash_button: Button
var _glow_tween: Tween


## One die face, drawn rather than generated: a cream rounded square with the
## pips arranged the way a real die has them.
class DieFace:
	extends Control

	const PIPS := {
		1: [Vector2(0.5, 0.5)],
		2: [Vector2(0.28, 0.28), Vector2(0.72, 0.72)],
		3: [Vector2(0.26, 0.26), Vector2(0.5, 0.5), Vector2(0.74, 0.74)],
		4: [Vector2(0.28, 0.28), Vector2(0.72, 0.28), Vector2(0.28, 0.72), Vector2(0.72, 0.72)],
		5: [Vector2(0.27, 0.27), Vector2(0.73, 0.27), Vector2(0.5, 0.5),
			Vector2(0.27, 0.73), Vector2(0.73, 0.73)],
		6: [Vector2(0.28, 0.24), Vector2(0.72, 0.24), Vector2(0.28, 0.5),
			Vector2(0.72, 0.5), Vector2(0.28, 0.76), Vector2(0.72, 0.76)],
	}

	var value := 1

	func _draw() -> void:
		var body := Rect2(Vector2.ZERO, size)
		draw_rect(body, Color(0.96, 0.93, 0.85), true)
		draw_rect(body, Color(0.83, 0.69, 0.22), false, 4.0)
		var radius: float = size.x * 0.085
		for spot: Vector2 in PIPS.get(value, PIPS[1]):
			draw_circle(spot * size, radius, Color(0.24, 0.08, 0.12))

	## The tumble: faces flicker past, then the real one lands with a pop.
	func tumble(final_value: int) -> void:
		var tween := create_tween()
		for i in 8:
			tween.tween_callback(func() -> void:
				value = randi_range(1, 6)
				queue_redraw())
			tween.tween_interval(0.05)
		tween.tween_callback(func() -> void:
			value = final_value
			queue_redraw())
		pivot_offset = size * 0.5
		var pop := create_tween()
		pop.tween_interval(0.4)
		pop.tween_property(self, "scale", Vector2(1.25, 1.25), 0.08)
		pop.tween_property(self, "scale", Vector2.ONE, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func start(rng: RandomNumberGenerator) -> void:
	_rng = rng
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 16)

	var table := PanelContainer.new()
	table.theme_type_variation = &"FeltPanel"
	table.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(table)
	_dice_row = HFlowContainer.new()
	_dice_row.alignment = FlowContainer.ALIGNMENT_CENTER
	_dice_row.add_theme_constant_override("h_separation", 16)
	_dice_row.add_theme_constant_override("v_separation", 16)
	_dice_row.custom_minimum_size = Vector2(660, DIE_SIZE + 16)
	table.add_child(_dice_row)

	_total_label = Label.new()
	_total_label.text = "0"
	_total_label.theme_type_variation = &"TitleLabel"
	_total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_total_label.add_theme_font_size_override("font_size", 56)
	add_child(_total_label)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 21)
	add_child(_hint)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 30)
	add_child(buttons)
	_roll_button = Button.new()
	_roll_button.text = "Roll another die"
	_roll_button.pressed.connect(_on_roll)
	buttons.add_child(_roll_button)
	_cash_button = Button.new()
	_cash_button.text = "Cash Out"
	_cash_button.pressed.connect(_on_cash_out)
	buttons.add_child(_cash_button)
	_refresh()

	if OS.get_environment("CB_DEBUG_AUTOSPIN") != "":
		await get_tree().create_timer(0.8).timeout
		while _game.can_roll():
			await _on_roll()


func _on_roll() -> void:
	if not _game.can_roll():
		return
	# The first die is the point of no return for this encounter.
	Game.commit_encounter()
	_roll_button.disabled = true
	_cash_button.disabled = true
	var value := _game.roll(_rng)
	var die := DieFace.new()
	die.custom_minimum_size = Vector2(DIE_SIZE, DIE_SIZE)
	_dice_row.add_child(die)
	die.tumble(value)
	await get_tree().create_timer(0.62).timeout
	_refresh()


func _refresh() -> void:
	_total_label.text = str(_game.total())
	_roll_button.disabled = not _game.can_roll()
	_cash_button.disabled = not _game.can_cash_out()
	if _glow_tween != null:
		_glow_tween.kill()
		_glow_tween = null
	_total_label.modulate = Color.WHITE
	_cash_button.modulate = Color.WHITE

	if _game.busted():
		# Doc: the options are replaced by a single "leave".
		_total_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
		_hint.text = "Bust! Over ten, and the house keeps the lot."
		_roll_button.visible = false
		_cash_button.visible = false
		if _dice_row.get_child_count() > 0:
			var leave := Button.new()
			leave.text = "Leave"
			leave.pressed.connect(func() -> void:
				finished.emit(["Bust! No winnings."] as Array, &""))
			add_child(leave)
			_roll_button.get_parent().visible = false
		return

	if _game.perfect():
		# Doc: the number glows golden, rolling is disabled, Cash Out glows.
		_total_label.add_theme_color_override("font_color", Color(1.0, 0.87, 0.38))
		_hint.text = "Exactly ten. Take the money."
		_glow_tween = create_tween().set_loops()
		_glow_tween.tween_property(_cash_button, "modulate", Color(1.4, 1.25, 0.7), 0.5)
		_glow_tween.tween_property(_cash_button, "modulate", Color.WHITE, 0.5)
		return

	_total_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
	_hint.text = "Roll toward ten. Go past it and you lose it all.\nCash out for %d coins." \
		% _game.cash_out_value(Game.run.encounter_number())


func _on_cash_out() -> void:
	if not _game.can_cash_out():
		return
	var payout := _game.cash_out(Game.run)
	finished.emit(["Cashed out on %d: +%d coins" % [_game.total(), payout]] as Array, &"")
