extends Control
## Combat screen presenter: owns a CombatSim, forwards player input as sim
## commands, and animates the sim's event queue. All rules live in the sim.

const ENEMY_GAP := 24

var sim: CombatSim
var run_mode := false   # true when launched by Game flow (reports results back)

var _background: TextureRect
var _round_label: Label
var _banner: Label
var _hero_view: UnitView
var _enemy_views: Dictionary = {}   # actor id -> UnitView
var _enemies_row: HBoxContainer
var _reel_strip: ReelStrip
var _tray_view: ChipTrayView
var _ability_row: HBoxContainer
var _ability_cards: Array[AbilityCard] = []
var _end_turn: Button
var _busy := false


func _ready() -> void:
	_build_layout()
	if get_tree().current_scene == self:
		# Standalone debug launch: a fixed fight with everything unlocked.
		# CB_DEBUG_ENEMIES="dealer,dealer,..." overrides the lineup.
		var enemies: Array = ["bouncer", "server"]
		var override := OS.get_environment("CB_DEBUG_ENEMIES")
		if override != "":
			enemies = override.split(",")
		setup({
			"hero": "ace",
			"abilities": ["card_sling", "quick_maneuvers", "color_up", "double_down"],
			"enemies": enemies,
			"seed": randi(),
		})


func setup(config: Dictionary) -> void:
	run_mode = config.get("run_mode", false)
	sim = CombatSim.new(Db.content, config)
	_spawn_units()
	_spawn_abilities()
	_reel_strip.set_reel_count(sim.machine.reels.size())
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
	add_child(_background)

	_round_label = Label.new()
	_round_label.theme_type_variation = &"SubtitleLabel"
	_round_label.position = Vector2(40, 24)
	add_child(_round_label)

	if Game.run != null:
		var hud := HBoxContainer.new()
		hud.anchor_left = 0.55
		hud.anchor_right = 0.99
		hud.anchor_top = 0.0
		hud.anchor_bottom = 0.05
		hud.alignment = BoxContainer.ALIGNMENT_END
		hud.add_theme_constant_override("separation", 10)
		add_child(hud)
		for relic_id in Game.run.relic_ids:
			var relic := Db.content.get_relic(relic_id)
			var icon_path := "res://assets/icons/relic_%s.png" % relic_id
			if ResourceLoader.exists(icon_path):
				var icon := TextureRect.new()
				icon.texture = load(icon_path)
				icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				icon.custom_minimum_size = Vector2(44, 44)
				icon.tooltip_text = "%s — %s" % [relic.name, relic.description]
				hud.add_child(icon)
			else:
				var chip := Label.new()
				chip.text = "[%s]" % relic.name
				chip.tooltip_text = relic.description
				hud.add_child(chip)
		var coins := Label.new()
		coins.theme_type_variation = &"SubtitleLabel"
		coins.text = "  🪙 %d   Encounter %d/10" % [Game.run.coins, Game.run.history.size()]
		hud.add_child(coins)

	_enemies_row = HBoxContainer.new()
	_enemies_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_enemies_row.add_theme_constant_override("separation", ENEMY_GAP)
	_enemies_row.anchor_left = 0.42
	_enemies_row.anchor_right = 0.99
	_enemies_row.anchor_top = 0.04
	_enemies_row.anchor_bottom = 0.66
	add_child(_enemies_row)

	var bottom := HBoxContainer.new()
	bottom.anchor_left = 0.01
	bottom.anchor_right = 0.99
	bottom.anchor_top = 0.68
	bottom.anchor_bottom = 0.99
	bottom.add_theme_constant_override("separation", 18)
	add_child(bottom)

	var machine_box := VBoxContainer.new()
	machine_box.alignment = BoxContainer.ALIGNMENT_CENTER
	machine_box.add_theme_constant_override("separation", 10)
	bottom.add_child(machine_box)
	_reel_strip = ReelStrip.new()
	machine_box.add_child(_reel_strip)
	_tray_view = ChipTrayView.new()
	machine_box.add_child(_tray_view)

	_ability_row = HBoxContainer.new()
	_ability_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_ability_row.add_theme_constant_override("separation", 12)
	_ability_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_ability_row)

	# End Turn lives in its own corner, off the ability line (patch 0.11).
	_end_turn = Button.new()
	_end_turn.text = "End Turn"
	_end_turn.pressed.connect(_on_end_turn)
	_end_turn.anchor_left = 1.0
	_end_turn.anchor_right = 1.0
	_end_turn.anchor_top = 1.0
	_end_turn.anchor_bottom = 1.0
	_end_turn.offset_left = -220
	_end_turn.offset_right = -24
	_end_turn.offset_top = -84
	_end_turn.offset_bottom = -20
	add_child(_end_turn)

	# Hero stands between the machine and the enemies.
	_banner = Label.new()
	_banner.theme_type_variation = &"TitleLabel"
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.visible = false
	add_child(_banner)


