extends GutTest
## CombatActor (hp/block/statuses) and StatusRules (damage math).
## Damage order: base + Strength -> Weak (-25%) -> Vulnerable (+50%)
## -> Block absorbs -> HP. Rounding is half-up (patch 0.1), minimum 1 on Weak.


func _actor(hp: int = 30, hero: bool = false) -> CombatActor:
	return CombatActor.new(&"a1", &"test_def", "Test", hp, hero)


func test_actor_starts_at_full_hp_and_alive() -> void:
	var actor := _actor(30)
	assert_eq(actor.hp, 30)
	assert_eq(actor.max_hp, 30)
	assert_true(actor.is_alive())


func test_take_damage_consumes_block_first() -> void:
	var actor := _actor(30)
	actor.gain_block(5)
	actor.take_damage(8)
	assert_eq(actor.block, 0)
	assert_eq(actor.hp, 27)


func test_block_fully_absorbs_small_hit() -> void:
	var actor := _actor(30)
	actor.gain_block(10)
	actor.take_damage(4)
	assert_eq(actor.block, 6)
	assert_eq(actor.hp, 30)


func test_hp_never_goes_below_zero_and_death_is_detected() -> void:
	var actor := _actor(5)
	actor.take_damage(99)
	assert_eq(actor.hp, 0)
	assert_false(actor.is_alive())


func test_heal_caps_at_max_hp() -> void:
	var actor := _actor(30)
	actor.take_damage(10)
	actor.heal(50)
	assert_eq(actor.hp, 30)


func test_apply_status_accumulates_stacks() -> void:
	var actor := _actor()
	actor.apply_status(&"weak", 2)
	actor.apply_status(&"weak", 1)
	assert_eq(actor.status_stacks(&"weak"), 3)
	assert_true(actor.has_status(&"weak"))


func test_turn_end_tick_decrements_debuff_durations_only() -> void:
	var actor := _actor()
	actor.apply_status(&"weak", 1)
	actor.apply_status(&"strength", 3)
	actor.tick_turn_end()
	assert_false(actor.has_status(&"weak"))
	assert_eq(actor.status_stacks(&"strength"), 3)


func test_block_clears_at_own_turn_start() -> void:
	var actor := _actor()
	actor.gain_block(7)
	actor.on_turn_start()
	assert_eq(actor.block, 0)


func test_weak_reduces_dealt_damage_by_quarter_half_up_min_one() -> void:
	var attacker := _actor()
	attacker.apply_status(&"weak", 1)
	assert_eq(StatusRules.attack_damage(6, attacker), 5)   # 6*0.75 = 4.5 -> 5 (half-up)
	assert_eq(StatusRules.attack_damage(10, attacker), 8)  # 10*0.75 = 7.5 -> 8
	assert_eq(StatusRules.attack_damage(9, attacker), 7)   # 9*0.75 = 6.75 -> 7
	assert_eq(StatusRules.attack_damage(5, attacker), 4)   # 5*0.75 = 3.75 -> 4
	assert_eq(StatusRules.attack_damage(1, attacker), 1)   # min 1


func test_strength_adds_to_each_hit_before_weak() -> void:
	var attacker := _actor()
	attacker.apply_status(&"strength", 2)
	assert_eq(StatusRules.attack_damage(4, attacker), 6)
	attacker.apply_status(&"weak", 1)
	assert_eq(StatusRules.attack_damage(4, attacker), 5)  # (4+2)*0.75 = 4.5 -> 5


## The sheet's figure is 50% (patch 0.114); we shipped 25% until then.
func test_vulnerable_increases_taken_damage_by_half_half_up() -> void:
	var target := _actor()
	target.apply_status(&"vulnerable", 1)
	assert_eq(StatusRules.damage_taken(10, target), 15)  # 10*1.5 = 15
	assert_eq(StatusRules.damage_taken(8, target), 12)   # 8*1.5 = 12
	assert_eq(StatusRules.damage_taken(5, target), 8)    # 5*1.5 = 7.5 -> 8


func test_mark_does_not_tick_at_turn_end() -> void:
	var actor := _actor()
	actor.apply_status(&"mark", 1)
	actor.tick_turn_end()
	assert_eq(actor.status_stacks(&"mark"), 1, "mark persists until cashed in")
