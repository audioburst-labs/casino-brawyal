extends Control
## Combat screen presenter: owns a CombatSim, forwards player input as sim
## commands, and animates the sim's event queue. All rules live in the sim.

const ENEMY_GAP := 16
## Doc "Behavior -> Unit Positioning": each side of the field has exactly four
## fixed slots. Index 0 is the slot nearest the centre of the screen, 3 the
## furthest out — the same order the sim keeps `enemies` in.
const ENEMY_SLOTS := 4
## 0.0.111: the machine has a FIXED-width area so the ability row never moves
## as reels are bought; ReelStrip shrinks its reels to fit at 5+ (see
## ReelStrip.MAX_ROW_WIDTH). 6 cards x 190 + 5 gaps fit in what is left.
const MACHINE_WIDTH := 640.0

## Per-ability attack animations from the design doc's Animations table.
## card_fling = a razor card flies at the target (flaming when it Marks),
## dagger = Ace's dagger slash with a teal/purple afterslash,
## cash_in = the Mark bursts, block = shield pulse on Ace,
## chip = a minted chip flies to the tray, ultimate = Flush's all-out barrage.
const ABILITY_ANIMS := {
	&"card_sling": ["card_fling"],
	&"quick_maneuvers": ["block"],
	&"color_up": ["chip"],
	&"double_down": ["dagger", "cash_in"],
	&"heartsteal": ["block"],
	&"pocket_rockets": ["card_fling", "card_fling"],
	&"slow_playing": ["block"],
	&"house_edge": [],
	&"bust": ["dagger", "cash_in"],
	&"dazzling_personality": ["mark_wave"],
	&"face_reader": ["block"],
	&"bad_beat": ["block"],
	&"on_a_roll": ["dagger", "cash_in"],
	&"pay_line": ["dagger", "go_again"],
	&"flush": ["ultimate"],
}
## The doc's "green, teal, and purple flame" — Mark/Cash In/flaming Card
## Fling all cycle through these instead of a single flat tint.
const FLAME_COLORS := [
	Color(0.6, 1.0, 0.5), Color(0.45, 1.0, 0.85), Color(0.65, 0.4, 1.0),
]
const DEBUFF_STATUSES: Array[StringName] = [&"weak", &"vulnerable", &"stun"]
## The dagger's default cut, a quarter turn clockwise from the 0.21 sweep
## (patch 0.22: "Rotate it 90 degrees clockwise").
const SLASH_ANGLE := -0.55 + PI * 0.5
## Flush's eight cuts, each the same quarter turn round from where they were.
const ULTIMATE_ANGLES := [
	-0.9 + PI * 0.5, 0.75 + PI * 0.5, -0.25 + PI * 0.5, 1.15 + PI * 0.5,
	-1.45 + PI * 0.5, 0.35 + PI * 0.5, -0.6 + PI * 0.5, 0.95 + PI * 0.5,
]
## The red swipe an enemy's hit leaves on Ace, likewise.
const IMPACT_ANGLE := 2.4 + PI * 0.5

var sim: CombatSim
var run_mode := false   # true when launched by Game flow (reports results back)
## Telemetry's running tally for this fight, or null outside a real run. The
## sim knows nothing about it: the presenter feeds it as events drain, which
## keeps `src/core/` free of autoloads and makes the 40-run balance bot silent
## by construction - RunBot never builds a presenter (patch 0.115).
var _summary: CombatSummary = null
var _def_ids: Dictionary = {}

var _background: TextureRect
var _round_label: Label
var _banner: Label
var _hero_view: UnitView
var _enemy_views: Dictionary = {}   # actor id -> UnitView (living)
## Dead enemies' views, still holding their slot in the line until the sim
## clears the corpse away (`actor_removed`). Kept apart from `_enemy_views`
## so nothing targets them, but the row still counts them as occupants —
## otherwise a spacer was added behind the corpse and the line shifted.
var _corpse_views: Dictionary = {}
## actor id -> slot index (0 = nearest centre). Assigned once, when the actor
## arrives, and never recomputed: the doc's table is an initial seating rule,
## and nobody moves when a neighbour arrives or dies (0.0.111).
var _enemy_slot_of: Dictionary = {}
var _enemies_row: HBoxContainer
var _reel_strip: ReelStrip
var _cabinet: SlotCabinet
var _tray_view: ChipTrayView
var _ability_row: HBoxContainer
var _ability_cards: Array[AbilityCard] = []
var _end_turn: Button
var _vfx: CombatVfx
var _busy := false


## Ultimate Animation (doc): "a streak of paint appears briefly on the screen".
## The reference is Persona's torn-paper slash, so the band is drawn as a
## polygon with a ragged top and bottom edge rather than a clean ColorRect,
## with a white deckle along each tear.
class PaintStreak:
	extends Control

	var streak_color := Color(0.85, 0.15, 0.35)
	var seed_value := 0
	## 0.0 draws only the torn white edges — used to lay the same tear back
	## over the close-up so the portrait sits INSIDE the band, not on top of it.
	var fill_alpha := 1.0
	## How far each torn edge can bite into the band, as a fraction of its
	## height. Anything drawn inside this margin is guaranteed to stay behind
	## the tear rather than poking through it.
	var jitter_ratio := 0.22

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var steps := 26
		var top := PackedVector2Array()
		var bottom := PackedVector2Array()
		for i in steps + 1:
			var t := float(i) / steps
			var x := size.x * t
			top.append(Vector2(x, rng.randf_range(0.0, size.y * jitter_ratio)))
			bottom.append(Vector2(x, size.y - rng.randf_range(0.0, size.y * jitter_ratio)))
		var shape := PackedVector2Array(top)
		for i in range(bottom.size() - 1, -1, -1):
			shape.append(bottom[i])
		if fill_alpha > 0.0:
			draw_colored_polygon(shape, Color(streak_color, fill_alpha))
		# The white deckle that sells the torn-paper edge.
		var deckle := Color(1.0, 1.0, 1.0, 0.9)
		draw_polyline(top, deckle, 5.0, true)
		draw_polyline(bottom, deckle, 5.0, true)


## Dagger Slash (doc: "a slash move with his dagger, briefly leaving a teal
## and purple afterslash"; reference GIF: a hooked crescent, fat through the
## middle and tapering to points, white-hot core, coloured rim, drybrush
## filaments). Drawn as three nested tapered bands along a circular arc,
## additively blended so it reads as light, drawn in along its length by
## `progress`. Replaces the two rotating rectangles of 0.19–0.20 (0.0.111).
class SlashArc:
	extends Control

	var progress := 0.0                      # 0..1, how much of the arc is drawn
	var fade := 1.0                          # alpha multiplier for the fade-out
	var radius := 118.0
	var sweep := 4.3                         # radians of arc (~250 deg)
	var start_angle := -2.6
	var thickness := 48.0
	var seed_value := 3
	## Outer -> core: purple, teal, white — Ace's Mark-flame palette in the
	## reference's three-band structure. The core stays narrow so the teal
	## reads as the body of the cut, not just a fringe on a white bar.
	var bands := [Color(0.60, 0.28, 1.0, 0.8), Color(0.30, 1.0, 0.86, 0.95), Color(1, 1, 1, 0.9)]
	var band_widths := [1.0, 0.66, 0.2]
	var filaments := 11

	## The mid-arc point of the spine, in the node's own space. The crescent is
	## drawn on a circle of `radius` around the node origin, so without this the
	## origin sits in the HOLE of the crescent — which is exactly the "goes
	## around the target" the designer reported (patch 0.22). Offsetting the
	## node by this puts the fat middle of the cut on the target.
	func belly() -> Vector2:
		var mid := start_angle + sweep * 0.5
		return Vector2(cos(mid), sin(mid)) * radius

	func _draw() -> void:
		if progress <= 0.002:
			return
		var steps := 48
		var shown := int(ceil(steps * clampf(progress, 0.0, 1.0)))
		# Each band is a RING between its own width and the next band's, not a
		# stack of overlapping strokes: with additive blending three strokes
		# piled on each other summed to white and the teal vanished.
		for band in bands.size():
			var color: Color = bands[band]
			color.a *= fade
			var outer_width := float(band_widths[band])
			var inner_width := float(band_widths[band + 1]) if band + 1 < band_widths.size() else 0.0
			for side: float in [1.0, -1.0]:
				var outer := PackedVector2Array()
				var inner := PackedVector2Array()
				for i in shown + 1:
					var t := float(i) / steps
					var angle: float = start_angle + sweep * t
					var normal: Vector2 = Vector2(cos(angle), sin(angle)) * side
					var centre: Vector2 = Vector2(cos(angle), sin(angle)) * radius
					# Swells through the middle, tapers to a point at both
					# tips; the leading tip also thins while still drawing.
					var taper := sin(t * PI)
					var head := clampf((progress - t) * 6.0, 0.0, 1.0)
					var reach := thickness * taper * head * 0.5
					outer.append(centre + normal * reach * outer_width)
					inner.append(centre + normal * reach * inner_width)
				if outer.size() < 3:
					continue
				var shape := PackedVector2Array(outer)
				for i in range(inner.size() - 1, -1, -1):
					shape.append(inner[i])
				draw_colored_polygon(shape, color)
				if inner_width <= 0.0:
					break   # the core is one solid stroke, drawn once
		# Drybrush: fine seeded strands feathering off the outer edge, only
		# along the part already drawn.
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var strand := Color(bands[1])
		strand.a = 0.55 * fade
		for k in filaments:
			var t := rng.randf_range(0.12, 0.92)
			if t > progress:
				continue
			var angle: float = start_angle + sweep * t
			var normal := Vector2(cos(angle), sin(angle))
			var tangent := Vector2(-normal.y, normal.x)
			var edge := normal * (radius + thickness * 0.5 * sin(t * PI))
			var length := rng.randf_range(14.0, 46.0)
			var drift := rng.randf_range(-0.35, 0.35)
			draw_line(edge, edge + (normal * 0.55 + tangent * (0.8 + drift)).normalized() * length,
				strand, rng.randf_range(1.2, 2.6), true)


