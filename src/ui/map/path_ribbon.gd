class_name PathRibbon
extends Control
## The road to Mr. Moneybags (doc "Choice", patch 0.116).
##
## Ten stops left to right. Everything behind the player is the encounter they
## actually took, drawn with that type's icon; everything ahead is a question
## mark, except #10, which is always the boss because it always is. At the
## current stop the road forks into the two offered encounters, and a marker
## hovers over where the player is standing.
##
## Drawn rather than built from child nodes: the fork, the dashes and the
## tokens all have to agree about one set of coordinates, and a Container
## would own those coordinates instead. Icons are looked up per type and the
## widget degrades to a drawn glyph plus a letter when a texture is missing,
## so it works before the art exists and improves when it lands.

const STOPS := 10
const TOKEN := 46.0
const FORK_SPREAD := 40.0
const MARKER_BOB := 5.0

const TYPE_LETTER := {
	&"combat": "C", &"elite": "E", &"story": "S", &"rest": "R",
	&"treasure": "T", &"casino": "$", &"shop": "B", &"boss": "M",
}
const TYPE_TINT := {
	&"combat": Color(0.78, 0.31, 0.28),
	&"elite": Color(0.85, 0.42, 0.72),
	&"story": Color(0.45, 0.63, 0.86),
	&"rest": Color(0.42, 0.76, 0.55),
	&"treasure": Color(0.92, 0.78, 0.35),
	&"casino": Color(0.63, 0.51, 0.81),
	&"shop": Color(0.96, 0.79, 0.63),
	&"boss": Color(0.92, 0.32, 0.30),
}

const ROAD := Color(0.10, 0.06, 0.09, 0.85)
const ROAD_EDGE := Color(0.83, 0.69, 0.22, 0.55)
const DIM := Color(0.36, 0.33, 0.30)

## `history` is the types already visited, `options` the pair on offer now.
var history: Array[StringName] = []
var options: Array[StringName] = []

var _phase := 0.0
var _icons: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(0, 170)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_phase = fposmod(_phase + delta * 2.2, TAU)
	queue_redraw()


func show_path(visited: Array[StringName], offered: Array[StringName]) -> void:
	history = visited.duplicate()
	options = offered.duplicate()
	queue_redraw()


## Where stop `i` (0-based) sits. The row is inset by half a token so the
## first and last icons are not clipped by the widget's own edge.
func _x_of(i: int) -> float:
	var inset := TOKEN * 0.85
	var span := maxf(1.0, size.x - inset * 2.0)
	return inset + span * (float(i) / float(STOPS - 1))


func _mid_y() -> float:
	return size.y * 0.5 + 8.0


func _icon_for(type: StringName) -> Texture2D:
	if _icons.has(type):
		return _icons[type]
	var path := "res://assets/icons/encounter_%s.png" % String(type)
	var texture: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_icons[type] = texture
	return texture


func _draw() -> void:
	var here := history.size()          # 0-based index of the current stop
	var mid := _mid_y()

	# --- the road. Solid behind the player, dashed ahead of them, because a
	# road you have not walked yet is not a promise about what is on it.
	for i in STOPS - 1:
		var a := Vector2(_x_of(i), mid)
		var b := Vector2(_x_of(i + 1), mid)
		# Solid only up to the stop the player is standing on. The leg from
		# there to the fork is drawn by the fork itself, so stopping one short
		# is what keeps a stub of road from running through the split.
		if i < here - 1:
			draw_line(a, b, ROAD, 9.0)
			draw_line(a, b, ROAD_EDGE, 2.0)
		elif i >= here:
			_dashed(a, b, Color(DIM, 0.5), 4.0)

	# --- the fork at the current stop (doc: "a split in the road in the
	# current encounter number"). Two short branches out of the road.
	if here < STOPS and options.size() >= 2:
		var from := Vector2(_x_of(maxi(here - 1, 0)), mid)
		if here == 0:
			from = Vector2(_x_of(0) - TOKEN, mid)
		for slot in mini(options.size(), 2):
			var offset := -FORK_SPREAD if slot == 0 else FORK_SPREAD
			var to := Vector2(_x_of(here), mid + offset)
			draw_line(from, to, ROAD, 9.0)
			draw_line(from, to, ROAD_EDGE, 2.0)

	# --- the stops themselves
	for i in STOPS:
		var x := _x_of(i)
		if i < here:
			_token(Vector2(x, mid), history[i], 1.0, false)
		elif i == here and options.size() >= 2:
			for slot in mini(options.size(), 2):
				var offset := -FORK_SPREAD if slot == 0 else FORK_SPREAD
				_token(Vector2(x, mid + offset), options[slot], 1.12, true)
		elif i == STOPS - 1:
			_token(Vector2(x, mid), &"boss", 1.2, false)
		else:
			_unknown(Vector2(x, mid))

	# --- "an Icon that shows the player's latest location, hovering up and
	# down slightly". It sits over the last stop actually walked; before the
	# first choice there is nothing behind the player, so it waits at the fork.
	var marker_x := _x_of(maxi(here - 1, 0))
	var bob := sin(_phase) * MARKER_BOB
	_marker(Vector2(marker_x, mid - TOKEN * 0.95 + bob))

	# --- numbers under the road, so "Encounter 7 of 10" has somewhere to land
	var font := get_theme_default_font()
	if font == null:
		return
	for i in STOPS:
		var label := str(i + 1)
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var tint := Color(0.83, 0.69, 0.22, 0.9) if i == here else Color(DIM, 0.85)
		# Clear of the lower fork token, which reaches TOKEN*1.45 down.
		draw_string(font, Vector2(_x_of(i) - width * 0.5, mid + TOKEN * 1.9),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, tint)


