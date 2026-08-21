extends GutTest
## Payout rules (doc v0.11): every landed symbol yields 1 chip of its suit;
## a suit that lands 3 or more symbols gains 1 additional bonus chip.

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


func test_three_of_a_kind_gains_one_bonus_chip() -> void:
	var payout := Payout.compute([D, D, D] as Array[StringName])
	assert_eq(payout, {D: 4})


func test_four_of_a_kind_still_gains_only_one_bonus() -> void:
	var payout := Payout.compute([C, C, C, C] as Array[StringName])
	assert_eq(payout, {C: 5})


func test_eight_reel_mixed_spin() -> void:
	# 3x spade -> 4 (bonus), 2x heart -> 2, 1 club -> 1, 2x diamond -> 2
	var payout := Payout.compute([S, H, C, S, D, H, S, D] as Array[StringName])
	assert_eq(payout, {S: 4, H: 2, C: 1, D: 2})


func test_empty_spin_pays_nothing() -> void:
	var payout := Payout.compute([] as Array[StringName])
	assert_eq(payout, {})
