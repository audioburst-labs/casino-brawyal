class_name RelicHuntView
extends VBoxContainer
## The Casino's "Find the Relic" (doc v0.120). Five cards — one blank, three
## gold, one relic — are shuffled face down behind identical backs, laid out
## three over two, and the player takes whichever they click. The other four
## turn over a moment later.
##
## Patch 0.114, two designer notes. The cards used to live inside HBoxContainers
## while the shuffle tweened their `global_position`: a container owns its
## children's positions, so it fought every tween, snapped the cards back, and
## left at least one card's input rect somewhere other than where it was drawn
## — which is why the bottom-right card could not be clicked. The table is a
## plain Control with absolute slots now, so nothing competes for the layout.
## The shuffle itself is rebuilt (see `_on_shuffle`) with a dust cloud over it,
## because the old version let a player follow the relic with their eyes.

signal finished(lines: Array, relic_id: StringName)

const CARD_SIZE := Vector2(186, 262)
const CARD_BACK := "res://assets/cards/card_back.png"
const COLUMN_GAP := 20.0
const ROW_GAP := 18.0

var _hunt: RelicHunt
var _rng: RandomNumberGenerator
var _cards: Array[Button] = []
var _slots: Array[Vector2] = []     # where each card rests, in table space
var _table: Control
var _dust: DustCloud
var _hint: Label
var _shuffle_button: Button
var _done_button: Button
var _shuffled := false


## The masking dust (doc: shuffled "in a way that does not allow the player to
## know which card is which"). Drawn OVER the cards while they are gathered, so
## the moment the deck is in one pile is the moment it cannot be read.
class DustCloud:
	extends Control

	const MOTES := 46

	var density := 0.0:
		set(v):
			density = v
			queue_redraw()
	var phase := 0.0:
		set(v):
			phase = v
			queue_redraw()
	var origin := Vector2.ZERO

	func _draw() -> void:
		if density <= 0.01:
			return
		var rng := RandomNumberGenerator.new()
		rng.seed = 90210
		for i in MOTES:
			# Each mote has a fixed heading and speed; `phase` pushes it out
			# along that heading, so the cloud billows rather than twinkles.
			var angle := rng.randf_range(0.0, TAU)
			var speed := rng.randf_range(0.35, 1.0)
			var wobble := sin(phase * 3.0 + float(i)) * 9.0
			var reach := (46.0 + 210.0 * phase * speed)
			var at := origin + Vector2(cos(angle), sin(angle) * 0.62) * reach \
				+ Vector2(0.0, wobble - 60.0 * phase)
			var radius := rng.randf_range(7.0, 26.0) * (0.45 + density)
			var alpha := density * (1.0 - phase * 0.75) * rng.randf_range(0.18, 0.42)
			draw_circle(at, radius, Color(0.86, 0.80, 0.66, alpha))


func start(rng: RandomNumberGenerator) -> void:
	_rng = rng
	_hunt = RelicHunt.build(Db.content, Game.run, rng)
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 14)

	_hint = Label.new()
	_hint.text = "One of these five hides a relic. Shuffle, then pick one."
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 22)
	add_child(_hint)

	# Doc's layout: a row of three over a row of two — but positioned by hand,
	# so the shuffle can move the cards without a container undoing it.
	_table = Control.new()
	_table.custom_minimum_size = Vector2(
		CARD_SIZE.x * 3.0 + COLUMN_GAP * 2.0, CARD_SIZE.y * 2.0 + ROW_GAP)
	_table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# SHRINK_CENTER, or the VBox stretches the table to the full screen width
	# and the hand-placed slots start at the far left instead of centred.
	_table.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(_table)
	_slots = _slot_positions()
	for index in RelicHunt.CARDS:
		var card := _build_card(index)
		card.position = _slots[index]
		_table.add_child(card)
		_cards.append(card)

	_dust = DustCloud.new()
	_dust.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dust.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dust.z_index = 60
	_table.add_child(_dust)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 30)
	add_child(buttons)
	_shuffle_button = Button.new()
	_shuffle_button.text = "Shuffle"
	_shuffle_button.pressed.connect(_on_shuffle)
	buttons.add_child(_shuffle_button)
	_done_button = Button.new()
	_done_button.text = "Take it"
	_done_button.disabled = true
	_done_button.pressed.connect(_on_done)
	buttons.add_child(_done_button)
	_paint_faces()
	# CB_DEBUG_AUTOSPIN=1: shuffle and pick automatically, for screenshots.
	if OS.get_environment("CB_DEBUG_AUTOSPIN") != "":
		await get_tree().create_timer(0.6).timeout
		await _on_shuffle()
		await get_tree().create_timer(0.3).timeout
		_on_card_pressed(0)