## "Options In Combat" (doc): a foe puts a decision to the player. The field
## darkens, the choices sit in the middle of it, and play resumes the moment
## one is taken. Built to the doc's mock (image1): a title plate over two
## option cards (patch 0.22).
class OptionsOverlay:
	extends Control

	signal picked(index: int)

	func build(title_text: String, options: Array) -> void:
		# Sized from the viewport directly, not from anchors: a Control built
		# and added in the same frame does not reliably resolve anchor
		# percentages yet (the lesson LayoutTab/SettingsTab already learned).
		var vp := get_viewport_rect().size
		position = Vector2.ZERO
		size = vp
		z_index = 120
		var dim := ColorRect.new()
		dim.color = Color(0.03, 0.01, 0.02, 0.62)
		dim.position = Vector2.ZERO
		dim.size = vp
		dim.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(dim)

		var plate := PanelContainer.new()
		var plate_size := Vector2(minf(760.0, vp.x * 0.5), 74.0)
		plate.position = Vector2((vp.x - plate_size.x) * 0.5, vp.y * 0.13)
		plate.size = plate_size
		add_child(plate)
		var title := Label.new()
		title.text = title_text
		title.theme_type_variation = &"SubtitleLabel"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		plate.add_child(title)

		var card_size := Vector2(380, 250)
		var gap := 48.0
		var total := card_size.x * options.size() + gap * maxf(0.0, options.size() - 1)
		var left := (vp.x - total) * 0.5
		var top := vp.y * 0.13 + plate_size.y + 34.0
		for index in options.size():
			var card := _option_card(options[index], index)
			card.position = Vector2(left + (card_size.x + gap) * index, top)
			card.size = card_size
			add_child(card)


	func _option_card(option: Dictionary, index: int) -> Button:
		var card := Button.new()
		card.custom_minimum_size = Vector2(380, 250)
		card.pressed.connect(func() -> void: picked.emit(index))
		var box := VBoxContainer.new()
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", 10)
		card.add_child(box)

		var name_label := Label.new()
		name_label.text = str(option.get("title", "?"))
		name_label.theme_type_variation = &"SubtitleLabel"
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(name_label)
		box.add_child(HSeparator.new())

		var reward := Label.new()
		reward.text = str(option.get("reward_text", ""))
		reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reward.add_theme_color_override("font_color", Color(0.62, 1.0, 0.68))
		reward.add_theme_font_size_override("font_size", 21)
		box.add_child(reward)

		var penalty := Label.new()
		penalty.text = str(option.get("penalty_text", ""))
		penalty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		penalty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		penalty.add_theme_color_override("font_color", Color(1.0, 0.62, 0.58))
		penalty.add_theme_font_size_override("font_size", 19)
		penalty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(penalty)
		return card


func _ready() -> void:
	_build_layout()
	if get_tree().current_scene == self:
		# Standalone debug launch: a fixed fight with everything unlocked.
		# CB_DEBUG_ENEMIES="dealer,dealer,..." overrides the lineup.
		var enemies: Array = ["bouncer", "server"]
		# CB_DEBUG_REELS=N: a machine with N reels, to review the fixed-width
		# machine area shrinking its reels at 5+ (0.0.111).
		var machine := SlotMachine.new()
		for i in OS.get_environment("CB_DEBUG_REELS").to_int() - machine.reels.size():
			machine.add_reel()
		setup({
			"hero": "ace",
			"abilities": ["card_sling", "quick_maneuvers", "color_up",
				"double_down", "heartsteal", "flush"],
			"enemies": enemies,
			"machine": machine,
			"seed": randi(),
		})
		# CB_DEBUG_AUTOFIRE=N: fire the Nth listed ability automatically
		# (1 = card_sling, 2 = quick_maneuvers, ...) for animation review.
		# Every socket is filled, so multi-chip abilities fire too.
		var autofire := OS.get_environment("CB_DEBUG_AUTOFIRE").to_int()
		if autofire > 0:
			await get_tree().create_timer(4.0).timeout
			var state := sim.abilities[autofire - 1]
			for slot in state.def.cost.size():
				var suit: StringName = state.def.cost[slot]
				if suit == &"any":
					suit = &"spade"
				sim.tray.add(suit, 1)
				_on_chip_dropped(autofire - 1, slot, suit)
		# CB_DEBUG_ENEMY_STATUS="mark,weak": put these on every enemy at the
		# start, so status-conditional UI (the card glow, the pips, the intent
		# numbers) can be reviewed without playing into the state first.
		var forced_status := OS.get_environment("CB_DEBUG_ENEMY_STATUS")
		if forced_status != "":
			for name in forced_status.split(",", false):
				for enemy in sim.enemies:
					enemy.apply_status(StringName(name.strip_edges()), 2)
		# CB_DEBUG_HERO_HP=N: start Ace on N hp, to reach a death quickly.
		var hero_hp := OS.get_environment("CB_DEBUG_HERO_HP").to_int()
		if hero_hp > 0:
			sim.hero.hp = hero_hp
			_hero_view.refresh()
		# CB_DEBUG_BANNER=victory|defeat: pop the end-of-combat banner.
		var banner := OS.get_environment("CB_DEBUG_BANNER")
		if banner != "":
			await get_tree().create_timer(1.0).timeout
			_show_banner("VICTORY!" if banner == "victory" else "DEFEAT")
		# CB_DEBUG_ENDTURN=N: auto-end N turns so enemy attacks play out too.
		var end_turns := OS.get_environment("CB_DEBUG_ENDTURN").to_int()
		for i in end_turns:
			await get_tree().create_timer(6.5).timeout
			_on_end_turn()


func setup(config: Dictionary) -> void:
	# CB_DEBUG_ENEMIES="dealer,dealer,..." forces a lineup from anywhere in the
	# flow, so a crowded field can be screenshot-reviewed without hunting for
	# the encounter that rolls it.
	var override := OS.get_environment("CB_DEBUG_ENEMIES")
	if override != "":
		config = config.duplicate()
		config["enemies"] = Array(override.split(","))
	# CB_DEBUG_ABILITIES="face_reader,color_up,..." does the same for the hand,
	# so a loadout can be reviewed without playing a run up to it (0.113).
	var hand := OS.get_environment("CB_DEBUG_ABILITIES")
	if hand != "":
		config = config.duplicate()
		config["abilities"] = Array(hand.split(","))
	# CB_DEBUG_TIERS=1|2: bring every equipped ability in at that upgrade tier,
	# to review the silver/gold cards without playing a run up to them.
	var forced_tier := OS.get_environment("CB_DEBUG_TIERS").to_int()
	if forced_tier > 0:
		config = config.duplicate()
		var tiers := {}
		for ability_id in config.get("abilities", []):
			tiers[StringName(str(ability_id))] = forced_tier
		config["ability_tiers"] = tiers
	run_mode = config.get("run_mode", false)
	sim = CombatSim.new(Db.content, config)
	# After the sim: the opening payload lists the enemies it just rolled.
	if run_mode:
		_open_summary(config)
	_spawn_units()
	_spawn_abilities()
	_reel_strip.set_reel_count(sim.machine.reels.size())
	_cabinet.refresh_layout()
	_tray_view.bind(sim.tray)
	_next_round.call_deferred()


