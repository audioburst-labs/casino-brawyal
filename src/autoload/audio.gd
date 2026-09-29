extends Node
## Autoload: music, ambience and sound effects (patch 0.120).
##
## Rules this file keeps:
##
## 1. **Every id comes from `SoundBank`** (`src/core/audio/`). An unknown id or
##    a missing file is a silent no-op, so the game runs before every asset
##    exists and a typo cannot throw inside an awaited presenter handler (the
##    `_busy` freeze, 0.118).
## 2. **Inert under `--headless`**, in the editor and with `CB_AUDIO=0`: no
##    players, no tweens, no hook on the tree, and every public method returns
##    on its first line. That keeps `tools/verify.ps1` quiet and the 40-run
##    balance bot deaf by construction.
## 3. **It references no other autoload.** `Game` calls in; the settings file
##    is read here directly. `Telemetry.settings` stays the single writer of
##    that file; this node never saves.
## 4. **Duck the player, never the bus.** The Settings sliders read the bus
##    levels live; a duck on the bus would show up as the slider jumping.
## 5. **Music tweens ignore `Engine.time_scale`.** `Fx.hitstop` drops it to
##    0.05 for a beat, and a crossfade caught in that would stall.

const SETTINGS_PATH := AppSettings.DEFAULT_PATH
const VOICES := 8
const DEFAULT_CROSSFADE := 1.2
const SILENT_DB := -60.0
const DUCK_DB := -9.0
## One-shots on the SFX bus play at this many dB (a hit still lands over the
## band without the band being quiet).
const SFX_TRIM_DB := 0.0

var _live := false
var _throttle := SfxThrottle.new()
var _voices: Array[AudioStreamPlayer] = []
var _voice_index := 0
var _music: Array[AudioStreamPlayer] = []          # two decks, crossfaded
var _deck := 0
var _current_music: StringName = &""
var _ambience: AudioStreamPlayer = null
var _current_ambience: StringName = &""
var _streams: Dictionary = {}                      # path -> AudioStream | null
var _variants: Dictionary = {}                     # id -> number of extra takes
var _music_tween: Tween = null
var _duck_tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_live = _resolve_live()
	if not _live:
		set_process(false)
		return
	for _i in VOICES:
		var voice := AudioStreamPlayer.new()
		voice.bus = &"Sfx"
		voice.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(voice)
		_voices.append(voice)
	for _i in 2:
		var deck := AudioStreamPlayer.new()
		deck.bus = &"Music"
		deck.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(deck)
		_music.append(deck)
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = &"Ambience"
	_ambience.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ambience)
	apply_settings(AppSettings.load_settings(SETTINGS_PATH))
	# One hook for every button in the game: hover and press sounds without a
	# per-screen edit. A control that has its own sounds (chips, sockets) sets
	# the `silent` meta before it enters the tree.
	get_tree().node_added.connect(_on_node_added)


func _resolve_live() -> bool:
	if DisplayServer.get_name() == "headless":
		return false                       # the house idiom (game.gd, telemetry.gd)
	if Engine.is_editor_hint():
		return false
	if OS.get_environment("CB_AUDIO") == "0":
		return false
	return true


func is_live() -> bool:
	return _live


func current_music() -> StringName:
	return _current_music


# ------------------------------------------------------------------ effects

## One-shot. `pitch_variance` < 0 means the bank's default (jitter for foley,
## none for jingles); `volume_db` trims this play only.
func play_sfx(id: StringName, pitch_variance := -1.0, volume_db := 0.0) -> void:
	if not _live or not SoundBank.is_known(id):
		return
	if not _throttle.allow(id, Time.get_ticks_msec()):
		return
	var stream := _stream_for(id, _pick_variant(id))
	if stream == null:
		return
	var voice := _voices[_voice_index]
	_voice_index = (_voice_index + 1) % _voices.size()
	var variance := pitch_variance if pitch_variance >= 0.0 else SoundBank.default_variance(id)
	voice.stop()
	voice.stream = stream
	voice.pitch_scale = 1.0 + randf_range(-variance, variance) if variance > 0.0 else 1.0
	voice.volume_db = SFX_TRIM_DB + volume_db
	voice.play()