## The five resting places: three across the top, two centred beneath.
static func _slot_positions() -> Array[Vector2]:
	var width := CARD_SIZE.x * 3.0 + COLUMN_GAP * 2.0
	var places: Array[Vector2] = []
	for i in 3:
		places.append(Vector2((CARD_SIZE.x + COLUMN_GAP) * float(i), 0.0))
	var indent := (width - CARD_SIZE.x * 2.0 - COLUMN_GAP) * 0.5
	for i in 2:
		places.append(Vector2(
			indent + (CARD_SIZE.x + COLUMN_GAP) * float(i), CARD_SIZE.y + ROW_GAP))
	return places


func _build_card(index: int) -> Button:
	var card := Button.new()
	card.size = CARD_SIZE
	card.custom_minimum_size = CARD_SIZE
	card.disabled = true
	card.pressed.connect(_on_card_pressed.bind(index))
	var art := TextureRect.new()
	art.name = "Art"
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.offset_left = 10
	art.offset_top = 10
	art.offset_right = -10
	art.offset_bottom = -46
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(art)
	var label := Label.new()
	label.name = "Caption"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.anchor_top = 1.0
	label.anchor_right = 1.0
	label.anchor_bottom = 1.0
	label.offset_top = -42
	label.offset_bottom = -8
	label.add_theme_font_size_override("font_size", 19)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(label)
	return card


## Face up: what each card is actually holding.
func _paint_faces() -> void:
	for index in _cards.size():
		_paint_face(index)


func _paint_face(index: int) -> void:
	var card := _cards[index]
	var entry: Dictionary = _hunt.cards[index]
	var art: TextureRect = card.get_node("Art")
	var caption: Label = card.get_node("Caption")
	match int(entry.kind):
		RelicHunt.Kind.GOLD:
			art.texture = load("res://assets/icons/coin.png")
			caption.text = "%d coins" % int(entry.value)
		RelicHunt.Kind.RELIC:
			art.texture = SuitAssets.relic_texture(entry.relic)
			var def := Db.content.get_relic(entry.relic)
			caption.text = def.name if def else "Relic"
		_:
			art.texture = null
			caption.text = "Nothing"
	art.modulate = Color.WHITE


func _paint_back(index: int) -> void:
	var card := _cards[index]
	var art: TextureRect = card.get_node("Art")
	var caption: Label = card.get_node("Caption")
	caption.text = ""
	art.texture = load(CARD_BACK) if ResourceLoader.exists(CARD_BACK) else null
	if art.texture == null:
		art.modulate = Color(0.45, 0.18, 0.26)