func _build_layout() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_background = TextureRect.new()
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if ResourceLoader.exists("res://assets/backgrounds/bg_casino_floor.png"):
		_background.texture = load("res://assets/backgrounds/bg_casino_floor.png")
	# Held back so the fighters and the cards read against it (patch 0.20).
	# Combat had no dim at all, unlike every ScreenBase screen.
	_background.modulate = Color(0.9, 0.9, 0.9)
	add_child(_background)

	_vfx = CombatVfx.new()
	add_child(_vfx)

	_round_label = Label.new()
	_round_label.theme_type_variation = &"SubtitleLabel"
	# Clear of the persistent run header bar, which draws above this screen.
	_round_label.position = Vector2(40, HeaderHud.BAR_HEIGHT + 16)
	add_child(_round_label)

	# Gold and the encounter number are part of the run header now (patch
	# 0.18: "placed on the same row as the other UI elements in this area"),
	# so the combat screen no longer draws its own tally.

	_enemies_row = HBoxContainer.new()
	_enemies_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_enemies_row.add_theme_constant_override("separation", ENEMY_GAP)
	# Patch 0.19: the band starts well right of screen centre, so even the
	# doc's "two central slots" pair still reads as standing on the right,
	# and it reaches lower down the felt so the fighters aren't floating in
	# the top half of the frame. End Turn has moved out of this column
	# entirely, which is what frees the vertical room.
	_enemies_row.anchor_left = 0.52
	_enemies_row.anchor_right = 0.985
	_enemies_row.anchor_top = 0.05
	_enemies_row.anchor_bottom = 0.635
	add_child(_enemies_row)

	# The bottom band spans the whole width (0.0.111): a fixed machine area on
	# the left, the ability row filling the rest — recalibrated so six cards
	# and a six-reel machine fit side by side. It starts a little lower than
	# before to leave the Pass strip its own room above.
	var bottom := HBoxContainer.new()
	bottom.anchor_left = 0.01
	bottom.anchor_right = 0.99
	bottom.anchor_top = 0.687
	bottom.anchor_bottom = 0.99
	bottom.add_theme_constant_override("separation", 12)
	add_child(bottom)

	# The machine is a real cabinet now (doc "Assets → Slot Machine", patch
	# 0.22): the reels sit in its window and the chip tray IS its drawer, so
	# paid-out chips fall into it the way the doc describes.
	var machine_box := CenterContainer.new()
	machine_box.custom_minimum_size = Vector2(MACHINE_WIDTH, 0)
	bottom.add_child(machine_box)
	_reel_strip = ReelStrip.new()
	_reel_strip.framed = false
	_tray_view = ChipTrayView.new()
	_tray_view.framed = false
	_cabinet = SlotCabinet.new()
	machine_box.add_child(_cabinet)
	_cabinet.setup(SlotCabinet.Mode.COMBAT, _reel_strip, _tray_view)

	_ability_row = HBoxContainer.new()
	_ability_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_ability_row.add_theme_constant_override("separation", 6)
	_ability_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_ability_row)

	# "Pass" sits in the strip between the enemies' band and the ability row
	# (0.0.111), on the right where the designer wants it — a lane of its own,
	# so no count of reels or cards can ever crowd it off the screen again.
	_end_turn = Button.new()
	_end_turn.text = "Pass"
	_end_turn.pressed.connect(_on_end_turn)
	_end_turn.anchor_left = 0.878
	_end_turn.anchor_right = 0.985
	_end_turn.anchor_top = 0.638
	_end_turn.anchor_bottom = 0.681
	add_child(_end_turn)

	# Hero stands between the machine and the enemies.
	_banner = Label.new()
	_banner.theme_type_variation = &"TitleLabel"
	# Patch 0.19: PRESET_CENTER on an empty Label bakes zero-size offsets, so
	# the text started at screen centre and ran off to the right. Spanning the
	# full width and centring the text inside it is size-independent.
	_banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	add_child(_banner)


func _spawn_units() -> void:
	_hero_view = UnitView.new()
	# Doc "Unit Positioning": a lone unit stands in the third slot out from the
	# middle — and every character keeps the same fixed size, so the hero's
	# panel is exactly as wide as an enemy's (patch 0.18).
	_hero_view.anchor_left = 0.150
	_hero_view.anchor_right = 0.244
	_hero_view.anchor_top = 0.05
	_hero_view.anchor_bottom = 0.635
	add_child(_hero_view)
	move_child(_banner, get_child_count() - 1)
	_hero_view.setup(sim.hero)
	_hero_view.set_ghost_layer(_vfx)  # motion smears during pose animations

	var slots := initial_slots(sim.enemies.size())
	for index in sim.enemies.size():
		var enemy: CombatActor = sim.enemies[index]
		var view := UnitView.new()
		_enemies_row.add_child(view)
		view.setup(enemy)
		view.clicked.connect(_on_unit_clicked)
		_enemy_views[enemy.id] = view
		_enemy_slot_of[enemy.id] = slots[index]
	_rebuild_enemy_row()
	_update_target_markers()
	_publish_hero_hp()


## Initial seating, counted outward from the middle of the screen: 1 unit
## takes the SECOND slot out (designer's call, 0.0.111 — the doc's table says
## the third, which stood the lone Manager a full slot further from Ace than
## it ended up after its first summon), 2 the two central slots, 3 everything
## but the outermost, 4 the lot.
static func initial_slots(count: int) -> Array:
	match count:
		0: return []
		1: return [1]
		2: return [0, 1]
		3: return [0, 1, 2]
	return [0, 1, 2, 3]


## Seats a summon (doc "Unit Positioning"): `order` is the sim's centre-outward
## roster with the newcomer already inserted, `seats` the persistent slots of
## everyone else. The newcomer takes the free slot nearest its summoner on the
## inward side; if there is none, it takes the summoner's slot and every unit
## from there outward shifts one further out. Returns the updated seats.
static func seat_summon(order: Array[StringName], seats: Dictionary, new_id: StringName) -> Dictionary:
	var out := seats.duplicate()
	var index := order.find(new_id)
	if index < 0:
		return out
	var inner := -1
	for i in range(index - 1, -1, -1):
		if out.has(order[i]):
			inner = int(out[order[i]])
			break
	var outer := ENEMY_SLOTS
	for i in range(index + 1, order.size()):
		if out.has(order[i]):
			outer = int(out[order[i]])
			break
	if outer - inner > 1:
		out[new_id] = outer - 1
		return out
	out[new_id] = outer
	for i in range(index + 1, order.size()):
		if out.has(order[i]):
			out[order[i]] = int(out[order[i]]) + 1
	return out


## Lays the four slots out left to right (slot 0 nearest the centre) from the
## persistent `_enemy_slot_of` seating, filling unoccupied slots with a
## same-width spacer. Corpses keep their slot, so nobody slides sideways when
## a neighbour dies (patch 0.17) or arrives (0.0.111) — only a cleared-away
## corpse frees a slot, and only a summon with no room pushes anyone.
func _rebuild_enemy_row() -> void:
	for child in _enemies_row.get_children():
		if not (child is UnitView):
			_enemies_row.remove_child(child)
			child.queue_free()
	var occupant := {}
	for actor_id: StringName in _enemy_slot_of:
		var view: Control = _enemy_views.get(actor_id, _corpse_views.get(actor_id))
		if view != null:
			occupant[int(_enemy_slot_of[actor_id])] = view
	for slot in ENEMY_SLOTS:
		var node: Control = occupant.get(slot)
		if node == null:
			node = Control.new()
			node.custom_minimum_size = Vector2(UnitView.UNIT_WIDTH, 0)
			node.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_enemies_row.add_child(node)
		_enemies_row.move_child(node, slot)


func _spawn_abilities() -> void:
	for index in sim.abilities.size():
		var card := AbilityCard.new()
		_ability_row.add_child(card)
		card.setup(sim.abilities[index], index, sim)
		card.socket_clicked.connect(_on_socket_clicked)
		card.chip_dropped.connect(_on_chip_dropped)
		_ability_cards.append(card)


func _next_round() -> void:
	_busy = true
	sim.begin_round()
	# A pending "Options In Combat" choice is drained as a `choice_offered`
	# event and awaited inside _play_events (patch 0.22).
	await _play_events(_drain())
	_busy = false
	_refresh_all()


## Chips arrive by drag-and-drop only (patch 0.11); clicking a filled socket
## returns its chip to the tray.
func _on_socket_clicked(ability_index: int, slot_index: int) -> void:
	if _busy or sim.phase != CombatSim.Phase.ASSIGNMENT:
		return
	if sim.unassign_chip(ability_index, slot_index):
		_drain()
		_refresh_all()


func _on_chip_dropped(ability_index: int, slot_index: int, suit: StringName) -> void:
	if _busy or sim.phase != CombatSim.Phase.ASSIGNMENT:
		return
	if sim.assign_chip(suit, ability_index, slot_index):
		_busy = true
		await _play_events(_drain())
		_busy = false
		_refresh_all()


func _on_unit_clicked(actor_id: StringName) -> void:
	if not _enemy_views.has(actor_id):
		return
	# `set_target` emits nothing, so the choice is recorded here. The enemy's
	# def_id, not its runtime id - `enemy_0` is minted per combat and means
	# nothing across runs.
	if run_mode and _summary != null:
		Telemetry.record(&"target_set",
			{"target": str(_def_ids.get(actor_id, actor_id))},
			_summary.combat_id, _summary.encounter_number, _summary.rounds)
	sim.set_target(actor_id)
	_update_target_markers()


