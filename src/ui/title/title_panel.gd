class_name TitlePanel
extends Control
## The menu column of the title screen (patch 0.125, doc "Title Screen"): the
## neon Casino Brawyal logo, Play / Continue / Settings / Quit, and under them
## the Codex link and the Play Tutorial toggle. Laid out in the 1920x1080 the
## game runs at, the way the designer's mock has it: a dark panel down the left
## quarter that blurs the scene behind it.
##
## The logo is baked from the mock's neon (assets/ui/title/logo_*.png), one
## transparent layer each, so every part can flicker on its own clock: the
## "Casino" and "Brawyal" tubes fault now and then, the cards flicker and bob,
## the pink diamond hums. Continue only appears when there is a saved run.

signal play_pressed
signal continue_pressed
signal settings_pressed
signal quit_pressed
signal codex_pressed
signal tutorial_toggled(on: bool)

const WIDTH := 518.0
const HEIGHT := 1080.0
const BUTTON_SIZE := Vector2(311.0, 75.0)
const GAP := 22.0
const MENU_TOP := 466.0
const LOGO_DIR := "res://assets/ui/title/logo_%s.png"
const LOGO_OFFSET := Vector2(-16.0, -24.5)     # where the 1100x900 layers sit so the logo box starts 42 px down
const LOGO_SIZE := Vector2(550.0, 450.0)
const FONT_PATH := "res://assets/fonts/Nunito-Variable.ttf"
const PANEL_SHADER := "res://assets/shaders/title_panel.gdshader"

var _buttons: Array[Button] = []
var _chevrons: Array[NeonChevron] = []
var _layers := {}
var _toggle: NeonToggle
var _selected := -1
var _sel_style: StyleBoxFlat
var _pulse: Tween
var _t := 0.0
var _font: Font


func setup(has_save: bool, tutorial_on: bool) -> void:
	position = Vector2.ZERO
	size = Vector2(WIDTH, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	var fv := FontVariation.new()
	fv.base_font = load(FONT_PATH)
	fv.variation_opentype = {2003265652: 800}      # wght
	_font = fv

	var back := ColorRect.new()
	back.size = size
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(PANEL_SHADER):
		var sm := ShaderMaterial.new()
		sm.shader = load(PANEL_SHADER)
		back.material = sm
	else:
		back.color = Color(0.03, 0.04, 0.12, 0.8)
	add_child(back)

	# the neon logo, one layer per tube
	for layer in ["diamond", "cardA", "cardB", "casino", "brawyal"]:
		var path: String = LOGO_DIR % layer
		var rect := TextureRect.new()
		if ResourceLoader.exists(path):
			rect.texture = load(path)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.size = LOGO_SIZE
		rect.position = Vector2((WIDTH - 441.0) * 0.5 - 54.5, 42.0 - 66.5)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rect)
		_layers[layer] = rect

	# the menu
	var entries: Array = [["Play", play_pressed]]
	if has_save:
		entries.append(["Continue", continue_pressed])
	entries.append(["Settings", settings_pressed])
	entries.append(["Quit", quit_pressed])
	_sel_style = _style(true)
	for i in entries.size():
		var b := Button.new()
		b.text = entries[i][0]
		b.size = BUTTON_SIZE
		b.position = Vector2((WIDTH - BUTTON_SIZE.x) * 0.5, MENU_TOP + i * (BUTTON_SIZE.y + GAP))
		b.focus_mode = Control.FOCUS_ALL
		b.add_theme_font_override("font", _font)
		b.add_theme_font_size_override("font_size", 30)
		for colour in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(colour, Color(0.96, 0.95, 1.0))
		b.add_theme_color_override("font_outline_color", Color(0.4, 0.9, 1.0, 0.0))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		_restyle(b, false)
		var index := i
		b.focus_entered.connect(func() -> void: _select(index))
		b.mouse_entered.connect(func() -> void: b.grab_focus())
		var sig: Signal = entries[i][1]
		b.pressed.connect(func() -> void: sig.emit())
		add_child(b)
		_buttons.append(b)
	for side in 2:
		var chev := NeonChevron.new()
		chev.mirrored = side == 1
		chev.modulate.a = 0.0
		add_child(chev)
		_chevrons.append(chev)

	# the small things under the buttons
	var rows_end := MENU_TOP + entries.size() * BUTTON_SIZE.y + (entries.size() - 1) * GAP
	var extras := HBoxContainer.new()
	extras.add_theme_constant_override("separation", 27)
	extras.alignment = BoxContainer.ALIGNMENT_CENTER
	extras.position = Vector2(0.0, rows_end + 36.0)
	extras.size = Vector2(WIDTH, 53.0)
	var codex := Button.new()
	codex.text = "Codex"
	codex.flat = true
	codex.focus_mode = Control.FOCUS_ALL
	codex.add_theme_font_override("font", _font)
	codex.add_theme_font_size_override("font_size", 20)
	for colour in ["font_color", "font_pressed_color"]:
		codex.add_theme_color_override(colour, Color(0.82, 0.8, 0.94, 0.85))
	for colour in ["font_hover_color", "font_focus_color"]:
		codex.add_theme_color_override(colour, Color.WHITE)
	codex.pressed.connect(func() -> void: codex_pressed.emit())
	extras.add_child(codex)
	_toggle = NeonToggle.new()
	_toggle.font = _font
	_toggle.button_pressed = tutorial_on
	_toggle.toggled.connect(func(on: bool) -> void: tutorial_toggled.emit(on))
	extras.add_child(_toggle)
	add_child(extras)

	var version := Label.new()
	version.text = "v" + str(ProjectSettings.get_setting("application/config/version", ""))
	version.position = Vector2(31.0, HEIGHT - 42.0)
	version.add_theme_font_size_override("font_size", 18)
	version.add_theme_color_override("font_color", Color(0.75, 0.73, 0.88, 0.5))
	version.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(version)

	# Continue is the way back into a run, so it takes the cursor when there is one
	var first := 1 if has_save else 0
	_buttons[first].call_deferred("grab_focus")


