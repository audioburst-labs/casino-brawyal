class_name RelicHuntView
extends VBoxContainer
## The Casino's "Find the Relic" (doc v0.120). Five cards — one blank, three
## gold, one relic — are shuffled face down behind identical backs, laid out
## three over two, and the player takes whichever they click. The other four
## turn over a moment later.

signal finished(lines: Array, relic_id: StringName)

const CARD_SIZE := Vector2(186, 262)
const CARD_BACK := "res://assets/cards/card_back.png"

var _hunt: RelicHunt
var _rng: RandomNumberGenerator
var _cards: Array[Button] = []
var _hint: Label
var _shuffle_button: Button
var _done_button: Button
var _shuffled := false


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

	# Doc's layout: a row of three over a row of two.
	var table := VBoxContainer.new()
	table.alignment = BoxContainer.ALIGNMENT_CENTER
	table.add_theme_constant_override("separation", 18)
	add_child(table)
	var rows: Array[HBoxContainer] = []
	for i in 2:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 20)
		table.add_child(row)
		rows.append(row)
	for index in RelicHunt.CARDS:
		var card := _build_card(index)
		rows[0 if index < 3 else 1].add_child(card)
		_cards.append(card)

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


func _build_card(index: int) -> Button:
	var card := Button.new()
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
	card.pivot_offset = card.size * 0.5
	var tween := card.create_tween()
	tween.tween_property(card, "scale:x", 0.0, 0.12).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		if to_face_up:
			_paint_face(index)
		else:
			_paint_back(index))
	tween.tween_property(card, "scale:x", 1.0, 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_shuffle() -> void:
	if _shuffled:
		return
	_shuffled = true
	_shuffle_button.disabled = true
	_hint.text = "Watch them go..."
	for index in _cards.size():
		_flip(index, false)
	await get_tree().create_timer(0.32).timeout

	# The deck really is shuffled; the visible swaps are there so the player
	# sees the cards move rather than being told they did.
	_hunt.shuffle(_rng)
	for pass_index in 6:
		var a := randi() % _cards.size()
		var b := randi() % _cards.size()
		if a != b:
			var card_a := _cards[a]
			var card_b := _cards[b]
			var pa := card_a.global_position
			var pb := card_b.global_position
			card_a.create_tween().tween_property(card_a, "global_position", pb, 0.16) \
				.set_trans(Tween.TRANS_SINE)
			card_b.create_tween().tween_property(card_b, "global_position", pa, 0.16) \
				.set_trans(Tween.TRANS_SINE)
		await get_tree().create_timer(0.18).timeout
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
