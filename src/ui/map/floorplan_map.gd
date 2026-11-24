class_name FloorplanMap
extends Control
## The Act I Choice screen as a top-down plan of the casino (build 1.29, from the
## designer's floorplan mock). A promenade runs from the Grand Lobby to Mr.
## Moneybags' penthouse; every stop from 2 to 9 is a pair of rooms off it, and
## the player walks into one. The doors on offer glow and pulse, the route walked
## is a lit line with a tick in the room taken, the other room of a pair is dimmed
## shut, and the stops ahead show their rooms faintly.
##
## The painting is neutral (sixteen different casino rooms); the TYPE of each room
## is drawn over it, so the same plan serves all six authored paths. Rules are the
## game's, not this screen's: it only asks `Game.choose_encounter` which room.
##
## Everything is laid out on the painting's own 1920 x 1072 stage
## (`FloorplanLayout`) scaled to fit the window. The old ribbon screen is still in
## `map_screen.gd`: set `MapScreen.USE_FLOORPLAN` to false to bring it back (git
## tag `act1-map-ribbon` is the version before this one).

const PAINTING := "res://assets/map/act1_floorplan.jpg"
const ICON := "res://assets/icons/encounter_%s.png"
const ACE_PORTRAIT := "res://assets/characters/ace_portrait.png"

enum State { DONE, CLOSED, HERE, FUTURE }

const TYPE_NAME := {
	&"combat": "Combat", &"story": "Story", &"treasure": "Treasure", &"elite": "Elite",
	&"casino": "Casino", &"shop": "Shop", &"rest": "Rest", &"boss": "Mr. Moneybags",
}
const TYPE_DESC := {
	&"combat": "The house always sends someone.",
	&"elite": "A mini-boss with its own tricks. Beat it for a relic.",
	&"story": "Something is happening here...",
	&"rest": "A quiet corner to catch your breath.",
	&"treasure": "Something glitters in the dark.",
	&"casino": "Try your luck at the tables.",
	&"shop": "Spend your winnings.",
	&"boss": "Time to settle the score.",
}
const TYPE_COLOUR := {
	&"combat": Color("#5aa0ff"), &"story": Color("#b48cff"), &"treasure": Color("#ffb84a"),
	&"elite": Color("#ff6b5e"), &"casino": Color("#ffd76a"), &"shop": Color("#ffd76a"),
	&"rest": Color("#5fe0a0"), &"boss": Color("#ffe08a"),
}
const LEGEND := [&"combat", &"story", &"treasure", &"elite", &"casino", &"shop", &"rest", &"boss"]
## The painted rooms above and below the promenade, by column (stops 2 to 9), for
## the hover card. They are flavour; nothing in the rules depends on them.
const ROOM_ABOVE := ["Poker Room", "Roulette Salon", "Slot Hall", "Cashier Cage",
	"Cocktail Bar", "VIP Lounge", "Blackjack Pit", "Vault"]
const ROOM_BELOW := ["Poker Annex", "Craps Room", "Chip Counting Room", "Security Room",
	"Card Room", "Champagne Cellar", "Private Cinema", "Jackpot Room"]

const TOKEN_RADIUS := 32.0
const DASH := 16.0
const GAP := 12.0

var _stage: Control
var _overlay: Control
var _rooms: Array[Dictionary] = []
var _buttons: Array[Button] = []
var _hover := -1
var _stop := 1
var _phase := 0.0
var _icons: Dictionary = {}
var _tip_title: Label
var _tip_body: Label
var _portrait: Texture2D


