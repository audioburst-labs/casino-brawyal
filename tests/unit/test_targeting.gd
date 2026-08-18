extends GutTest
## Targeting rules from the design doc:
## - manual target persists across turns while alive
## - Taunt overrides everything (leftmost taunting enemy)
## - on target death, auto-retarget to lowest-HP living enemy
## - a single living enemy is always the target


func _enemy(id: String, hp: int) -> CombatActor:
	return CombatActor.new(StringName(id), &"e", id, hp)


func test_defaults_to_lowest_hp_enemy() -> void:
	var enemies: Array[CombatActor] = [_enemy("a", 20), _enemy("b", 10), _enemy("c", 15)]
	var targeting := Targeting.new()
	assert_eq(targeting.effective_target(enemies).id, &"b")


func test_manual_target_persists() -> void:
	var enemies: Array[CombatActor] = [_enemy("a", 20), _enemy("b", 10)]
	var targeting := Targeting.new()
	targeting.set_target(&"a")
	assert_eq(targeting.effective_target(enemies).id, &"a")


func test_taunt_overrides_manual_target() -> void:
	var enemies: Array[CombatActor] = [_enemy("a", 20), _enemy("b", 10), _enemy("c", 15)]
	enemies[2].apply_status(&"taunt", 2)
	var targeting := Targeting.new()
	targeting.set_target(&"a")
	assert_eq(targeting.effective_target(enemies).id, &"c")


func test_leftmost_taunting_enemy_wins() -> void:
	var enemies: Array[CombatActor] = [_enemy("a", 20), _enemy("b", 10), _enemy("c", 15)]
	enemies[1].apply_status(&"taunt", 1)
	enemies[2].apply_status(&"taunt", 1)
	var targeting := Targeting.new()
	assert_eq(targeting.effective_target(enemies).id, &"b")


func test_dead_target_falls_back_to_lowest_hp() -> void:
	var enemies: Array[CombatActor] = [_enemy("a", 20), _enemy("b", 10), _enemy("c", 15)]
	var targeting := Targeting.new()
	targeting.set_target(&"b")
	enemies[1].take_damage(99)
	assert_eq(targeting.effective_target(enemies).id, &"c")


func test_single_living_enemy_is_always_target() -> void:
	var enemies: Array[CombatActor] = [_enemy("a", 20), _enemy("b", 10)]
	enemies[0].take_damage(99)
	var targeting := Targeting.new()
	targeting.set_target(&"a")
	assert_eq(targeting.effective_target(enemies).id, &"b")


func test_no_living_enemies_returns_null() -> void:
	var enemies: Array[CombatActor] = [_enemy("a", 5)]
	enemies[0].take_damage(99)
	var targeting := Targeting.new()
	assert_null(targeting.effective_target(enemies))
