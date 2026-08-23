class_name SlotMachine
extends RefCounted
## The player's slot machine: 3 reels to start (per the design doc),
## upgradeable to MAX_REELS. Reels resolve left to right.

const START_REELS := 3
const MAX_REELS := 8

var reels: Array[Reel] = []


func _init() -> void:
	for i in START_REELS:
		reels.append(Reel.new())


func spin(rng: RandomNumberGenerator) -> SpinResult:
	var symbols: Array[StringName] = []
	for reel in reels:
		symbols.append(reel.spin(rng))
	return SpinResult.new(symbols)


## Adds a default reel. Returns false when the machine is already at MAX_REELS.
func add_reel() -> bool:
	if reels.size() >= MAX_REELS:
		return false
	reels.append(Reel.new())
	return true


func apply_sticker(reel_index: int, slot_index: int, suit: StringName) -> void:
	reels[reel_index].set_symbol(slot_index, suit)