## `history` is the types already visited, `path` the run's authored path, and
## `options` the pair on offer now (from `Game.map_options()`). The abilities are
## one click away in the header (the Layout button), so the map carries no button
## of its own for them (designer, 1.29).
func setup(history: Array[StringName], path: Dictionary, options: Array[Dictionary]) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_stop = history.size() + 1
	_build_rooms(history, path, options)

	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)

	_stage = Control.new()
	_stage.size = FloorplanLayout.STAGE
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)

	var painting := TextureRect.new()
	if ResourceLoader.exists(PAINTING):
		painting.texture = load(PAINTING)
	painting.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	painting.stretch_mode = TextureRect.STRETCH_SCALE
	painting.size = FloorplanLayout.STAGE
	painting.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(painting)

	_overlay = Control.new()
	_overlay.size = FloorplanLayout.STAGE
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_paint)
	_stage.add_child(_overlay)

	for room_index in _rooms.size():
		_stage.add_child(_room_button(room_index))

	_build_title()
	_build_tip()
	if ResourceLoader.exists(ACE_PORTRAIT):
		_portrait = load(ACE_PORTRAIT)
	get_viewport().size_changed.connect(_fit)
	_fit()
	_show_default_tip()
	# Review hook: CB_DEBUG_MAP_PICK=N walks through the Nth open door after a moment,
	# as a click would (the same path, so a real run can be driven without a mouse).
	var pick := OS.get_environment("CB_DEBUG_MAP_PICK")
	if pick != "":
		get_tree().create_timer(1.5).timeout.connect(func() -> void:
			var open: Array[int] = []
			for i in _rooms.size():
				if _rooms[i].state == State.HERE:
					open.append(i)
			if int(pick) < open.size():
				_take(open[int(pick)]))


func _process(delta: float) -> void:
	_phase = fposmod(_phase + delta, 1000.0)
	if _overlay != null:
		_overlay.queue_redraw()


# ------------------------------------------------------------------ the data

## Every room on the plan, from the lobby to the penthouse. A visited stop shows
## the room taken and the one that closed; the current stop shows what is on
## offer; stops ahead show the path's pair.
func _build_rooms(history: Array[StringName], path: Dictionary, options: Array[Dictionary]) -> void:
	_rooms.clear()
	_rooms.append(_room(1, 0, &"combat", State.DONE if _stop > 1 else State.HERE, _first_option(options, 1)))
	for stop in range(FloorplanLayout.PAIR_FIRST, FloorplanLayout.PAIR_LAST + 1):
		var pair: Array[StringName] = MapGenerator.pair_at(path, stop)
		if stop < _stop:
			var taken: StringName = history[stop - 1] if stop - 1 < history.size() else &"combat"
			var types: Array = pair.duplicate()
			if types.is_empty():
				types = [taken]
			for slot in types.size():
				var type := StringName(str(types[slot]))
				_rooms.append(_room(stop, slot, type, State.DONE if slot == FloorplanLayout.slot_of(types, taken) else State.CLOSED))
		elif stop == _stop:
			for slot in options.size():
				_rooms.append(_room(stop, slot, StringName(str(options[slot].type)), State.HERE, options[slot]))
		else:
			for slot in pair.size():
				_rooms.append(_room(stop, slot, pair[slot], State.FUTURE))
	if _stop >= FloorplanLayout.LAST_STOP:
		_rooms.append(_room(10, 0, &"boss", State.HERE, _first_option(options, 10)))
	else:
		_rooms.append(_room(10, 0, &"boss", State.FUTURE))


func _room(stop: int, slot: int, type: StringName, state: int, option := {}) -> Dictionary:
	return {"stop": stop, "slot": slot, "type": type, "state": state, "option": option}


func _first_option(options: Array[Dictionary], stop: int) -> Dictionary:
	if stop == _stop and not options.is_empty():
		return options[0]
	return {}


func _room_name(room: Dictionary) -> String:
	var stop: int = room.stop
	if stop <= 1:
		return "Grand Lobby"
	if stop >= 10:
		return "Penthouse Office"
	var names: Array = ROOM_ABOVE if int(room.slot) == 0 else ROOM_BELOW
	return str(names[stop - FloorplanLayout.PAIR_FIRST])


# ------------------------------------------------------------------ building

func _room_button(index: int) -> Button:
	var room := _rooms[index]
	var rect := FloorplanLayout.room_rect(room.stop, room.slot)
	var button := Button.new()
	button.position = rect.position
	button.size = rect.size
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, empty)
	button.mouse_entered.connect(func() -> void: _set_hover(index))
	button.mouse_exited.connect(func() -> void: _set_hover(-1))
	button.focus_entered.connect(func() -> void: _set_hover(index))
	button.focus_exited.connect(func() -> void: _set_hover(-1))
	if room.state == State.HERE:
		button.pressed.connect(func() -> void: _take(index))
	else:
		button.mouse_default_cursor_shape = Control.CURSOR_ARROW
		button.set_meta("silent", true)     # a closed door makes no click
	_buttons.append(button)
	return button


