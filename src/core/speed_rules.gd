class_name SpeedRules
extends RefCounted
## The combat speed toggle, as a pure rule (phase 0 of the roadmap).
##
## `Engine.time_scale` has exactly one writer, `Fx`, and `Fx` asks this
## function what the scale should be from four facts: the speed the player
## chose, whether combat animations are playing, whether a hitstop is in
## force, and any slow-mo factor an animation asked for. Speed applies only
## while animations play, so tooltips, hovers and the player's own thinking
## time never run fast; a hitstop beats everything, because a freeze-frame at
## 2x is not a freeze.

const ALLOWED: Array[float] = [1.0, 1.5, 2.0]
const HITSTOP_SCALE := 0.05


static func effective(base: float, animating: bool, hitstop: bool, slowmo := 1.0) -> float:
	if hitstop:
		return HITSTOP_SCALE
	var scale := clamp_speed(base) if animating else 1.0
	return scale * slowmo


## Snaps any value to the nearest allowed speed (ties go to the slower one).
static func clamp_speed(value: float) -> float:
	var best := ALLOWED[0]
	for speed in ALLOWED:
		if absf(speed - value) < absf(best - value):
			best = speed
	return best


static func next(value: float) -> float:
	var index := ALLOWED.find(clamp_speed(value))
	return ALLOWED[(index + 1) % ALLOWED.size()]


static func label(value: float) -> String:
	var speed := clamp_speed(value)
	if is_equal_approx(speed, roundf(speed)):
		return "%dx" % int(speed)
	return "%sx" % str(speed)
