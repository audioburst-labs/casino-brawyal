extends GutTest
## Patch 0.21 (build 0.0.111): the small doc syncs (free Casino spin with the
## new prize table, the final shop back at #9, Frail, the enemy number
## changes), per-actor enemy seating, loadout swaps, and the run remembering
## the encounter it was in the middle of.

var _db: ContentDB


func before_all() -> void:
	_db = ContentDB.new()
	assert_true(_db.load_all("res://data"), str(_db.errors))


func _rng(seed_value: int = 8) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _sim(enemies: Array = ["manager"], abilities: Array = ["card_sling"],
		seed_value: int = 7) -> CombatSim:
	return CombatSim.new(_db, {
		"hero": "ace",
		"abilities": abilities,
		"enemies": enemies,
		"seed": seed_value,
	})


# ---- Casino: the doc dropped the spin cost and added Broken Coins ----

func test_casino_spin_is_free() -> void:
	var run := RunState.new()
	run.coins = 0
	var result := CasinoGame.spin(_db, run, _rng())
	assert_false(result.is_empty(), "a spin no longer needs coins")
	assert_eq(result.symbols.size(), 3)


func test_casino_prize_table_is_the_docs_and_every_roll_lands_a_listed_prize() -> void:
	# The doc's v0.120 table adds up to 90, not 100 (flagged in the report);
	# the draw rolls over the real total so no weight is silently inflated.
	var total := 0
	var ids: Array[StringName] = []
	for prize: Dictionary in CasinoGame.PRIZES:
		total += int(prize.weight)
		ids.append(prize.id)
	# The 0.122 doc added Empty Money Sack and Multiple Broken Hearts and
	# halved the four stickers, so the listed shares total 80, not 90. The
	# draw rolls over total_weight(), so every share stays in proportion.
	assert_eq(total, 80)
	assert_eq(CasinoGame.total_weight(), total)
	assert_has(ids, &"broken_coins")
	assert_eq(int(CasinoGame.PRIZES[0].weight), 10, "coins are 10% now, not 20%")
	var seen := {}
	for seed_value in 900:
		seen[CasinoGame._draw(_rng(seed_value))] = true
	assert_false(seen.has(&"__fallthrough"))
	assert_true(seen.has(&"broken_coins"))
	assert_true(seen.has(&"extra_reel"), "the 1% reel still lands over 900 rolls")


func test_broken_coins_lose_five_per_encounter_and_never_go_negative() -> void:
	var run := RunState.new()
	run.record_visit(&"combat")
	run.record_visit(&"combat")  # encounter number = 3
	run.coins = 40
	CasinoGame._award(&"broken_coins", _db, run, _rng())
	assert_eq(run.coins, 25, "lose 5 x encounter 3")
	run.coins = 4
	CasinoGame._award(&"broken_coins", _db, run, _rng())
	assert_eq(run.coins, 0, "clamped at zero")


# ---- Choice: the guaranteed final shop moved back to #9 ----

## Patch 0.114: placement is authored in the six Paths now, so this asks the
## data rather than a generator constant — but the guarantee is the same one.
func test_final_shop_is_offered_at_encounter_nine_beside_the_rest() -> void:
	for path: Dictionary in _db.all_paths():
		var ninth: Array = path.encounters[8]
		assert_has(ninth, &"shop", "%s offers the last shop at 9" % path.id)
		assert_has(ninth, &"rest", "%s offers rest beside it" % path.id)


# ---- Frail: 25% less Block from abilities ----

func test_frail_cuts_block_gained_by_a_quarter_half_up() -> void:
	var sim := _sim()
	sim.hero.apply_status(&"frail", 2)
	var effects: Array[Dictionary] = [{"op": "gain_block", "amount": 8}]
	EffectInterpreter.execute(effects, sim, sim.hero, null)
	assert_eq(sim.hero.block, 6, "8 x 0.75 = 6")
	sim.hero.block = 0
	effects = [{"op": "gain_block", "amount": 5}]
	EffectInterpreter.execute(effects, sim, sim.hero, null)
	assert_eq(sim.hero.block, 4, "3.75 rounds half-up to 4")


func test_frail_is_a_duration_status_that_ticks_down() -> void:
	assert_has(StatusRules.DURATION_STATUSES, &"frail")
	var sim := _sim()
	sim.hero.apply_status(&"frail", 1)
	sim.hero.tick_turn_end()
	assert_false(sim.hero.has_status(&"frail"))
	var effects: Array[Dictionary] = [{"op": "gain_block", "amount": 8}]
	EffectInterpreter.execute(effects, sim, sim.hero, null)
	assert_eq(sim.hero.block, 8, "full block once Frail wears off")


func test_server_spilled_drink_now_applies_frail() -> void:
	var server := _db.get_enemy(&"server")
	var debuffs: Array = server.moves["spilled_drink"].intent.debuffs
	assert_eq(str(debuffs[0].status), "frail")
	assert_eq(int(debuffs[0].stacks), 2)


# ---- the sheet's other number changes ----

