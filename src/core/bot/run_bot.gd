class_name RunBot
extends RefCounted
## Plays an entire seeded run headlessly: random map choices, greedy combats,
## random story picks, sensible shop spending. The balance instrument.


## Returns {finished, won, encounters, coins, hp}.
static func play(db: ContentDB, seed_value: int) -> Dictionary:
	var rng := GameRng.new(seed_value)
	var run := RunState.new()
	var hero := db.get_hero(run.hero_id)
	run.seed_value = seed_value
	run.max_hp = hero.max_hp
	run.hp = hero.max_hp
	for ability_id in hero.starting_abilities:
		run.acquire_ability(ability_id)

	var choice_rng := rng.stream(&"bot")
	while run.encounter_number() <= 10:
		var options := MapGenerator.next_options(run, rng.stream(&"map"))
		var option: Dictionary = options[choice_rng.randi_range(0, options.size() - 1)]
		run.record_visit(option.type)
		match option.type:
			&"combat", &"hard_combat", &"boss":
				if not _play_combat(db, run, rng, option, choice_rng):
					return _result(run, false)
			&"story":
				_play_story(db, run, rng, choice_rng)
			&"rest":
				run.hp = mini(run.max_hp, run.hp + int(ceil(run.max_hp * 0.3)))
			&"treasure":
				var relic := Rewards.random_unowned_relic(db, run, rng.stream(&"rewards"))
				if relic != &"":
					run.relic_ids.append(relic)
			&"casino":
				# One paid spin (doc v0.13), then chase any free re-spins.
				if run.coins >= CasinoGame.spin_cost(run) + 10:
					var result := CasinoGame.spin(db, run, rng.stream(&"rewards"))
					while not result.is_empty() and result.free_respin:
						result = CasinoGame.spin(db, run, rng.stream(&"rewards"), true)
			&"shop":
				_play_shop(db, run, rng, choice_rng)
	return _result(run, true)


static func _result(run: RunState, won: bool) -> Dictionary:
	return {
		"finished": true,
		"won": won,
		"encounters": run.history.size(),
		"coins": run.coins,
		"hp": run.hp,
	}


static func _play_combat(db: ContentDB, run: RunState, rng: GameRng,
		option: Dictionary, choice_rng: RandomNumberGenerator) -> bool:
	run.process_trash()
	_equip_best(db, run)
	var config := EncounterFactory.combat_config(db, run, rng.stream(&"map"), option)
	config["seed"] = rng.stream(&"combat_seeds").randi()
	var sim := CombatSim.new(db, config)
	if not GreedyBot.play_combat(sim):
		return false
	run.hp = maxi(1, sim.hero.hp)
	RunEffects.apply(sim.pending_rewards, db, run, rng.stream(&"rewards"))
	if option.type != &"boss":
		run.coins += Rewards.roll_coins(
			int(config.gold_min), int(config.gold_max), rng.stream(&"rewards"))
		var choices := Rewards.ability_choices(db, run, rng.stream(&"rewards"))
		if not choices.is_empty():
			run.acquire_ability(choices[choice_rng.randi_range(0, choices.size() - 1)])
		if option.type == &"hard_combat":
			var relic := Rewards.random_unowned_relic(db, run, rng.stream(&"rewards"))
			if relic != &"":
				run.relic_ids.append(relic)
	return true


## Equips the 6 highest-value owned abilities before each combat.
static func _equip_best(db: ContentDB, run: RunState) -> void:
	var owned := run.ability_ids.filter(
		func(id: StringName) -> bool: return id != run.trash_id)
	# Scored at the tier the run actually owns each one at (v0.19), so an
	# upgraded ability is valued for what it does now, not its base form.
	owned.sort_custom(func(a: StringName, b: StringName) -> bool:
		var score_a := GreedyBot._score(db.get_ability(a, run.ability_tier(a)), 2)
		var score_b := GreedyBot._score(db.get_ability(b, run.ability_tier(b)), 2)
		return score_a > score_b)
	run.equipped_ids.clear()
	for id: StringName in owned.slice(0, RunState.EQUIP_CAP):
		run.equipped_ids.append(id)


static func _play_story(db: ContentDB, run: RunState, rng: GameRng,
		choice_rng: RandomNumberGenerator) -> void:
	var ids := db.all_story_event_ids()
	var event := db.get_story_event(ids[choice_rng.randi_range(0, ids.size() - 1)])
	var choice: Dictionary = event.choices[choice_rng.randi_range(0, event.choices.size() - 1)]
	RunEffects.apply(choice.get("effects", []), db, run, rng.stream(&"rewards"))


static func _play_shop(db: ContentDB, run: RunState, rng: GameRng,
		choice_rng: RandomNumberGenerator) -> void:
	var stock := ShopStock.generate(db, run, rng.stream(&"shop"))
	# Priorities: reels are the core scaling (more chips per spin), then
	# abilities, then a relic with whatever is left.
	var reel: Dictionary = stock.reel
	if reel.available and run.spend(int(reel.price)):
		run.machine.add_reel()
	for offer: Dictionary in stock.abilities:
		if run.spend(int(offer.price)):
			run.acquire_ability(offer.id)
	for offer: Dictionary in stock.relics:
		if run.spend(int(offer.price)):
			run.relic_ids.append(offer.id)
			break
	# One sticker toward spades when affordable, applied to a random slot.
	if not stock.stickers.is_empty():
		var sticker: Dictionary = stock.stickers[0]
		if run.spend(int(sticker.price)):
			var machine := run.machine
			var reel_index := choice_rng.randi_range(0, machine.reels.size() - 1)
			var slot_index := choice_rng.randi_range(0,
				machine.reels[reel_index].symbols.size() - 1)
			machine.apply_sticker(reel_index, slot_index, &"spade")
