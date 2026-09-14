class_name DiceGame
extends RefCounted
## The Casino's Dice Game (doc v0.120): "Roll dice one at a time and earn gold
## based on the result, while trying not to bust."
##
##   * Roll a die; its result is added to a running count.
##   * After any roll, choose to roll another or cash out.
##   * Past 10 you bust and win nothing; your only option left is to leave.
##   * Exactly 10 and the count glows: rolling is closed, cashing out is lit.
##   * Cashing out pays [Encounter Number x Counted Result] coins.
##
## Pure logic — the screen animates it, the RunBot plays it headless.

const TARGET := 10
const SIDES := 6

var rolls: Array[int] = []


func total() -> int:
	var sum := 0
	for value: int in rolls:
		sum += value
	return sum


func busted() -> bool:
	return total() > TARGET


## Exactly on the number: the best possible finish.
func perfect() -> bool:
	return total() == TARGET


func can_roll() -> bool:
	return not busted() and not perfect()


func can_cash_out() -> bool:
	return not rolls.is_empty() and not busted()


func roll(rng: RandomNumberGenerator) -> int:
	if not can_roll():
		return 0
	var value := rng.randi_range(1, SIDES)
	rolls.append(value)
	return value


## What cashing out is worth right now (0 once busted).
func cash_out_value(encounter: int) -> int:
	if busted():
		return 0
	return maxi(0, encounter) * total()


## Banks the winnings and returns what was paid.
func cash_out(run: RunState) -> int:
	var payout := cash_out_value(run.encounter_number())
	run.coins += payout
	return payout
