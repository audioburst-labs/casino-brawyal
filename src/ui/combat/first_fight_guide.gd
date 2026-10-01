class_name FirstFightGuide
extends Control
## The first-fight guide (roadmap phase 0, patch 0.121). Four short cards,
## each pointing at the thing it talks about, shown once per machine on a
## player's first fight. The game keeps playing underneath: the guide never
## dims the screen or swallows input, so a player who already knows can just
## play through it. Steps advance on the matching action or on Next.
##
## Positioned from global rects each frame rather than anchors, for the
## documented reason: a fresh Control does not resolve anchor percentages
## against the real viewport in the frame it is created.

signal finished

const PANEL_WIDTH := 360.0
const RING_PAD := 10.0
const RING_COLOR := Color(1.0, 0.86, 0.45, 0.95)

## Each step: text, the event that advances it, and a callable returning the
## Control to point at (resolved late, because the screen builds its views
## after the guide is created).
var _steps: Array[Dictionary] = []
var _index := -1
var _target: Control = null
var _panel: PanelContainer
var _label: Label
var _next: Button
var _pulse := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 190

	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"TooltipPanel"
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_panel.visible = false
	add_child(_panel)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 14)
	_panel.add_child(pad)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	pad.add_child(column)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(PANEL_WIDTH - 28, 0)
	_label.add_theme_font_size_override("font_size", 17)
	column.add_child(_label)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)
	var skip := Button.new()
	skip.text = "Skip guide"
	skip.flat = true
	skip.pressed.connect(_finish)
	buttons.add_child(skip)
	_next = Button.new()
	_next.text = "Next"
	_next.pressed.connect(advance)
	buttons.add_child(_next)


## `steps`: [{text, on, target: Callable}] in order. `on` is the event name
## that completes the step on its own (&"" for Next only).
func begin(steps: Array[Dictionary]) -> void:
	_steps = steps
	_index = -1
	advance()


## Something happened in the fight. If this step or any later one was
## waiting for it, the guide jumps past that step: a player who starts
## dragging chips during the first card is not held back by Next.
func notice(event: StringName) -> void:
	if _index < 0 or _index >= _steps.size():
		return
	for j in range(_index, _steps.size()):
		if _steps[j].get("on", &"") == event:
			_index = j
			advance()
			return


func advance() -> void:
	_index += 1
	if _index >= _steps.size():
		_finish()
		return
	var step := _steps[_index]
	_label.text = str(step.text)
	_next.text = "Got it" if _index == _steps.size() - 1 else "Next"
	var resolve: Callable = step.get("target", Callable())
	_target = resolve.call() if resolve.is_valid() else null
	_panel.visible = true
	_pulse = 0.0
	queue_redraw()


func _finish() -> void:
	_index = _steps.size()
	_panel.visible = false
	_target = null
	queue_redraw()
	finished.emit()
	queue_free()


func _process(delta: float) -> void:
	if not _panel.visible:
		return
	_pulse += delta
	_place_panel()
	queue_redraw()


## Beside the target, in the first direction with room: below, right, above,
## left. The machine sits in the bottom-left corner, so "above" would have
## covered Ace's panel; "right" is the free felt beside it.
func _place_panel() -> void:
	var vp := get_viewport_rect().size
	var panel_size := _panel.get_combined_minimum_size()
	var pos := Vector2(vp.x * 0.5 - panel_size.x * 0.5, vp.y * 0.42)
	if _target != null and is_instance_valid(_target):
		var rect := _target.get_global_rect()
		var gap := RING_PAD + 16.0
		var by_side := {
			"below": Vector2(rect.get_center().x - panel_size.x * 0.5, rect.end.y + gap),
			"right": Vector2(rect.end.x + gap, rect.get_center().y - panel_size.y * 0.5),
			"above": Vector2(rect.get_center().x - panel_size.x * 0.5, rect.position.y - gap - panel_size.y),
			"left": Vector2(rect.position.x - gap - panel_size.x, rect.get_center().y - panel_size.y * 0.5),
		}
		# The step's preferred side first (an enemy wants the free felt on its
		# left, not the ability row below it), then the rest in a fixed order.
		var order: Array = ["below", "right", "above", "left"]
		var preferred := str(_steps[_index].get("side", "")) if _index < _steps.size() else ""
		if by_side.has(preferred):
			order.erase(preferred)
			order.push_front(preferred)
		var candidates: Array = []
		for side: String in order:
			candidates.append(by_side[side])
		pos = candidates[0]
		for candidate: Vector2 in candidates:
			var fits := candidate.x >= 8.0 and candidate.y >= 8.0 \
				and candidate.x + panel_size.x <= vp.x - 8.0 \
				and candidate.y + panel_size.y <= vp.y - 8.0
			if fits:
				pos = candidate
				break
	pos.x = clampf(pos.x, 8.0, vp.x - panel_size.x - 8.0)
	pos.y = clampf(pos.y, 8.0, vp.y - panel_size.y - 8.0)
	_panel.global_position = pos


func _draw() -> void:
	if not _panel.visible or _target == null or not is_instance_valid(_target):
		return
	var rect := _target.get_global_rect().grow(RING_PAD + 3.0 * sin(_pulse * 4.0))
	rect.position -= global_position
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.border_color = RING_COLOR
	style.set_border_width_all(3)
	style.set_corner_radius_all(14)
	draw_style_box(style, rect)
	var glow := StyleBoxFlat.new()
	glow.draw_center = false
	glow.border_color = Color(RING_COLOR, 0.35)
	glow.set_border_width_all(8)
	glow.set_corner_radius_all(18)
	draw_style_box(glow, rect.grow(4.0))
