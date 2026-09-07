extends ScreenBase
## Post-combat rewards: coins (auto-claimed), pick 1 of 3 abilities, and a
## relic after Hard Combat. Picking one already owned upgrades it instead of
## adding a second copy (doc "Ability Upgrades").

var _ability_row: HBoxContainer


func _ready() -> void:
	# Standalone debug launch, so the choice cards can be reviewed on their own.
	if get_tree().current_scene == self and Game.run == null:
		Game.run = RunState.new()
		Game.rng = GameRng.new(randi())
		for id in ["card_sling", "quick_maneuvers", "color_up", "double_down",
				"heartsteal", "pocket_rockets", "bust", "on_a_roll", "flush",
				"bad_beat", "pay_line", "slow_playing"]:
			Game.run.acquire_ability(StringName(id))
		Game.run.acquire_ability(&"bust")   # a silver copy, so gold is on offer
		setup({"gold_min": 27, "gold_max": 33})


func setup(args: Dictionary) -> void:
	build_screen("Winnings", "res://assets/backgrounds/bg_casino_floor.png")
	var reward_rng := Game.rng.stream(&"rewards")

	var coins := Rewards.roll_coins(
		int(args.get("gold_min", 0)), int(args.get("gold_max", 0)), reward_rng)
	Game.run.coins += coins
	add_info_label("🪙 +%d coins" % coins, 30)

	if args.get("hard", false):
		var relic := Rewards.random_unowned_relic(Db.content, Game.run, reward_rng)
		if relic != &"":
			Game.run.relic_ids.append(relic)
			var def := Db.content.get_relic(relic)
			add_info_label("Hard combat bonus — Relic: %s\n%s" % [def.name, def.description], 24)

	var choices := Rewards.ability_choices(Db.content, Game.run, reward_rng)
	if not choices.is_empty():
		add_info_label("Choose one:", 24)
		_ability_row = HBoxContainer.new()
		_ability_row.alignment = BoxContainer.ALIGNMENT_CENTER
		_ability_row.add_theme_constant_override("separation", 22)
		content.add_child(_ability_row)
		for ability_id: StringName in choices:
			_ability_row.add_child(_build_ability_card(ability_id))

	add_continue_button("Skip / Continue", Game.encounter_finished)


## A Button's own text never wraps, so a long description could grow wider
## than its sibling card and crowd it off-screen (patch 0.17). This builds
## the button with an internal wrapped Label instead, capping its width so
## all three choices fit.
const CARD_WIDTH := 320.0


## One choice. An ability already owned shows what it would become — the doc's
## "distinctive glowing border and an UPGRADE! indicator in the upper right".
func _build_ability_card(ability_id: StringName) -> Button:
	var owned := Game.run.ability_ids.has(ability_id)
	var tier := Game.run.ability_tier(ability_id)
	var shown_tier := tier + 1 if owned else 0
	var def := Db.content.get_ability(ability_id, shown_tier)

	var card := Button.new()
	card.custom_minimum_size = Vector2(CARD_WIDTH, 246)
	card.pressed.connect(_pick_ability.bind(ability_id))
	for state in ["normal", "hover", "pressed", "focus"]:
		card.add_theme_stylebox_override(state,
			TierStyle.upgrade_panel() if owned else TierStyle.panel(0))

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)

	var icon_texture := SuitAssets.ability_texture(ability_id)
	if icon_texture != null:
		var icon_holder := CenterContainer.new()
		var icon := TextureRect.new()
		icon.texture = icon_texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(54, 54)
		icon_holder.add_child(icon)
		box.add_child(icon_holder)

	var title_label := Label.new()
	title_label.text = def.name
	title_label.theme_type_variation = &"SubtitleLabel"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	if shown_tier > 0:
		title_label.add_theme_color_override("font_color", TierStyle.color(shown_tier))
	box.add_child(title_label)

	var cost_text := " ".join(def.cost.map(
		func(suit: StringName) -> String: return String(suit).left(1).to_upper()))
	var body_label := Label.new()
	body_label.text = "Cost: %s\n%s" % [cost_text, def.description]
	body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	body_label.custom_minimum_size = Vector2(CARD_WIDTH - 30.0, 0)
	body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(body_label)

	if owned:
		# Says what it becomes, so the choice is legible without hovering.
		var to_label := Label.new()
		to_label.text = "You own this — upgrade to %s" % TierStyle.label(shown_tier)
		to_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		to_label.add_theme_font_size_override("font_size", 15)
		to_label.add_theme_color_override("font_color", TierStyle.color(shown_tier))
		box.add_child(to_label)

		var overlay := Control.new()
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(overlay)
		var badge := TierStyle.upgrade_badge(shown_tier)
		badge.position = Vector2(CARD_WIDTH - 108.0, 8.0)
		overlay.add_child(badge)
	return card


func _pick_ability(ability_id: StringName) -> void:
	Game.run.acquire_ability(ability_id)
	Game.encounter_finished()