func _on_end_turn() -> void:
	if _busy or sim.phase != CombatSim.Phase.ASSIGNMENT:
		return
	# Pass. `end_assignment` emits `turn_ended` for both sides, so the hero's
	# own decision is clearer recorded at the button.
	if run_mode and _summary != null:
		Telemetry.record(&"pass", {}, _summary.combat_id,
			_summary.encounter_number, _summary.rounds)
	_busy = true
	sim.end_assignment()
	await _play_events(_drain())
	_busy = false
	if sim.phase == CombatSim.Phase.ROUND_START:
		_next_round()


## Puts a foe's decision to the player and blocks until they answer, then
## lets the round start finish (the machine has not spun yet).
func _offer_choice(data: Dictionary) -> void:
	var overlay := OptionsOverlay.new()
	add_child(overlay)
	var title := "The Loan Shark makes you an offer"
	if str(data.get("kind", "")) != "loan":
		title = "Choose"
	overlay.build(title, data.get("options", []))
	# CB_DEBUG_CHOICE=N: take option N automatically, so a fight that pauses on
	# a decision can still be screenshot-reviewed end to end. Kicked off
	# WITHOUT awaiting, so the listener below is already in place when it fires.
	var auto := OS.get_environment("CB_DEBUG_CHOICE")
	if auto != "":
		_auto_pick(overlay, maxi(0, auto.to_int() - 1))
	var index: int = await overlay.picked
	overlay.queue_free()
	if sim.choose(index):
		await _play_events(_drain())
	_refresh_all()


func _auto_pick(overlay: OptionsOverlay, index: int) -> void:
	await get_tree().create_timer(1.2).timeout
	if is_instance_valid(overlay):
		overlay.picked.emit(index)


func _refresh_all() -> void:
	_hero_view.refresh()
	_publish_hero_hp()
	for view: UnitView in _enemy_views.values():
		view.refresh()
	_tray_view.refresh()
	for card in _ability_cards:
		card.refresh()
	_update_target_markers()
	_end_turn.disabled = sim.phase != CombatSim.Phase.ASSIGNMENT


func _update_target_markers() -> void:
	var target := sim.targeting.effective_target(sim.enemies)
	for id: StringName in _enemy_views:
		_enemy_views[id].set_targeted(target != null and id == target.id)


## The header's heart reads `Game.live_hp` during a fight (0.0.111): the run's
## own `hp` is only written back when combat ends, so without this the header
## and Ace's panel would show two different numbers mid-fight. Published from
## the panel's SHOWN value, so both step down hit by hit together.
func _publish_hero_hp() -> void:
	if run_mode and Game.run != null:
		Game.live_hp = _hero_view.shown_hp()


func _view_of(actor_id: StringName) -> UnitView:
	if actor_id == sim.hero.id:
		return _hero_view
	return _enemy_views.get(actor_id)


## True when this enemy's announced move actually throws a punch at the hero —
## a summon, a heal or a pure buff should not animate like one.
func _intent_strikes(actor_id: StringName) -> bool:
	var entry := sim.intent_display(actor_id)
	if entry.is_empty():
		return false
	var intent: Dictionary = entry.get("intent", {})
	return int(entry.get("display_instances", intent.get("instances", 0))) > 0


## Opens the per-fight tally and tells telemetry the fight has begun.
func _open_summary(config: Dictionary) -> void:
	if Game.run == null:
		return
	_def_ids.clear()
	for enemy in sim.enemies:
		_def_ids[enemy.id] = String(enemy.def_id)
	_summary = CombatSummary.new(TelemetryIds.uuid4(), Game.run.run_uid)
	_summary.encounter_number = Game.run.encounter_number()
	_summary.encounter_type = str(config.get("type", "combat"))
	_summary.lineup_id = str(config.get("lineup", ""))
	_summary.combat_seed = int(config.get("seed", 0))
	_summary.hp_before = sim.hero.hp
	var ids: Array[String] = []
	for enemy in sim.enemies:
		ids.append(String(enemy.def_id))
	_summary.enemy_ids = ids
	Telemetry.set_run(Game.run.run_uid)
	Telemetry.record(&"combat_started", _summary.opening(),
		_summary.combat_id, _summary.encounter_number)


## Closes the tally. `reason` is "won", "lost" or "abandoned" - a player who
## walks out of a fight through the menu is a real outcome, not missing data.
func _close_summary(reason: String) -> void:
	if _summary == null or _summary.combat_id == "":
		return
	_summary.hp_after = sim.hero.hp if sim != null and sim.hero != null else 0
	Telemetry.record(&"combat_ended", _summary.closing(reason),
		_summary.combat_id, _summary.encounter_number)
	_summary.combat_id = ""          # idempotent: _exit_tree must not double-fire


## A fight left through the menu still gets an ending.
func _exit_tree() -> void:
	if run_mode and _summary != null and not _summary.finished:
		_close_summary("abandoned")


func _card_of(ability_id: StringName) -> AbilityCard:
	for card in _ability_cards:
		if card.ability_index >= 0 and sim.abilities[card.ability_index].def.id == ability_id:
			return card
	return null


func _add_enemy_view(actor_id: StringName) -> void:
	for enemy in sim.enemies:
		if enemy.id == actor_id and not _enemy_views.has(actor_id):
			var view := UnitView.new()
			_enemies_row.add_child(view)
			view.setup(enemy)
			view.clicked.connect(_on_unit_clicked)
			view.modulate.a = 0.0
			view.create_tween().tween_property(view, "modulate:a", 1.0, 0.4)
			_enemy_views[actor_id] = view
			var order: Array[StringName] = []
			for e in sim.enemies:
				order.append(e.id)
			_enemy_slot_of = seat_summon(order, _enemy_slot_of, actor_id)
			_rebuild_enemy_row()


## A corpse whose slot the sim handed to someone else leaves the field.
func _remove_enemy_view(actor_id: StringName) -> void:
	var view: UnitView = _enemy_views.get(actor_id, _corpse_views.get(actor_id))
	_enemy_views.erase(actor_id)
	_corpse_views.erase(actor_id)
	_enemy_slot_of.erase(actor_id)
	if view != null:
		_enemies_row.remove_child(view)
		view.queue_free()
	_rebuild_enemy_row()


## The ONLY place `sim.drain_events()` may be called. Telemetry taps it here,
## synchronously and without awaiting - an await inside the tap would interleave
## with the presenter's animation awaits and reorder the world.
func _drain() -> Array[CombatEvent]:
	var events := sim.drain_events()
	if run_mode and _summary != null:
		for event in events:
			_summary.feed(event.type, event.data, sim.hero.id)
			if TelemetryFilter.keeps(event.type):
				Telemetry.record(event.type,
					TelemetryFilter.project(event.type, event.data, sim.hero.id, _def_ids),
					_summary.combat_id, _summary.encounter_number, _summary.rounds)
	return events


