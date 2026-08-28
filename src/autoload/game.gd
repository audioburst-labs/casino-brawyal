extends Node
## Autoload: run flow. Owns the active RunState and routes between screens.
## Encounter #1 auto-starts as combat; #10 is the boss; everything else goes
## through the map choice screen.

const ACE_INTRO_VIDEO := "res://assets/video/ace_intro.ogv"
const BOSS_INTRO_VIDEO := "res://assets/video/moneyman_boss_intro.ogv"

var run: RunState
var rng: GameRng

## Run duration, for the header Timer (doc: "does not include the videos").
var run_elapsed_sec := 0.0
var cinematic_playing := false

var _screen_root: Node = null
var _combat_gold := Vector2i.ZERO   # gold range of the lineup being fought


func register_screen_root(root: Node) -> void:
	_screen_root = root


func goto_screen(scene_path: String, args: Dictionary = {}) -> void:
	assert(_screen_root != null, "Main scene must register its ScreenRoot before navigation.")
	for child in _screen_root.get_children():
		# Detach immediately so the incoming screen never collides with the
		# outgoing one (same-name siblings get auto-renamed by Godot).
		_screen_root.remove_child(child)
		child.queue_free()
	var screen: Node = load(scene_path).instantiate()
	_screen_root.add_child(screen)
	if not args.is_empty() and screen.has_method("setup"):
		screen.setup(args)


func new_run(seed_value: int = -1, skip_cinematic := false) -> void:
	var run_seed := seed_value if seed_value >= 0 else (randi() % 1_000_000_000)
	run = RunState.new()
	run.seed_value = run_seed
	run_elapsed_sec = 0.0
	rng = GameRng.new(run_seed)
	var hero := Db.content.get_hero(run.hero_id)
	run.max_hp = hero.max_hp
	run.hp = hero.max_hp
	for ability_id in hero.starting_abilities:
		run.acquire_ability(ability_id)
	if skip_cinematic:
		choose_encounter({"type": &"combat"})
	else:
		play_cinematic(ACE_INTRO_VIDEO,
			func() -> void: choose_encounter({"type": &"combat"}))


var _cached_options: Array[Dictionary] = []
var _cached_for_encounter := -1


func show_map() -> void:
	RunSave.save_run(run)
	goto_screen("res://scenes/screens/map_screen.tscn")


func continue_run() -> bool:
	var loaded := RunSave.load_run()
	if loaded == null:
		return false
	run = loaded
	run_elapsed_sec = 0.0
	# Salt the RNG with progress so a reloaded run doesn't replay identical draws.
	rng = GameRng.new(run.seed_value + run.history.size() * 7919)
	goto_screen("res://scenes/screens/map_screen.tscn")
	return true


## The offered pair is rolled once per encounter and cached, so detours
## (e.g. the Abilities screen) don't re-roll the choice (patch 0.12).
func map_options() -> Array[Dictionary]:
	if _cached_for_encounter != run.encounter_number():
		_cached_options = MapGenerator.next_options(run, rng.stream(&"map"))
		_cached_for_encounter = run.encounter_number()
	return _cached_options


func choose_encounter(option: Dictionary) -> void:
	run.record_visit(option.type)
	match option.type:
		&"combat", &"hard_combat", &"boss":
			run.process_trash()  # the trash slot empties when combat begins
			_start_combat(option)
		&"story":
			goto_screen("res://scenes/screens/story_screen.tscn", {"event": _pick_story_event()})
		&"rest":
			goto_screen("res://scenes/screens/rest_screen.tscn")
		&"treasure":
			goto_screen("res://scenes/screens/treasure_screen.tscn")
		&"casino":
			goto_screen("res://scenes/screens/casino_screen.tscn")
		&"shop":
			goto_screen("res://scenes/screens/shop_screen.tscn")


func show_loadout() -> void:
	goto_screen("res://scenes/screens/loadout_screen.tscn")


