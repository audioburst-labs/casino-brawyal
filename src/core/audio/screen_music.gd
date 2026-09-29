class_name ScreenMusic
extends RefCounted
## Which theme and which ambience play under which screen (patch 0.120).
##
## `Game.goto_screen` asks this on every swap. Pure, so a test can walk
## `res://scenes/screens` and prove no screen ships silent by accident.

## Scene basename -> theme. Between-fights screens share the map theme so the
## music does not restart on every reward; the casino is a shop with dice.
const TRACKS := {
	"main_menu": &"menu",
	"map_screen": &"map",
	"reward_screen": &"map",
	"loadout_screen": &"map",
	"sticker_screen": &"map",
	"combat_screen": &"combat",
	"shop_screen": &"shop",
	"casino_screen": &"shop",
	"story_screen": &"story",
	"rest_screen": &"story",
	"treasure_screen": &"story",
	"victory_screen": &"victory",
	"game_over_screen": &"defeat",
}

## The hub screens: the player is on the casino floor between fights, so the
## floor is heard. Not in combat (its own score) and not on the menu (rain).
const AMBIENT_SCREENS := [
	"map_screen", "reward_screen", "loadout_screen", "sticker_screen",
	"shop_screen", "casino_screen",
]


## `args.music` wins when it names a real theme (the boss fight opens the
## combat screen with `{music: "boss"}`); otherwise the screen's own theme.
static func track_for(scene_path: String, args: Dictionary = {}) -> StringName:
	var override := StringName(str(args.get("music", "")))
	if override != &"" and SoundBank.MUSIC_IDS.has(override):
		return override
	return TRACKS.get(scene_path.get_file().get_basename(), &"")


static func ambience_for(scene_path: String) -> StringName:
	if AMBIENT_SCREENS.has(scene_path.get_file().get_basename()):
		return &"amb_casino_floor"
	return &""