func _dashed(a: Vector2, b: Vector2, tint: Color, width: float) -> void:
	var span := a.distance_to(b)
	var step := 13.0
	var dir := (b - a).normalized()
	var travelled := 0.0
	while travelled < span:
		var run: float = minf(7.0, span - travelled)
		draw_line(a + dir * travelled, a + dir * (travelled + run), tint, width)
		travelled += step


func _token(at: Vector2, type: StringName, scale: float, live: bool) -> void:
	var radius := TOKEN * 0.5 * scale
	var tint: Color = TYPE_TINT.get(type, Color(0.6, 0.6, 0.6))
	if not live:
		tint = tint.lerp(Color(0.22, 0.18, 0.2), 0.45)
	draw_circle(at, radius + 3.0, Color(0.06, 0.04, 0.06, 0.9))
	draw_circle(at, radius, tint.darkened(0.55))
	# A live option gets the full gold rim; a walked one keeps a quiet edge.
	var rim := Color(1.0, 0.84, 0.35, 0.55 + 0.45 * (0.5 + 0.5 * sin(_phase))) \
		if live else Color(0.83, 0.69, 0.22, 0.35)
	draw_arc(at, radius, 0.0, TAU, 40, rim, 3.0 if live else 2.0)

	var texture := _icon_for(type)
	if texture != null:
		var box := radius * 1.35
		draw_texture_rect(texture,
			Rect2(at - Vector2(box, box) * 0.5, Vector2(box, box)),
			false, Color(1, 1, 1, 1.0 if live else 0.75))
		return
	var font := get_theme_default_font()
	if font == null:
		return
	var letter: String = TYPE_LETTER.get(type, "?")
	var s := int(radius * 1.1)
	var w := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x
	draw_string(font, at + Vector2(-w * 0.5, s * 0.36), letter,
		HORIZONTAL_ALIGNMENT_LEFT, -1, s, tint.lightened(0.45))


func _unknown(at: Vector2) -> void:
	var radius := TOKEN * 0.38
	draw_circle(at, radius, Color(0.10, 0.08, 0.10, 0.75))
	draw_arc(at, radius, 0.0, TAU, 32, Color(DIM, 0.6), 2.0)
	var font := get_theme_default_font()
	if font == null:
		return
	var s := int(radius * 1.25)
	var w := font.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, s).x
	draw_string(font, at + Vector2(-w * 0.5, s * 0.38), "?",
		HORIZONTAL_ALIGNMENT_LEFT, -1, s, Color(DIM, 0.95))


## Ace's medallion, the same portrait the header wears, so "you are here"
## reads as the player rather than as another map symbol.
func _marker(at: Vector2) -> void:
	var radius := 20.0
	var portrait := _icon_for(&"__ace")
	if portrait == null:
		portrait = load("res://assets/characters/ace_portrait.png") \
			if ResourceLoader.exists("res://assets/characters/ace_portrait.png") else null
		_icons[&"__ace"] = portrait
	draw_circle(at, radius + 2.5, Color(0.83, 0.69, 0.22, 0.95))
	draw_circle(at, radius, Color(0.12, 0.07, 0.10))
	if portrait != null:
		# The source is a full portrait, so squeezing all of it into 40 px
		# reads as a smudge. Crop a square around the head instead: the
		# upper-middle of the image, which is where a portrait keeps a face.
		var src := portrait.get_size()
		var side: float = minf(src.x, src.y) * 0.62
		var region := Rect2(Vector2((src.x - side) * 0.5, src.y * 0.04),
			Vector2(side, side))
		draw_texture_rect_region(portrait,
			Rect2(at - Vector2(radius, radius), Vector2(radius, radius) * 2.0),
			region)
		draw_arc(at, radius + 1.0, 0.0, TAU, 40, Color(0.83, 0.69, 0.22), 3.0)
	# A little spike under the medallion, pointing at the stop it marks.
	draw_colored_polygon([
		at + Vector2(-6, radius - 1), at + Vector2(6, radius - 1),
		at + Vector2(0, radius + 10)], Color(0.83, 0.69, 0.22, 0.95))
