extends GutTest
## The run-level ops the sheet's Story tab needs (patch 0.116).
##
## The designer's five story encounters price almost everything off the
## encounter number ("[Encounter Value X 5] Coins"), hand out stickers, and in
## one case spend a spin on the Casino's own prize table. None of that existed
## as an op, so every story shipped with hand-rolled flat numbers instead.

var db: ContentDB
var run: RunState
var rng: RandomNumberGenerator


func before_each() -> void:
	db = ContentDB.new()
	assert_true(db.load_all("res://data"), str(db.errors))
	run = RunState.new()
	run.max_hp = 80
	run.hp = 40
	run.coins = 100
	rng = RandomNumberGenerator.new()
	rng.seed = 7


## Walk the run to `n` so `encounter_number()` reports it.
func _at_encounter(n: int) -> void:
	run.history.clear()
	for i in n - 1:
		run.history.append(&"combat")


func test_per_encounter_scales_coins_by_the_encounter_number() -> void:
	_at_encounter(4)
	RunEffects.apply([{"op": "gain_coins", "per_encounter": 5}], db, run, rng)
	assert_eq(run.coins, 120, "4th encounter x 5 = 20 coins")


func test_per_encounter_scales_hp_loss() -> void:
	_at_encounter(3)
	RunEffects.apply([{"op": "lose_hp", "per_encounter": 3}], db, run, rng)
	assert_eq(run.hp, 31, "3rd encounter x 3 = 9 damage")


## The existing clamp still applies: a story must never be the thing that
## kills a run outright.
func test_a_scaled_wound_still_leaves_one_hp() -> void:
	_at_encounter(9)
	run.hp = 4
	RunEffects.apply([{"op": "lose_hp", "per_encounter": 9}], db, run, rng)
	assert_eq(run.hp, 1)


func test_a_flat_amount_still_works_alongside_per_encounter() -> void:
	_at_encounter(6)
	RunEffects.apply([{"op": "gain_coins", "amount": 30}], db, run, rng)
	assert_eq(run.coins, 130, "an explicit amount ignores the encounter")


func test_losing_coins_can_scale_too_and_never_goes_below_zero() -> void:
	_at_encounter(8)
	run.coins = 10
	RunEffects.apply([{"op": "lose_coins", "per_encounter": 10}], db, run, rng)
	assert_eq(run.coins, 0)


func test_grant_sticker_puts_the_named_suit_in_the_inventory() -> void:
	RunEffects.apply([{"op": "grant_sticker", "suit": "heart"}], db, run, rng)
	assert_eq(run.sticker_inventory, [&"heart"] as Array[StringName])


func test_grant_sticker_random_picks_a_real_suit() -> void:
	RunEffects.apply([{"op": "grant_sticker", "suit": "random"}], db, run, rng)
	assert_eq(run.sticker_inventory.size(), 1)
	assert_has([&"spade", &"heart", &"club", &"diamond"], run.sticker_inventory[0])


## Lost Soul's third option is the sheet's own note: "grants a use of the Slot
## Machine in the Casino Encounter". It resolves in place rather than routing
## to the casino screen, because the reward is the spin, not the visit.
func test_casino_spin_awards_from_the_casino_prize_table() -> void:
	_at_encounter(5)
	var before_coins := run.coins
	var before_hp := run.hp
	var before_stickers := run.sticker_inventory.size()
	var lines := RunEffects.apply([{"op": "casino_spin"}], db, run, rng)
	assert_false(lines.is_empty(), "the spin reports what it landed")
	var moved := run.coins != before_coins or run.hp != before_hp \
		or run.sticker_inventory.size() != before_stickers \
		or not run.relic_ids.is_empty()
	assert_true(moved, "three reels of the prize table always do something")


func test_every_story_effect_in_the_shipped_content_is_a_known_op() -> void:
	assert_eq(db.errors, [] as Array[String],
		"content linter: " + "\n".join(db.errors))


## The five encounters the designer wrote in the sheet's Story tab.
func test_the_sheet_s_five_stories_are_all_present() -> void:
	var ids := db.all_story_event_ids()
	for expected in ["lost_soul", "risky_dealings", "guarded_treasure",
			"quick_catch", "cheap_tricks"]:
		assert_has(ids, StringName(expected))


## Guarded Treasure's first option is a fight, not an effect. The relic is the
## prize for WINNING it, so it is staged on the run and paid out by
## `combat_finished`, never by the story screen.
func test_a_story_choice_can_stage_a_bonus_for_the_fight_it_starts() -> void:
	var event := db.get_story_event(&"guarded_treasure")
	assert_not_null(event)
	var fight: Dictionary = event.choices[0]
	assert_eq(str(fight.get("then", "")), "combat")
	assert_false(fight.get("bonus_rewards", []).is_empty(),
		"winning the guards has to be worth a relic")


func test_bonus_rewards_survive_a_save_and_load() -> void:
	run.bonus_rewards = [{"op": "grant_relic"}]
	var revived := RunState.from_dict(run.to_dict())
	assert_eq(revived.bonus_rewards, [{"op": "grant_relic"}] as Array[Dictionary])
