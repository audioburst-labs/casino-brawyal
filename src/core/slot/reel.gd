class_name Reel
extends RefCounted
## One slot machine reel: an ordered list of suit symbols.
## New reels carry one of each default suit; stickers replace single slots.

const DEFAULT_SYMBOLS: Array[StringName] = [&"spade", &"club", &"heart", &"diamond"]

var symbols: Array[StringName] = []


func _init() -> void:
	symbols = DEFAULT_SYMBOLS.duplicate()


func spin(rng: RandomNumberGenerator) -> StringName:
	return symbols[rng.randi_range(0, symbols.size() - 1)]


func set_symbol(index: int, suit: StringName) -> void:
	symbols[index] = suit
