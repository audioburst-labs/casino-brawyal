class_name CodexTab
extends Control
## The codex (roadmap phase 0, patch 0.121): how a turn works, every keyword
## and every status, read straight from the content so it can never drift
## from the rules the way the Vulnerable text did. Opened from Settings and
## from the main menu; lives in `HudLayer` like the other overlays.

const TURN_TEXT := (
	"Every round starts with a spin. The chips it pays land in the drawer.\n\n"
	+ "Drag a chip onto a card's socket. A card fires the moment its last socket "
	+ "fills, at the enemy you aimed at. Click an enemy to aim. The numbers above "
	+ "an enemy are what it will do next turn.\n\n"
	+ "Pass ends your turn. Chips left in the drawer are discarded; chips already in "
	+ "sockets stay for next round.\n\n"
	+ "Buffs tick down at the start of their owner's turn, debuffs at the end of it. "
	+ "Block is spent when its owner's next turn begins."
)


func _ready() -> void:
	var vp := get_viewport_rect().size
	position = Vector2.ZERO
	size = vp
	z_index = 210

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.01, 0.02, 0.72)
	backdrop.position = Vector2.ZERO
	backdrop.size = vp
	backdrop.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			queue_free())
	add_child(backdrop)

	var panel_size := Vector2(760, 820)
	var panel := PanelContainer.new()
	panel.position = vp * 0.5 - panel_size * 0.5
	panel.size = panel_size
	add_child(panel)

	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	pad.add_child(column)

	var title := Label.new()
	title.text = "Codex"
	title.theme_type_variation = &"TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)

	body.add_child(_heading("How a turn works"))
	body.add_child(_paragraph(TURN_TEXT))

	body.add_child(_heading("Keywords"))
	for id: StringName in Db.content.all_keyword_ids():
		var keyword := Db.content.get_keyword(id)
		body.add_child(_entry(keyword.name, keyword.text))

	body.add_child(_heading("Statuses"))
	for id: StringName in Db.content.all_status_ids():
		var status := Db.content.get_status(id)
		var kind := "buff" if status.kind == "buff" else "debuff"
		var timing := "Stacks, and does not expire on its own."
		if status.stack_mode == "duration":
			timing = ("Ticks down at the start of its owner's turn." if status.kind == "buff"
				else "Ticks down at the end of its owner's turn.")
		body.add_child(_entry("%s (%s)" % [status.name, kind],
			"%s %s" % [status.description, timing]))

	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(queue_free)
	column.add_child(close)


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"SubtitleLabel"
	return label


func _paragraph(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 17)
	return label


func _entry(name: String, text: String) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	var title := Label.new()
	title.text = name
	title.add_theme_font_size_override("font_size", 18)
	row.add_child(title)
	var body := Label.new()
	body.text = text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 15)
	body.modulate = Color(0.9, 0.86, 0.8)
	row.add_child(body)
	return row


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()
