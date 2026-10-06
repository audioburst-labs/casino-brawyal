extends GutTest
## Patch 0.117: the designer's playtest list, the parts a test can pin.
##
## Not here, because they are presentation: the Block readout vanishing at a
## turn start, the loan HP bounce, the Earn and gift-chip animations, the
## passive plaques, the suit icons and limit pills on the ability lists.
## Those are checked on screen in the report.

var db: ContentDB


func before_each() -> void:
	db = ContentDB.new()
	assert_true(db.load_all("res://data"), str(db.errors))


func _sim(enemies: Array, abilities: Array, seed_value := 7,
		extra: Dictionary = {}) -> CombatSim:
	var config := {"hero": "ace", "enemies": enemies, "abilities": abilities,
		"seed": seed_value}
	config.merge(extra)
	var sim := CombatSim.new(db, config)
	sim.begin_round()
	sim.drain_events()
	return sim


## Fill every socket of ability `index` with what it asks for (Spade for any).
func _fire(sim: CombatSim, index: int, any_as: StringName = &"spade") -> void:
	var state: AbilityState = sim.abilities[index]
	for slot in state.def.cost.size():
		var suit: StringName = state.def.cost[slot]
		if suit == &"any":
			suit = any_as
		sim.tray.add(suit, 1)
		assert_true(sim.assign_chip(suit, index, slot),
			"%s slot %d refused %s" % [state.def.id, slot, suit])


func _types(sim: CombatSim) -> Array:
	return sim.drain_events().map(func(e: CombatEvent) -> StringName: return e.type)


# ---------------------------------------------------------------- Mark

## "Mark should not be stackable: a toggle state (marked or not marked)."
func test_marking_a_marked_enemy_does_not_stack() -> void:
	var sim := _sim(["bouncer"], ["sharp_edge", "card_sling"])
	_fire(sim, 0)          # Sharp Edge's active half: Mark
	_fire(sim, 1)          # Card Sling with a Spade: Mark again
	assert_eq(sim.enemies[0].status_stacks(&"mark"), 1, "marked is marked")


func test_one_cash_in_clears_the_mark_entirely() -> void:
	var sim := _sim(["bouncer"], ["sharp_edge", "card_sling", "double_down", "bust"])
	_fire(sim, 0)
	_fire(sim, 1)
	sim.drain_events()
	_fire(sim, 2)          # Double Down cashes in
	assert_false(sim.enemies[0].has_status(&"mark"), "the Mark is spent")
	var before := sim.enemies[0].hp
	_fire(sim, 3)          # Bust has nothing to cash: no else_effects, no damage
	assert_eq(sim.enemies[0].hp, before, "Bust unmarked does nothing")


func test_a_second_mark_does_not_fire_the_mark_triggers() -> void:
	# Reversed in 0.121 (designer): Sharp Edge pays when a Mark goes ON, not
	# when one is merely applied to an enemy that already wears it.
	var sim := _sim(["bouncer"], ["sharp_edge", "card_sling"])
	_fire(sim, 0)
	sim.drain_events()
	_fire(sim, 1)
	var fired := _types(sim).count(&"passive_fired")
	assert_eq(fired, 0, "already marked, so Sharp Edge stays quiet")


# ------------------------------------------------------------ Chip Tricks

## "Chip Tricks passive doesn't always work with other abilities that Earn."
## Every ability carrying the Earn keyword, played after Chip Tricks is
## active, must hand the hero 1 Block.
func test_chip_tricks_pays_for_every_earn_in_the_kit() -> void:
	var earners: Array[String] = []
	for id in db.all_ability_ids():
		var def := db.get_ability(StringName(id))
		if def.keywords.has(&"earn") and def.id != &"chip_tricks":
			earners.append(String(id))
	assert_false(earners.is_empty())
	for id in earners:
		var sim := _sim(["bouncer"], ["chip_tricks", id])
		_fire(sim, 0)                       # activate the passive
		sim.drain_events()
		var block_before := sim.hero.block
		var mark_it := id in ["card_trick"]   # its Earn is behind a Cash In
		if mark_it:
			sim.enemies[0].apply_status(&"mark", 1)
		_fire(sim, 1)
		assert_gt(sim.hero.block, block_before,
			"%s Earned but Chip Tricks did not pay" % id)


