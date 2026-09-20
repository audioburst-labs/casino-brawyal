extends GutTest
## Patch 0.22: "Options In Combat" and the Loan Shark's Loans (doc "Loan") —
## the round pauses on a choice, the reward lands at once, and the price is
## paid N turns later.

var _db: ContentDB


func before_all() -> void:
	_db = ContentDB.new()
	assert_true(_db.load_all("res://data"), str(_db.errors))


func _sim(enemies: Array = ["loan_shark"], seed_value: int = 4) -> CombatSim:
	var sim := CombatSim.new(_db, {
		"hero": "ace",
		"abilities": ["card_sling"],
		"enemies": enemies,
		"seed": seed_value,
	})
	sim.hero.max_hp = 9999
	sim.hero.hp = 9999
	return sim


func _types(events: Array) -> Array:
	return events.map(func(e: CombatEvent) -> StringName: return e.type)


# ---- the content ----

func test_the_five_loans_load() -> void:
	var ids := _db.all_loan_ids()
	assert_eq(ids.size(), 5)
	for id: StringName in ids:
		var loan := _db.get_loan(id)
		assert_gt(loan.turns, 0, str(id))
		assert_false(loan.reward.is_empty(), str(id))
		assert_false(loan.penalty.is_empty(), str(id))
		assert_ne(loan.reward_text, "", str(id))
		assert_ne(loan.penalty_text, "", str(id))


func test_the_sheets_five_loans_are_the_ones_shipped() -> void:
	var turns := {}
	for id: StringName in _db.all_loan_ids():
		var loan := _db.get_loan(id)
		turns[loan.reward_text] = loan.turns
	# Sheet v0.122 (patch 0.114): Pocket Change came in to 2 turns and House
	# Doctor now heals 10, so BOTH heal loans read "Heal 10." — they are told
	# apart by their term, 2 turns against 3.
	assert_eq(int(turns.get("Gain 1 random Chip.", -1)), 2)
	assert_eq(int(turns.get("Gain 2 random Chips.", -1)), 4)
	assert_eq(int(turns.get("Gain 20 Coins.", -1)), 2)
	assert_eq(_db.get_loan(&"quick_patch").turns, 2)
	assert_eq(_db.get_loan(&"house_doctor").turns, 3)


# ---- the choice ----

func test_the_loan_shark_stops_the_round_before_the_spin() -> void:
	var sim := _sim()
	sim.begin_round()
	assert_eq(sim.phase, CombatSim.Phase.CHOICE)
	var types := _types(sim.drain_events())
	assert_has(types, &"intents_shown")
	assert_has(types, &"choice_offered")
	assert_does_not_have(types, &"spin_resolved", "the machine waits for the answer")
	assert_eq(sim.tray.total(), 0)
	var options: Array = sim.pending_choice().options
	assert_eq(options.size(), 2, "1 of 2 loans")
	assert_ne(str(options[0].id), str(options[1].id), "two different ones")


func test_choosing_pays_out_then_spins_into_the_assignment_phase() -> void:
	var sim := _sim()
	sim.begin_round()
	sim.drain_events()
	assert_true(sim.choose(0))
	assert_eq(sim.phase, CombatSim.Phase.ASSIGNMENT)
	var types := _types(sim.drain_events())
	assert_has(types, &"loan_taken")
	assert_has(types, &"spin_resolved")
	assert_gt(sim.tray.total(), 0, "the round's chips arrive as usual")
	assert_eq(sim.hero.loans.size(), 1, "and the debt is on the books")


func test_a_bad_index_or_the_wrong_phase_is_refused() -> void:
	var sim := _sim()
	sim.begin_round()
	assert_false(sim.choose(-1))
	assert_false(sim.choose(9))
	assert_eq(sim.phase, CombatSim.Phase.CHOICE, "still waiting")
	assert_true(sim.choose(1))
	assert_false(sim.choose(0), "and only once")


func test_a_loan_is_offered_every_third_round() -> void:
	var sim := _sim()
	var offered: Array[int] = []
	for i in 7:
		sim.begin_round()
		if sim.phase == CombatSim.Phase.CHOICE:
			offered.append(sim.round_number)
			sim.choose(0)
		sim.tray.discard_all()
		sim.end_assignment()
		if sim.phase == CombatSim.Phase.ENDED:
			break
	assert_has(offered, 1)
	assert_has(offered, 4)
	assert_does_not_have(offered, 2)
	assert_does_not_have(offered, 3)


