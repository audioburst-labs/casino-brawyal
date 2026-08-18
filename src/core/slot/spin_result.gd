class_name SpinResult
extends RefCounted
## Outcome of one machine spin: the landed symbols (left to right)
## and the chip payout computed from them.

var symbols: Array[StringName]
var payout: Dictionary


func _init(spun_symbols: Array[StringName]) -> void:
	symbols = spun_symbols
	payout = Payout.compute(symbols)