func test_bouncer_health_is_fifty_to_fifty_five() -> void:
	# 50-60 in the 0.120 sheet, 50-55 in the 0.121 pull (patch 0.113).
	var bouncer := _db.get_enemy(&"bouncer")
	assert_eq(bouncer.hp_min, 56)
	assert_eq(bouncer.hp_max, 60)


func test_boss_summons_one_bouncer_and_grows_stronger_when_he_heals() -> void:
	var boss := _db.get_enemy(&"mr_moneybags")
	assert_eq(int(boss.moves["call_bouncers"].intent.summon.count), 1)
	var bonuses: Dictionary = boss.moves["bonuses"].intent
	assert_eq(int(bonuses.heal_allies), 20)
	assert_eq(str(bonuses.self_status[0].status), "strength")
	# Sheet v0.121: "Heal all allies 20. Strength 3." (was Increase Damage 2).
	assert_eq(int(bonuses.self_status[0].stacks), 3)


# ---- Unit positioning: a lone enemy stands one slot nearer the centre, and
# ---- nobody moves when a summon arrives ----

const CombatScreenScript := preload("res://src/ui/combat_screen.gd")


func test_a_lone_enemy_takes_the_second_slot_out() -> void:
	assert_eq(CombatScreenScript.initial_slots(1), [1])
	assert_eq(CombatScreenScript.initial_slots(2), [0, 1])
	assert_eq(CombatScreenScript.initial_slots(4), [0, 1, 2, 3])


func test_a_summon_takes_the_free_inner_slot_and_the_summoner_stays_put() -> void:
	# Sim order is centre-outward: the summon is inserted inward of its summoner.
	var seats := {&"manager": 1}
	var order: Array[StringName] = [&"summon", &"manager"]
	var result := CombatScreenScript.seat_summon(order, seats, &"summon")
	assert_eq(int(result[&"summon"]), 0)
	assert_eq(int(result[&"manager"]), 1, "the manager does not move")


func test_a_summon_with_no_inner_room_pushes_the_summoner_outward() -> void:
	var seats := {&"a": 0, &"b": 1}
	var order: Array[StringName] = [&"a", &"summon", &"b"]
	var result := CombatScreenScript.seat_summon(order, seats, &"summon")
	assert_eq(int(result[&"a"]), 0)
	assert_eq(int(result[&"summon"]), 1)
	assert_eq(int(result[&"b"]), 2, "the doc: the summoner shifts one position outward")


func test_a_summon_prefers_the_free_slot_nearest_its_summoner() -> void:
	var seats := {&"a": 0, &"b": 3}
	var order: Array[StringName] = [&"a", &"summon", &"b"]
	var result := CombatScreenScript.seat_summon(order, seats, &"summon")
	assert_eq(int(result[&"summon"]), 2)
	assert_eq(int(result[&"b"]), 3)


# ---- Ability Choosing screen: dropping one ability on another swaps them ----

func test_swapping_two_equipped_abilities_exchanges_their_positions() -> void:
	var run := RunState.new()
	for id in [&"a", &"b", &"c"]:
		run.acquire_ability(id)
	assert_true(run.swap_abilities(&"a", &"c"))
	assert_eq(run.equipped_ids, [&"c", &"b", &"a"] as Array[StringName])


func test_swapping_an_equipped_ability_with_the_trashed_one() -> void:
	var run := RunState.new()
	for i in 7:
		run.acquire_ability(StringName("ability_%d" % i))
	assert_eq(run.trash_id, &"ability_6")
	assert_true(run.swap_abilities(&"ability_2", &"ability_6"))
	assert_eq(run.trash_id, &"ability_2")
	assert_eq(run.equipped_ids[2], &"ability_6", "the rescued one takes the vacated position")
	assert_eq(run.ability_ids.size(), 7, "nothing was deleted")


func test_swapping_with_itself_or_an_unknown_ability_is_refused() -> void:
	var run := RunState.new()
	run.acquire_ability(&"a")
	assert_false(run.swap_abilities(&"a", &"a"))
	assert_false(run.swap_abilities(&"a", &"nope"))


# ---- the run remembers the encounter it is in ----

func test_pending_encounter_survives_the_save_roundtrip() -> void:
	var run := RunState.new()
	run.record_visit(&"combat")
	run.pending_encounter = {"type": "combat", "lineup": "door_duty", "seed": 4242}
	var restored := RunState.from_dict(run.to_dict())
	assert_eq(str(restored.pending_encounter.type), "combat")
	assert_eq(str(restored.pending_encounter.lineup), "door_duty")
	assert_eq(int(restored.pending_encounter.seed), 4242)
	run.pending_encounter = {}
	assert_true(RunState.from_dict(run.to_dict()).pending_encounter.is_empty())


func test_combat_config_can_be_pinned_to_a_lineup() -> void:
	var run := RunState.new()
	run.record_visit(&"combat")
	var config := EncounterFactory.combat_config(_db, run, _rng(),
		{"type": &"combat", "lineup": &"double_shift"})
	assert_eq(config.enemies, [&"server", &"server"] as Array[StringName])
	assert_eq(str(config.lineup), "double_shift", "the config names the lineup it drew")