func _play_events(events: Array[CombatEvent]) -> void:
	for event in events:
		match event.type:
			&"round_started":
				_round_label.text = "Round %d" % event.data.round
			&"intents_shown":
				for entry: Dictionary in event.data.intents:
					var view := _view_of(entry.actor)
					if view != null:
						view.show_intent(entry)
				await get_tree().create_timer(0.2).timeout
			&"spin_resolved":
				# The lever is what starts a spin, so it swings with one (0.113).
				_cabinet.pull_lever()
				await _reel_strip.spin_to(event.data.symbols)
				await _payout_flourish(event.data.symbols)
				_tray_view.refresh()
			&"chips_generated", &"chips_converted":
				# Break (patch 0.114): the Chip Golem sheds a chip every time its
				# counter runs out, and you should SEE it fall into the drawer
				# rather than just find the tray one richer.
				if StringName(str(event.data.get("source", ""))) == &"break":
					await _golem_drops_chip(StringName(str(event.data.get("suit", ""))))
				_tray_view.refresh()
			&"chip_assigned":
				# Paint the chip into its socket immediately so the final chip
				# is visible before the ability fires (patch 0.1). The TRAY is
				# deliberately not refreshed here: by now the sim has already
				# run the whole ability, so a Go Again's new chips would pop
				# into the tray a couple of seconds before the reels are seen
				# to spin for them (patch 0.20). `spin_resolved` reveals a
				# payout, at round start and on a re-spin alike.
				var assigned_card := _card_of(event.data.ability)
				if assigned_card != null:
					assigned_card.show_chip(event.data.slot, event.data.suit)
				_tray_view.spend(event.data.suit)
			&"chip_unassigned":
				_tray_view.refresh()
			&"ability_fired":
				await get_tree().create_timer(0.3).timeout  # let the last chip be seen
				var fired_card := _card_of(event.data.ability)
				if fired_card != null:
					fired_card.flash_fire()
				# Abilities with their own pose animation drive their own
				# motion; the rest keep the generic lunge.
				if not _has_pose_anim(event.data.ability):
					_hero_view.play_lunge()
					await get_tree().create_timer(0.12).timeout
				await _play_ability_anims(event.data.ability, _view_of(event.data.target))
			&"passive_gained":
				var passive_card := _card_of(event.data.ability)
				if passive_card != null:
					passive_card.flash_fire()
				await get_tree().create_timer(0.2).timeout
			&"enemy_summoned":
				_add_enemy_view(event.data.actor)
				Fx.shake(8.0)
				await get_tree().create_timer(0.35).timeout
			&"actor_removed":
				_remove_enemy_view(event.data.actor)
			&"encore":
				var encore_view := _view_of(event.data.actor)
				if encore_view != null:
					Fx.spawn_number(encore_view.sprite_center(), "ENCORE!", Color(1.0, 0.85, 0.4))
				await get_tree().create_timer(0.25).timeout
			&"damage_negated":
				Fx.spawn_number(_hero_view.sprite_center(), "MISS!", Color(0.7, 0.9, 1.0))
				await get_tree().create_timer(0.2).timeout
			&"mark_cashed":
				var cashed_view := _view_of(event.data.actor)
				if cashed_view != null:
					Fx.spawn_number(cashed_view.sprite_center(), "CASH IN!", Color(0.5, 1.0, 0.8))
				await get_tree().create_timer(0.15).timeout
			&"damage_dealt":
				# One hit, one number, one beat — instances stay in sync with
				# their damage numbers (patch 0.1).
				var target := _view_of(event.data.target)
				var amount := int(event.data.amount)
				if target != null:
					if event.data.target == sim.hero.id:
						_impact(target.sprite_center())  # enemy strike swipe
					else:
						_sparks(target.sprite_center(), Color(1.0, 0.85, 0.5), 8)
					# Layered impact: flash+squash, shockwave, freeze, kick.
					target.play_hit()
					# Step the bar down by this hit alone (patch 0.17) — a
					# full refresh() would already show every instance of a
					# multi-hit attack landed, before the rest even animate.
					# Block is spent first, and only what got through touches
					# HP (patch 0.18: blocked hits used to drop the bar and
					# then spring back, reading as a heal).
					target.apply_damage_display(int(event.data.get("hp_lost", amount)),
						int(event.data.get("blocked", 0)))
					if event.data.target == sim.hero.id:
						_publish_hero_hp()
					# Damage (doc animation): a small explosion icon on the hit.
					_burst(target.sprite_center(), "res://assets/icons/fx_explosion.png",
						Color(1.0, 0.75, 0.3))
					_vfx.shockwave(target.sprite_center(),
						Color(1.0, 0.85, 0.5) if amount < 20 else Color(1.0, 0.6, 0.3),
						90.0 + amount * 3.0)
					var hp_lost := int(event.data.get("hp_lost", amount))
					var blocked := int(event.data.get("blocked", 0))
					if hp_lost <= 0 and blocked > 0:
						Fx.spawn_number(target.sprite_center(), "BLOCKED",
							Color(0.6, 0.85, 1.0))
					else:
						Fx.spawn_number(target.sprite_center(), str(hp_lost))
					if amount >= 25:
						Fx.hitstop(0.12)
						Fx.punch_zoom(0.05)
						_vfx.screen_flash(0.25)
					elif amount >= 12:
						Fx.hitstop(0.05)
						Fx.punch_zoom(0.025)
				Fx.shake(clampf(amount * 1.2, 4.0, 18.0))
				await get_tree().create_timer(0.36).timeout
			&"block_gained":
				var actor_view := _view_of(event.data.actor)
				if actor_view != null:
					# Block only. An ability that both hits and blocks would otherwise
					# snap the target's HP bar mid-animation (patch 0.113).
					actor_view.refresh_block()
					# Patch 0.114: every source animates the same, relics and
					# start-of-turn passives included. Those fire at a round start,
					# a beat before the reels spin, so the cue has to be big enough
					# and slow enough to survive the player looking at the machine.
					actor_view.play_block_gain(int(event.data.amount))
					Fx.spawn_number(actor_view.sprite_center(),
						"+%d" % event.data.amount, Color(0.6, 0.85, 1.0))
					_burst(actor_view.sprite_center(),
						"res://assets/icons/status_block.png", Color(0.6, 0.85, 1.0))
				await get_tree().create_timer(0.34).timeout
			&"status_applied":
				var status_view := _view_of(event.data.actor)
				if status_view != null:
					status_view.refresh_statuses()
					Fx.spawn_number(status_view.sprite_center(),
						"%s %d" % [event.data.status, event.data.stacks],
						Color(0.85, 0.7, 1.0))
					# Apply Debuff (doc animation): a quick side-to-side shake.
					if StringName(event.data.status) in DEBUFF_STATUSES:
						status_view.play_debuff_shake()
					# Stun gets its own animation on top (patch 0.113).
					if StringName(event.data.status) == &"stun":
						status_view.play_stun()
					# Shown intent numbers track live buffs/debuffs (patch 0.13).
					if event.data.actor != sim.hero.id:
						var updated := sim.intent_display(event.data.actor)
						if not updated.is_empty():
							status_view.show_intent(updated)
				# A Mark or a Weak landing on an ENEMY changes which cards are primed,
				# so the glow is re-evaluated here as well as on the hero's own ticks
				# (doc "Glow", patch 0.115).
				for card in _ability_cards:
					card.set_glowing(AbilityCard.wants_glow(card.ability_def(), sim))
				await get_tree().create_timer(0.18).timeout
			&"healed":
				var healed_view := _view_of(event.data.actor)
				if healed_view != null:
					healed_view.refresh()
					if event.data.actor == sim.hero.id:
						_publish_hero_hp()
					# A heal has to read AS a heal on the unit receiving it
					# (patch 0.19): green burst on the ally, plus a beat, so a
					# three-ally heal no longer pops every number on one frame.
					_burst(healed_view.sprite_center(),
						"res://assets/icons/fx_heal.png", Color(0.5, 0.95, 0.55))
					_vfx.shockwave(healed_view.sprite_center(),
						Color(0.5, 0.95, 0.55), 90.0)
					Fx.spawn_number(healed_view.sprite_center(),
						"+%d" % event.data.amount, Color(0.5, 0.95, 0.55))
					await get_tree().create_timer(0.16).timeout
			&"actor_died":
				var dead_view := _view_of(event.data.actor)
				var hero_died: bool = event.data.actor == sim.hero.id
				if dead_view != null:
					if hero_died:
						# Ace going down is not a payout — no chips, no
						# confetti. The screen darkens and he drops, on the
						# same beat as the hit that killed him (patch 0.19).
						_vfx.vignette(0.6, 1.4)
						_impact(dead_view.sprite_center())
					else:
						# Enemies cash out: a burst of house chips and a shockwave.
						_vfx.shockwave(dead_view.sprite_center(), Color(1.0, 0.7, 0.4), 170.0)
						_vfx.confetti(dead_view.sprite_center(), 18)
						_sparks(dead_view.sprite_center(), Color(1.0, 0.85, 0.4), 20)
					dead_view.play_death()
					dead_view.clear_intent()
				Fx.hitstop(0.1)
				Fx.punch_zoom(0.04)
				await get_tree().create_timer(0.45).timeout
				# The dead unit keeps its slot in the row (patch 0.17: no more
				# auto-recentering the survivors) — it's already invisible
				# from play_death()'s fade, so it just stops being a target.
				if dead_view != null and not hero_died:
					_enemy_views.erase(event.data.actor)
					_corpse_views[event.data.actor] = dead_view
					dead_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
				_update_target_markers()
			&"enemy_move":
				var mover := _view_of(event.data.actor)
				if mover != null and event.data.get("skipped", false):
					# Stunned: it loses its turn, and now that reads as a stun rather
					# than as the game quietly skipping a unit (patch 0.113).
					mover.play_stun()
					mover.clear_intent()
					await get_tree().create_timer(0.75).timeout
				if mover != null and not event.data.get("skipped", false):
					mover.play_telegraph()  # menace first...
					await get_tree().create_timer(0.32).timeout
					# Only a move that actually hits the hero plays the attack
					# pose. Mr. Moneybags heals his crew with the same
					# money-hurling art otherwise, which read as an attack on
					# Ace (patch 0.19).
					if _intent_strikes(event.data.actor):
						await mover.play_attack()
					else:
						mover.play_lunge()
						await get_tree().create_timer(0.22).timeout
					mover.clear_intent()
					await get_tree().create_timer(0.2).timeout
			&"chips_discarded":
				_tray_view.refresh()
			&"combat_won":
				_close_summary("won")
				_show_banner("VICTORY!")
				if run_mode:
					await get_tree().create_timer(1.3).timeout
					Game.combat_finished(true, sim.hero.hp, sim.pending_rewards)
			&"combat_lost":
				_close_summary("lost")
				_show_banner("DEFEAT")
				if run_mode:
					await get_tree().create_timer(1.6).timeout
					Game.combat_finished(false, 0, [])
			&"choice_offered":
				await _offer_choice(event.data)
			&"loan_taken":
				_hero_view.refresh()
				Fx.spawn_number(_hero_view.sprite_center(),
					str(event.data.get("title", "LOAN")), Color(0.85, 0.75, 1.0))
				await get_tree().create_timer(0.3).timeout
			&"loan_ticked":
				_hero_view.refresh()
			&"loan_due":
				Fx.spawn_number(_hero_view.sprite_center(), "DUE!", Color(1.0, 0.55, 0.5))
				_vfx.vignette(0.4, 0.7)
				_hero_view.refresh()
				await get_tree().create_timer(0.3).timeout
			&"chips_absorbed":
				for card in _ability_cards:
					card.refresh()
				_vfx.shockwave(_cabinet.window_rect_global().get_center(),
					Color(0.7, 0.5, 1.0), 200.0)
				Fx.shake(14.0)
				await get_tree().create_timer(0.35).timeout
			&"enemy_busted":
				var busted := _view_of(event.data.actor)
				if busted != null:
					Fx.spawn_number(busted.sprite_center(), "BUST!", Color(1.0, 0.85, 0.4))
					_vfx.shockwave(busted.sprite_center(), Color(1.0, 0.85, 0.4), 150.0)
					busted.refresh_statuses()
				await get_tree().create_timer(0.3).timeout
			&"rage_spent":
				var raging := _view_of(event.data.actor)
				if raging != null:
					raging.refresh_statuses()
			&"passive_counter":
				# An enemy passive ticked (patch 0.113): the plaque it wears as a
				# permanent buff carries the new number and flashes for it.
				var counted := _view_of(event.data.actor)
				if counted != null:
					counted.refresh_statuses()
			&"turn_started", &"turn_ended":
				# Statuses tick per actor now (patch 0.22), so the pips under
				# that unit — and the hero's live ability numbers, which Frail
				# and Weak both move — refresh on its own boundary. Statuses
				# only: snapping HP here is half of what made the bar bounce.
				var ticked := _view_of(event.data.actor)
				if ticked != null:
					ticked.refresh_statuses()
				if event.data.actor == sim.hero.id:
					for card in _ability_cards:
						card.refresh()
			&"round_ended":
				_hero_view.refresh()
				for view: UnitView in _enemy_views.values():
					view.refresh()