func _process(delta: float) -> void:
	_t += delta
	_animate_logo()
	queue_redraw()


## The panel's right edge: a thin neon line whose colour runs from cyan to pink and slowly scrolls.
func _draw() -> void:
	var x := WIDTH - 2.0
	var segs := 54
	for i in segs:
		var y0 := HEIGHT * i / segs
		var f := fposmod(float(i) / segs * 2.0 - _t / 7.0, 2.0)
		f = f if f <= 1.0 else 2.0 - f
		var c := Color(0.36, 0.95, 1.0).lerp(Color(1.0, 0.31, 0.72), smoothstep(0.0, 1.0, f))
		draw_rect(Rect2(x - 5.0, y0, 9.0, HEIGHT / segs + 1.0), Color(c, 0.16))
		draw_rect(Rect2(x, y0, 2.0, HEIGHT / segs + 1.0), Color(c, 0.9))


func _animate_logo() -> void:
	# "Casino" and "Brawyal" fault now and then; the cards flicker together; the diamond hums.
	_set_alpha("casino", TitleLights._track([[0.0, 1.0], [0.05, 1.0], [0.06, 0.55], [0.07, 1.0], [0.08, 0.65], [0.09, 1.0], [0.52, 1.0], [0.526, 0.5], [0.532, 1.0], [1.0, 1.0]], fposmod(_t / 8.0, 1.0)))
	_set_alpha("brawyal", TitleLights._track([[0.0, 1.0], [0.31, 1.0], [0.314, 0.4], [0.319, 1.0], [0.326, 0.6], [0.332, 1.0], [0.74, 0.9], [1.0, 1.0]], fposmod(_t / 11.0, 1.0)))
	var cards := TitleLights._track([[0.0, 1.0], [0.61, 1.0], [0.614, 0.5], [0.619, 1.0], [0.626, 0.7], [0.631, 1.0], [1.0, 1.0]], fposmod(_t / 9.0, 1.0))
	_set_alpha("cardA", cards)
	_set_alpha("cardB", cards)
	_set_alpha("diamond", 0.75 + 0.25 * (0.5 - 0.5 * cos(TAU * _t / 6.0)))
	# the cards bob, 2 s out of step
	(_layers.cardA as TextureRect).position.y = 42.0 - 66.5 - 4.4 * (0.5 - 0.5 * cos(TAU * _t / 4.4))
	(_layers.cardB as TextureRect).position.y = 42.0 - 66.5 - 4.4 * (0.5 - 0.5 * cos(TAU * (_t + 2.2) / 4.4))


func _set_alpha(layer: String, a: float) -> void:
	(_layers[layer] as TextureRect).modulate.a = a


## The neon button looks: a cyan outline with a glow, and for the selected one a purple fill and a pink glow.
func _style(selected: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(17)
	s.set_border_width_all(2)
	if selected:
		s.bg_color = Color(0.58, 0.2, 0.86, 0.78)
		s.border_color = Color(1.0, 0.7, 0.94)
		s.shadow_color = Color(1.0, 0.39, 0.9, 0.85)
		s.shadow_size = 22
	else:
		s.bg_color = Color(0.035, 0.047, 0.15, 0.55)
		s.border_color = Color(0.49, 0.91, 1.0, 0.8)
		s.shadow_color = Color(0.36, 0.95, 1.0, 0.45)
		s.shadow_size = 11
	return s


func _restyle(b: Button, selected: bool) -> void:
	var s := _sel_style if selected else _style(false)
	for slot in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(slot, s)


func _select(i: int) -> void:
	if i == _selected:
		return
	_selected = i
	for k in _buttons.size():
		_restyle(_buttons[k], k == i)
	var centre_y := _buttons[i].position.y + BUTTON_SIZE.y * 0.5 - NeonChevron.SIZE * 0.5
	var xs := [WIDTH * 0.5 - 220.0, WIDTH * 0.5 + 170.0]
	for side in 2:
		var c := _chevrons[side]
		var target := Vector2(xs[side], centre_y)
		if c.modulate.a < 0.5:
			c.position = target
		else:
			create_tween().tween_property(c, "position", target, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		create_tween().tween_property(c, "modulate:a", 1.0, 0.12)
	# the selected button's glow breathes
	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
	_pulse = create_tween().set_loops()
	_pulse.tween_property(_sel_style, "shadow_size", 32, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse.tween_property(_sel_style, "shadow_size", 18, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
