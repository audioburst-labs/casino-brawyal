class_name SfxThrottle
extends RefCounted
## Denies the same sound twice inside a short window (patch 0.120).
##
## The sim resolves a whole multi-hit attack in one call and the presenter
## can ask for three `hit_enemy` in the same frame; played together they sum
## to one 3x-louder phased thud. Time is injected (`now_msec`) so the rule is
## a pure function of its inputs.

const DEFAULT_WINDOW_MSEC := 40

var _last_played: Dictionary = {}          # StringName -> int msec


func allow(id: StringName, now_msec: int, window_msec := DEFAULT_WINDOW_MSEC) -> bool:
	if _last_played.has(id) and now_msec - int(_last_played[id]) < window_msec:
		return false
	_last_played[id] = now_msec
	return true
