extends GutTest
## Undo turn (phase 0 of the roadmap): the sim takes a snapshot the moment
## the assignment phase opens and can return to it until the player passes.
## The dangerous failure is a forgotten field: an undo that silently changes
## a later spin, which no player can see. Two tests guard against it: every
## script variable on the sim and the actor must be classified as snapshotted
## or static, and an undone round must end exactly where a clean one does.

var _db: ContentDB


func before_all() -> void:
	_db = ContentDB.new()
	assert_true(_db.load_all("res://data"), str(_db.errors))


func _sim(enemies: Array, seed_value: int, abilities: Array = ["card_sling", "quick_maneuvers",
		"double_down", "color_up"]) -> CombatSim:
	return CombatSim.new(_db, {
		"hero": "ace",
		"abilities": abilities,
		"enemies": enemies,
		"seed": seed_value,
	})


func _open_round(sim: CombatSim) -> void:
	sim.begin_round()
	if sim.phase == CombatSim.Phase.CHOICE:
		sim.choose(0)
	sim.drain_events()


## A deterministic policy that depends only on the sim's state, so two sims
## in the same state make the same moves.
func _play_a_few_chips(sim: CombatSim, how_many: int) -> void:
	var placed := 0
	for ability_index in sim.abilities.size():
		var ability: AbilityState = sim.abilities[ability_index]
		for slot in ability.def.cost.size():
			for suit: StringName in [&"spade", &"club", &"heart", &"diamond"]:
				if placed >= how_many:
					return
				if sim.tray.count(suit) > 0 and sim.assign_chip(suit, ability_index, slot):
					placed += 1
					break


func _fingerprint(sim: CombatSim) -> Dictionary:
	var enemies := []
	for enemy in sim.enemies:
		enemies.append([enemy.id, enemy.hp, enemy.block, enemy.statuses.duplicate(), enemy.passive_counter])
	var abilities := []
	for ability in sim.abilities:
		abilities.append([ability.filled.duplicate(), ability.uses_this_round, ability.uses_this_combat])
	return {
		"phase": sim.phase, "round": sim.round_number,
		"hero": [sim.hero.hp, sim.hero.block, sim.hero.statuses.duplicate(), sim.hero.loans.duplicate(true)],
		"enemies": enemies, "abilities": abilities,
		"tray": [sim.tray.count(&"spade"), sim.tray.count(&"club"), sim.tray.count(&"heart"), sim.tray.count(&"diamond")],
		"symbols": sim.last_symbols.duplicate(), "payout": sim.last_payout.duplicate(),
		"rewards": sim.pending_rewards.duplicate(true), "run_ops": sim.run_ops.duplicate(true),
	}


# ------------------------------------------------------------ the contract

func test_undo_is_not_offered_before_anything_happened() -> void:
	var sim := _sim(["bouncer"], 3)
	assert_false(sim.can_undo(), "nothing to undo before the round opens")
	_open_round(sim)
	assert_false(sim.can_undo(), "the snapshot is the present; nothing to undo yet")


func test_undo_returns_the_chips_and_the_damage() -> void:
	var sim := _sim(["bouncer"], 3)
	_open_round(sim)
	var before := _fingerprint(sim)
	_play_a_few_chips(sim, 6)
	assert_true(sim.can_undo())
	assert_true(sim.undo_turn())
	assert_eq(_fingerprint(sim), before)
	assert_false(sim.can_undo(), "undone: back at the snapshot")
	var types := sim.drain_events().map(func(e: CombatEvent) -> StringName: return e.type)
	assert_has(types, &"turn_undone")


func test_undo_is_refused_after_the_turn_was_passed() -> void:
	var sim := _sim(["bouncer"], 3)
	_open_round(sim)
	_play_a_few_chips(sim, 2)
	sim.end_assignment()
	assert_false(sim.can_undo())
	assert_false(sim.undo_turn())


## The target is the player's aim, not an action: undo returns the chips and
## leaves the aim where the player last put it.
func test_undo_keeps_the_target_the_player_chose_last() -> void:
	var sim := _sim(["bouncer", "server"], 11)
	_open_round(sim)
	sim.set_target(sim.enemies[0].id)
	_play_a_few_chips(sim, 1)
	var second := sim.enemies[1].id
	sim.set_target(second)
	assert_true(sim.undo_turn())
	assert_eq(sim.targeting.manual_target_id, second)


## The guard against the invisible bug: for many seeds, a round that was
## played, undone and replayed ends exactly where a straight play ends, and
## so does the rest of the fight.
func test_an_undone_round_ends_where_a_clean_one_does() -> void:
	for seed_value in range(1, 31):
		var clean := _sim(["dealer", "server"], seed_value)
		var undone := _sim(["dealer", "server"], seed_value)
		for round_index in 4:
			if clean.phase == CombatSim.Phase.ENDED:
				break
			_open_round(clean)
			_open_round(undone)
			assert_eq(_fingerprint(undone), _fingerprint(clean), "seed %d round %d opens alike" % [seed_value, round_index])
			# The undone sim plays garbage first, then takes it all back.
			_play_a_few_chips(undone, 7)
			undone.undo_turn()
			undone.drain_events()
			_play_a_few_chips(clean, 3)
			_play_a_few_chips(undone, 3)
			clean.end_assignment()
			undone.end_assignment()
			clean.drain_events()
			undone.drain_events()
			assert_eq(_fingerprint(undone), _fingerprint(clean),
				"seed %d round %d: an undone round must leave no trace" % [seed_value, round_index])


# ---------------------------------------------------- every field is classified

func _script_vars(object: Object) -> Array[String]:
	var names: Array[String] = []
	for prop in object.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(str(prop.name))
	return names


func test_every_sim_field_is_snapshotted_or_declared_static() -> void:
	var sim := _sim(["bouncer"], 1)
	for name in _script_vars(sim):
		assert_true(CombatSim.SNAPSHOT_FIELDS.has(name) or CombatSim.STATIC_FIELDS.has(name),
			"CombatSim.%s is neither in SNAPSHOT_FIELDS nor STATIC_FIELDS: decide" % name)


func test_every_actor_field_is_snapshotted_or_declared_static() -> void:
	var sim := _sim(["bouncer"], 1)
	for name in _script_vars(sim.hero):
		assert_true(CombatActor.SNAPSHOT_FIELDS.has(name) or CombatActor.STATIC_FIELDS.has(name),
			"CombatActor.%s is neither in SNAPSHOT_FIELDS nor STATIC_FIELDS: decide" % name)


func test_reel_pools_and_rng_streams_are_part_of_the_snapshot() -> void:
	var sim := _sim(["bouncer"], 5)
	_open_round(sim)
	var pool_before: Array = sim.machine.reels[0].snapshot()["pool"]
	var rng_before := sim.rng.snapshot()
	_play_a_few_chips(sim, 4)
	# Spend randomness and a reel pull outside the snapshot's world.
	sim.rng.stream(&"combat").randi()
	sim.machine.reels[0].spin(sim.rng.stream(&"combat"))
	sim.undo_turn()
	assert_eq(sim.machine.reels[0].snapshot()["pool"], pool_before)
	assert_eq(sim.rng.snapshot(), rng_before)
