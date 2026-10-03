class_name Reel
extends RefCounted
## One slot machine reel: an ordered list of suit symbols.
## New reels carry one of each default suit; stickers replace single slots.

const DEFAULT_SYMBOLS: Array[StringName] = [&"spade", &"club", &"heart", &"diamond"]
## Doc "Behavior -> Combat -> Slot Machine": the reel's internal pool holds
## two instances of every symbol assigned to it (v0.19 — was three).
const POOL_COPIES := 2

var symbols: Array[StringName] = []

## Draws come out of this pool without replacement; it refills the moment it
## empties. A reel with two Spades, a Heart and a Diamond therefore raffles an
## 8-item pool of 4 Spades, 2 Hearts and 2 Diamonds — weighted like the
## reel's face, but with bounded streaks and droughts.
var _pool: Array[StringName] = []


func _init() -> void:
	symbols = DEFAULT_SYMBOLS.duplicate()


func spin(rng: RandomNumberGenerator) -> StringName:
	if _pool.is_empty():
		refill_pool()
	var index := rng.randi_range(0, _pool.size() - 1)
	var symbol := _pool[index]
	_pool.remove_at(index)
	return symbol


func refill_pool() -> void:
	_pool.clear()
	for symbol in symbols:
		for copy in POOL_COPIES:
			_pool.append(symbol)


func set_symbol(index: int, suit: StringName) -> void:
	symbols[index] = suit
	_pool.clear()  # the pool is raffled against the reel's current face
