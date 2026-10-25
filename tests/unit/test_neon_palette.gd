extends GutTest
## Patch 0.126: the neon look is a palette per act, so the office and the hells
## can change the glow colours without touching a single widget.


func after_each() -> void:
	NeonPalette.set_act(NeonPalette.DEFAULT_ACT)


func test_every_act_has_the_same_roles() -> void:
	var roles := NeonPalette.ROLES
	for act: StringName in NeonPalette.acts():
		var palette: Dictionary = NeonPalette.for_act(act)
		for role: String in roles:
			assert_true(palette.has(role), "%s is missing %s" % [act, role])
			assert_true(palette[role] is Color, "%s.%s must be a Color" % [act, role])


func test_the_casino_is_magenta_and_the_next_two_acts_are_blue_and_red() -> void:
	assert_eq(NeonPalette.DEFAULT_ACT, &"casino")
	var casino: Dictionary = NeonPalette.for_act(&"casino")
	var office: Dictionary = NeonPalette.for_act(&"office")
	var hells: Dictionary = NeonPalette.for_act(&"hells")
	assert_gt(casino.tube.r, casino.tube.g, "magenta leans red")
	assert_gt(casino.tube.b, casino.tube.g, "and blue")
	assert_gt(office.tube.b, office.tube.r, "the office glows blue")
	assert_gt(hells.tube.r, hells.tube.b, "the hells glow red")


func test_acts_are_told_apart_by_hue_not_just_brightness() -> void:
	var seen := {}
	for act: StringName in NeonPalette.acts():
		seen[roundi(NeonPalette.for_act(act).tube.h * 12.0)] = true
	assert_eq(seen.size(), NeonPalette.acts().size())


func test_money_stays_gold_in_every_act() -> void:
	var gold: Color = NeonPalette.for_act(&"casino").money
	for act: StringName in NeonPalette.acts():
		assert_eq(NeonPalette.for_act(act).money, gold, act)


func test_enemies_and_the_hero_never_share_a_colour() -> void:
	for act: StringName in NeonPalette.acts():
		var palette: Dictionary = NeonPalette.for_act(act)
		assert_gt(absf(palette.foe.h - palette.hero.h), 0.08, "%s: foe and hero hues" % act)


func test_switching_the_act_changes_what_current_returns() -> void:
	var before: Color = NeonPalette.current().tube
	NeonPalette.set_act(&"hells")
	assert_ne(NeonPalette.current().tube, before)
	NeonPalette.set_act(&"nowhere")
	assert_eq(NeonPalette.act(), &"hells", "an unknown act is ignored")


func test_the_theme_follows_the_palette() -> void:
	var casino := NeonTheme.build(NeonPalette.for_act(&"casino"))
	var hells := NeonTheme.build(NeonPalette.for_act(&"hells"))
	var a: StyleBoxFlat = casino.get_stylebox("normal", "Button")
	var b: StyleBoxFlat = hells.get_stylebox("normal", "Button")
	assert_ne(a.border_color, b.border_color)
	assert_eq(a.border_color, NeonPalette.for_act(&"casino").tube)


func test_the_theme_has_every_type_the_screens_use() -> void:
	var theme := NeonTheme.build(NeonPalette.current())
	for type_name in ["Button", "PanelContainer", "Panel", "ProgressBar", "HSlider",
			"TooltipPanel", "TitleLabel", "SubtitleLabel", "FeltPanel"]:
		assert_true(theme.get_type_list().has(type_name), type_name)
	assert_true(theme.has_stylebox("normal", "PrimaryButton"))
	assert_true(theme.has_stylebox("fill", "HeroBar"))
	assert_true(theme.has_stylebox("fill", "FoeBar"))
