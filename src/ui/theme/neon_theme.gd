class_name NeonTheme
extends RefCounted
## Builds the game's Theme from a NeonPalette (patch 0.126). Everything the
## screens draw with stock controls (buttons, panels, bars, sliders, tooltips,
## titles) comes from here, so one palette change recolours the whole game.
## `Main` assigns the result to the root window; the old casino_theme.tres is
## now only the project-level fallback.

const BODY_FONT := "res://assets/fonts/Nunito-Variable.ttf"
# The display face is the game's original one (0.126: the Exo 2 trial was unclear in combat).
const HEAD_FONT := "res://assets/fonts/AlfaSlabOne-Regular.ttf"
const SCRIPT_FONT := "res://assets/fonts/Yellowtail-Regular.ttf"


static func build(p: Dictionary) -> Theme:
	var theme := Theme.new()
	var tube: Color = p.tube
	var glass: Color = p.glass
	var deep: Color = p.glass_deep
	var text: Color = p.text

	var body := _font(BODY_FONT, 0)
	var head := _font(HEAD_FONT, 0)
	var script := _font(SCRIPT_FONT, 0)
	if body != null:
		theme.default_font = body
	theme.default_font_size = 22

	# ----- buttons: an outlined tube; the live one (PrimaryButton) is filled -----
	_button(theme, "Button", glass, tube, p, false)
	_button(theme, "PrimaryButton", NeonPalette.alpha(tube.darkened(0.15), 0.95), tube.lerp(Color.WHITE, 0.45), p, true)
	theme.set_type_variation("PrimaryButton", "Button")
	for type_name in ["Button", "PrimaryButton"]:
		theme.set_stylebox("focus", type_name, StyleBoxEmpty.new())
		theme.set_color("font_color", type_name, text)
		theme.set_color("font_hover_color", type_name, Color.WHITE)
		theme.set_color("font_pressed_color", type_name, p.tube_hi)
		theme.set_color("font_disabled_color", type_name, NeonPalette.alpha(p.dim, 0.55))
		theme.set_font_size("font_size", type_name, 24)

	# ----- panels: warm-black glass with a lit edge -----
	var panel := _glass(glass, NeonPalette.alpha(tube, 0.55), 12, 0.18, tube)
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)
	theme.set_type_variation("FeltPanel", "PanelContainer")
	theme.set_stylebox("panel", "FeltPanel", _glass(deep, NeonPalette.alpha(p.hero, 0.6), 12, 0.2, p.hero))
	theme.set_stylebox("panel", "TooltipPanel", _glass(deep, NeonPalette.alpha(tube, 0.85), 8, 0.3, tube))
	theme.set_color("font_color", "TooltipLabel", text)

	# ----- labels -----
	theme.set_color("font_color", "Label", text)
	theme.set_type_variation("TitleLabel", "Label")
	theme.set_color("font_color", "TitleLabel", Color(1.0, 0.97, 0.99))
	theme.set_color("font_outline_color", "TitleLabel", NeonPalette.alpha(tube, 0.55))
	theme.set_constant("outline_size", "TitleLabel", 14)
	theme.set_font_size("font_size", "TitleLabel", 78)
	theme.set_color("font_shadow_color", "TitleLabel", NeonPalette.alpha(tube, 0.5))
	theme.set_constant("shadow_offset_x", "TitleLabel", 0)
	theme.set_constant("shadow_offset_y", "TitleLabel", 0)
	theme.set_constant("shadow_outline_size", "TitleLabel", 20)
	if script != null:
		theme.set_font("font", "TitleLabel", script)
	# The banner face (victory, defeat, the run's end): the same neon script as the
	# other big titles (0.126: the designer wants victory in the new stylised font).
	theme.set_type_variation("BannerLabel", "TitleLabel")
	theme.set_font_size("font_size", "BannerLabel", 110)
	theme.set_type_variation("SubtitleLabel", "Label")
	theme.set_color("font_color", "SubtitleLabel", Color(1.0, 0.97, 0.99))
	theme.set_font_size("font_size", "SubtitleLabel", 30)
	if head != null:
		theme.set_font("font", "SubtitleLabel", head)

	# ----- bars: a dark trough, a lit fill; hero and foe have their own colours -----
	var trough := StyleBoxFlat.new()
	trough.bg_color = Color(1, 1, 1, 0.08)
	trough.set_corner_radius_all(6)
	trough.set_border_width_all(1)
	trough.border_color = Color(1, 1, 1, 0.16)
	theme.set_stylebox("background", "ProgressBar", trough)
	theme.set_stylebox("fill", "ProgressBar", _bar_fill(tube))
	for variation in [["HeroBar", p.hero], ["FoeBar", p.foe]]:
		theme.set_type_variation(variation[0], "ProgressBar")
		theme.set_stylebox("background", variation[0], trough)
		theme.set_stylebox("fill", variation[0], _bar_fill(variation[1]))
	theme.set_color("font_color", "ProgressBar", Color.WHITE)

	# ----- sliders -----
	var rail := StyleBoxFlat.new()
	rail.bg_color = Color(1, 1, 1, 0.14)
	rail.set_corner_radius_all(4)
	rail.content_margin_top = 4
	rail.content_margin_bottom = 4
	theme.set_stylebox("slider", "HSlider", rail)
	var lit := StyleBoxFlat.new()
	lit.bg_color = tube
	lit.set_corner_radius_all(4)
	lit.shadow_color = NeonPalette.alpha(tube, 0.6)
	lit.shadow_size = 6
	theme.set_stylebox("grabber_area", "HSlider", lit)
	theme.set_stylebox("grabber_area_highlight", "HSlider", lit)
	theme.set_icon("grabber", "HSlider", _knob(Color.WHITE, tube))
	theme.set_icon("grabber_highlight", "HSlider", _knob(Color.WHITE, p.tube_hi))
	theme.set_icon("grabber_disabled", "HSlider", _knob(p.dim, p.dim))
	return theme


