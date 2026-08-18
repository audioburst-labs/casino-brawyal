extends Node
## Autoload: run flow. Owns the active RunState and routes between screens.
## Encounter #1 auto-starts as combat; #10 is the boss; everything else goes
## through the map choice screen.

const ACE_INTRO_VIDEO := "res://assets/video/ace_intro.ogv"
const BOSS_INTRO_VIDEO := "res://assets/video/moneyman_boss_intro.ogv"

var run: RunState
var rng: GameRng

var _screen_root: Node = null


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


func new_run(seed_value: int = -1) -> void:
	var run_seed := seed_value if seed_value >= 0 else (randi() % 1_000_000_000)
	run = RunState.new()
	run.seed_value = run_seed
	rng = GameRng.new(run_seed)
	var hero := Db.content.get_hero(run.hero_id)
	run.max_hp = hero.max_hp
	run.hp = hero.max_hp
	run.ability_ids = hero.starting_abilities.duplicate()
	play_cinematic(ACE_INTRO_VIDEO,
		func() -> void: choose_encounter({"type": &"combat"}))


func show_map() -> void:
	RunSave.save_run(run)
	goto_screen("res://scenes/screens/map_screen.tscn")


func continue_run() -> bool:
	var loaded := RunSave.load_run()
	if loaded == null:
		return false
	run = loaded
	# Salt the RNG with progress so a reloaded run doesn't replay identical draws.
	rng = GameRng.new(run.seed_value + run.history.size() * 7919)
	goto_screen("res://scenes/screens/map_screen.tscn")
	return true


func map_options() -> Array[Dictionary]:
	return MapGenerator.next_options(run, rng.stream(&"map"))


func choose_encounter(option: Dictionary) -> void:
	run.record_visit(option.type)
	match option.type:
		&"combat", &"hard_combat", &"boss":
			_start_combat(option)
		&"story":
			goto_screen("res://scenes/screens/story_screen.tscn", {"event": _pick_story_event()})
		&"rest":
			goto_screen("res://scenes/screens/rest_screen.tscn")
		&"treasure":
			goto_screen("res://scenes/screens/treasure_screen.tscn")
		&"shop":
			goto_screen("res://scenes/screens/shop_screen.tscn")


## Called by non-combat encounter screens when the player is done.
func encounter_finished() -> void:
	show_map()


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
			"encounter": run.history.size(),
			"hard": run.last_visited() == &"hard_combat",
		})


func _start_combat(option: Dictionary) -> void:
	var config := EncounterFactory.combat_config(Db.content, run,
		rng.stream(&"map"), option)
	config["seed"] = rng.stream(&"combat_seeds").randi()
	config["run_mode"] = true
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
	var hint := Label.new()
	hint.text = "click to skip"
	hint.anchor_left = 0.85
	hint.anchor_top = 0.94
	hint.anchor_right = 0.99
	hint.anchor_bottom = 0.99
	layer.add_child(hint)
	var finish := func() -> void:
		if is_instance_valid(layer):
			layer.queue_free()
			on_done.call()
	player.finished.connect(finish)
	backdrop.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			finish.call())
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
