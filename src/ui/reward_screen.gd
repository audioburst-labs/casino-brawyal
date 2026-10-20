extends ScreenBase
## Post-combat rewards: coins (auto-claimed), pick 1 of 3 abilities, and a
## relic after an Elite (doc: "Relic (Elite Only)"). Picking an ability you
## already own upgrades it instead of adding a second copy.

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

	if args.get("elite", false):
		var relic := Rewards.random_unowned_relic(Db.content, Game.run, reward_rng)
		if relic != &"":
			Game.run.relic_ids.append(relic)
			var def := Db.content.get_relic(relic)
			# The relic the Elite dropped, with its own art (patch 0.22).
			var relic_row := HBoxContainer.new()
			relic_row.alignment = BoxContainer.ALIGNMENT_CENTER
			relic_row.add_theme_constant_override("separation", 14)
			relic_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			content.add_child(relic_row)
			var icon := TextureRect.new()
			icon.texture = SuitAssets.relic_texture(relic)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(72, 72)
			relic_row.add_child(icon)
			var text := Label.new()
			text.text = "Elite bonus. Relic: %s\n%s" % [def.name, def.description]
			text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			text.custom_minimum_size = Vector2(560, 0)
			text.add_theme_font_size_override("font_size", 22)
			relic_row.add_child(text)

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
## Patch 0.125: a choice is the combat card enlarged.
const CARD_SCALE := 1.7


## One choice. An ability already owned shows what it would become — the doc's
## "distinctive glowing border and an UPGRADE! indicator in the upper right".
func _build_ability_card(ability_id: StringName) -> Button:
	var owned := Game.run.ability_ids.has(ability_id)
	var tier := Game.run.ability_tier(ability_id)
	var shown_tier := tier + 1 if owned else 0
	var def := Db.content.get_ability(ability_id, shown_tier)

	# The card itself (patch 0.125), bigger than it is in combat. The whole thing
	# is the button: a click anywhere on it takes the ability. An ability already
	# owned shows what it would become, with the glowing ring and the flag.
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
		var badge := TierStyle.upgrade_badge(shown_tier)
		badge.position = Vector2(AbilityCard.CARD_SIZE.x * CARD_SCALE - 112.0, -22.0)
		card.add_child(badge)
	return card


func _pick_ability(ability_id: StringName) -> void:
	Audio.play_sfx(&"reward_pick")
	Game.run.acquire_ability(ability_id)
	Game.encounter_finished()
