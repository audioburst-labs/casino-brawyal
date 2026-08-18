extends GutTest
## Payout rules (patch 0.1 "Ori Fix" — no free chips on doubles or triples):
## every landed symbol yields exactly 1 chip of its suit. Payout per suit = count.

const S := &"spade"
const C := &"club"
const H := &"heart"
const D := &"diamond"


func test_all_unique_pays_one_chip_per_symbol() -> void:
	var payout := Payout.compute([S, C, H] as Array[StringName])
	assert_eq(payout, {S: 1, C: 1, H: 1})


func test_pair_pays_exactly_two_chips_no_bonus() -> void:
	var payout := Payout.compute([S, S, H] as Array[StringName])
	assert_eq(payout, {S: 2, H: 1})


func test_triple_pays_exactly_three_chips_no_bonus() -> void:
	var payout := Payout.compute([D, D, D] as Array[StringName])
	assert_eq(payout, {D: 3})


func test_eight_reel_mixed_spin_counts_only() -> void:
	var payout := Payout.compute([S, H, C, S, D, H, S, D] as Array[StringName])
	assert_eq(payout, {S: 3, H: 2, C: 1, D: 2})


func test_empty_spin_pays_nothing() -> void:
	var payout := Payout.compute([] as Array[StringName])
	assert_eq(payout, {})
