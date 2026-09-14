extends GutTest
## Patch 0.22 (build 0.0.112), designer's rule: "Debuff counters should reduce
## by 1 at the end of each character's turn, not the start" — and, on the
## follow-up question, buffs tick at the START of their owner's turn while
## debuffs tick at its END.
##
## Turn boundaries in this sim:
##   hero turn start = begin_round()      hero turn end = end_assignment()
##   enemy turn start = just before it acts in the enemy phase
##   enemy turn end   = right after it acts (or after its action was skipped)
##
## What that buys: a Weak 2 an enemy lands on Ace covers Ace's next TWO turns
## (it used to lose a stack before he acted once), a Taunt 2 the Bouncer gives
## itself covers two hero turns, and a Stun is spent by the action it skipped.

var _db: ContentDB


func before_all() -> void:
	_db = ContentDB.new()
	assert_true(_db.load_all("res://data"), str(_db.errors))


func _sim(enemies: Array = ["bouncer"], abilities: Array = ["card_sling"],
		seed_value: int = 7) -> CombatSim:
	var sim := CombatSim.new(_db, {
		"hero": "ace",
		"abilities": abilities,
		"enemies": enemies,
		"seed": seed_value,
	})
	sim.hero.max_hp = 9999
	sim.hero.hp = 9999
	return sim


## One full round with no player action.
func _pass_turn(sim: CombatSim) -> void:
	sim.begin_round()
	sim.tray.discard_all()
	sim.end_assignment()


# ---- the split itself ----

func test_duration_statuses_are_split_into_buffs_and_debuffs() -> void:
	assert_has(StatusRules.DURATION_BUFFS, &"taunt")
	for id: StringName in [&"weak", &"vulnerable", &"frail", &"stun"]:
		assert_has(StatusRules.DURATION_DEBUFFS, id)
	for id: StringName in StatusRules.DURATION_STATUSES:
		assert_true(StatusRules.DURATION_BUFFS.has(id) != StatusRules.DURATION_DEBUFFS.has(id),
			"%s is exactly one of buff/debuff" % id)


func test_the_content_agrees_with_the_split() -> void:
	# statuses.json carries the same "kind" so the data is self-describing.
	for id: StringName in StatusRules.DURATION_STATUSES:
		var status := _db.get_status(id)
		assert_not_null(status, str(id))
		var expected := "buff" if StatusRules.DURATION_BUFFS.has(id) else "debuff"
		assert_eq(status.kind, expected, "%s kind" % id)


func test_turn_start_ticks_buffs_and_turn_end_ticks_debuffs() -> void:
	var actor := CombatActor.new(&"x", &"x", "X", 30)
	actor.apply_status(&"taunt", 2)
	actor.apply_status(&"weak", 2)
	actor.apply_status(&"strength", 3)

	actor.tick_turn_start()
	assert_eq(actor.status_stacks(&"taunt"), 1, "buffs tick at the start")
	assert_eq(actor.status_stacks(&"weak"), 2, "debuffs do not")
	actor.tick_turn_end()
	assert_eq(actor.status_stacks(&"taunt"), 1, "buffs do not tick at the end")
	assert_eq(actor.status_stacks(&"weak"), 1, "debuffs tick at the end")
	assert_eq(actor.status_stacks(&"strength"), 3, "intensity statuses never tick")


# ---- the hero's side ----

func test_an_enemy_debuff_on_ace_covers_his_next_two_turns() -> void:
	# The Manager's Performance Review applies Vulnerable 1 + Weak 1; the
	# Server's Hot Plate applies Vulnerable 2. Apply Weak 2 directly so the
	# rule is tested rather than one enemy's move order.
	var sim := _sim()
	sim.begin_round()
	sim.hero.apply_status(&"weak", 2)      # as if an enemy had just landed it
	sim.tray.discard_all()
	sim.end_assignment()                   # hero turn end: 2 -> 1
	assert_eq(sim.hero.status_stacks(&"weak"), 1, "one stack spent per hero turn")
	sim.begin_round()
	assert_eq(sim.hero.status_stacks(&"weak"), 1, "still weak on his second turn")
	sim.tray.discard_all()
	sim.end_assignment()
	assert_false(sim.hero.has_status(&"weak"), "gone after the second turn")


