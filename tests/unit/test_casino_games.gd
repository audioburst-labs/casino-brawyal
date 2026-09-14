extends GutTest
## Patch 0.22: the Casino's two new games (doc v0.120) — the Dice Game and
## Find the Relic — and the choice between them.

var _db: ContentDB


func before_all() -> void:
	_db = ContentDB.new()
	assert_true(_db.load_all("res://data"), str(_db.errors))


func _rng(seed_value: int = 5) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _run_at(encounter: int) -> RunState:
	var run := RunState.new()
	for i in encounter - 1:
		run.record_visit(&"combat")
	return run


# ---------------------------------------------------------------- dice game

func test_a_fresh_table_can_roll_but_not_cash_out() -> void:
	var game := DiceGame.new()
	assert_true(game.can_roll())
	assert_false(game.can_cash_out(), "nothing to cash out yet")
	assert_eq(game.total(), 0)
	assert_false(game.busted())
	assert_false(game.perfect())


func test_every_roll_is_a_real_die_and_lands_in_the_count() -> void:
	var game := DiceGame.new()
	var rng := _rng()
	var expected := 0
	while game.can_roll():
		var value := game.roll(rng)
		assert_between(value, 1, 6)
		expected += value
		assert_eq(game.total(), expected)


func test_passing_ten_busts_and_closes_the_table() -> void:
	var game := DiceGame.new()
	game.rolls = [6, 6]
	assert_true(game.busted())
	assert_false(game.can_roll(), "the only option left is to leave")
	assert_false(game.can_cash_out())
	assert_eq(game.cash_out_value(5), 0, "a bust wins nothing")


func test_exactly_ten_closes_rolling_but_lights_the_cash_out() -> void:
	var game := DiceGame.new()
	game.rolls = [4, 6]
	assert_true(game.perfect())
	assert_false(game.can_roll(), "rolling is disabled on the nose")
	assert_true(game.can_cash_out())


func test_cashing_out_pays_encounter_times_the_count() -> void:
	var game := DiceGame.new()
	game.rolls = [3, 4]
	assert_eq(game.cash_out_value(1), 7)
	assert_eq(game.cash_out_value(6), 42)
	var run := _run_at(6)
	run.coins = 10
	assert_eq(game.cash_out(run), 42)
	assert_eq(run.coins, 52)


func test_a_busted_table_cannot_be_rolled_again() -> void:
	var game := DiceGame.new()
	game.rolls = [6, 6]
	assert_eq(game.roll(_rng()), 0)
	assert_eq(game.rolls.size(), 2, "the roll was refused")


# ---------------------------------------------------------------- find the relic

func test_the_deck_is_one_blank_three_golds_and_a_relic() -> void:
	var run := _run_at(4)
	var hunt := RelicHunt.build(_db, run, _rng())
	assert_eq(hunt.cards.size(), 5)
	var kinds := {RelicHunt.Kind.BLANK: 0, RelicHunt.Kind.GOLD: 0, RelicHunt.Kind.RELIC: 0}
	for card: Dictionary in hunt.cards:
		kinds[int(card.kind)] += 1
	assert_eq(kinds[RelicHunt.Kind.BLANK], 1)
	assert_eq(kinds[RelicHunt.Kind.GOLD], 3)
	assert_eq(kinds[RelicHunt.Kind.RELIC], 1)


func test_gold_cards_are_five_per_encounter() -> void:
	var hunt := RelicHunt.build(_db, _run_at(7), _rng())
	for card: Dictionary in hunt.cards:
		if int(card.kind) == RelicHunt.Kind.GOLD:
			assert_eq(int(card.value), 35, "5 x encounter 7")


func test_the_relic_offered_is_one_the_player_does_not_own() -> void:
	var run := _run_at(3)
	var hunt := RelicHunt.build(_db, run, _rng())
	for card: Dictionary in hunt.cards:
		if int(card.kind) == RelicHunt.Kind.RELIC:
			assert_false(run.relic_ids.has(card.relic))
			assert_not_null(_db.get_relic(card.relic))


func test_with_every_relic_owned_the_fifth_card_pays_gold_instead() -> void:
	var run := _run_at(3)
	for id: StringName in _db.all_relic_ids():
		run.relic_ids.append(id)
	var hunt := RelicHunt.build(_db, run, _rng())
	assert_eq(hunt.cards.size(), 5)
	assert_false(hunt.has_relic())


func test_shuffling_keeps_every_card_and_moves_them() -> void:
	var moved := 0
	for seed_value in 12:
		var hunt := RelicHunt.build(_db, _run_at(3), _rng(seed_value))
		var before := hunt.cards.duplicate()
		hunt.shuffle(_rng(seed_value + 100))
		assert_eq(hunt.cards.size(), 5, "no card lost")
		var kinds_before := before.map(func(c: Dictionary) -> int: return int(c.kind))
		var kinds_after := hunt.cards.map(func(c: Dictionary) -> int: return int(c.kind))
		kinds_before.sort()
		kinds_after.sort()
		assert_eq(kinds_after, kinds_before, "the same five cards")
		if before[4] != hunt.cards[4]:
			moved += 1
	assert_gt(moved, 6, "the relic does not sit in the same place every time")


func test_only_the_first_pick_counts() -> void:
	var hunt := RelicHunt.build(_db, _run_at(3), _rng())
	assert_false(hunt.reveal(0).is_empty())
	assert_true(hunt.reveal(1).is_empty(), "the table is already turned")
	assert_eq(hunt.revealed, 0)
	assert_true(hunt.reveal(-1).is_empty())


func test_claiming_a_gold_card_pays_and_a_relic_card_is_kept() -> void:
	var run := _run_at(4)
	var hunt := RelicHunt.build(_db, run, _rng())
	var gold_index := -1
	var relic_index := -1
	for i in hunt.cards.size():
		if int(hunt.cards[i].kind) == RelicHunt.Kind.GOLD and gold_index < 0:
			gold_index = i
		if int(hunt.cards[i].kind) == RelicHunt.Kind.RELIC:
			relic_index = i
	hunt.reveal(gold_index)
	assert_string_contains(hunt.claim(_db, run), "coins")
	assert_eq(run.coins, 20, "5 x encounter 4")

	var hunt2 := RelicHunt.build(_db, run, _rng(3))
	relic_index = -1
	for i in hunt2.cards.size():
		if int(hunt2.cards[i].kind) == RelicHunt.Kind.RELIC:
			relic_index = i
	hunt2.reveal(relic_index)
	assert_string_contains(hunt2.claim(_db, run), "Relic")
	assert_eq(run.relic_ids.size(), 1)


func test_the_blank_card_pays_nothing() -> void:
	var run := _run_at(4)
	run.coins = 5
	var hunt := RelicHunt.build(_db, run, _rng())
	for i in hunt.cards.size():
		if int(hunt.cards[i].kind) == RelicHunt.Kind.BLANK:
			hunt.reveal(i)
			break
	hunt.claim(_db, run)
	assert_eq(run.coins, 5)
	assert_true(run.relic_ids.is_empty())


func test_claiming_before_revealing_does_nothing() -> void:
	var run := _run_at(4)
	var hunt := RelicHunt.build(_db, run, _rng())
	assert_eq(hunt.claim(_db, run), "")
	assert_eq(run.coins, 0)
