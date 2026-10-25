class_name SlotCabinet
extends Control
## The slot machine itself (doc "Assets → Gameplay Elements → Slot Machine":
## "a golden machine, with a drawer for the chips on the game to 'fall' into,
## with a fancy header with the name of the casino 'Dreams Casino'").
##
## Three generated art bands plus a lever, stacked:
##
##     [ marquee ]   gold sign; the casino's name is a Label on its plaque
##     [ window  ]   gold frame with a HOLE — the live reels show through   ) lever
##     [ drawer  ]   maroon drawer with a HOLE — the chip tray sits in it
##
## The holes are real. The art is generated on magenta and `chroma_key.gd` keys
## every magenta pixel, including the rectangle painted inside each frame, so
## the cabinet can be drawn OVER its contents and they still show through. That
## is what lets every existing animation keep working untouched: the reels are
## the same `ReelStrip`, the chips the same `ChipTrayView`, the spin the same
## tweens — they are simply framed now (patch 0.22).
##
## Each band is nine-sliced by hand in `_draw` rather than with a NinePatchRect:
## the source art is ~1500 px wide, so a NinePatch would draw its margins at
## that scale and swallow a 600 px cabinet whole. The slice margins are the
## measured distance from each band's edge to its hole, so the stretched middle
## of the art lands exactly on the content.

enum Mode {
	COMBAT,   ## reels in the window, chip tray in the drawer
	CASINO,   ## prize reels in the window, the result line in the drawer
	GRID,     ## a symbol grid in the window; no drawer, no lever
}

## Preloaded, not loaded inside _draw: a load() during the draw pass hands
## back a placeholder that paints a flat white rectangle (patch 0.22).
const MARQUEE_ART: Texture2D = preload("res://assets/props/cabinet_marquee.png")
const WINDOW_ART: Texture2D = preload("res://assets/props/cabinet_window.png")
const DRAWER_ART: Texture2D = preload("res://assets/props/cabinet_drawer.png")
const LEVER_ART: Texture2D = preload("res://assets/props/cabinet_lever.png")

## Where the drawn band actually sits inside each 1536x1024 source image, and
## where its cut-out hole sits inside that band — both measured off the keyed
## PNGs. Regenerating the art means re-measuring these (see the patch report).
const MARQUEE_BOX := Rect2(45, 135, 1445, 746)
const WINDOW_BOX := Rect2(31, 28, 1473, 958)
const DRAWER_BOX := Rect2(51, 105, 1439, 842)
## Fractions of the band, left/top .. right/bottom.
const WINDOW_HOLE := Rect2(0.1208, 0.1534, 0.7584, 0.6775)
const DRAWER_HOLE := Rect2(0.1258, 0.2755, 0.7484, 0.4561)
## The marquee has no hole; its bulb clusters live in the outer thirds, so only
## the plain plaque between them is ever stretched.
const MARQUEE_MARGIN := Vector2(0.30, 0.26)

## Frame thickness around the content, in pixels at art_scale 1.
const WINDOW_FRAME := Vector2(26.0, 15.0)
const DRAWER_FRAME := Vector2(24.0, 14.0)
const MARQUEE_HEIGHT := 34.0
const LEVER_WIDTH := 58.0

## Patch 0.113 ("make the slot machine flashier, with all parts connected and
## animated"). The three generated bands are separate pictures with their own
## transparent padding, so they used to read as three things stacked near each
## other. A drawn CHASSIS now runs behind and between them — a body slab, two
## side rails and a coupler across the seam — and a chase of bulbs runs around
## the whole outline, so the machine reads as one lit object.
const CHASSIS_GOLD := Color(0.78, 0.60, 0.24)
const CHASSIS_GOLD_DARK := Color(0.44, 0.31, 0.12)
const CHASSIS_BODY := Color(0.22, 0.09, 0.11)
const CHASSIS_RECESS := Color(0.05, 0.03, 0.05)
const RAIL_WIDTH := 7.0
const BULB_LIT := Color(1.0, 0.93, 0.62)
const BULB_DIM := Color(0.34, 0.19, 0.08)
const BULB_SPACING := 27.0
const BULB_RADIUS := 3.4
## How far in from the cabinet's outer edge the bulbs are seated. Centring
## them on the very edge left half of every bulb hanging over the felt.
const BULB_INSET := 11.0
## How fast the chase travels, in bulbs per second.
const BULB_SPEED := 5.0