func _build_title() -> void:
	var title := Label.new()
	title.text = "Choose\nYour Path"
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_size_override("font_size", 42)
	title.position = Vector2(62, 116)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(title)

	# The same face as the timer and the gold counters in the header (the
	# SubtitleLabel variation), not the plain body font (1.29).
	var sub := Label.new()
	sub.text = "ENCOUNTER %d OF 10" % _stop
	sub.theme_type_variation = &"SubtitleLabel"
	sub.add_theme_font_size_override("font_size", 16)
	sub.position = Vector2(66, 236)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(sub)


func _build_tip() -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"TooltipPanel"
	panel.position = Vector2(1210, 950)
	panel.custom_minimum_size = Vector2(640, 92)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	_tip_title = Label.new()
	_tip_title.theme_type_variation = &"SubtitleLabel"
	_tip_title.add_theme_font_size_override("font_size", 24)
	_tip_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_tip_title)
	_tip_body = Label.new()
	_tip_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_body.custom_minimum_size = Vector2(600, 0)
	_tip_body.add_theme_font_size_override("font_size", 17)
	_tip_body.add_theme_color_override("font_color", NeonPalette.current().dim)
	_tip_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_tip_body)
	_stage.add_child(panel)


## The stage keeps its shape, centred, whatever the window.
func _fit() -> void:
	if _stage == null:
		return
	var view := get_viewport().get_visible_rect().size
	var factor := minf(view.x / FloorplanLayout.STAGE.x, view.y / FloorplanLayout.STAGE.y)
	_stage.scale = Vector2(factor, factor)
	_stage.position = (view - FloorplanLayout.STAGE * factor) * 0.5


# ------------------------------------------------------------------ input

func _take(index: int) -> void:
	var option: Dictionary = _rooms[index].option
	if option.is_empty():
		return
	Audio.play_sfx(&"ui_confirm")
	Game.choose_encounter(option)


func _set_hover(index: int) -> void:
	_hover = index
	if index < 0:
		_show_default_tip()
		return
	var room := _rooms[index]
	var type: StringName = room.type
	var kind := String(TYPE_NAME.get(type, str(type)))
	var where := "%s, stop %d" % [_room_name(room), room.stop]
	match room.state:
		State.DONE:
			_tip_title.text = "%s: %s" % [_room_name(room), kind]
			_tip_body.text = "You came through here."
		State.CLOSED:
			_tip_title.text = "%s: %s" % [_room_name(room), kind]
			_tip_body.text = "The door closed behind you. You took the other room."
		State.FUTURE:
			_tip_title.text = "%s: %s" % [_room_name(room), kind]
			_tip_body.text = "Stop %d. %s" % [room.stop, TYPE_DESC.get(type, "")]
		_:
			_tip_title.text = "%s: %s" % [where, kind]
			_tip_body.text = str(TYPE_DESC.get(type, ""))
	_tip_title.add_theme_color_override("font_color", TYPE_COLOUR.get(type, Color.WHITE))


func _show_default_tip() -> void:
	_tip_title.remove_theme_color_override("font_color")
	if _stop >= FloorplanLayout.LAST_STOP:
		_tip_title.text = "The penthouse"
		_tip_body.text = "Every path ends here. Mr. Moneybags is waiting."
		return
	var names: Array[String] = []
	for room in _rooms:
		if room.state == State.HERE:
			names.append(String(TYPE_NAME.get(room.type, str(room.type))))
	_tip_title.text = "Stop %d: choose a door" % _stop
	_tip_body.text = "%s. Click a lit room. The other door closes behind you." % " or ".join(names)


# ------------------------------------------------------------------ drawing

