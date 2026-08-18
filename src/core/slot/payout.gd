class_name Payout
extends RefCounted
## Chip payout for a resolved spin.
##
## Patch 0.1 ruling ("Ori Fix" — no free chips on doubles or triples):
## every landed symbol yields exactly 1 chip of its suit, so the payout per
## suit equals its symbol count. Matching combos pay through ability synergies
## (e.g. Flush) and relics (High Roller), not through bonus chips.


static func compute(symbols: Array[StringName]) -> Dictionary:
	var payout := {}
	for symbol in symbols:
		payout[symbol] = payout.get(symbol, 0) + 1
	return payout
