extends GutTest
## Patch 0.125: the theatre curtain between screens.

const MAP := "res://scenes/screens/map_screen.tscn"
const COMBAT := "res://scenes/screens/combat_screen.tscn"
const REWARD := "res://scenes/screens/reward_screen.tscn"
const MENU := "res://scenes/screens/main_menu.tscn"
const OVER := "res://scenes/screens/game_over_screen.tscn"
const VICTORY := "res://scenes/screens/victory_screen.tscn"


func test_the_whole_act_takes_about_a_second_and_a_half() -> void:
	assert_almost_eq(ScreenTransitionRules.total_sec(), 1.5, 0.05)


func test_in_run_swaps_are_masked() -> void:
	assert_true(ScreenTransitionRules.wants_curtain(COMBAT, REWARD))
	assert_true(ScreenTransitionRules.wants_curtain(REWARD, MAP))
	assert_true(ScreenTransitionRules.wants_curtain(MAP, COMBAT))


func test_the_boss_victory_is_masked_on_the_way_in() -> void:
	assert_true(ScreenTransitionRules.wants_curtain(COMBAT, VICTORY))


func test_the_menu_and_game_over_keep_their_plain_cuts() -> void:
	assert_false(ScreenTransitionRules.wants_curtain(MENU, COMBAT), "leaving the menu")
	assert_false(ScreenTransitionRules.wants_curtain(COMBAT, OVER), "losing")
	assert_false(ScreenTransitionRules.wants_curtain(OVER, MENU))
	assert_false(ScreenTransitionRules.wants_curtain(VICTORY, MENU))
	assert_false(ScreenTransitionRules.wants_curtain(MAP, MENU))


func test_the_first_screen_has_nothing_to_hide() -> void:
	assert_false(ScreenTransitionRules.wants_curtain("", MENU))