var mode: Mode = Mode.COMBAT
var art_scale := 1.0
var show_lever := true
var show_drawer := true
var marquee_text := "DREAMS CASINO"

var _content: Control = null
var _drawer_content: Control = null
var _window_holder: Control
var _drawer_holder: Control
var _backdrop: CabinetArt
var _art: CabinetArt
var _marquee_label: Label
## The bulb chase's travelling phase, and how long the machine is still
## celebrating a payout (the chase runs hot and the rails glow while it is
## above zero).
var _phase := 0.0
var _excited := 0.0
var _lever_angle := 0.0


## A drawing layer that hands its `_draw` back to the cabinet. Two exist: the
## backdrop (added FIRST, so the reels and chips cover it) carries the chassis
## the bands sit on; the art layer (added LAST) carries the bands themselves,
## which draw ABOVE the reels and bevel their edges — their keyed-out holes are
## what let the reels read through.
class CabinetArt:
	extends Control

	var cabinet: SlotCabinet
	var behind := false

	func _draw() -> void:
		if cabinet == null:
			return
		if behind:
			cabinet.draw_chassis(self)
		else:
			cabinet.draw_cabinet(self)


func setup(cabinet_mode: Mode, content: Control, drawer_content: Control = null) -> void:
	mode = cabinet_mode
	_content = content
	_drawer_content = drawer_content
	show_drawer = drawer_content != null and mode != Mode.GRID
	# No lever (0.126, designer: it never did anything and was confusing). The
	# flag and `pull_lever()` stay so callers need no change; they just do nothing.
	show_lever = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_backdrop = CabinetArt.new()
	_backdrop.cabinet = self
	_backdrop.behind = true
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)

	_window_holder = Control.new()
	_window_holder.clip_contents = true
	_window_holder.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_window_holder)
	if _content != null:
		_reparent_into(_content, _window_holder)

	_drawer_holder = Control.new()
	_drawer_holder.clip_contents = true
	_drawer_holder.mouse_filter = Control.MOUSE_FILTER_PASS
	_drawer_holder.visible = show_drawer
	add_child(_drawer_holder)
	if show_drawer and _drawer_content != null:
		_reparent_into(_drawer_content, _drawer_holder)

	_art = CabinetArt.new()
	_art.cabinet = self
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_art)

	_marquee_label = Label.new()
	_marquee_label.text = marquee_text
	_marquee_label.theme_type_variation = &"SubtitleLabel"
	_marquee_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_marquee_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# The size is set from the plaque's real width in _relayout.
	_marquee_label.add_theme_color_override("font_color", NeonPalette.current().money)
	_marquee_label.add_theme_color_override("font_outline_color", NeonPalette.alpha(NeonPalette.current().money, 0.35))
	_marquee_label.add_theme_constant_override("outline_size", 6)
	_marquee_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marquee_label.visible = marquee_text != ""
	add_child(_marquee_label)

	_relayout()


static func _reparent_into(node: Control, holder: Control) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	holder.add_child(node)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_relayout()


## Re-measures the contents and re-hugs them. Called after the reel count
## changes (a bought reel makes the window wider, or shrinks the reels inside
## it) — a plain Control gets no sort-children notification to hang this on.
func refresh_layout() -> void:
	_relayout()


func _marquee_height() -> float:
	return MARQUEE_HEIGHT * art_scale


func _window_frame() -> Vector2:
	return WINDOW_FRAME * art_scale


func _drawer_frame() -> Vector2:
	return DRAWER_FRAME * art_scale


func _lever_width() -> float:
	return (LEVER_WIDTH * art_scale) if show_lever else 0.0


