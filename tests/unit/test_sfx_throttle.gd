extends GutTest
## Three identical hits resolved in one frame must play once, not as a
## 3x-louder phased mess. Time is injected so the rule is testable.


func test_the_first_play_is_allowed() -> void:
	var throttle := SfxThrottle.new()
	assert_true(throttle.allow(&"hit_enemy", 1000))


func test_a_repeat_inside_the_window_is_denied() -> void:
	var throttle := SfxThrottle.new()
	throttle.allow(&"hit_enemy", 1000)
	assert_false(throttle.allow(&"hit_enemy", 1000))
	assert_false(throttle.allow(&"hit_enemy", 1039))


func test_a_repeat_after_the_window_is_allowed() -> void:
	var throttle := SfxThrottle.new()
	throttle.allow(&"hit_enemy", 1000)
	assert_true(throttle.allow(&"hit_enemy", 1040))


func test_ids_are_independent() -> void:
	var throttle := SfxThrottle.new()
	throttle.allow(&"hit_enemy", 1000)
	assert_true(throttle.allow(&"hit_hero", 1000))


func test_the_window_is_a_parameter() -> void:
	var throttle := SfxThrottle.new()
	throttle.allow(&"reel_stop", 1000, 10)
	assert_false(throttle.allow(&"reel_stop", 1005, 10))
	assert_true(throttle.allow(&"reel_stop", 1010, 10))
