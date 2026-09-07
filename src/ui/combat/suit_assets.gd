class_name SuitAssets
extends RefCounted
## Texture/color lookup for suits and chips, with graceful fallbacks while
## art is still being generated (missing texture -> tinted placeholder color).

const SUIT_COLORS := {
	&"spade": Color(0.16, 0.18, 0.32),
	&"club": Color(0.1, 0.42, 0.25),
	&"heart": Color(0.78, 0.2, 0.24),
	&"diamond": Color(0.2, 0.4, 0.85),
}


static func suit_color(suit: StringName) -> Color:
	return SUIT_COLORS.get(suit, Color.GRAY)


static func suit_texture(suit: StringName) -> Texture2D:
	return _load("res://assets/icons/suit_%s.png" % suit)  # incl. suit_any.png for &"any"


static func chip_texture(suit: StringName) -> Texture2D:
	return _load("res://assets/icons/chip_%s.png" % suit)


static func character_texture(def_id: StringName, is_hero: bool) -> Texture2D:
	if is_hero:
		return _load("res://assets/characters/%s_idle.png" % def_id)
	var boss := _load("res://assets/characters/boss_%s.png" % def_id)
	if boss != null:
		return boss
	return _load("res://assets/characters/enemy_%s.png" % def_id)


## Relic art, with a generic house chip standing in for anything missing —
## the two relic UIs used to build this path by hand and silently render
## nothing when the file was absent (patch 0.19).
static func relic_texture(relic_id: StringName) -> Texture2D:
	var art := _load("res://assets/icons/relic_%s.png" % relic_id)
	if art != null:
		return art
	return _load("res://assets/icons/relic_house_chip.png")


static func status_texture(status_id: StringName) -> Texture2D:
	return _load("res://assets/icons/status_%s.png" % status_id)


static func ability_texture(ability_id: StringName) -> Texture2D:
	return _load("res://assets/icons/ability_%s.png" % ability_id)


static func _load(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null