## The cabinet hugs whatever it holds: the window band is its content plus a
## frame, the drawer band its drawer content plus a lip, the lever rides
## outside the body on the right.
func _relayout() -> void:
	if _window_holder == null:
		return
	var content_size := Vector2.ZERO
	if _content != null:
		content_size = _content.get_combined_minimum_size()
	var drawer_size := Vector2.ZERO
	if show_drawer and _drawer_content != null:
		drawer_size = _drawer_content.get_combined_minimum_size()

	var frame := _window_frame()
	var lip := _drawer_frame()
	var body_width: float = maxf(content_size.x + frame.x * 2.0,
		drawer_size.x + lip.x * 2.0)
	var window_height := content_size.y + frame.y * 2.0
	var drawer_height := (drawer_size.y + lip.y * 2.0) if show_drawer else 0.0
	var marquee := _marquee_height()

	custom_minimum_size = Vector2(body_width + _lever_width(),
		marquee + window_height + drawer_height)

	_window_holder.position = Vector2((body_width - content_size.x) * 0.5, marquee + frame.y)
	_window_holder.size = content_size
	if _content != null:
		_content.position = Vector2.ZERO
		_content.size = content_size

	if show_drawer:
		_drawer_holder.position = Vector2((body_width - drawer_size.x) * 0.5,
			marquee + window_height + lip.y)
		_drawer_holder.size = drawer_size
		if _drawer_content != null:
			_drawer_content.position = Vector2.ZERO
			_drawer_content.size = drawer_size

	if _marquee_label != null:
		# The casino's name fills the marquee's plaque — the flat middle third
		# between the bulb clusters — at whatever size actually fits it.
		var inset := body_width * 0.12
		var plaque := maxf(10.0, body_width - inset * 2.0)
		_marquee_label.position = Vector2(inset, marquee * 0.16)
		_marquee_label.size = Vector2(plaque, marquee * 0.68)
		_marquee_label.add_theme_font_size_override("font_size",
			clampi(int(plaque / maxf(1.0, float(marquee_text.length())) * 1.45), 8, 24))
	if _art != null:
		_art.queue_redraw()
	if _backdrop != null:
		_backdrop.queue_redraw()



## The chase never stops while the machine is on screen — a dark slot machine
## in a casino is a broken one.
func _process(delta: float) -> void:
	if _art == null or not is_visible_in_tree():
		return
	_excited = maxf(0.0, _excited - delta)
	_phase += delta * BULB_SPEED * (1.0 + 2.0 * clampf(_excited, 0.0, 1.0))
	_art.queue_redraw()


## A win: the chase runs hot and the rails flare for a beat.
func celebrate(strength: float = 1.0) -> void:
	_excited = maxf(_excited, strength)


## The lever swings down and springs back, the way a spin is actually started.
## Purely cosmetic — the spin itself is already under way when this is called.
func pull_lever() -> void:
	if not show_lever:
		return
	var tween := create_tween()
	tween.tween_method(_set_lever_angle, 0.0, 0.85, 0.12) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_method(_set_lever_angle, 0.85, 0.0, 0.42) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _set_lever_angle(value: float) -> void:
	_lever_angle = value
	if _art != null:
		_art.queue_redraw()


## Where the reels sit, in global coordinates.
func window_rect_global() -> Rect2:
	if _window_holder == null:
		return Rect2(global_position, size)
	return Rect2(_window_holder.global_position, _window_holder.size)


## Where a paid-out chip should land: in the drawer, the way the doc describes
## chips "falling into" it.
func drawer_centre_global() -> Vector2:
	if show_drawer and _drawer_holder != null and _drawer_holder.size != Vector2.ZERO:
		return _drawer_holder.global_position + _drawer_holder.size * 0.5
	return window_rect_global().get_center()