## Pocket Rockets Earns only when both chips are Spades; with Chip Tricks
## active that is the only time it should pay.
func test_chip_tricks_does_not_pay_for_an_earn_that_did_not_happen() -> void:
	var sim := _sim(["bouncer"], ["chip_tricks", "pocket_rockets"])
	_fire(sim, 0)
	sim.drain_events()
	var before := sim.hero.block
	_fire(sim, 1, &"club")              # not Spades: no Earn
	assert_eq(sim.hero.block, before)


# ------------------------------------------------------------ the sheet

## Sheet 0.117: Pocket Rockets is "Deal 6 damage twice" (7, 8 upgraded).
func test_pocket_rockets_hits_twice() -> void:
	var def := db.get_ability(&"pocket_rockets")
	assert_eq(int(def.effects[0].get("amount", 0)), 6)
	assert_eq(int(def.effects[0].get("times", 1)), 2)
	assert_eq(int(db.get_ability(&"pocket_rockets", 1).effects[0].get("amount", 0)), 7)
	assert_eq(int(db.get_ability(&"pocket_rockets", 2).effects[0].get("amount", 0)), 8)
	var sim := _sim(["bouncer"], ["pocket_rockets"])
	var before := sim.enemies[0].hp
	_fire(sim, 0, &"club")
	assert_eq(before - sim.enemies[0].hp, 12, "two hits of 6")
	assert_eq(_types(sim).count(&"damage_dealt"), 2)


func test_absorb_keyword_reads_as_the_sheet_says() -> void:
	assert_eq(db.get_keyword(&"absorb").text, "Consume all chips left on abilities.")


## The Chip Golem's passive fires every 30 health (sheet v0.122); its
## tooltip still said 20. The number is read off the def so it cannot drift.
func test_break_tooltip_matches_the_golem_def() -> void:
	var golem := db.get_enemy(&"chip_golem")
	assert_eq(int(golem.passive.get("every", 0)), 30)
	assert_false(db.get_keyword(&"break").text.contains("20"))
	assert_true(db.get_keyword(&"break").text.contains("30"))


# ------------------------------------------------------------- Max HP

## "Max HP numbers in the UI and below the character are inconsistent."
## The header shows run.max_hp; the panel showed the hero def's 80 because
## the combat config only ever carried current HP.
func test_combat_hero_carries_the_runs_max_hp() -> void:
	var run := RunState.new()
	run.max_hp = 95
	run.hp = 60
	run.history.append(&"combat")
	var config := EncounterFactory.combat_config(db, run,
		RandomNumberGenerator.new(), {"type": &"combat"})
	assert_eq(int(config.get("hero_max_hp", 0)), 95)
	var sim := CombatSim.new(db, config)
	assert_eq(sim.hero.max_hp, 95)
	assert_eq(sim.hero.hp, 60)


# -------------------------------------------------------------- Elites

## "You should only be able to fight an elite once: two Elite encounters
## must be two different ones."
func test_a_run_never_offers_the_same_elite_lineup_twice() -> void:
	var run := RunState.new()
	run.history.append(&"combat")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var first := EncounterFactory.combat_config(db, run, rng, {"type": &"elite"})
	run.record_lineup(StringName(str(first.lineup)))
	for i in 30:
		var again := EncounterFactory.combat_config(db, run, rng, {"type": &"elite"})
		assert_ne(String(again.lineup), String(first.lineup),
			"the second Elite rolled the first one again")


func test_fought_lineups_survive_a_save() -> void:
	var run := RunState.new()
	run.record_lineup(&"vault_golem")
	var revived := RunState.from_dict(run.to_dict())
	assert_eq(revived.fought_lineups, [&"vault_golem"] as Array[StringName])


func test_a_resumed_elite_keeps_its_pinned_lineup_even_if_fought() -> void:
	# Resuming mid-fight must give the SAME fight back, never a re-roll.
	var run := RunState.new()
	run.history.append(&"combat")
	var elite_id: StringName = db.elite_lineups()[0].id
	run.record_lineup(elite_id)
	var config := EncounterFactory.combat_config(db, run,
		RandomNumberGenerator.new(), {"type": &"elite", "lineup": elite_id})
	assert_eq(StringName(str(config.lineup)), elite_id)


