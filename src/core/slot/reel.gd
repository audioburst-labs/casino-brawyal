class_name Reel
extends RefCounted
## One slot machine reel: an ordered list of suit symbols.
## New reels carry one of each default suit; stickers replace single slots.

const DEFAULT_SYMBOLS: Array[StringName] = [&"spade", &"club", &"heart", &"diamond"]
## Doc "Behavior -> Combat -> Slot Machine": the reel's internal pool holds
## two instances of every symbol assigned to it (v0.19 — was three).
const POOL_COPIES := 2
## Doc "Pool Refresh" (still on the page in 0.122): "once a pool is completely
## depleted, it immediately resets, refilling with THREE fresh copies of each
## symbol", while the first pool holds two. A sticker starts a fresh first pool.
const REFILL_COPIES := 3

var symbols: Array[StringName] = []

## Draws come out of this pool without replacement; it refills the moment it
## empties. A reel with two Spades, a Heart and a Diamond therefore raffles an
## 8-item pool of 4 Spades, 2 Hearts and 2 Diamonds — weighted like the
## reel's face, but with bounded streaks and droughts.
var _pool: Array[StringName] = []
var _depleted_once := false


func _init() -> void:
	symbols = DEFAULT_SYMBOLS.duplicate()


func spin(rng: RandomNumberGenerator) -> StringName:
	if _pool.is_empty():
		refill_pool(REFILL_COPIES if _depleted_once else POOL_COPIES)
		_depleted_once = true
	var index := rng.randi_range(0, _pool.size() - 1)
	var symbol := _pool[index]
	_pool.remove_at(index)
	return symbol


func refill_pool(copies: int = POOL_COPIES) -> void:
	_pool.clear()
	for symbol in symbols:
		for copy in copies:
			_pool.append(symbol)


func set_symbol(index: int, suit: StringName) -> void:
	symbols[index] = suit
	_pool.clear()  # the pool is raffled against the reel's current face
	_depleted_once = false