func test_frail_lands_in_the_enemy_phase_and_taxes_the_whole_next_turn() -> void:
	var sim := _sim(["server"], ["quick_maneuvers"], 3)
	var landed := false
	for i in 6:
		_pass_turn(sim)
		if sim.hero.has_status(&"frail"):
			landed = true
			break
	assert_true(landed, "the Server spills a drink within six rounds")
	var stacks := sim.hero.status_stacks(&"frail")
	sim.begin_round()
	assert_eq(sim.hero.status_stacks(&"frail"), stacks,
		"a debuff is not spent before Ace has acted under it")


# ---- the enemies' side ----

func test_a_weak_ace_applies_covers_one_enemy_action_then_expires() -> void:
	var sim := _sim()
	sim.begin_round()
	var bouncer := sim.enemies[0]
	bouncer.apply_status(&"weak", 1)
	sim.tray.discard_all()
	sim.end_assignment()                   # it acts weakened, then its turn ends
	assert_false(bouncer.has_status(&"weak"), "spent by the action it weakened")


func test_the_bouncers_door_check_taunts_for_two() -> void:
	var bouncer := _db.get_enemy(&"bouncer")
	var buff: Dictionary = bouncer.moves["door_check"].intent.self_status[0]
	assert_eq(str(buff.status), "taunt")
	assert_eq(int(buff.stacks), 2)


func test_a_taunt_on_an_enemy_covers_two_hero_turns() -> void:
	# Applied directly, and to a Server rather than the Bouncer: the Bouncer's
	# own Door Check would re-taunt mid-test, so this would be measuring its
	# shuffled brain instead of the tick rule.
	var sim := _sim(["server"], ["card_sling"], 3)
	var server := sim.enemies[0]
	sim.begin_round()
	server.apply_status(&"taunt", 2)      # as if it had just taunted
	sim.tray.discard_all()
	sim.end_assignment()                  # its own turn start spends a stack
	assert_eq(server.status_stacks(&"taunt"), 1)

	sim.begin_round()
	assert_true(server.has_status(&"taunt"), "still forced on the second hero turn")
	sim.tray.discard_all()
	sim.end_assignment()
	assert_false(server.has_status(&"taunt"), "spent after its second turn start")

	sim.begin_round()
	assert_false(server.has_status(&"taunt"), "free on the third hero turn")


func test_a_stun_is_spent_by_the_action_it_skipped() -> void:
	var sim := _sim()
	sim.begin_round()
	sim.enemies[0].apply_status(&"stun", 1)
	sim.tray.discard_all()
	sim.end_assignment()
	assert_eq(sim.hero.hp, sim.hero.max_hp, "the move was skipped")
	assert_false(sim.enemies[0].has_status(&"stun"), "and the stun is used up")
	var hp_before := sim.hero.hp
	_pass_turn(sim)
	assert_lt(sim.hero.hp, hp_before, "it acts again the next round")


func test_enemy_block_survives_until_its_own_next_turn() -> void:
	# The Chip Golem's Harden gains 20 Block; that shield has to still be
	# standing when Ace swings at it, so block now clears at the enemy's own
	# turn start rather than at the hero's round start.
	var sim := _sim()
	sim.begin_round()
	sim.enemies[0].gain_block(20)
	sim.tray.discard_all()
	sim.end_assignment()
	sim.begin_round()
	assert_eq(sim.enemies[0].block, 0, "spent at its own turn start")

	sim.end_assignment()
	sim.begin_round()
	sim.enemies[0].block = 0
	sim.enemies[0].gain_block(20)          # as if it had just hardened
	assert_eq(sim.enemies[0].block, 20)
	sim.tray.discard_all()
	assert_eq(sim.enemies[0].block, 20, "still up while Ace takes his turn")


# ---- block preview (note 2 of the patch) ----

func test_preview_block_matches_what_the_ability_will_actually_grant() -> void:
	var sim := _sim()
	assert_eq(sim.preview_block(8), 8)
	sim.hero.apply_status(&"frail", 2)
	assert_eq(sim.preview_block(8), 6, "8 x 0.75")
	assert_eq(sim.preview_block(5), 4, "3.75 rounds half-up")
	var effects: Array[Dictionary] = [{"op": "gain_block", "amount": 8}]
	EffectInterpreter.execute(effects, sim, sim.hero, null)
	assert_eq(sim.hero.block, 6, "the preview is the payout")
