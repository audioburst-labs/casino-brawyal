class_name IntroComic
extends CanvasLayer
## The opening comic (patch 0.129): a book spread over the darkened casino whose
## panels fade in one after another, then the neon logo flickers over the last.
## Layout and timing live in `IntroComicScript`; this only draws them.
##
## Controls: Mute and Skip sit bottom right. Click or Space jumps to the finished
## spread, and once the last panel has landed Skip is replaced by a Play button
## that swells and shrinks. Skip, Play, or a click on the finished spread all end it.

signal finished

const PAPER := Color("#f7e9b8")
const INK := Color("#2a1320")
const FONT := "res://assets/fonts/AlfaSlabOne-Regular.ttf"
const BUTTON_Y := 1036.0

var _t := 0.0
var _done := false
var _stage: Control
var _holders: Array[Control] = []
var _captions: Array[Control] = []
var _logo: TextureRect
var _mute: Button
var _skip: Button
var _play: Button
var _muted := false
var _speaker: SpeakerIcon


## `start_at` seeks into the timeline (the review hook `CB_DEBUG_INTRO_T`).
func _init(start_at := 0.0) -> void:
	layer = 50
	_t = start_at


func _ready() -> void:
	var settings := Telemetry.settings
	_muted = settings != null and settings.muted
	Audio.play_music(IntroComicScript.MUSIC)

	var backdrop := TextureRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	if ResourceLoader.exists(IntroComicScript.BACKDROP):
		backdrop.texture = load(IntroComicScript.BACKDROP)
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.modulate = Color(0.42, 0.4, 0.5)
	backdrop.gui_input.connect(_on_backdrop_input)
	add_child(backdrop)

	_stage = Control.new()
	_stage.size = IntroComicScript.STAGE
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)

	for page: Rect2 in IntroComicScript.PAGES:
		_stage.add_child(_block(page, PAPER))
	_stage.add_child(_block(Rect2(936, 40, 48, 1000), Color(0, 0, 0, 0.35)))

	for panel: Dictionary in IntroComicScript.panels():
		_build_panel(panel)

	_logo = TextureRect.new()
	if ResourceLoader.exists(IntroComicScript.LOGO):
		_logo.texture = load(IntroComicScript.LOGO)
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_SCALE
	_logo.position = IntroComicScript.LOGO_RECT.position
	_logo.size = IntroComicScript.LOGO_RECT.size
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.modulate.a = 0.0
	_stage.add_child(_logo)

	_build_controls()
	get_viewport().size_changed.connect(_fit)
	_fit()
	_tick()


func _exit_tree() -> void:
	# The Mute button silenced the master bus for this scene only: hand it back
	# as the Settings tab left it.
	var settings := Telemetry.settings
	Audio.set_master_muted(settings != null and settings.muted)


func _process(delta: float) -> void:
	# Wall clock: the combat-speed toggle must not change how long a story reads.
	_t += delta / maxf(Engine.time_scale, 0.001)
	_tick()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo() \
			and (event.is_action(&"ui_accept") or event.is_action(&"ui_cancel")):
		_advance()
		get_viewport().set_input_as_handled()


# ----------------------------------------------------------------- building

func _block(rect: Rect2, color: Color) -> ColorRect:
	var block := ColorRect.new()
	block.position = rect.position
	block.size = rect.size
	block.color = color
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return block


## A framed picture: a black border, then the picture cropped to the cell.
func _build_panel(panel: Dictionary) -> void:
	var rect: Rect2 = panel.rect
	var holder := Control.new()
	holder.position = rect.position
	holder.size = rect.size
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.modulate.a = 0.0
	holder.add_child(_block(Rect2(Vector2.ZERO, rect.size), Color.BLACK))

	var inner_size := rect.size - Vector2(6, 6)
	var clip := Control.new()
	clip.position = Vector2(3, 3)
	clip.size = inner_size
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(clip)
	var path: String = panel.texture
	if ResourceLoader.exists(path):
		var texture: Texture2D = load(path)
		var picture := TextureRect.new()
		picture.texture = texture
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_SCALE
		var fit := IntroComicScript.cover_rect(inner_size, texture.get_size(), float(panel.fx), float(panel.fy))
		picture.position = fit.position
		picture.size = fit.size
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.add_child(picture)
	_stage.add_child(holder)
	_holders.append(holder)

	var caption: Dictionary = panel.caption
	if caption.is_empty():
		_captions.append(null)
		return
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.set_content_margin_all(8)
	box.add_theme_stylebox_override("panel", style)
	box.position = caption.pos
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = String(caption.text)
	label.add_theme_font_override("font", load(FONT))
	label.add_theme_font_size_override("font_size", int(caption.size))
	label.add_theme_color_override("font_color", INK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)
	box.modulate.a = 0.0
	_stage.add_child(box)
	_captions.append(box)


