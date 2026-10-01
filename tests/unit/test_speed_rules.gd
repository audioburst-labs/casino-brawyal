extends GutTest
## The combat speed toggle (phase 0 of the roadmap): one pure rule decides
## `Engine.time_scale` from the player's chosen speed, whether animations are
## playing, a hitstop and a slow-mo factor. `Fx` applies it; nothing else may
## write the time scale.


func test_speed_is_one_while_the_player_is_thinking() -> void:
	assert_eq(SpeedRules.effective(3.0, false, false, 1.0), 1.0)


func test_speed_applies_while_animations_play() -> void:
	assert_eq(SpeedRules.effective(2.0, true, false, 1.0), 2.0)


func test_hitstop_wins_over_everything() -> void:
	assert_eq(SpeedRules.effective(3.0, true, true, 0.65), SpeedRules.HITSTOP_SCALE)
	assert_lt(SpeedRules.HITSTOP_SCALE, 0.1)


func test_slow_mo_scales_the_active_speed() -> void:
	assert_almost_eq(SpeedRules.effective(2.0, true, false, 0.65), 1.3, 0.0001)


func test_allowed_speeds_and_clamping() -> void:
	assert_eq(SpeedRules.ALLOWED, [1.0, 1.5, 2.0, 3.0] as Array[float])
	assert_eq(SpeedRules.clamp_speed(2.0), 2.0)
	assert_eq(SpeedRules.clamp_speed(1.7), 1.5, "snaps to the nearest allowed value")
	assert_eq(SpeedRules.clamp_speed(99.0), 3.0)
	assert_eq(SpeedRules.clamp_speed(0.0), 1.0)
	assert_eq(SpeedRules.clamp_speed(-4.0), 1.0)


func test_next_cycles_through_the_allowed_speeds() -> void:
	assert_eq(SpeedRules.next(1.0), 1.5)
	assert_eq(SpeedRules.next(1.5), 2.0)
	assert_eq(SpeedRules.next(2.0), 3.0)
	assert_eq(SpeedRules.next(3.0), 1.0)
	assert_eq(SpeedRules.next(1.7), 2.0, "an off-list value snaps first, then advances")


func test_labels_are_short_and_dashless() -> void:
	assert_eq(SpeedRules.label(1.0), "1x")
	assert_eq(SpeedRules.label(1.5), "1.5x")
	assert_eq(SpeedRules.label(2.0), "2x")
	assert_eq(SpeedRules.label(3.0), "3x")
