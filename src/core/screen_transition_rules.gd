class_name ScreenTransitionRules
extends RefCounted
## Which screen changes get the theatre curtain (patch 0.125), and how long it
## takes. Pure, so the rule is tested without a window.
##
## Designer's list: every swap INSIDE a run is masked (combat to rewards,
## rewards to the choice screen, the shop, the casino, the boss victory...).
## The main menu and the game-over screen keep their plain cuts, in either
## direction, because they are not part of the act.

## Close, swap behind the cloth, open: about a second and a half in all. The
## victory banner has already finished playing by the time Game asks for the
## swap, so none of this budget is spent waiting for it.
const COVER_SEC := 0.55
const HOLD_SEC := 0.2    # shut and still swinging, before it opens (designer: 0.2 s)
const REVEAL_SEC := 0.75

## Never masked, whichever side of the swap they are on.
const PLAIN := ["main_menu", "game_over_screen"]
## Masked on the way IN (combat to victory) but not on the way out to the menu.
const PLAIN_AS_SOURCE := ["main_menu", "game_over_screen", "victory_screen"]


static func total_sec() -> float:
	return COVER_SEC + HOLD_SEC + REVEAL_SEC


static func wants_curtain(from_path: String, to_path: String) -> bool:
	if from_path == "" or to_path == "":
		return false   # the first screen of the game has nothing to hide
	return not PLAIN_AS_SOURCE.has(_name(from_path)) and not PLAIN.has(_name(to_path))


static func _name(path: String) -> String:
	return path.get_file().get_basename()
