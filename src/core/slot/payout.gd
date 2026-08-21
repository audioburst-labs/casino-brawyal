class_name Payout
extends RefCounted
## Chip payout for a resolved spin.
##
## Doc v0.11 ruling: every landed symbol yields 1 chip of its suit, and a
## suit that lands 3 or more symbols gains exactly 1 additional bonus chip.


static func compute(symbols: Array[StringName]) -> Dictionary:
	var payout := {}
	for symbol in symbols:
		payout[symbol] = payout.get(symbol, 0) + 1
	for suit: StringName in payout:
		if payout[suit] >= 3:
			payout[suit] += 1
	return payout
