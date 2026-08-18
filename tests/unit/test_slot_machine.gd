extends GutTest
## Reel and SlotMachine: default configuration, spinning, stickers, extra reels.

const S := &"spade"
const C := &"club"
const H := &"heart"
const D := &"diamond"


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	return rng


func test_default_reel_has_one_of_each_suit() -> void:
	var reel := Reel.new()
	assert_eq(reel.symbols, [S, C, H, D] as Array[StringName])


func test_reel_spin_returns_one_of_its_symbols() -> void:
	var reel := Reel.new()
	var rng := _rng()
	for i in 30:
		assert_has(reel.symbols, reel.spin(rng))


func test_reel_sticker_replaces_symbol() -> void:
	var reel := Reel.new()
	reel.set_symbol(2, S)
	assert_eq(reel.symbols, [S, C, S, D] as Array[StringName])


func test_machine_starts_with_default_reel_count() -> void:
	var machine := SlotMachine.new()
	assert_eq(machine.reels.size(), SlotMachine.START_REELS)
	for reel in machine.reels:
		assert_eq(reel.symbols, [S, C, H, D] as Array[StringName])


func test_machine_spin_returns_symbol_per_reel_with_matching_payout() -> void:
	var machine := SlotMachine.new()
	var rng := _rng()
	for i in 20:
		var result := machine.spin(rng)
		assert_eq(result.symbols.size(), SlotMachine.START_REELS)
		assert_eq(result.payout, Payout.compute(result.symbols))


func test_add_reel_appends_default_reel_up_to_eight() -> void:
	var machine := SlotMachine.new()
	for i in SlotMachine.MAX_REELS - SlotMachine.START_REELS:
		assert_true(machine.add_reel())
	assert_eq(machine.reels.size(), 8)
	assert_false(machine.add_reel())
	assert_eq(machine.reels.size(), 8)
	assert_eq(machine.reels[7].symbols, [S, C, H, D] as Array[StringName])


func test_machine_spin_is_deterministic_for_a_seed() -> void:
	var a := SlotMachine.new().spin(_rng())
	var b := SlotMachine.new().spin(_rng())
	assert_eq(a.symbols, b.symbols)


func test_apply_sticker_changes_targeted_reel_slot() -> void:
	var machine := SlotMachine.new()
	machine.apply_sticker(1, 3, H)
	assert_eq(machine.reels[1].symbols, [S, C, H, H] as Array[StringName])
	assert_eq(machine.reels[0].symbols, [S, C, H, D] as Array[StringName])