func _spawn_units() -> void:
	_hero_view = UnitView.new()
	_hero_view.anchor_left = 0.05
	_hero_view.anchor_right = 0.28
	_hero_view.anchor_top = 0.04
	_hero_view.anchor_bottom = 0.66
	add_child(_hero_view)
	move_child(_banner, get_child_count() - 1)
	_hero_view.setup(sim.hero)

	for enemy in sim.enemies:
		var view := UnitView.new()
		view.sprite_height = _unit_height()
		_enemies_row.add_child(view)
		view.setup(enemy)
		view.apply_height(_unit_height())  # also shrinks the panel width
		view.clicked.connect(_on_unit_clicked)
		_enemy_views[enemy.id] = view
	_update_target_markers()


## Enemies shrink as the lineup grows so 4-5 fighters still fit (patch 0.11).
func _unit_height() -> float:
	return clampf(430.0 - 55.0 * maxf(0.0, sim.enemies.size() - 2), 240.0, 430.0)


func _spawn_abilities() -> void:
	for index in sim.abilities.size():
		var card := AbilityCard.new()
		_ability_row.add_child(card)
		card.setup(sim.abilities[index], index)
		card.socket_clicked.connect(_on_socket_clicked)
		card.chip_dropped.connect(_on_chip_dropped)
		_ability_cards.append(card)


func _next_round() -> void:
	_busy = true
	sim.begin_round()
	await _play_events(sim.drain_events())
	_busy = false
	_refresh_all()


## Chips arrive by drag-and-drop only (patch 0.11); clicking a filled socket
## returns its chip to the tray.
func _on_socket_clicked(ability_index: int, slot_index: int) -> void:
	if _busy or sim.phase != CombatSim.Phase.ASSIGNMENT:
		return
	if sim.unassign_chip(ability_index, slot_index):
		sim.drain_events()
		_refresh_all()


func _on_chip_dropped(ability_index: int, slot_index: int, suit: StringName) -> void:
	if _busy or sim.phase != CombatSim.Phase.ASSIGNMENT:
		return
	if sim.assign_chip(suit, ability_index, slot_index):
		_busy = true
		await _play_events(sim.drain_events())
		_busy = false
		_refresh_all()


func _on_unit_clicked(actor_id: StringName) -> void:
	if not _enemy_views.has(actor_id):
		return
	sim.set_target(actor_id)
	_update_target_markers()


func _on_end_turn() -> void:
	if _busy or sim.phase != CombatSim.Phase.ASSIGNMENT:
		return
	_busy = true
	sim.end_assignment()
	await _play_events(sim.drain_events())
	_busy = false
	if sim.phase == CombatSim.Phase.ROUND_START:
		_next_round()


func _refresh_all() -> void:
	_hero_view.refresh()
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


func _view_of(actor_id: StringName) -> UnitView:
	if actor_id == sim.hero.id:
		return _hero_view
	return _enemy_views.get(actor_id)


func _card_of(ability_id: StringName) -> AbilityCard:
	for card in _ability_cards:
		if card.ability_index >= 0 and sim.abilities[card.ability_index].def.id == ability_id:
			return card
	return null