# --------------------------------------------------------------- Loans

## "Cash Advance should always give coins, taking as many as it can at the
## end of the cooldown." Coins cannot wait for the fight to end (a lost fight
## paid nothing), so loan coin ops are handed to the run at once.
func test_cash_advance_pays_its_coins_the_moment_it_is_taken() -> void:
	var sim := _sim(["loan_shark"], ["card_sling"])
	if sim.phase != CombatSim.Phase.CHOICE:
		sim.drain_events()
	assert_eq(sim.phase, CombatSim.Phase.CHOICE, "the Loan Shark offers on round 1")
	var options: Array = sim.pending_choice().get("options", [])
	var index := -1
	for i in options.size():
		if str(options[i].get("id", "")) == "cash_advance":
			index = i
	if index < 0:
		pass_test("cash_advance was not among this seed's two offers")
		return
	sim.choose(index)
	var ops: Array = []
	for e in sim.drain_events():
		if e.type == &"run_effect":
			ops.append(e.data.get("op"))
	assert_has(ops, "gain_coins", "the coins are a run_effect now, not a pending reward")
	assert_false(sim.pending_rewards.any(
		func(r: Dictionary) -> bool: return str(r.get("op", "")) == "gain_coins"),
		"and they are not ALSO queued for the end of the fight")


func test_the_loan_penalty_takes_as_many_coins_as_it_can() -> void:
	var run := RunState.new()
	run.coins = 30
	RunEffects.apply([{"op": "lose_coins", "amount": 50}], db, run,
		RandomNumberGenerator.new())
	assert_eq(run.coins, 0)


# ------------------------------------------------------ Chip placement

## Doc "Chip Placement on Abilities" (0.117): a chip dropped on the CARD
## takes a matching suit slot first, then the leftmost open generic slot.
func test_placement_prefers_the_matching_suit_slot() -> void:
	var def := db.get_ability(&"double_down")      # [any, spade]
	var state := AbilityState.new(def)
	assert_eq(state.placement_slot(&"spade"), 1, "the Spade slot first")
	assert_eq(state.placement_slot(&"heart"), 0, "a Heart can only go generic")


func test_placement_takes_the_leftmost_open_generic_slot() -> void:
	var def := db.get_ability(&"pocket_rockets")   # [any, any]
	var state := AbilityState.new(def)
	assert_eq(state.placement_slot(&"heart"), 0)
	state.fill(0, &"heart")
	assert_eq(state.placement_slot(&"heart"), 1)
	state.fill(1, &"club")
	assert_eq(state.placement_slot(&"heart"), -1, "full")


func test_placement_rejects_a_suit_with_nowhere_to_go() -> void:
	var def := db.get_ability(&"card_trick")       # [club]
	var state := AbilityState.new(def)
	assert_eq(state.placement_slot(&"heart"), -1)
	assert_eq(state.placement_slot(&"club"), 0)


# ---------------------------------------------------------------- Weak

## "Weak should change all damage instances on an ability." With Ace Weak,
## every printed damage figure dropped except The River's: its op is
## damage_per_ability and the card's number walker only knew plain damage.
func test_the_rivers_figure_is_a_damage_amount_the_card_can_modify() -> void:
	var river := db.get_ability(&"the_river")
	assert_eq(AbilityCard.damage_amounts(river), [10] as Array[int])


func test_every_kit_ability_that_deals_damage_prints_a_modifiable_figure() -> void:
	# Any ability whose description says "Deal N" must expose N, or Weak,
	# Strength and All In cannot move the number on the card.
	var regex := RegEx.new()
	# "deal 30% more damage" (All In) is a percentage, not a figure to modify.
	regex.compile("[Dd]eal ([0-9]+)(?![0-9%])")
	for id in db.all_ability_ids():
		var def := db.get_ability(StringName(id))
		var printed := AbilityCard.damage_amounts(def)
		for m in regex.search_all(def.description):
			var figure := int(m.get_string(1))
			assert_has(printed, figure,
				"%s prints %d but the card cannot modify it" % [id, figure])