func _build_controls() -> void:
	var hint := Label.new()
	hint.text = "Click to continue"
	hint.position = Vector2(70, 1040)
	hint.add_theme_font_override("font", load(FONT))
	hint.add_theme_font_size_override("font_size", 20)
	hint.add_theme_color_override("font_color", Color("#d8c8aa"))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(hint)

	_mute = _button("", Rect2(1648, BUTTON_Y, 56, 34), 20)
	_mute.tooltip_text = "Mute"
	_speaker = SpeakerIcon.new()
	_speaker.muted = _muted
	_speaker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_speaker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mute.add_child(_speaker)
	_mute.pressed.connect(_on_mute_pressed)
	_skip = _button("Skip  >", Rect2(1716, BUTTON_Y, 144, 34), 20)
	_skip.pressed.connect(_finish)
	_play = _button("Play  >", Rect2(1716, BUTTON_Y - 3, 150, 40), 24)
	_play.theme_type_variation = &"PrimaryButton"
	_play.pivot_offset = _play.size * 0.5
	_play.pressed.connect(_finish)
	_play.visible = false


func _button(text: String, rect: Rect2, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.position = rect.position
	button.custom_minimum_size = rect.size
	button.size = rect.size
	button.add_theme_font_size_override("font_size", font_size)
	button.focus_mode = Control.FOCUS_NONE
	_stage.add_child(button)
	return button


# ------------------------------------------------------------------- timeline

## The whole spread is a function of the clock, so a jump to the end is just a
## bigger `_t`.
func _tick() -> void:
	var panels := IntroComicScript.panels()
	for i in panels.size():
		var reveal: float = panels[i].reveal
		_holders[i].modulate.a = IntroComicScript.alpha_at(_t, reveal, IntroComicScript.FADE)
		var caption := _captions[i]
		if caption != null:
			caption.modulate.a = IntroComicScript.alpha_at(_t, reveal + IntroComicScript.CAPTION_DELAY, IntroComicScript.FADE)
	_logo.modulate.a = IntroComicScript.alpha_at(_t, IntroComicScript.LOGO_AT, IntroComicScript.LOGO_FADE) * IntroComicScript.flicker(_t)

	var skip_alpha := 1.0 - IntroComicScript.alpha_at(_t, IntroComicScript.SKIP_FADE_AT, IntroComicScript.SKIP_FADE)
	_skip.modulate.a = skip_alpha
	_skip.visible = skip_alpha > 0.0
	var play_alpha := IntroComicScript.alpha_at(_t, IntroComicScript.PLAY_AT, IntroComicScript.PLAY_FADE)
	_play.visible = play_alpha > 0.0
	_play.modulate.a = play_alpha
	_play.scale = Vector2.ONE * IntroComicScript.pulse(_t)


## The spread keeps its 16:9 shape, centred, whatever the window.
func _fit() -> void:
	var viewport := get_viewport().get_visible_rect().size
	var factor := minf(viewport.x / IntroComicScript.STAGE.x, viewport.y / IntroComicScript.STAGE.y)
	_stage.scale = Vector2(factor, factor)
	_stage.position = (viewport - IntroComicScript.STAGE * factor) * 0.5


# ------------------------------------------------------------------- input

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_advance()


## Before the spread is finished a click completes it; after, it ends the comic.
func _advance() -> void:
	if _t < IntroComicScript.COMPLETE_AT:
		_t = IntroComicScript.COMPLETE_AT
		_tick()
	else:
		_finish()


func _on_mute_pressed() -> void:
	_muted = not _muted
	_speaker.muted = _muted
	_speaker.queue_redraw()
	Audio.set_master_muted(_muted)


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit()
	queue_free()


## A small speaker, drawn rather than typed, so no font has to carry an emoji. With
## sound off it wears a cross instead of sound waves.
class SpeakerIcon extends Control:
	var muted := false

	func _draw() -> void:
		var ink := Color("#f3e8d6")
		var o := (size - Vector2(32, 22)) * 0.5
		draw_colored_polygon(PackedVector2Array([
			o + Vector2(0, 7), o + Vector2(6, 7), o + Vector2(13, 0),
			o + Vector2(13, 22), o + Vector2(6, 15), o + Vector2(0, 15)]), ink)
		if muted:
			draw_line(o + Vector2(19, 6), o + Vector2(30, 16), ink, 2.5)
			draw_line(o + Vector2(19, 16), o + Vector2(30, 6), ink, 2.5)
		else:
			draw_arc(o + Vector2(14, 11), 7.0, -0.9, 0.9, 10, ink, 2.5)
			draw_arc(o + Vector2(14, 11), 12.0, -0.9, 0.9, 12, ink, 2.5)