## Takes are `id_1.ogg`, `id_2.ogg`... beside the plain file; counted once.
func _pick_variant(id: StringName) -> int:
	if not _variants.has(id):
		var count := 0
		while ResourceLoader.exists(SoundBank.path_for(id, count + 1)):
			count += 1
		_variants[id] = count
	var extra := int(_variants[id])
	if extra == 0:
		return 0
	# The plain file counts as take 0 when it exists, otherwise only the takes.
	var has_plain := ResourceLoader.exists(SoundBank.path_for(id, 0))
	return randi_range(0 if has_plain else 1, extra)


# -------------------------------------------------------------------- music

## Crossfade to `id`. The same track is a no-op; a missing file still fades
## the old track out, so the map theme never plays under the boss.
func play_music(id: StringName, crossfade := DEFAULT_CROSSFADE) -> void:
	if not _live:
		return
	if id == _current_music:
		return
	_current_music = id
	var stream := _stream_for(id, 0, true) if SoundBank.category_of(id) == "music" else null
	var outgoing := _music[_deck]
	_deck = 1 - _deck
	var incoming := _music[_deck]
	_kill(_music_tween)
	_kill(_duck_tween)
	if not outgoing.playing and stream == null:
		return                             # nothing to fade either way (an empty
		                                   # Tween is an engine error, seen 0.120)
	_music_tween = create_tween()
	_music_tween.set_ignore_time_scale(true)
	_music_tween.set_parallel(true)
	if outgoing.playing:
		_music_tween.tween_property(outgoing, "volume_db", SILENT_DB, crossfade)
		_music_tween.chain().tween_callback(outgoing.stop)
	if stream != null:
		incoming.stream = stream
		incoming.volume_db = SILENT_DB
		incoming.play()
		_music_tween.tween_property(incoming, "volume_db", 0.0, crossfade)


func stop_music(fade := 0.6) -> void:
	if not _live:
		return
	play_music(&"", fade)


## The active track dips for a stinger and comes back.
func duck(depth_db := DUCK_DB, hold := 0.6, release := 0.8) -> void:
	if not _live:
		return
	var deck := _music[_deck]
	if not deck.playing:
		return
	_kill(_duck_tween)
	_duck_tween = create_tween()
	_duck_tween.set_ignore_time_scale(true)
	_duck_tween.tween_property(deck, "volume_db", depth_db, 0.08)
	_duck_tween.tween_interval(hold)
	_duck_tween.tween_property(deck, "volume_db", 0.0, release)


func play_ambience(id: StringName) -> void:
	if not _live:
		return
	if id == _current_ambience:
		return
	_current_ambience = id
	var stream := _stream_for(id, 0, true) if SoundBank.category_of(id) == "ambience" else null
	if stream == null:
		_ambience.stop()
		return
	_ambience.stream = stream
	_ambience.play()


# ----------------------------------------------------------------- settings

## Bus level as the Settings sliders express it (0..100). Unknown bus: no-op.
func set_bus_pct(bus: String, pct: float) -> void:
	if not _live:
		return
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		return
	var linear := clampf(pct, 0.0, 100.0) / 100.0
	AudioServer.set_bus_volume_db(index, linear_to_db(linear) if linear > 0.0 else -80.0)


func set_master_muted(muted: bool) -> void:
	if not _live:
		return
	AudioServer.set_bus_mute(0, muted)


func apply_settings(settings: AppSettings) -> void:
	if not _live or settings == null:
		return
	set_bus_pct("Master", settings.volume_pct)
	set_bus_pct("Music", settings.music_pct)
	set_bus_pct("Sfx", settings.sfx_pct)
	set_master_muted(settings.muted)


# ------------------------------------------------------------------ helpers

## Loads once and remembers misses too, so a missing asset costs one disk
## look, not one per hit.
func _stream_for(id: StringName, variant: int, looping := false) -> AudioStream:
	var path := SoundBank.path_for(id, variant)
	if path == "":
		return null
	if _streams.has(path):
		return _streams[path]
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
		if stream != null and looping and "loop" in stream:
			# The OGG importer defaults loop=false; the pipeline never writes
			# .import files, so the loop flag is set here instead.
			stream.set("loop", true)
	_streams[path] = stream
	return stream


func _kill(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()


func _on_node_added(node: Node) -> void:
	if not node is BaseButton or node.has_meta(&"silent"):
		return
	var button := node as BaseButton
	button.pressed.connect(func() -> void: play_sfx(&"ui_press"))
	button.mouse_entered.connect(func() -> void:
		if not button.disabled:
			play_sfx(&"ui_hover"))
