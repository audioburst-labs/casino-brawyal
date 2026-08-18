class_name SlotMachine
extends RefCounted
## The player's slot machine: 4 reels to start, upgradeable to MAX_REELS.
## Reels resolve left to right.
## (Patch 0.1: raised from 3 to 4 to offset the "no free chips" payout fix —
## the enemy sheet is tuned against pre-fix chip income.)

const START_REELS := 4
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
