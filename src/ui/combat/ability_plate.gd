class_name AbilityPlate
extends RefCounted
## The compact form of an ability card (patch 0.125) for the lists where a whole
## card will not fit: the Layout tab, the Shop's loadout column and the Choose
## Your Hand screen. The art as a plate in the tier's metal frame (copper, silver,
## gold: the same shader as the card), the cost as small suit icons in the top
## left, and the name on a dark strip along the bottom.
##
## `fill()` dresses a host control (the drag-and-drop `AbilityChit` each screen
## owns) rather than being a control itself, so dragging, dropping and the
## tooltips stay exactly where they were.

const FRAME_SHADER := "res://assets/shaders/ability_card_frame.gdshader"
const TITLE_FONT := "res://assets/fonts/AlfaSlabOne-Regular.ttf"
const FRAME := 4.0
const RADIUS := 10.0


## `size` is the host's size in pixels; `font_size` the name's size.
static func fill(host: PanelContainer, id: StringName, tier: int, size: Vector2, font_size: int = 15) -> void:
	var metal := TierStyle.metal(tier)
	host.custom_minimum_size = size
	host.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	var body := ColorRect.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(FRAME_SHADER):
		var shader_material := ShaderMaterial.new()
		shader_material.shader = load(FRAME_SHADER)
		shader_material.set_shader_parameter("size_px", size)
		shader_material.set_shader_parameter("m_hi", metal.hi)
		shader_material.set_shader_parameter("m_mid", metal.mid)
		shader_material.set_shader_parameter("m_lo", metal.lo)
		shader_material.set_shader_parameter("radius", RADIUS)
		shader_material.set_shader_parameter("frame", FRAME)
		body.material = shader_material
	else:
		body.color = Color(0.05, 0.27, 0.28)
	host.add_child(body)

	var inset := MarginContainer.new()
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		inset.add_theme_constant_override("margin_" + side, int(FRAME))
	host.add_child(inset)
	var layers := Control.new()
	layers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layers.clip_contents = true
	inset.add_child(layers)

	var art_texture := SuitAssets.card_art(id)
	if art_texture != null:
		var art := TextureRect.new()
		art.texture = art_texture
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layers.add_child(art)

	# the dark strip the name sits on: clear at the top, nearly solid at the bottom
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(0.01, 0.1, 0.11, 0.0), Color(0.01, 0.1, 0.11, 0.8), Color(0.01, 0.1, 0.11, 0.95)])
	fade.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	var fade_texture := GradientTexture2D.new()
	fade_texture.gradient = fade
	fade_texture.fill_from = Vector2(0.0, 0.0)
	fade_texture.fill_to = Vector2(0.0, 1.0)
	fade_texture.width = 4
	fade_texture.height = 64
	var strip := TextureRect.new()
	strip.texture = fade_texture
	strip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	strip.stretch_mode = TextureRect.STRETCH_SCALE
	strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_top = -(font_size + 18.0)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layers.add_child(strip)

	var def := Db.content.get_ability(id, tier)
	var caption := Label.new()
	caption.text = def.name if def != null else String(id)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_top = -(font_size + 12.0)
	caption.offset_bottom = -2.0
	caption.clip_text = true
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font := load(TITLE_FONT) as Font
	caption.add_theme_font_override("font", font)
	caption.add_theme_font_size_override("font_size", fit_size(font, caption.text, size.x - FRAME * 2.0 - 8.0, font_size))
	caption.add_theme_color_override("font_color", metal.title)
	caption.add_theme_color_override("font_outline_color", Color(0.0, 0.05, 0.06, 0.95))
	caption.add_theme_constant_override("outline_size", 3)
	layers.add_child(caption)

	if def != null:
		layers.add_child(_cost_pill(def))


## The largest size, down to 9, at which `text` fits on one line.
static func fit_size(font: Font, text: String, width: float, max_size: int) -> int:
	for s in range(max_size, 8, -1):
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x <= width:
			return s
	return 9


## The suits an ability costs, small, in the top left.
static func _cost_pill(def: Defs.AbilityDef) -> Control:
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.position = Vector2(4, 4)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.01, 0.1, 0.11, 0.8)
	box.set_corner_radius_all(9)
	box.content_margin_left = 4.0
	box.content_margin_right = 4.0
	box.content_margin_top = 2.0
	box.content_margin_bottom = 2.0
	pill.add_theme_stylebox_override("panel", box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(row)
	for suit: StringName in def.cost:
		var icon := TextureRect.new()
		icon.texture = SuitAssets.suit_texture(suit)
		icon.custom_minimum_size = Vector2(15, 15)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
	return pill