## The Go Again wobble: the whole machine rocks, not just the reels.
func shake() -> void:
	var origin := position
	pivot_offset = size * 0.5
	var tween := create_tween()
	tween.tween_property(self, "position", origin + Vector2(-6, 0), 0.05)
	tween.tween_property(self, "position", origin + Vector2(6, 0), 0.06)
	tween.tween_property(self, "position", origin + Vector2(-4, 0), 0.06)
	tween.tween_property(self, "position", origin, 0.07) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Behind everything: the body the three bands are bolted to. Drawn under the
## reels and the chip tray, so their own art still reads normally — this only
## fills the transparent padding around and between the generated bands, which
## is what used to make them look like three loose pictures (patch 0.113).
func draw_chassis(canvas: CanvasItem) -> void:
	var body_width := maxf(0.0, size.x - _lever_width())
	if body_width <= 0.0 or _window_holder == null:
		return
	var slab := StyleBoxFlat.new()
	slab.bg_color = NeonPalette.current().glass_deep
	slab.set_corner_radius_all(int(14.0 * art_scale))
	slab.set_border_width_all(int(maxf(2.0, 3.0 * art_scale)))
	slab.border_color = NeonPalette.current().tube
	# A neon tube round the machine (0.126): the border IS the light, the shadow its glow.
	slab.shadow_color = NeonPalette.alpha(NeonPalette.current().tube, 0.5)
	slab.shadow_size = int(18.0 * art_scale)
	canvas.draw_style_box(slab, Rect2(0, 0, body_width, size.y))

	# A dark well behind the REEL window only, so the reels read against it.
	# The drawer deliberately gets none (patch 0.114, designer's note: "remove
	# the brown square area, leaving the wooden plank already in the slot
	# machine") — the chips lie straight on the chassis's own maroon wood,
	# which is the same wood the drawer frame is painted in. A well there, dark
	# or brown, only hides the plank the machine already has.
	var recess := StyleBoxFlat.new()
	recess.bg_color = CHASSIS_RECESS
	recess.set_corner_radius_all(int(6.0 * art_scale))
	canvas.draw_style_box(recess, Rect2(
		_window_holder.position - Vector2(4, 4) * art_scale,
		_window_holder.size + Vector2(8, 8) * art_scale))


func draw_cabinet(canvas: CanvasItem) -> void:
	var body_width := maxf(0.0, size.x - _lever_width())
	if body_width <= 0.0 or _window_holder == null:
		return
	var frame := _window_frame()
	var lip := _drawer_frame()
	var marquee := _marquee_height()
	var window_band := Rect2(
		_window_holder.position - frame, _window_holder.size + frame * 2.0)
	window_band.position.x = 0.0
	window_band.size.x = body_width

	var p := NeonPalette.current()
	var tube: Color = p.tube
	var gold: Color = p.money
	var glass_deep: Color = p.glass_deep

	# Neon cabinet (0.126, from the designer's mock): no generated gold bands any
	# more. A glass marquee plate with the casino's name in gold, a gold-framed
	# window the reels show through, and a tube-edged drawer for the chips.
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(glass_deep.r, glass_deep.g, glass_deep.b, 0.97)
	plate.border_color = tube
	plate.set_border_width_all(int(maxf(2.0, 3.0 * art_scale)))
	plate.border_width_bottom = 0
	plate.corner_radius_top_left = int(14.0 * art_scale)
	plate.corner_radius_top_right = int(14.0 * art_scale)
	plate.shadow_color = NeonPalette.alpha(tube, 0.5)
	plate.shadow_size = int(10.0 * art_scale)
	canvas.draw_style_box(plate, Rect2(0, 0, body_width, marquee))

	var window_frame := StyleBoxFlat.new()
	window_frame.draw_center = false
	window_frame.border_color = gold
	window_frame.set_border_width_all(int(maxf(2.0, 3.0 * art_scale)))
	window_frame.set_corner_radius_all(int(10.0 * art_scale))
	window_frame.shadow_color = NeonPalette.alpha(gold, 0.45)
	window_frame.shadow_size = int(12.0 * art_scale)
	var window_rect := Rect2(_window_holder.position - frame * 0.55,
		_window_holder.size + frame * 1.1)
	canvas.draw_style_box(window_frame, window_rect)

	if show_drawer and _drawer_holder != null and _drawer_holder.visible:
		var drawer_frame := StyleBoxFlat.new()
		drawer_frame.draw_center = false
		drawer_frame.border_color = tube
		drawer_frame.set_border_width_all(int(maxf(2.0, 2.0 * art_scale)))
		drawer_frame.set_corner_radius_all(int(10.0 * art_scale))
		drawer_frame.shadow_color = NeonPalette.alpha(tube, 0.4)
		drawer_frame.shadow_size = int(8.0 * art_scale)
		canvas.draw_style_box(drawer_frame, Rect2(
			_drawer_holder.position - lip * 0.55, _drawer_holder.size + lip * 1.1))

	var rail := RAIL_WIDTH * art_scale
	var rail_top := marquee * 0.55

	_draw_marquee_bulbs(canvas, body_width, marquee)