func test_a_fight_without_a_loan_shark_never_pauses() -> void:
	var sim := _sim(["bouncer"])
	sim.begin_round()
	assert_eq(sim.phase, CombatSim.Phase.ASSIGNMENT)


# ---- the countdown ----

func test_the_countdown_runs_at_the_end_of_the_heros_turn_and_then_bites() -> void:
	var sim := _sim(["bouncer"])
	sim.begin_round()
	sim.hero.loans.append({"id": &"quick_patch", "turns_left": 2})  # 2 turns, 20 damage
	sim.hero.hp = 100
	sim.hero.max_hp = 100
	sim.tray.discard_all()
	sim.end_assignment()
	assert_eq(int(sim.hero.loans[0].turns_left), 1, "one turn gone")
	var hp_after_first := sim.hero.hp

	sim.begin_round()
	sim.hero.block = 0
	sim.tray.discard_all()
	sim.end_assignment()
	assert_true(sim.hero.loans.is_empty(), "paid off")
	# The Bouncer also hits, so compare against a run of the same fight is
	# awkward; assert the loan's own 20 landed on top of whatever it did.
	assert_lte(sim.hero.hp, hp_after_first - 20, "the 20 damage came due")


func test_the_loan_event_trail_is_complete() -> void:
	var sim := _sim(["bouncer"])
	sim.begin_round()
	sim.hero.loans.append({"id": &"pocket_change", "turns_left": 1})
	sim.tray.discard_all()
	sim.drain_events()
	sim.end_assignment()
	var types := _types(sim.drain_events())
	assert_has(types, &"loan_ticked")
	assert_has(types, &"loan_due")


func test_a_loan_can_kill_and_ends_the_combat_before_the_enemy_phase() -> void:
	var sim := _sim(["bouncer"])
	sim.begin_round()
	sim.hero.max_hp = 15
	sim.hero.hp = 15
	sim.hero.block = 0
	sim.hero.loans.append({"id": &"quick_patch", "turns_left": 1})   # 20 damage
	sim.tray.discard_all()
	sim.drain_events()
	sim.end_assignment()
	assert_eq(sim.phase, CombatSim.Phase.ENDED)
	var types := _types(sim.drain_events())
	assert_has(types, &"combat_lost")
	assert_does_not_have(types, &"enemy_move", "the enemy phase never ran")


func test_block_absorbs_a_loan_coming_due() -> void:
	var sim := _sim(["bouncer"])
	sim.begin_round()
	sim.hero.hp = 100
	sim.hero.max_hp = 100
	sim.hero.gain_block(50)
	sim.hero.loans.append({"id": &"quick_patch", "turns_left": 1})
	sim.tray.discard_all()
	sim.end_assignment()
	assert_eq(sim.hero.hp, 100, "the shield ate the whole debt")


# ---- the rewards ----

func test_a_chip_loan_hands_over_real_suits() -> void:
	var sim := _sim(["bouncer"])
	sim.begin_round()
	sim.tray.discard_all()
	var loan := _db.get_loan(&"double_stack")
	EffectInterpreter.execute(loan.reward, sim, sim.hero, null)
	assert_eq(sim.tray.total(), 2)
	var counted := 0
	for suit: StringName in ContentDB.SUITS:
		counted += sim.tray.count(suit)
	assert_eq(counted, 2, "both chips are one of the four suits")


func test_a_heal_loan_heals_and_a_coin_loan_reaches_the_run_layer() -> void:
	var sim := _sim(["bouncer"])
	sim.hero.max_hp = 100
	sim.hero.hp = 50
	EffectInterpreter.execute(_db.get_loan(&"house_doctor").reward, sim, sim.hero, null)
	assert_eq(sim.hero.hp, 60, "House Doctor heals 10 in sheet v0.122")

	EffectInterpreter.execute(_db.get_loan(&"cash_advance").reward, sim, sim.hero, null)
	var coins := sim.pending_rewards.filter(
		func(effect: Dictionary) -> bool: return str(effect.op) == "gain_coins")
	assert_eq(coins.size(), 1)
	assert_eq(int(coins[0].amount), 20)


func test_the_greedy_bot_can_finish_a_loan_shark_fight() -> void:
	var sim := CombatSim.new(_db, {
		"hero": "ace",
		"abilities": ["card_sling", "double_down", "flush"],
		"enemies": ["loan_shark"],
		"seed": 11,
	})
	GreedyBot.play_combat(sim)
	assert_eq(sim.phase, CombatSim.Phase.ENDED, "the choice never deadlocks the bot")