func _add_enemy_view(actor_id: StringName) -> void:
	for enemy in sim.enemies:
		if enemy.id == actor_id and not _enemy_views.has(actor_id):
			var view := UnitView.new()
			view.sprite_height = _unit_height()
			_enemies_row.add_child(view)
			view.setup(enemy)
			view.clicked.connect(_on_unit_clicked)
			view.modulate.a = 0.0
			view.create_tween().tween_property(view, "modulate:a", 1.0, 0.4)
			_enemy_views[actor_id] = view
	# Re-fit the whole row to the new crowd size.
	for view: UnitView in _enemy_views.values():
		view.apply_height(_unit_height())


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
				await _reel_strip.spin_to(event.data.symbols)
				_tray_view.refresh()
			&"chips_generated", &"chips_converted":
				_tray_view.refresh()
			&"chip_assigned":
				# Paint the chip into its socket immediately so the final chip
				# is visible before the ability fires (patch 0.1).
				var assigned_card := _card_of(event.data.ability)
				if assigned_card != null:
					assigned_card.show_chip(event.data.slot, event.data.suit)
				_tray_view.refresh()
			&"chip_unassigned":
				_tray_view.refresh()
			&"ability_fired":
				await get_tree().create_timer(0.3).timeout  # let the last chip be seen
				var fired_card := _card_of(event.data.ability)
				if fired_card != null:
					fired_card.flash_fire()
				_hero_view.play_lunge()
				await get_tree().create_timer(0.18).timeout
			&"passive_gained":
				var passive_card := _card_of(event.data.ability)
				if passive_card != null:
					passive_card.flash_fire()
				await get_tree().create_timer(0.2).timeout
			&"enemy_summoned":
				_add_enemy_view(event.data.actor)
				Fx.shake(8.0)
				await get_tree().create_timer(0.35).timeout
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
				if target != null:
					target.play_hit()
					target.refresh()
					Fx.spawn_number(target.sprite_center(), str(event.data.amount))
				Fx.shake(clampf(event.data.amount * 1.2, 4.0, 18.0))
				await get_tree().create_timer(0.3).timeout
			&"block_gained":
				var actor_view := _view_of(event.data.actor)
				if actor_view != null:
					actor_view.refresh()
					Fx.spawn_number(actor_view.sprite_center(),
						"+%d" % event.data.amount, Color(0.6, 0.85, 1.0))
				await get_tree().create_timer(0.15).timeout
			&"status_applied":
				var status_view := _view_of(event.data.actor)
				if status_view != null:
					status_view.refresh()
					Fx.spawn_number(status_view.sprite_center(),
						"%s %d" % [event.data.status, event.data.stacks],
						Color(0.85, 0.7, 1.0))
				await get_tree().create_timer(0.15).timeout
			&"healed":
				var healed_view := _view_of(event.data.actor)
				if healed_view != null:
					healed_view.refresh()
					Fx.spawn_number(healed_view.sprite_center(),
						"+%d" % event.data.amount, Color(0.5, 0.95, 0.55))
			&"actor_died":
				var dead_view := _view_of(event.data.actor)
				if dead_view != null:
					dead_view.play_death()
					dead_view.clear_intent()
				Fx.hitstop()
				await get_tree().create_timer(0.35).timeout
				_update_target_markers()
			&"enemy_move":
				var mover := _view_of(event.data.actor)
				if mover != null and not event.data.get("skipped", false):
					mover.play_lunge()
					mover.clear_intent()
					await get_tree().create_timer(0.15).timeout
			&"chips_discarded":
				_tray_view.refresh()
			&"combat_won":
				_show_banner("VICTORY!")
				if run_mode:
					await get_tree().create_timer(1.3).timeout
					Game.combat_finished(true, sim.hero.hp, sim.pending_rewards)
			&"combat_lost":
				_show_banner("DEFEAT")
				if run_mode:
					await get_tree().create_timer(1.6).timeout
					Game.combat_finished(false, 0, [])
			&"round_ended":
				_hero_view.refresh()
				for view: UnitView in _enemy_views.values():
					view.refresh()


func _show_banner(text: String) -> void:
	_banner.text = text
	_banner.visible = true
	_banner.scale = Vector2(0.3, 0.3)
	_banner.pivot_offset = _banner.size * 0.5
	var tween := _banner.create_tween()
	tween.tween_property(_banner, "scale", Vector2.ONE, 0.5) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_end_turn.disabled = true