func _paint() -> void:
	var palette := NeonPalette.current()
	var here_x := FloorplanLayout.column_x(_stop)
	var hall_y := FloorplanLayout.HALL_Y
	var lit: Color = palette.tube_hi

	# The promenade: lit as far as Ace has walked, dotted beyond.
	_overlay.draw_line(Vector2(FloorplanLayout.HALL_START_X, hall_y), Vector2(here_x, hall_y), lit, 9.0, true)
	_dotted(Vector2(here_x, hall_y), Vector2(FloorplanLayout.HALL_END_X, hall_y), Color(0.6, 0.47, 0.75, 0.55), 5.0)

	# Rooms: tint, border, the way in.
	for index in _rooms.size():
		_paint_room(index, palette)
	for index in _rooms.size():
		_paint_token(index, palette)

	_paint_ace(here_x, hall_y)
	_paint_legend(palette)


func _paint_room(index: int, palette: Dictionary) -> void:
	var room := _rooms[index]
	var stop: int = room.stop
	if not FloorplanLayout.is_pair_stop(stop):
		return
	var state: int = room.state
	var type: StringName = room.type
	var colour: Color = TYPE_COLOUR.get(type, Color.WHITE)
	var rect := FloorplanLayout.room_rect(stop, room.slot)
	var door := FloorplanLayout.door_position(stop, room.slot)
	var hall := Vector2(door.x, FloorplanLayout.HALL_Y)
	var focused := _hover == index or _buttons[index].has_focus()
	match state:
		State.CLOSED:
			_overlay.draw_rect(rect, Color(0.02, 0.01, 0.04, 0.68))
			_overlay.draw_rect(rect, Color(0.17, 0.11, 0.23), false, 3.0)
		State.HERE:
			_overlay.draw_rect(rect, Color(colour.r, colour.g, colour.b, 0.26 if focused else 0.2))
			var glow := 0.75 + 0.25 * sin(_phase * 3.4)
			_overlay.draw_rect(rect, Color(1.0, 0.84, 0.42, glow), false, 6.0)
			_dashed(door, hall, Color(1.0, 0.84, 0.42), 7.0, _phase * 28.0)
		State.DONE:
			_overlay.draw_rect(rect, Color(colour.r, colour.g, colour.b, 0.22))
			_overlay.draw_rect(rect, palette.tube_hi, false, 4.0)
			_overlay.draw_line(door, hall, palette.tube_hi, 9.0, true)
		_:
			_overlay.draw_rect(rect, Color(colour.r, colour.g, colour.b, 0.15))
			_overlay.draw_rect(rect, Color(colour.r, colour.g, colour.b, 0.55), false, 3.0)
	if focused and state != State.HERE:
		_overlay.draw_rect(rect.grow(2.0), Color(1, 1, 1, 0.5), false, 2.0)


func _paint_token(index: int, palette: Dictionary) -> void:
	var room := _rooms[index]
	var stop: int = room.stop
	var state: int = room.state
	var type: StringName = room.type
	var colour: Color = TYPE_COLOUR.get(type, Color.WHITE)
	var centre := FloorplanLayout.token_position(stop, room.slot)
	var closed := state == State.CLOSED
	var rim: Color = Color(0.3, 0.24, 0.38) if closed else (palette.tube_hi if state == State.DONE else colour)
	if state == State.HERE:
		var pulse := 0.5 + 0.5 * sin(_phase * 4.2)
		_overlay.draw_arc(centre, TOKEN_RADIUS + 12.0 + 6.0 * pulse, 0.0, TAU, 40,
			Color(1.0, 0.84, 0.42, 0.85 - 0.5 * pulse), 4.0, true)
	_overlay.draw_circle(centre, TOKEN_RADIUS + 4.0, Color(0.03, 0.01, 0.05, 0.85))
	_overlay.draw_circle(centre, TOKEN_RADIUS, Color(0.09, 0.04, 0.14))
	_overlay.draw_arc(centre, TOKEN_RADIUS, 0.0, TAU, 40, rim, 5.0, true)
	var icon := _icon(type)
	var tint := Color(0.45, 0.4, 0.5, 0.7) if closed else Color.WHITE
	if icon != null:
		var side := TOKEN_RADIUS * 1.5
		_overlay.draw_texture_rect(icon, Rect2(centre - Vector2(side, side) * 0.5, Vector2(side, side)), false, tint)
	if state == State.DONE:
		# A tick on the room taken.
		var badge := centre + Vector2(TOKEN_RADIUS * 0.75, -TOKEN_RADIUS * 0.75)
		_overlay.draw_circle(badge, 13.0, Color(0.05, 0.02, 0.09))
		_overlay.draw_polyline(PackedVector2Array([badge + Vector2(-6, 0), badge + Vector2(-1.5, 5), badge + Vector2(7, -5)]),
			palette.tube_hi, 3.5, true)
	# The name under (or over) the marker, outlined so it reads on the painting.
	var font := get_theme_font(&"font", &"SubtitleLabel")
	var label := String(TYPE_NAME.get(type, str(type)))
	var above := stop >= 2 and stop <= 9 and int(room.slot) == 0
	var label_y := centre.y - TOKEN_RADIUS - 14.0 if above else centre.y + TOKEN_RADIUS + 26.0
	var label_colour := Color(0.48, 0.42, 0.55) if closed else Color(0.96, 0.93, 0.99)
	var width := 190.0
	_overlay.draw_string_outline(font, Vector2(centre.x - width * 0.5, label_y), label,
		HORIZONTAL_ALIGNMENT_CENTER, width, 19, 6, Color(0.02, 0.01, 0.04))
	_overlay.draw_string(font, Vector2(centre.x - width * 0.5, label_y), label,
		HORIZONTAL_ALIGNMENT_CENTER, width, 19, label_colour)


