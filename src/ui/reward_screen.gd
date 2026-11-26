class_name RewardScreen
extends ScreenBase
## Post-combat rewards (build 1.30, from the designer's mock): a "Winnings" title,
## one lit tile per reward (the coins always, and after an Elite the relic beside
## them), then the three ability choices under a "Choose one ability" rule, and a
## Skip that says what it does. Picking an ability you already own upgrades it
## instead of adding a second copy.

const CARD_SCALE := 1.6
const TIER_NAMES: Array[String] = ["COPPER", "SILVER", "GOLD"]
const GOLD := Color(1.0, 0.79, 0.35)
const NEW_GREEN := Color(0.25, 0.88, 0.69)


## The tag on an upgrade offer: "UPGRADE  COPPER TO SILVER".
static func upgrade_tag(to_tier: int) -> String:
	var to := clampi(to_tier, 1, TIER_NAMES.size() - 1)
	return "UPGRADE  %s TO %s" % [TIER_NAMES[to - 1], TIER_NAMES[to]]


## The doc's Ability Choosing Screen: with six equipped, a NEW ability goes to the
## trash slot and opens the loadout. An upgrade never does.
static func hand_full_warning(run: RunState, choices: Array) -> bool:
	if run.equipped_ids.size() < RunState.EQUIP_CAP:
		return false
	for id: StringName in choices:
		if not run.ability_ids.has(id):
			return true
	return false


func _ready() -> void:
	# Standalone debug launch, so the screen can be reviewed on its own.
	if get_tree().current_scene == self and Game.run == null:
		Game.run = RunState.new()
		Game.rng = GameRng.new(randi())
		for id in ["card_sling", "quick_maneuvers", "color_up", "double_down",
				"heartsteal", "pocket_rockets", "bust", "on_a_roll", "flush",
				"bad_beat", "pay_line", "slow_playing"]:
			Game.run.acquire_ability(StringName(id))
		Game.run.acquire_ability(&"bust")   # a silver copy, so gold is on offer
		setup({"gold_min": 27, "gold_max": 33, "elite": OS.get_environment("CB_DEBUG_ELITE") == "1"})


func setup(args: Dictionary) -> void:
	build_screen("Winnings", "res://assets/backgrounds/bg_casino_floor.png")
	var palette := NeonPalette.current()
	_title_label.add_theme_font_size_override("font_size", 76)
	_title_label.get_parent().add_theme_constant_override("separation", 6)
	content.add_theme_constant_override("separation", 10)
	var eyebrow := add_eyebrow("Victory")
	eyebrow.add_theme_color_override("font_color", palette.tube_hi)
	var reward_rng := Game.rng.stream(&"rewards")

	var coins := Rewards.roll_coins(
		int(args.get("gold_min", 0)), int(args.get("gold_max", 0)), reward_rng)
	Game.run.coins += coins
	var tiles := HBoxContainer.new()
	tiles.alignment = BoxContainer.ALIGNMENT_CENTER
	tiles.add_theme_constant_override("separation", 28)
	content.add_child(tiles)
	tiles.add_child(RewardTiles.coin_tile(coins))

	if args.get("elite", false):
		var relic := Rewards.random_unowned_relic(Db.content, Game.run, reward_rng)
		if relic != &"":
			Game.run.relic_ids.append(relic)
			tiles.add_child(RewardTiles.relic_tile(relic, "Elite bonus relic"))

	var choices := Rewards.ability_choices(Db.content, Game.run, reward_rng)
	if not choices.is_empty():
		content.add_child(_choose_rule())
		var gap := Control.new()   # room for the tags that hang over the cards' top edge
		gap.custom_minimum_size = Vector2(0, 14)
		content.add_child(gap)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 44)
		content.add_child(row)
		for ability_id: StringName in choices:
			row.add_child(_build_ability_card(ability_id))
		if hand_full_warning(Game.run, choices):
			add_child(_full_hand_note())

	var skip_box := VBoxContainer.new()
	skip_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	skip_box.add_theme_constant_override("separation", 2)
	content.add_child(skip_box)
	var skip := Button.new()
	skip.text = "Skip, take no ability" if not choices.is_empty() else "Continue"
	skip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	skip.add_theme_font_size_override("font_size", 22)
	skip.pressed.connect(Game.encounter_finished)
	skip_box.add_child(skip)
	var hint := Label.new()
	hint.text = "The coins are already yours."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 17)
	hint.add_theme_color_override("font_color", palette.dim)
	skip_box.add_child(hint)