## The chase: bulbs around the machine's outline, lit in a running wave. The
## marquee art has its own painted bulb clusters; these are the live ones.
func _draw_bulbs(canvas: CanvasItem, body_width: float, rail: float,
		rail_top: float) -> void:
	var spacing := BULB_SPACING * art_scale
	if spacing <= 0.0:
		return
	var inset := BULB_INSET * art_scale
	var points: Array[Vector2] = []
	var top := maxf(inset, marquee_top_inset())
	var span := body_width - inset * 2.0
	var across := int(maxf(1.0, span / spacing))
	for i in across + 1:
		points.append(Vector2(inset + span * float(i) / float(across), top))
	var first := rail_top + inset
	var last := custom_minimum_size.y - inset
	var down := int(maxf(1.0, (last - first) / spacing))
	for i in down + 1:
		var y := first + (last - first) * float(i) / float(down)
		points.append(Vector2(inset, y))
		points.append(Vector2(body_width - inset, y))
	var glow := clampf(_excited, 0.0, 1.0)
	for i in points.size():
		# A travelling wave rather than a blink: every bulb is somewhere on it.
		var wave := 0.5 + 0.5 * sin(_phase - float(i) * 0.7)
		var tube: Color = NeonPalette.current().tube
		var lit: Color = tube.darkened(0.55).lerp(NeonPalette.current().tube_hi, wave * (0.75 + 0.25 * glow))
		if wave > 0.80 or glow > 0.05:
			canvas.draw_circle(points[i], BULB_RADIUS * art_scale * 1.9,
				Color(lit.r, lit.g, lit.b, 0.26 * (wave - 0.6 + glow)))
		canvas.draw_circle(points[i], BULB_RADIUS * art_scale, lit)


