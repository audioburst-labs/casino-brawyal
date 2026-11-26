class_name RestScreen
extends ScreenBase
## Rest node (build 1.30, from the designer's mock): two big lit cards, Rest
## (heal 30% of max HP) and Scrounge (a random reward instead), then what you got in
## the same glass tile the Winnings screen uses.

const HEAL_FRACTION := 0.3
const CARD_SIZE := Vector2(430, 470)

var _choice_row: HBoxContainer
var _eyebrow: Label


## How much a rest heals right now: 30% of max, never past full health.
static func heal_amount(hp: int, max_hp: int) -> int:
	return mini(int(ceil(max_hp * HEAL_FRACTION)), maxi(0, max_hp - hp))


func _ready() -> void:
	build_screen("A Quiet Corner", "res://assets/backgrounds/bg_rest.png")
	_title_label.add_theme_font_size_override("font_size", 80)
	_title_label.get_parent().add_theme_constant_override("separation", 6)
	content.add_theme_constant_override("separation", 14)
	_eyebrow = add_eyebrow("Rest")
	_eyebrow.add_theme_color_override("font_color", NeonPalette.current().tube_hi)

	_choice_row = HBoxContainer.new()
	_choice_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_choice_row.add_theme_constant_override("separation", 56)
	content.add_child(_choice_row)

	var run := Game.run
	var heal := heal_amount(run.hp, run.max_hp)
	_choice_row.add_child(_card(RewardTiles.HEAL, "Rest", "+%d HP" % heal,
		"Restore 30% of your max health.", "Take a rest", _on_rest, heal))
	_choice_row.add_child(_card(RewardTiles.GOLD, "Scrounge", "A reward",
		"Take a random reward instead: some coins, or a relic.", "Take the reward", _on_reward, -1))


## One option: the whole card is the button.
func _card(edge: Color, title: String, big: String, text: String, tag: String,
		on_pressed: Callable, heal: int) -> Button:
	var card := Button.new()
	card.custom_minimum_size = CARD_SIZE
	card.flat = true
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		card.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	card.pressed.connect(on_pressed)
	card.pivot_offset = CARD_SIZE * 0.5
	card.mouse_entered.connect(func() -> void:
		create_tween().tween_property(card, "scale", Vector2(1.03, 1.03), 0.1))
	card.mouse_exited.connect(func() -> void:
		create_tween().tween_property(card, "scale", Vector2.ONE, 0.12))

	var panel := RewardTiles.tile(edge)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(panel)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)

	if heal >= 0:
		var heart := NeonHeart.new()
		heart.custom_minimum_size = Vector2(120, 120)
		heart.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(heart)
	else:
		var chest := RewardTiles.icon(_chest(), 120)
		chest.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		chest.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(chest)

	column.add_child(_centred(title, 44, Color.WHITE, true))
	column.add_child(_centred(big, 54, edge, true))
	var description := _centred(text, 22, NeonPalette.current().text, false)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size = Vector2(340, 60)
	column.add_child(description)

	if heal >= 0:
		var bar := HealBar.new()
		bar.setup(Game.run.hp, heal, Game.run.max_hp)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(bar)
		var reading := Label.new()
		reading.text = "%d / %d   to   %d / %d" % [Game.run.hp, Game.run.max_hp,
			Game.run.hp + heal, Game.run.max_hp]
		reading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		reading.add_theme_font_size_override("font_size", 18)
		reading.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(reading)
	else:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 46)
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(spacer)

	var pill := choose_tag(tag)
	column.add_child(pill)
	return card


func _centred(text: String, size: int, colour: Color, display: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if display:
		label.theme_type_variation = &"SubtitleLabel"
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	return label


static func _chest() -> Texture2D:
	return load("res://assets/props/treasure_chest.png") as Texture2D


func _on_rest() -> void:
	Game.commit_encounter()
	Audio.play_sfx(&"heal")
	var healed := heal_amount(Game.run.hp, Game.run.max_hp)
	Game.run.hp += healed
	_show_result("Feeling Better", RewardTiles.heal_tile(healed, Game.run.hp, Game.run.max_hp),
		"You rest by the fire.")


func _on_reward() -> void:
	Game.commit_encounter()
	var reward_rng := Game.rng.stream(&"rewards")
	var relic := Rewards.random_unowned_relic(Db.content, Game.run, reward_rng)
	if relic != &"" and reward_rng.randi_range(0, 1) == 0:
		Game.run.relic_ids.append(relic)
		_show_result("A Lucky Find", RewardTiles.relic_tile(relic, "Relic found"),
			"You find something tucked under the cushions.")
	else:
		var before := Game.run.coins
		RunEffects.apply([{"op": "gain_coins",
			"min": Game.run.encounter_number() * 6,
			"max": Game.run.encounter_number() * 10}], Db.content, Game.run, reward_rng)
		_show_result("A Little Luck", RewardTiles.coin_tile(Game.run.coins - before, "Coins found"),
			"Loose change in the sofa. Jackpot... sort of.")


## Swap the two cards for what the choice gave.
func _show_result(title: String, tile: Control, flavour: String) -> void:
	_choice_row.queue_free()
	set_title(title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(tile)
	content.add_child(row)
	var line := Label.new()
	line.text = flavour
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_theme_font_size_override("font_size", 28)
	line.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	line.add_theme_constant_override("outline_size", 6)
	content.add_child(line)
	add_continue_button()