## ---- attack animations (doc's Animations table) ----


func _play_ability_anims(ability_id: StringName, target_view: UnitView) -> void:
	var marks := _ability_marks(ability_id)
	for anim: String in ABILITY_ANIMS.get(ability_id, []):
		match anim:
			"card_fling":
				# Ace physically throws: the card leaves his hand on the
				# release frame of the pose animation.
				await _hero_view.play_throw()
				await _fly("res://assets/icons/ability_card_sling.png",
					_hero_view.sprite_center(), _target_point(target_view), marks)
			"dagger":
				# The slash VFX lands ON the strike frame: play_slash() only
				# returns once the lunge has finished (0.09 s after the frame
				# shows), so the arc waits for the pose's own signal instead.
				_hero_view.play_slash()
				await _hero_view.strike_landed
				await _dagger_slash(_target_point(target_view))
			"cash_in":
				await _burst_duo(_target_point(target_view),
					"res://assets/icons/status_mark.png",
					FLAME_COLORS[1], FLAME_COLORS[2])
			"block":
				# The shield-icon + blue-flash burst itself now plays generically
				# off the sim's block_gained event (doc: "Block Gain animation"
				# applies to every source of Block, not just abilities).
				await get_tree().create_timer(0.15).timeout
			"chip":
				await _fly("res://assets/icons/chip_spade.png",
					_hero_view.sprite_center(),
					_tray_view.global_position + _tray_view.size * 0.5, false)
			"mark_wave":
				for view: UnitView in _enemy_views.values():
					_burst_duo(view.sprite_center(), "res://assets/icons/status_mark.png",
						FLAME_COLORS[0], FLAME_COLORS[2])
				await get_tree().create_timer(0.35).timeout
			"go_again":
				await _go_again_flourish()
			"ultimate":
				# _ultimate_flourish already lands the flash, the hitstop and
				# the shockwaves — doing them again here fired everything
				# twice (patch 0.19).
				await _ultimate_flourish()


## True when the ability's animation list drives the hero's own pose frames.
func _has_pose_anim(ability_id: StringName) -> bool:
	for anim: String in ABILITY_ANIMS.get(ability_id, []):
		if anim in ["card_fling", "dagger", "ultimate"]:
			return true
	return false


func _ability_marks(ability_id: StringName) -> bool:
	var def := Db.content.get_ability(ability_id)
	if def == null:
		return false
	for effect: Dictionary in def.effects + def.bonus_effects:
		if str(effect.get("op", "")) == "apply_status" and str(effect.get("status", "")) == "mark":
			return true
	return false


func _target_point(target_view: UnitView) -> Vector2:
	if target_view != null:
		return target_view.sprite_center()
	return Vector2(get_viewport_rect().size.x * 0.7, get_viewport_rect().size.y * 0.35)