## Called by non-combat encounter screens when the player is done; detours
## through the loadout screen when a new acquisition overflowed Equipped.
func _after_encounter() -> void:
	if run.needs_loadout:
		run.needs_loadout = false
		show_loadout()
	else:
		show_map()


## Called by non-combat encounter screens when the player is done.
func encounter_finished() -> void:
	_after_encounter()


func combat_finished(won: bool, hero_hp: int, pending_rewards: Array) -> void:
	if not won:
		RunSave.clear()
		goto_screen("res://scenes/screens/game_over_screen.tscn")
		return
	run.hp = maxi(1, hero_hp)
	RunEffects.apply(pending_rewards, Db.content, run, rng.stream(&"rewards"))
	if run.last_visited() == &"boss":
		RunSave.clear()
		goto_screen("res://scenes/screens/victory_screen.tscn")
	else:
		goto_screen("res://scenes/screens/reward_screen.tscn", {
			"gold_min": _combat_gold.x,
			"gold_max": _combat_gold.y,
			"hard": run.last_visited() == &"hard_combat",
		})


func _start_combat(option: Dictionary) -> void:
	var config := EncounterFactory.combat_config(Db.content, run,
		rng.stream(&"map"), option)
	config["seed"] = rng.stream(&"combat_seeds").randi()
	config["run_mode"] = true
	_combat_gold = Vector2i(int(config.gold_min), int(config.gold_max))
	var start := func() -> void:
		goto_screen("res://scenes/screens/combat_screen.tscn", config)
	if option.type == &"boss":
		play_cinematic(BOSS_INTRO_VIDEO, start)
	else:
		start.call()


## Fullscreen skippable video overlay. Calls on_done immediately when the
## clip is missing (HeyGen videos are optional polish) or when running
## headless (tests/CI can't play video).
func play_cinematic(path: String, on_done: Callable) -> void:
	if not ResourceLoader.exists(path) or DisplayServer.get_name() == "headless":
		on_done.call()
		return
	cinematic_playing = true
	var layer := CanvasLayer.new()
	layer.layer = 50
	var backdrop := ColorRect.new()
	backdrop.color = Color.BLACK
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(backdrop)
	var player := VideoStreamPlayer.new()
	player.stream = load(path)
	player.expand = true
	player.autoplay = true
	player.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(player)
	var finish := func() -> void:
		if is_instance_valid(layer):
			layer.queue_free()
			cinematic_playing = false
			on_done.call()
	player.finished.connect(finish)
	backdrop.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			finish.call())

	# Explicit Skip and Mute controls (patch 0.11).
	var controls := HBoxContainer.new()
	controls.anchor_left = 0.8
	controls.anchor_top = 0.9
	controls.anchor_right = 0.98
	controls.anchor_bottom = 0.98
	controls.alignment = BoxContainer.ALIGNMENT_END
	controls.add_theme_constant_override("separation", 12)
	layer.add_child(controls)
	var mute := Button.new()
	mute.text = "🔊"
	mute.tooltip_text = "Mute"
	mute.pressed.connect(func() -> void:
		var muted := player.volume_db > -70.0
		player.volume_db = -80.0 if muted else 0.0
		mute.text = "🔇" if muted else "🔊")
	controls.add_child(mute)
	var skip := Button.new()
	skip.text = "Skip ▶"
	skip.pressed.connect(finish)
	controls.add_child(skip)

	get_tree().root.add_child(layer)


func _pick_story_event() -> StringName:
	var unseen: Array[StringName] = []
	for id: StringName in Db.content.all_story_event_ids():
		if not run.seen_events.has(id):
			unseen.append(id)
	if unseen.is_empty():
		for id: StringName in Db.content.all_story_event_ids():
			unseen.append(id)
	var picked := unseen[rng.stream(&"map").randi_range(0, unseen.size() - 1)]
	run.seen_events.append(picked)
	return picked