static func _font(path: String, weight: int) -> Font:
	if not ResourceLoader.exists(path):
		return null
	var base: Font = load(path)
	if weight <= 0:
		return base
	var variation := FontVariation.new()
	variation.base_font = base
	variation.variation_opentype = {2003265652: weight}   # wght
	return variation


## A rounded glass box with a 2 px tube edge and a soft glow outside it.
static func _glass(fill: Color, edge: Color, radius: int, glow: float, glow_colour: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(2)
	box.set_corner_radius_all(radius)
	box.shadow_color = NeonPalette.alpha(glow_colour, glow)
	box.shadow_size = 10
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	return box


static func _button(theme: Theme, type_name: String, fill: Color, edge: Color, p: Dictionary, solid: bool) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box := StyleBoxFlat.new()
		box.set_corner_radius_all(12)
		box.set_border_width_all(2)
		box.content_margin_left = 24
		box.content_margin_right = 24
		box.content_margin_top = 10
		box.content_margin_bottom = 10
		match state:
			"normal":
				box.bg_color = fill
				box.border_color = edge
				box.shadow_color = NeonPalette.alpha(edge, 0.45 if solid else 0.30)
				box.shadow_size = 9
			"hover":
				box.bg_color = fill.lerp(edge, 0.30) if not solid else fill.lerp(Color.WHITE, 0.18)
				box.border_color = edge.lerp(Color.WHITE, 0.35)
				box.shadow_color = NeonPalette.alpha(edge, 0.7)
				box.shadow_size = 14
			"pressed":
				box.bg_color = fill.lerp(edge, 0.5) if not solid else fill.darkened(0.2)
				box.border_color = edge
				box.shadow_size = 4
				box.shadow_color = NeonPalette.alpha(edge, 0.5)
				box.content_margin_top = 12
				box.content_margin_bottom = 8
			"disabled":
				box.bg_color = Color(0.1, 0.09, 0.11, 0.7)
				box.border_color = NeonPalette.alpha(p.dim, 0.35)
		theme.set_stylebox(state, type_name, box)


static func _bar_fill(colour: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(6)
	box.shadow_color = NeonPalette.alpha(colour, 0.55)
	box.shadow_size = 8
	return box


## A round slider knob with a coloured halo, drawn into an image so no art is needed.
static func _knob(core: Color, halo: Color) -> Texture2D:
	var size := 28
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var centre := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(centre)
			var c := Color(0, 0, 0, 0)
			if d <= 8.5:
				c = core
			elif d <= 10.5:
				c = NeonPalette.alpha(halo, 1.0)
			elif d <= 14.0:
				c = NeonPalette.alpha(halo, 0.45 * (1.0 - (d - 10.5) / 3.5))
			image.set_pixel(x, y, c)
	return ImageTexture.create_from_image(image)


## A name/health plate for one side: the glass box with that side's colour on its edge.
static func plate(p: Dictionary, side: Color) -> StyleBoxFlat:
	var box := _glass(p.glass, NeonPalette.alpha(side, 0.85), 12, 0.35, side)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 10
	return box


## Rewrites the PROJECT theme in place from the current act's palette. The
## header and its overlays live under a CanvasLayer, which does not pass a
## window theme down, and a screen opened on its own (debug, screenshots) has no
## Main above it, so the project theme is the one place every Control reaches.
## Call again after `NeonPalette.set_act()` when a new act begins.
static func apply_project() -> void:
	var built := build(NeonPalette.current())
	var project := ThemeDB.get_project_theme()
	if project == null:
		return
	project.clear()
	project.merge_with(built)
