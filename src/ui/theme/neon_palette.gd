class_name NeonPalette
extends RefCounted
## The neon UI's colours, one set per act (patch 0.126, designer: the casino is
## magenta; the office will be blue and the hells red). Every widget that glows
## asks `current()` for a role, never for a literal, so a new act is a new row
## here and nothing else. `Main` rebuilds the theme from it whenever the act
## changes.
##
## Roles:
##   tube    the main glow: borders, the live button, the target reticle
##   tube_hi a lighter tube for highlights and hover fills
##   foe     enemies: their health bars, floors and intent bubbles
##   hero    you: your bar, your floor, your health number
##   money   gold and prices. The same gold in every act, on purpose.
##   text / dim  body and secondary text
##   glass   the translucent panel fill, glass_deep a darker fill for inlays

const DEFAULT_ACT := &"casino"

const ROLES := ["tube", "tube_hi", "foe", "hero", "money", "text", "dim", "glass", "glass_deep"]

const MONEY := Color(1.0, 0.79, 0.35)

const _ACTS := {
	# Act I: the Dreams Casino. Neon purple (the title screen's), blue enemies, aqua for Ace.
	&"casino": {
		"tube": Color(0.76, 0.32, 1.0),
		"tube_hi": Color(0.87, 0.64, 1.0),
		"foe": Color(0.36, 0.56, 1.0),
		"hero": Color(0.31, 1.0, 0.84),
		"money": MONEY,
		"text": Color(0.98, 0.96, 1.0),
		"dim": Color(0.78, 0.72, 0.88),
		"glass": Color(0.05, 0.03, 0.09, 0.84),
		"glass_deep": Color(0.025, 0.015, 0.05, 0.92),
	},
	# Act II (not built yet): the office, cold blue.
	&"office": {
		"tube": Color(0.31, 0.62, 1.0),
		"tube_hi": Color(0.65, 0.82, 1.0),
		"foe": Color(1.0, 0.59, 0.24),
		"hero": Color(0.35, 1.0, 0.67),
		"money": MONEY,
		"text": Color(0.95, 0.97, 1.0),
		"dim": Color(0.68, 0.74, 0.84),
		"glass": Color(0.02, 0.04, 0.09, 0.84),
		"glass_deep": Color(0.01, 0.02, 0.05, 0.92),
	},
	# Act III (not built yet): the hells, red.
	&"hells": {
		"tube": Color(1.0, 0.22, 0.26),
		"tube_hi": Color(1.0, 0.58, 0.55),
		"foe": Color(1.0, 0.67, 0.16),
		"hero": Color(0.31, 0.90, 1.0),
		"money": MONEY,
		"text": Color(1.0, 0.96, 0.94),
		"dim": Color(0.84, 0.70, 0.66),
		"glass": Color(0.08, 0.02, 0.02, 0.84),
		"glass_deep": Color(0.04, 0.01, 0.01, 0.92),
	},
}

static var _act: StringName = DEFAULT_ACT


static func acts() -> Array:
	return _ACTS.keys()


static func for_act(act: StringName) -> Dictionary:
	return _ACTS.get(act, _ACTS[DEFAULT_ACT])


static func act() -> StringName:
	return _act


## Unknown acts are ignored, so a typo in future content cannot blank the UI.
static func set_act(act_id: StringName) -> void:
	if _ACTS.has(act_id):
		_act = act_id


static func current() -> Dictionary:
	return for_act(_act)


## `colour` at a given alpha, for glows and fills.
static func alpha(colour: Color, a: float) -> Color:
	return Color(colour.r, colour.g, colour.b, a)
