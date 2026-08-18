extends GutTest
## Payout rules (per-suit generalization of the design doc):
## count n of a suit in a spin -> n=1: 1 chip, n=2: 3 chips, n>=3: n+2 chips.

const S := &"spade"
const C := &"club"
const H := &"heart"
const D := &"diamond"


func test_all_unique_pays_one_chip_per_symbol() -> void:
	var payout := Payout.compute([S, C, H] as Array[StringName])
	assert_eq(payout, {S: 1, C: 1, H: 1})


func test_pair_pays_three_chips_of_that_suit() -> void:
	var payout := Payout.compute([S, S, H] as Array[StringName])
	assert_eq(payout, {S: 3, H: 1})


func test_three_matching_pays_count_plus_two() -> void:
	var payout := Payout.compute([D, D, D] as Array[StringName])
	assert_eq(payout, {D: 5})


func test_two_pairs_each_pay_three() -> void:
	var payout := Payout.compute([S, S, H, H] as Array[StringName])
	assert_eq(payout, {S: 3, H: 3})


func test_four_matching_pays_six() -> void:
	var payout := Payout.compute([C, C, C, C] as Array[StringName])
	assert_eq(payout, {C: 6})


func test_eight_reel_mixed_spin() -> void:
	# 3x spade -> 5, 2x heart -> 3, 1 club -> 1, 2x diamond -> 3
	var payout := Payout.compute([S, H, C, S, D, H, S, D] as Array[StringName])
	assert_eq(payout, {S: 5, H: 3, C: 1, D: 3})


func test_empty_spin_pays_nothing() -> void:
	var payout := Payout.compute([] as Array[StringName])
	assert_eq(payout, {})
