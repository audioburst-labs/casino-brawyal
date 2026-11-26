extends GutTest
## Build 1.30: the rest and treasure screens (heal maths, the heart's outline).


func test_a_rest_heals_thirty_percent_of_max_rounded_up() -> void:
	assert_eq(RestScreen.heal_amount(10, 80), 24)
	assert_eq(RestScreen.heal_amount(10, 75), 23, "22.5 rounds up")


func test_a_rest_never_heals_past_full() -> void:
	assert_eq(RestScreen.heal_amount(70, 80), 10)
	assert_eq(RestScreen.heal_amount(80, 80), 0)


func test_the_heart_outline_is_closed_and_inside_its_canvas() -> void:
	var points := NeonHeart.outline()
	assert_gt(points.size(), 20)
	assert_eq(points[0], points[points.size() - 1], "it closes on its start")
	for p in points:
		assert_between(p.x, 0.0, 100.0)
		assert_between(p.y, 0.0, 100.0)