## The flip: the card squashes to nothing, swaps its face, and springs back.
func _flip(index: int, to_face_up: bool) -> void:
	var card := _cards[index]
	card.pivot_offset = CARD_SIZE * 0.5
	var tween := card.create_tween()
	tween.tween_property(card, "scale:x", 0.0, 0.12).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		if to_face_up:
			_paint_face(index)
		else:
			_paint_back(index))
	tween.tween_property(card, "scale:x", 1.0, 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Gather into one pile behind a cloud of dust, cut the deck three times where
## nobody can see it, then deal back out (patch 0.114). The player watches five
## cards become one pile and one pile become five cards; there is no individual
## card to follow, which is what the doc asks for and what the old swap-in-place
## animation failed to deliver.
func _on_shuffle() -> void:
	if _shuffled:
		return
	_shuffled = true
	_shuffle_button.disabled = true
	_hint.text = "Watch them go..."
	for index in _cards.size():
		_flip(index, false)
	await get_tree().create_timer(0.34).timeout

	var pile := Vector2(
		_table.size.x * 0.5 - CARD_SIZE.x * 0.5, (CARD_SIZE.y + ROW_GAP) * 0.5)
	_dust.origin = pile + CARD_SIZE * 0.5

	# ---- gather, each card on its own arc so they arrive at slightly
	# different times and the pile forms rather than snapping shut.
	var kick := create_tween()
	kick.tween_method(func(v: float) -> void: _dust.density = v, 0.0, 1.0, 0.22)
	for index in _cards.size():
		var card := _cards[index]
		card.z_index = index
		var gather := card.create_tween()
		gather.set_parallel(true)
		gather.tween_property(card, "position", pile, 0.30 + 0.035 * float(index)) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		gather.tween_property(card, "rotation",
			deg_to_rad(randf_range(-9.0, 9.0)), 0.30)
		gather.tween_property(card, "scale", Vector2(0.92, 0.92), 0.30)
	await get_tree().create_timer(0.46).timeout

	# ---- the deck is really shuffled here, under the dust.
	_hunt.shuffle(_rng)
	var billow := create_tween()
	billow.tween_method(func(v: float) -> void: _dust.phase = v, 0.0, 0.55, 0.50)
	# Three cuts: the pile splits, crosses over itself and closes again. All of
	# it happens inside the cloud, so it is texture rather than information.
	for cut in 3:
		var lift := (1 + cut) % _cards.size()
		var card := _cards[lift]
		card.z_index = 10 + cut
		var swing := card.create_tween()
		swing.tween_property(card, "position",
			pile + Vector2(52.0 if cut % 2 == 0 else -52.0, -16.0), 0.14) \
			.set_trans(Tween.TRANS_SINE)
		swing.tween_property(card, "position", pile, 0.14) \
			.set_trans(Tween.TRANS_SINE)
		await get_tree().create_timer(0.17).timeout

	# ---- deal back out, left to right, and let the dust settle behind them.
	var settle := create_tween()
	settle.set_parallel(true)
	settle.tween_method(func(v: float) -> void: _dust.phase = v, 0.55, 1.0, 0.45)
	settle.tween_method(func(v: float) -> void: _dust.density = v, 1.0, 0.0, 0.45)
	for index in _cards.size():
		var card := _cards[index]
		card.z_index = 0
		var deal := card.create_tween()
		deal.set_parallel(true)
		deal.tween_property(card, "position", _slots[index], 0.26) \
			.set_delay(0.05 * float(index)) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		deal.tween_property(card, "rotation", 0.0, 0.26).set_delay(0.05 * float(index))
		deal.tween_property(card, "scale", Vector2.ONE, 0.26).set_delay(0.05 * float(index))
	await get_tree().create_timer(0.52).timeout

	for card in _cards:
		card.disabled = false
	_hint.text = "Pick a card."


func _on_card_pressed(index: int) -> void:
	if _hunt.revealed >= 0:
		return
	if _hunt.reveal(index).is_empty():
		return
	Game.commit_encounter()
	for card in _cards:
		card.disabled = true
	_flip(index, true)
	_hint.text = "..."
	await get_tree().create_timer(0.85).timeout
	for other in _cards.size():
		if other != index:
			_flip(other, true)
	await get_tree().create_timer(0.4).timeout
	_hint.text = "Yours to keep."
	_done_button.disabled = false


func _on_done() -> void:
	var line := _hunt.claim(Db.content, Game.run)
	var relic: StringName = &""
	if _hunt.revealed >= 0 and int(_hunt.cards[_hunt.revealed].kind) == RelicHunt.Kind.RELIC:
		relic = _hunt.cards[_hunt.revealed].relic
	finished.emit([line] as Array, relic)