## "Choose one ability" between two lit rules.
func _choose_rule() -> Control:
	var palette := NeonPalette.current()
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	row.add_child(_rule(palette.tube))
	var label := Label.new()
	label.text = "CHOOSE ONE ABILITY"
	label.theme_type_variation = &"SubtitleLabel"
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", palette.text)
	row.add_child(label)
	row.add_child(_rule(palette.tube))
	return row


func _rule(colour: Color) -> Control:
	var line := ColorRect.new()
	line.color = colour
	line.custom_minimum_size = Vector2(220, 2)
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return line


## Optional note at the side (designer: keep it): a new ability will open the loadout.
func _full_hand_note() -> Control:
	var tile := RewardTiles.tile(GOLD)
	tile.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	tile.offset_left = -330.0
	tile.offset_right = -60.0
	tile.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tile.grow_vertical = Control.GROW_DIRECTION_BOTH
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(230, 0)
	tile.add_child(column)
	var head := Label.new()
	head.text = "Your hand is full (%d of %d)." % [RunState.EQUIP_CAP, RunState.EQUIP_CAP]
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_theme_font_size_override("font_size", 20)
	head.add_theme_color_override("font_color", GOLD)
	column.add_child(head)
	var body := Label.new()
	body.text = "Taking a new ability opens the loadout so you can swap one out. Upgrades never do."
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 18)
	column.add_child(body)
	return tile


## One choice. The whole card is the button. An ability already owned shows what
## it would become, with the glowing ring and a tag naming the step; a new one
## says NEW.
func _build_ability_card(ability_id: StringName) -> Button:
	var owned := Game.run.ability_ids.has(ability_id)
	var tier := Game.run.ability_tier(ability_id)
	var shown_tier := tier + 1 if owned else 0
	var def := Db.content.get_ability(ability_id, shown_tier)

	var card := Button.new()
	card.custom_minimum_size = AbilityCard.CARD_SIZE * CARD_SCALE
	card.flat = true
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		card.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	card.pressed.connect(_pick_ability.bind(ability_id))
	card.pivot_offset = card.custom_minimum_size * 0.5
	card.mouse_entered.connect(func() -> void:
		create_tween().tween_property(card, "scale", Vector2(1.04, 1.04), 0.1))
	card.mouse_exited.connect(func() -> void:
		create_tween().tween_property(card, "scale", Vector2.ONE, 0.12))
	card.add_child(AbilityCard.preview(def, CARD_SCALE))

	if owned:
		card.add_child(TierStyle.glow_ring(shown_tier))
	card.add_child(_tag(upgrade_tag(shown_tier) if owned else "NEW", owned, shown_tier))
	return card


## The pill hung over the top edge of a card.
func _tag(text: String, upgrade: bool, tier: int) -> Control:
	var holder := HBoxContainer.new()
	holder.alignment = BoxContainer.ALIGNMENT_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_preset(Control.PRESET_TOP_WIDE)
	holder.offset_top = -20.0
	holder.offset_bottom = 8.0
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	var fill: Color = TierStyle.metal(tier).hi if upgrade else NEW_GREEN
	box.bg_color = fill
	box.set_corner_radius_all(14)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	box.shadow_color = Color(TierStyle.metal(tier).mid if upgrade else NEW_GREEN, 0.7)
	box.shadow_size = 10
	pill.add_theme_stylebox_override("panel", box)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.1, 0.06, 0.14))
	pill.add_child(label)
	holder.add_child(pill)
	return holder


func _pick_ability(ability_id: StringName) -> void:
	Audio.play_sfx(&"reward_pick")
	Game.run.acquire_ability(ability_id)
	Game.encounter_finished()
