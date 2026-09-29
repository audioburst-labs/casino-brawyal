class_name SoundBank
extends RefCounted
## The one list of every sound the game can ask for (patch 0.120).
##
## Three consumers key off it and must agree: the `Audio` autoload resolves an
## id to a file here, `tools/audio/audio_manifest.json` must name exactly these
## ids (a GUT test holds the two together), and the presenters ask for sounds
## by these names. An unknown id is answered with "" / false, never an error:
## the game has to run before every asset exists.
##
## Pure, static, no autoload references (`src/core/` rule).

const ROOT := "res://assets/audio"
## Pitch jitter for one-shots, so the fortieth chip landing does not sound
## like the first. Stingers, jingles and music are locked at pitch.
const DEFAULT_VARIANCE := 0.06

## One looping theme per screen type; `ScreenMusic` maps screens onto these.
const MUSIC_IDS: Array[StringName] = [
	&"menu", &"map", &"combat", &"boss", &"shop", &"story", &"victory", &"defeat",
]

const AMBIENCE_IDS: Array[StringName] = [&"amb_casino_floor"]

## One id per presenter beat. Grouped by where it fires; the order is only
## for reading.
const SFX_IDS: Array[StringName] = [
	# the machine
	&"lever_pull", &"reel_stop", &"chip_land", &"jackpot", &"chip_shuffle",
	&"chip_pickup", &"chip_socket", &"chip_return",
	# Ace's cards
	&"card_activate", &"card_throw", &"card_hit", &"dagger_slash", &"cash_in",
	&"mark_wave", &"go_again", &"ultimate_barrage", &"passive_ping", &"miss",
	# hits and statuses
	&"hit_enemy", &"hit_hero", &"hit_heavy", &"block_absorb", &"block_gain",
	&"mark_apply", &"debuff_apply", &"buff_apply", &"stun", &"heal",
	# the enemies
	&"intent_show", &"enemy_telegraph", &"enemy_cashout", &"summon", &"encore",
	&"golem_crack", &"absorb", &"bust", &"hero_down",
	# loans and options in combat
	&"choice_open", &"loan_sign", &"loan_due", &"coins_gain", &"coins_lose",
	# turn flow
	&"pass_turn", &"sting_victory", &"sting_defeat",
	# screens
	&"ui_hover", &"ui_press", &"ui_confirm", &"reward_pick", &"shop_buy",
	&"sticker_place", &"dice_roll", &"card_flip", &"card_shuffle", &"treasure_open",
]

## Designed one-shots whose pitch IS the design: a jingle a semitone flat is
## a wrong jingle.
const PITCH_LOCKED: Array[StringName] = [
	&"sting_victory", &"sting_defeat", &"jackpot", &"reward_pick",
	&"treasure_open", &"encore", &"ui_confirm", &"ultimate_barrage",
]


static func category_of(id: StringName) -> String:
	if MUSIC_IDS.has(id):
		return "music"
	if SFX_IDS.has(id):
		return "sfx"
	if AMBIENCE_IDS.has(id):
		return "ambience"
	return ""


static func is_known(id: StringName) -> bool:
	return category_of(id) != ""


## `variant` 0 is the plain file; 1..N are the extra takes the manifest's
## `variants` field produced (`hit_enemy_2.ogg`).
static func path_for(id: StringName, variant := 0) -> String:
	var category := category_of(id)
	if category == "":
		return ""
	var stem := String(id) if variant <= 0 else "%s_%d" % [id, variant]
	return "%s/%s/%s.ogg" % [ROOT, category, stem]


static func default_variance(id: StringName) -> float:
	if category_of(id) != "sfx" or PITCH_LOCKED.has(id):
		return 0.0
	return DEFAULT_VARIANCE


static func all_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.append_array(MUSIC_IDS)
	ids.append_array(SFX_IDS)
	ids.append_array(AMBIENCE_IDS)
	return ids
