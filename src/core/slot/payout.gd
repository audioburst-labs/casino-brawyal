class_name Payout
extends RefCounted
## Chip payout rules for a resolved spin.
##
## Per-suit ruling (generalizes the design doc to any reel count):
## count n of a suit in the spin -> n=1: 1 chip, n=2: 3 chips, n>=3: n+2 chips.
## If the design re-rules mixed spins, this is the only file to change.


static func compute(symbols: Array[StringName]) -> Dictionary:
	var counts := {}
	for symbol in symbols:
		counts[symbol] = counts.get(symbol, 0) + 1

	var payout := {}
	for suit: StringName in counts:
		var n: int = counts[suit]
		if n == 1:
			payout[suit] = 1
		elif n == 2:
			payout[suit] = 3
		else:
			payout[suit] = n + 2
	return payout