## A projectile arcing from -> to with ghost afterimages, facing its velocity
## (Card Fling; flaming when the hit Marks). Straight-and-level is the
## giveaway of flat animation — this one travels.
func _fly(texture_path: String, from: Vector2, to: Vector2, flaming: bool) -> void:
	if not ResourceLoader.exists(texture_path):
		return
	var projectile := TextureRect.new()
	projectile.texture = load(texture_path)
	projectile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	projectile.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	projectile.size = Vector2(72, 72)
	projectile.pivot_offset = Vector2(36, 36)
	projectile.z_index = 90
	if flaming:
		projectile.modulate = FLAME_COLORS[0]
	add_child(projectile)
	var duration := 0.34
	var apex := (from + to) * 0.5 + Vector2(0, -140)  # parabolic arc
	var previous := from
	var tween := create_tween()
	tween.tween_method(func(t: float) -> void:
		var p01 := from.lerp(apex, t)
		var p12 := apex.lerp(to, t)
		var at := p01.lerp(p12, t)
		projectile.global_position = at - Vector2(36, 36)
		projectile.rotation = (at - previous).angle() + PI * 0.25
		if flaming:
			# Blazing with green, teal, and purple flame (doc's "Flaming Card
			# Fling") as the card travels, not a single flat tint.
			projectile.modulate = _flame_color_at(t)
		if Engine.get_frames_drawn() % 2 == 0:
			_vfx.ghost(projectile)
		previous = at, 0.0, 1.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished
	var impact_color := _flame_color_at(1.0) if flaming else Color(1.0, 0.9, 0.6)
	_sparks(to, impact_color)
	_vfx.shockwave(to, impact_color, 80.0)
	projectile.queue_free()


## Interpolates across the green -> teal -> purple flame gradient (t in 0..1).
func _flame_color_at(t: float) -> Color:
	var scaled := clampf(t, 0.0, 1.0) * (FLAME_COLORS.size() - 1)
	var i := int(scaled)
	if i >= FLAME_COLORS.size() - 1:
		return FLAME_COLORS[-1]
	return FLAME_COLORS[i].lerp(FLAME_COLORS[i + 1], scaled - i)


## Ace's dagger slash: a crescent of light that draws itself in along the
## cut in a tenth of a second, hangs for a blink, and dissolves outward with
## a slight turn — angle in radians so a flurry can cut from every side.
## `palette` swaps the bands (the enemy impact uses it in red).
##
## Patch 0.22, both halves of the designer's note. (1) The default sweep is
## rotated a quarter turn CLOCKWISE (+PI/2 with y pointing down) so the cut
## comes down across the target instead of along it. (2) The arc is offset by
## its own belly so the stroke crosses the target: it is drawn on a circle
## centred on the node origin, so pinning the origin to the target put the
## target in the crescent's empty middle — "it goes around it".
func _dagger_slash(at: Vector2, angle := SLASH_ANGLE, palette: Array = [],
		scale_factor := 1.0) -> void:
	var arc := SlashArc.new()
	if not palette.is_empty():
		arc.bands = palette
	arc.radius *= scale_factor
	arc.thickness *= scale_factor
	arc.seed_value = randi() % 1000
	arc.material = _vfx._additive
	arc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arc.z_index = 90
	arc.rotation = angle
	add_child(arc)
	var centring := arc.belly().rotated(angle)
	arc.global_position = at - centring
	# A dim, wider twin behind fakes the bloom the reference's soft edges have.
	var halo := SlashArc.new()
	halo.bands = [Color(arc.bands[0], 0.2), Color(arc.bands[1], 0.14)]
	halo.band_widths = [2.0, 1.25]
	halo.filaments = 0
	halo.radius = arc.radius
	halo.thickness = arc.thickness
	halo.material = _vfx._additive
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	halo.z_index = 89
	halo.rotation = angle
	add_child(halo)
	halo.global_position = at - centring
	_sparks(at, arc.bands[1], 12)
	var tween := create_tween()
	tween.set_parallel(true)
	var draw_in := func(p: float) -> void:
		arc.progress = p
		halo.progress = p
		arc.queue_redraw()
		halo.queue_redraw()
	tween.tween_method(draw_in, 0.0, 1.0, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.chain().tween_interval(0.05)
	var dissolve := func(f: float) -> void:
		arc.fade = f
		halo.fade = f
		arc.queue_redraw()
		halo.queue_redraw()
	tween.chain().tween_method(dissolve, 1.0, 0.0, 0.2).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(arc, "scale", Vector2(1.14, 1.14), 0.2)
	tween.parallel().tween_property(halo, "scale", Vector2(1.3, 1.3), 0.2)
	tween.parallel().tween_property(arc, "rotation", angle + 0.16, 0.2)
	await tween.finished
	arc.queue_free()
	halo.queue_free()


## A symbol swelling and fading at a point (Cash In burst, Block gain...).
func _burst(at: Vector2, texture_path: String, tint: Color) -> void:
	if not ResourceLoader.exists(texture_path):
		return
	var symbol := TextureRect.new()
	symbol.texture = load(texture_path)
	symbol.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	symbol.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	symbol.size = Vector2(80, 80)
	symbol.pivot_offset = Vector2(40, 40)
	symbol.modulate = tint
	symbol.scale = Vector2(0.4, 0.4)
	symbol.z_index = 90
	add_child(symbol)
	symbol.global_position = at - Vector2(40, 40)
	_sparks(at, tint)
	var tween := symbol.create_tween()
	tween.set_parallel(true)
	tween.tween_property(symbol, "scale", Vector2(1.7, 1.7), 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(symbol, "modulate:a", 0.0, 0.4).set_ease(Tween.EASE_IN)
	await tween.finished
	symbol.queue_free()


## Two-tone flash (Cash In doc animation: "bursts in a teal and purple
## flash") — a teal symbol swells first, a purple one a beat behind it.
func _burst_duo(at: Vector2, texture_path: String, tint_a: Color, tint_b: Color) -> void:
	_burst(at, texture_path, tint_a)
	await get_tree().create_timer(0.05).timeout
	await _burst(at, texture_path, tint_b)


## Break (doc "Chip Golem", patch 0.114): the golem drops a chip, and it falls
## into the drawer the same way a paid-out chip does. Deliberately the same
## flight as `_payout_flourish` so a chip arriving always looks like a chip
## arriving, wherever it came from.
func _golem_drops_chip(suit: StringName) -> void:
	var golem: UnitView = null
	for view: UnitView in _enemy_views.values():
		if is_instance_valid(view) and view.actor != null \
			and view.actor.def_id == &"chip_golem":
			golem = view
			break
	if golem == null:
		return
	var texture := SuitAssets.chip_texture(suit)
	if texture == null:
		return
	var from := golem.sprite_center()
	var chip := TextureRect.new()
	chip.texture = texture
	chip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	chip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	chip.size = Vector2(54, 54)
	chip.pivot_offset = Vector2(27, 27)
	chip.z_index = 88
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(chip)
	chip.global_position = from - Vector2(27, 27)
	golem.play_hit()
	_sparks(from, Color(0.75, 0.9, 1.0), 8)
	var drawer := _cabinet.drawer_centre_global() - Vector2(27, 27)
	var fall := create_tween()
	fall.set_parallel(true)
	# Shed downward first, so it reads as falling OFF the golem...
	fall.tween_property(chip, "global_position",
		chip.global_position + Vector2(0, 70), 0.20) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.tween_property(chip, "rotation", TAU * 0.6, 0.20)
	# ...then across into the drawer.
	fall.chain().tween_property(chip, "global_position", drawer, 0.42) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.parallel().tween_property(chip, "rotation", TAU * 1.6, 0.42)
	await fall.finished
	_sparks(_cabinet.drawer_centre_global(), Color(1.0, 0.9, 0.6), 6)
	_cabinet.celebrate(0.7)
	chip.queue_free()


## Go Again (doc animation): the Slot Machine shakes in joy, and the
## End Turn button flips over to read "Go Again!" for a beat.
func _go_again_flourish() -> void:
	await _burst(_cabinet.window_rect_global().get_center(),
		"res://assets/icons/coin.png", Color(1.3, 1.15, 0.6))
	_cabinet.celebrate(1.4)
	_cabinet.shake()

	var original_text := _end_turn.text
	_end_turn.pivot_offset = _end_turn.size * 0.5
	var flip := create_tween()
	flip.tween_property(_end_turn, "scale:x", 0.0, 0.08).set_ease(Tween.EASE_IN)
	flip.tween_callback(func() -> void: _end_turn.text = "Go Again!")
	flip.tween_property(_end_turn, "scale:x", 1.0, 0.1) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await flip.finished
	await get_tree().create_timer(1.0).timeout
	if not is_instance_valid(_end_turn):
		return
	var flip_back := create_tween()
	flip_back.tween_property(_end_turn, "scale:x", 0.0, 0.08).set_ease(Tween.EASE_IN)
	flip_back.tween_callback(func() -> void: _end_turn.text = original_text)
	flip_back.tween_property(_end_turn, "scale:x", 1.0, 0.1) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Ultimate Animation (doc): Flush leads with a streak of paint crossing the
## screen and a close-up of Ace's face, fading quickly — then the actual
## multi-hit flurry (lights dim, time slows, the cuts land, detonation).
func _ultimate_flourish() -> void:
	await _splash_cut_in()
	_vfx.vignette(0.6, 1.3)
	Engine.time_scale = 0.65
	Fx.shake(22.0)
	_hero_view.play_slash()
	await _hero_view.strike_landed
	# Eight cuts from eight directions, a beat apart, over every living enemy.
	var angles := ULTIMATE_ANGLES
	var cut := 0
	for view: UnitView in _enemy_views.values():
		if not is_instance_valid(view):
			continue
		for i in 2:
			var offset := Vector2(randf_range(-26, 26), randf_range(-20, 20))
			_dagger_slash(view.sprite_center() + offset, angles[cut % angles.size()], [], 1.15)
			cut += 1
			await get_tree().create_timer(0.07).timeout
	await get_tree().create_timer(0.24).timeout
	# Restored unconditionally: a slow-mo leak would drag the whole run.
	Engine.time_scale = 1.0
	_vfx.screen_flash(0.4)
	Fx.punch_zoom(0.06)
	Fx.hitstop(0.1)
	for view: UnitView in _enemy_views.values():
		_vfx.shockwave(view.sprite_center(), Color(0.6, 0.95, 1.0), 160.0)


## The cut-in itself (designer's call, 0.20/0.0.111; rebuilt in 0.113): the
## purpose-drawn splash of Ace's eyes (`ace_flush_splash.png`) FILLS THE WHOLE
## SCREEN, wiped in from left to right behind a bright leading edge, held on
## his face, then wiped away the same way. The purple-pink geometric tear that
## used to sit behind it is gone at the designer's request.
##
## The wipe is a clipping mask whose width grows across the viewport while the
## art inside it stays perfectly still, so the image is REVEALED left to right
## rather than flown in — sliding a full-bleed image across would read as a pan.
## Falls back to the old procedural band and portrait crop if the art is
## missing, so a fresh checkout without generated art still plays something.
func _splash_cut_in() -> void:
	var splash_path := "res://assets/characters/ace_flush_splash.png"
	if not ResourceLoader.exists(splash_path):
		await _paint_streak_closeup()
		return
	var viewport_size := get_viewport_rect().size
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.z_index = 95
	add_child(layer)

	var mask := Control.new()
	mask.clip_contents = true
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask.position = Vector2.ZERO
	mask.size = Vector2(0.0, viewport_size.y)
	layer.add_child(mask)

	var splash := TextureRect.new()
	splash.texture = load(splash_path)
	splash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# COVERED, not CENTERED: the art reaches every edge instead of leaving the
	# combat screen showing above and below it.
	splash.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	splash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	splash.position = Vector2.ZERO
	splash.size = viewport_size
	mask.add_child(splash)

	# The wipe's leading edge: a bright blade running just ahead of the art.
	var edge := ColorRect.new()
	edge.color = Color(0.55, 1.0, 0.92, 0.9)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge.size = Vector2(16.0, viewport_size.y)
	edge.position = Vector2.ZERO
	layer.add_child(edge)

	Fx.shake(16.0)
	Fx.punch_zoom(0.05)
	_vfx.screen_flash(0.5)
	var sweep := create_tween()
	sweep.set_parallel(true)
	sweep.tween_property(mask, "size:x", viewport_size.x, 0.30) \
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	sweep.tween_property(edge, "position:x", viewport_size.x, 0.30) \
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	sweep.tween_property(edge, "modulate:a", 0.0, 0.30).set_delay(0.16)
	await sweep.finished
	_vfx.ray_burst(viewport_size * 0.5, Color(0.35, 1.0, 0.88, 0.35), 520.0, 0.5)
	await get_tree().create_timer(0.42).timeout   # hold on his eyes
	# Away the same way: the mask's left edge chases its right one off screen
	# while the art counter-moves, so the picture stays pinned as it is uncovered.
	var whip := create_tween()
	whip.set_parallel(true)
	whip.tween_property(mask, "position:x", viewport_size.x, 0.20) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	whip.tween_property(mask, "size:x", 0.0, 0.20) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	whip.tween_property(splash, "position:x", -viewport_size.x, 0.20) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	whip.tween_property(layer, "modulate:a", 0.0, 0.18).set_delay(0.06)
	await whip.finished
	layer.queue_free()


## Fallback cut-in when the generated splash art is missing: a procedural
## torn band with the talking-head portrait cropped to the eyes (0.19).
func _paint_streak_closeup() -> void:
	var viewport_size := get_viewport_rect().size
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.z_index = 95
	add_child(layer)

	var band_size := Vector2(viewport_size.x * 2.0, 340)
	# The tear can bite this far in from either edge, so the close-up is inset
	# by exactly that much and is never cut by it — the band frames the face.
	var tear_bite := band_size.y * 0.22
	var band_pos := Vector2(-viewport_size.x, viewport_size.y * 0.40)
	var tear_seed := 21

	# Behind: a wider purple tear, offset, so the slash has depth.
	var band_back := PaintStreak.new()
	band_back.streak_color = Color(0.48, 0.20, 0.85)
	band_back.seed_value = 7
	band_back.size = band_size + Vector2(0, 80)
	band_back.pivot_offset = band_back.size * 0.5
	band_back.rotation = -0.20
	band_back.position = band_pos - Vector2(0, 40)
	layer.add_child(band_back)

	var band := PaintStreak.new()
	band.streak_color = Color(0.10, 0.42, 0.38)
	band.seed_value = tear_seed
	band.size = band_size
	band.pivot_offset = band_size * 0.5
	band.rotation = -0.17
	band.position = band_pos
	layer.add_child(band)

	# The close-up and the edge overlay are CHILDREN of the band, so they
	# inherit its rotation and pivot exactly. Rotating them independently put
	# their corners outside the tear (they rotate about their own centres).
	var clip := Control.new()
	clip.clip_contents = true
	clip.size = Vector2(viewport_size.x * 0.34, band_size.y - tear_bite * 2.0)
	clip.position = Vector2(viewport_size.x * 0.735, tear_bite)
	clip.modulate.a = 0.0
	band.add_child(clip)
	var portrait_path := "res://assets/characters/ace_portrait.png"
	if not ResourceLoader.exists(portrait_path):
		portrait_path = "res://assets/characters/ace_idle.png"
	if ResourceLoader.exists(portrait_path):
		var portrait := TextureRect.new()
		portrait.texture = load(portrait_path)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		# Blown up well past the window and pulled up, so the slice showing
		# through the tear is his eyes — the reference's framing.
		var blown := clip.size.x * 2.2
		portrait.size = Vector2(blown, blown)
		portrait.position = Vector2(-blown * 0.30, -blown * 0.22)
		clip.add_child(portrait)

	# The same tear, edges only, laid back over the portrait.
	var edge := PaintStreak.new()
	edge.streak_color = Color(0.10, 0.42, 0.38)
	edge.seed_value = tear_seed
	edge.fill_alpha = 0.0
	edge.size = band_size
	band.add_child(edge)

	Fx.shake(16.0)
	Fx.punch_zoom(0.05)
	_vfx.screen_flash(0.5)
	var sweep := create_tween()
	sweep.set_parallel(true)
	sweep.tween_property(band_back, "position:x", -viewport_size.x * 0.52, 0.30) 		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	sweep.tween_property(band, "position:x", -viewport_size.x * 0.5, 0.26) 		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	sweep.tween_property(clip, "modulate:a", 1.0, 0.12).set_delay(0.08)
	await sweep.finished
	await get_tree().create_timer(0.18).timeout   # hold on his face
	var fade := create_tween()
	fade.tween_property(layer, "modulate:a", 0.0, 0.16)
	await fade.finished
	layer.queue_free()


## Balatro rule: never pay the total at once. Each landed symbol's chip flies
## from its reel to the tray on its own beat; a three-of-a-kind detonates a
## jackpot of rays and confetti.
func _payout_flourish(symbols: Array) -> void:
	# Each chip leaves the reel that actually paid it and falls into the
	# cabinet's drawer (patch 0.22; before, they fanned out from the panel's
	# top-left corner on a uniform step that only lined up with the reels when
	# the row happened to fill the panel).
	var window := _cabinet.window_rect_global()
	var tray_center := _cabinet.drawer_centre_global()
	_cabinet.celebrate(1.0)
	var triple: bool = symbols.size() >= 3 and symbols[0] == symbols[1] and symbols[1] == symbols[2]
	if triple:
		_vfx.ray_burst(window.get_center(), Color(1.0, 0.9, 0.4, 0.6), 220.0, 0.9)
		_vfx.confetti(Vector2(window.get_center().x, window.position.y))
		Fx.punch_zoom(0.04)
		Fx.shake(10.0)
	for i in symbols.size():
		var chip_path := "res://assets/icons/chip_%s.png" % symbols[i]
		if not ResourceLoader.exists(chip_path):
			continue
		var chip := TextureRect.new()
		chip.texture = load(chip_path)
		chip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		chip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		chip.size = Vector2(56, 56)
		chip.pivot_offset = Vector2(28, 28)
		chip.z_index = 92
		add_child(chip)
		chip.global_position = _reel_strip.reel_centre(i) - Vector2(28, 28)
		chip.scale = Vector2(0.4, 0.4)
		var hop := chip.create_tween()
		hop.tween_property(chip, "scale", Vector2.ONE, 0.12) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		hop.set_parallel(true)
		hop.tween_property(chip, "global_position", tray_center - Vector2(28, 28), 0.24) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		hop.tween_property(chip, "rotation", TAU, 0.24)
		hop.chain().tween_callback(func() -> void:
			_sparks(tray_center, Color(1.0, 0.9, 0.6), 6)
			_tray_view.refresh()
			chip.queue_free())
		await get_tree().create_timer(0.09).timeout  # one payoff per beat
	await get_tree().create_timer(0.22).timeout


## A one-shot spark puff — the VFX layer under every hit and burst (patch 0.13).
func _sparks(at: Vector2, color: Color, amount := 14) -> void:
	var particles := CPUParticles2D.new()
	particles.one_shot = true
	particles.emitting = true
	particles.amount = amount
	particles.lifetime = 0.5
	particles.explosiveness = 0.9
	particles.direction = Vector2.UP
	particles.spread = 180.0
	particles.initial_velocity_min = 120.0
	particles.initial_velocity_max = 260.0
	particles.gravity = Vector2(0, 500)
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 5.0
	particles.color = color
	particles.z_index = 95
	add_child(particles)
	particles.global_position = at
	get_tree().create_timer(0.8).timeout.connect(particles.queue_free)


## Enemy hits land with a visible strike swipe on Ace (patch 0.12) — the same
## drawn crescent as the Dagger Slash, in red and orange, smaller and cut the
## other way, so the two vocabularies match (0.0.111).
func _impact(at: Vector2) -> void:
	_dagger_slash(at, IMPACT_ANGLE + randf_range(-0.3, 0.3),
		[Color(1.0, 0.25, 0.2, 0.75), Color(1.0, 0.6, 0.3, 0.95), Color(1.0, 0.95, 0.85, 1.0)],
		0.68)


func _show_banner(text: String) -> void:
	_banner.text = text
	_banner.visible = true
	var center := get_viewport_rect().size * 0.5
	# The pivot has to be read after the layout pass that setting .text kicks
	# off, or the pop-in scales around the wrong point.
	await get_tree().process_frame
	_banner.pivot_offset = _banner.size * 0.5
	_banner.scale = Vector2(0.3, 0.3)
	if text.begins_with("VICTORY"):
		_vfx.ray_burst(center, Color(1.0, 0.9, 0.5, 0.5), 320.0, 1.2)
		_vfx.confetti(center + Vector2(-220, -60), 30)
		_vfx.confetti(center + Vector2(220, -60), 30)
		_vfx.screen_flash(0.3)
		Fx.punch_zoom(0.05)
	else:
		_vfx.vignette(0.55, 1.2)
	var tween := _banner.create_tween()
	tween.tween_property(_banner, "scale", Vector2.ONE, 0.5) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_end_turn.disabled = true
