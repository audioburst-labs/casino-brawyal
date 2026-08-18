extends GutTest
## M0 sanity: proves the headless test loop works end to end.


func test_engine_math_still_works() -> void:
	assert_eq(2 + 2, 4)


func test_project_boot_scene_exists() -> void:
	assert_true(ResourceLoader.exists("res://scenes/main.tscn"))