## The marquee's lamps, as in the mock: a short row either side of the name,
## blinking in alternate steps, quicker and hotter while the machine celebrates.
func _draw_marquee_bulbs(canvas: CanvasItem, body_width: float, marquee: float) -> void:
	if _marquee_label == null:
		return
	var p := NeonPalette.current()
	var font := _marquee_label.get_theme_font("font")
	var font_size := _marquee_label.get_theme_font_size("font_size")
	var text_width := font.get_string_size(marquee_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var centre := body_width * 0.5
	var gap := 14.0 * art_scale
	var spacing := 16.0 * art_scale
	var y := marquee * 0.5
	var edge := 18.0 * art_scale
	var step := int(_phase * 0.5)
	for side in [-1, 1]:
		var x: float = centre + side * (text_width * 0.5 + gap)
		var index := 0
		while (x - edge >= 0.0 if side < 0 else x + edge <= body_width):
			var lit := (index + step) % 2 == 0 or _excited > 0.05
			var tube: Color = p.tube
			var bulb: Color = (p.tube_hi if lit else tube.darkened(0.55))
			if lit:
				canvas.draw_circle(Vector2(x, y), 6.5 * art_scale, Color(tube.r, tube.g, tube.b, 0.32))
				canvas.draw_circle(Vector2(x, y), 2.0 * art_scale, Color.WHITE)
			canvas.draw_circle(Vector2(x, y), 3.6 * art_scale, Color(bulb.r, bulb.g, bulb.b, 0.9 if lit else 0.7))
			if lit:
				canvas.draw_circle(Vector2(x, y), 1.8 * art_scale, Color.WHITE)
			x += side * spacing
			index += 1


## Where the bulb row across the top sits: just inside the marquee's crown.
func marquee_top_inset() -> float:
	return _marquee_height() * 0.30


## The lever, mounted on the right rail and swung by `pull_lever()`.
func _draw_lever(canvas: CanvasItem, body_width: float, window_band: Rect2) -> void:
	var lever_height := minf(window_band.size.y * 0.72, 120.0 * art_scale)
	var pivot := Vector2(body_width + 14.0 * art_scale,
		window_band.end.y - 18.0 * art_scale)
	var tube: Color = NeonPalette.current().tube
	var bracket := StyleBoxFlat.new()
	bracket.bg_color = tube
	bracket.set_corner_radius_all(int(5.0 * art_scale))
	canvas.draw_style_box(bracket, Rect2(
		body_width - 6.0 * art_scale, pivot.y - 9.0 * art_scale,
		maxf(8.0, pivot.x - body_width + 6.0 * art_scale), 18.0 * art_scale))
	canvas.draw_set_transform(pivot, _lever_angle, Vector2.ONE)
	# A steel stem and a lit knob, the mock's lever.
	var stem := StyleBoxFlat.new()
	stem.bg_color = Color(0.84, 0.87, 0.95)
	stem.set_corner_radius_all(int(4.0 * art_scale))
	canvas.draw_style_box(stem, Rect2(-4.0 * art_scale, -lever_height, 8.0 * art_scale, lever_height))
	var knob := Vector2(0.0, -lever_height)
	canvas.draw_circle(knob, 21.0 * art_scale, NeonPalette.alpha(tube, 0.30))
	canvas.draw_circle(knob, 15.0 * art_scale, tube)
	canvas.draw_circle(knob + Vector2(-4, -5) * art_scale, 5.0 * art_scale, NeonPalette.current().tube_hi)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	canvas.draw_circle(pivot, 7.0 * art_scale, NeonPalette.current().tube_hi)


## Hand-rolled nine-slice. `source_box` is the drawn part of the art inside its
## padded image; `src_margin` is the distance from that box's edge to the hole;
## `dst_margin` is the frame thickness we want on screen. Corners are drawn at
## `dst_margin`, so the stretched middle lands exactly on the content.
static func _draw_nine(canvas: CanvasItem, texture: Texture2D, source_box: Rect2,
		rect: Rect2, src_margin: Vector2, dst_margin: Vector2) -> void:
	if texture == null or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	# Never let the two margins overlap on a band shorter than they are.
	var margin := Vector2(
		minf(dst_margin.x, rect.size.x * 0.48), minf(dst_margin.y, rect.size.y * 0.48))
	var src_x := [source_box.position.x, source_box.position.x + src_margin.x,
		source_box.end.x - src_margin.x, source_box.end.x]
	var src_y := [source_box.position.y, source_box.position.y + src_margin.y,
		source_box.end.y - src_margin.y, source_box.end.y]
	var dst_x := [rect.position.x, rect.position.x + margin.x,
		rect.end.x - margin.x, rect.end.x]
	var dst_y := [rect.position.y, rect.position.y + margin.y,
		rect.end.y - margin.y, rect.end.y]
	for row in 3:
		for column in 3:
			var src := Rect2(Vector2(src_x[column], src_y[row]),
				Vector2(src_x[column + 1] - src_x[column], src_y[row + 1] - src_y[row]))
			var dst := Rect2(Vector2(dst_x[column], dst_y[row]),
				Vector2(dst_x[column + 1] - dst_x[column], dst_y[row + 1] - dst_y[row]))
			if src.size.x <= 0.0 or src.size.y <= 0.0 or dst.size.x <= 0.0 or dst.size.y <= 0.0:
				continue
			canvas.draw_texture_rect_region(texture, dst, src)