func _paint_ace(x: float, y: float) -> void:
	var centre := Vector2(x, y)
	_overlay.draw_circle(centre, 38.0, Color(0.02, 0.01, 0.04, 0.85))
	if _portrait != null:
		var points := PackedVector2Array()
		var uvs := PackedVector2Array()
		for i in 40:
			var angle := TAU * float(i) / 40.0
			var dir := Vector2(cos(angle), sin(angle))
			points.append(centre + dir * 34.0)
			uvs.append(Vector2(0.5, 0.36) + dir * 0.36)
		_overlay.draw_colored_polygon(points, Color.WHITE, uvs, _portrait)
	_overlay.draw_arc(centre, 36.0, 0.0, TAU, 40, NeonPalette.current().hero, 4.0, true)


func _paint_legend(palette: Dictionary) -> void:
	var font := get_theme_font(&"font", &"SubtitleLabel")
	var origin := Vector2(50, 978)
	_overlay.draw_rect(Rect2(origin, Vector2(1140, 48)), Color(0.04, 0.02, 0.07, 0.86))
	_overlay.draw_rect(Rect2(origin, Vector2(1140, 48)), Color(0.2, 0.13, 0.29), false, 1.0)
	var x := origin.x + 16.0
	for type: StringName in LEGEND:
		var icon := _icon(type)
		if icon != null:
			_overlay.draw_texture_rect(icon, Rect2(Vector2(x, origin.y + 8), Vector2(32, 32)), false)
		x += 38.0
		var name := String(TYPE_NAME.get(type, str(type)))
		_overlay.draw_string(font, Vector2(x, origin.y + 32), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 19,
			Color(0.91, 0.86, 0.95))
		x += font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x + 22.0


func _icon(type: StringName) -> Texture2D:
	if not _icons.has(type):
		var path := ICON % String(type)
		_icons[type] = load(path) if ResourceLoader.exists(path) else null
	return _icons[type]


## A moving dashed line: `phase` slides the dashes along it.
func _dashed(from: Vector2, to: Vector2, colour: Color, width: float, phase: float) -> void:
	var length := from.distance_to(to)
	if length <= 0.0:
		return
	var dir := (to - from) / length
	var step := DASH + GAP
	var start := -fposmod(phase, step)
	while start < length:
		var a := maxf(start, 0.0)
		var b := minf(start + DASH, length)
		if b > a:
			_overlay.draw_line(from + dir * a, from + dir * b, colour, width, true)
		start += step


func _dotted(from: Vector2, to: Vector2, colour: Color, width: float) -> void:
	var length := from.distance_to(to)
	if length <= 0.0:
		return
	var dir := (to - from) / length
	var at := 0.0
	while at < length:
		_overlay.draw_circle(from + dir * at, width * 0.5, colour)
		at += 14.0
