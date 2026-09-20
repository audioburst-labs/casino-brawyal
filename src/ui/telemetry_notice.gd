class_name TelemetryNotice
extends Control
## The first-launch notice (patch 0.115).
##
## The build goes to players and it reports their IP address. That is personal
## data, so saying so once, plainly, with the off switch in reach, is the
## minimum — and it costs an hour. Shown once; dismissing either way marks it
## seen. Alt-F4 at the notice leaves it unseen, so it asks again next launch.
##
## Positioned from `get_viewport_rect().size` rather than anchors: a freshly
## instantiated Control does not reliably resolve anchor percentages against
## the true viewport in the same frame it is created (the documented gotcha
## that bit the Options overlay in 0.22).

const BODY := """Casino Brawyal sends anonymous play data — which encounters you
reach, which abilities you use, how long you play, and your IP address — so the
game can be balanced against how people actually play it.

No account, no name, nothing you typed. You can turn it off any time in
Settings, and turning it off deletes what is stored on this machine."""


func _ready() -> void:
	var vp := get_viewport_rect().size
	position = Vector2.ZERO
	size = vp
	z_index = 220

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.01, 0.02, 0.78)
	backdrop.position = Vector2.ZERO
	backdrop.size = vp
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var panel_size := Vector2(620, 420)
	var panel := PanelContainer.new()
	panel.position = vp * 0.5 - panel_size * 0.5
	panel.size = panel_size
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	panel.add_child(column)

	var title := Label.new()
	title.text = "Before you play"
	title.theme_type_variation = &"TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var body := Label.new()
	body.text = BODY
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	column.add_child(buttons)

	var accept := Button.new()
	accept.text = "Got it"
	accept.custom_minimum_size = Vector2(190, 0)
	accept.pressed.connect(func() -> void:
		Telemetry.mark_notice_seen()
		queue_free())
	buttons.add_child(accept)

	var decline := Button.new()
	decline.text = "Turn it off"
	decline.custom_minimum_size = Vector2(190, 0)
	decline.pressed.connect(func() -> void:
		Telemetry.set_enabled(false)
		queue_free())
	buttons.add_child(decline)


## True when this build reports anywhere and the player has not been told yet.
## A build with no endpoint baked in says nothing, because it sends nothing.
static func should_show() -> bool:
	return Telemetry.is_live() and not Telemetry.notice_seen()
