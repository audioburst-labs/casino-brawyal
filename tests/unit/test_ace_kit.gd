extends GutTest
## Ace's 25-ability kit (sheet v0.122, patch 0.115) and the five mechanics it
## introduced: Earn, the "when you Earn" and "when you Mark" triggers, damage
## that scales with abilities spent, a per-turn damage percentage, and suits
## read as conditions.

var _db: ContentDB


func before_all() -> void:
	_db = ContentDB.new()
	assert_true(_db.load_all("res://data"), str(_db.errors))


func _sim(enemies: Array, abilities: Array, seed_value: int = 5) -> CombatSim:
	var sim := CombatSim.new(_db, {
		"hero": "ace",
		"abilities": abilities,
		"enemies": enemies,
		"seed": seed_value,
	})
	sim.hero.max_hp = 9999
	sim.hero.hp = 9999
	return sim


func _fire(sim: CombatSim, index: int, suits: Array) -> bool:
	for slot in suits.size():
		sim.tray.add(suits[slot], 1)
		if not sim.assign_chip(suits[slot], index, slot):
			return false
	return true


# ---- the roster ------------------------------------------------------------

func test_the_sheets_twenty_five_abilities_all_ship() -> void:
	# Transcribed from `Abilities - Ace`. 25, not 29 - the extra entries in the
	# trailing columns of rows 16-19 are the designer's scratch space.
	var expected := [
		"card_sling", "quick_maneuvers", "double_down", "heartsteal", "color_up",
		"pocket_rockets", "slow_playing", "house_edge", "bust",
		"dazzling_personality", "face_reader", "bad_beat", "on_a_roll",
		"pay_line", "flush", "chip_tricks", "hit", "the_river", "card_trick",
		"fold", "all_in", "sharp_edge", "rainbow", "bluff_call", "safe_play",
	]
	for id: String in expected:
		assert_not_null(_db.get_ability(StringName(id)), "%s is missing" % id)
	assert_eq(_db.all_ability_ids().size(), expected.size(),
		"exactly the sheet's 25, nothing extra")


func test_every_ability_resolves_all_three_tiers() -> void:
	for id: StringName in _db.all_ability_ids():
		for tier in 3:
			var def := _db.get_ability(id, tier)
			assert_not_null(def, "%s tier %d" % [id, tier])
			assert_false(def.description.is_empty(), "%s tier %d text" % [id, tier])


# ---- Earn ------------------------------------------------------------------

func test_color_up_earns_a_spade() -> void:
	var sim := _sim(["bouncer"], ["color_up"])
	sim.begin_round()
	sim.tray.discard_all()
	assert_true(_fire(sim, 0, [&"heart"]))
	assert_eq(sim.tray.count(&"spade"), 1, "Earn a Spade")


## Hit and All In hand back a chip they were paid with, which is what makes
## them nearly free.
func test_hit_earns_back_the_chip_it_was_paid_with() -> void:
	var sim := _sim(["bouncer"], ["hit"])
	sim.begin_round()
	var enemy := sim.enemies[0]
	var hp_start := enemy.hp
	sim.tray.discard_all()
	assert_true(_fire(sim, 0, [&"club"]))
	assert_eq(enemy.hp, hp_start - 3, "Deal 3")
	assert_eq(sim.tray.count(&"club"), 1, "and the Club comes back")


## Chip Tricks' passive half fires whenever anything Earns - including
## another ability's Earn, which is the point of it.
func test_chip_tricks_turns_every_earn_into_block() -> void:
	var sim := _sim(["bouncer"], ["chip_tricks", "color_up"])
	sim.begin_round()
	sim.tray.discard_all()
	# Playing it runs the ACTIVE half (Earn a random chip), and that Earn
	# immediately trips its own passive.
	assert_true(_fire(sim, 0, [&"heart"]))
	assert_eq(sim.tray.total(), 1, "the active half Earned one chip")
	var after_self := sim.hero.block
	assert_gt(after_self, 0, "its own Earn paid Block")
	# Now somebody else Earns, and the passive pays again.
	assert_true(_fire(sim, 1, [&"heart"]))
	assert_gt(sim.hero.block, after_self, "Color Up's Earn paid Block too")


func test_chip_tricks_does_not_pay_without_an_earn() -> void:
	var sim := _sim(["bouncer"], ["chip_tricks", "card_sling"])
	sim.begin_round()
	assert_true(_fire(sim, 0, [&"heart"]))
	var baseline := sim.hero.block
	assert_true(_fire(sim, 1, [&"club"]))       # Card Sling Earns nothing
	assert_eq(sim.hero.block, baseline, "a plain attack is not an Earn")


# ---- the Mark trigger ------------------------------------------------------

func test_sharp_edge_deals_damage_whenever_a_mark_lands() -> void:
	var sim := _sim(["bouncer"], ["sharp_edge", "card_sling"])
	sim.begin_round()
	var enemy := sim.enemies[0]
	# Its active half Marks, which trips its own passive for 3.
	var hp_start := enemy.hp
	assert_true(_fire(sim, 0, [&"heart"]))
	assert_eq(enemy.status_stacks(&"mark"), 1, "the active half Marked")
	assert_eq(enemy.hp, hp_start - 3, "and the passive answered for 3")
	# Card Sling's Spade bonus Marks too, so Sharp Edge fires again.
	enemy.statuses.erase(&"mark")
	var hp_mid := enemy.hp
	assert_true(_fire(sim, 1, [&"spade"]))
	assert_eq(enemy.hp, hp_mid - 6 - 3, "6 from Card Sling, 3 from Sharp Edge")


## A triggered passive must not trip itself for ever.
func test_a_triggered_passive_does_not_recurse() -> void:
	var sim := _sim(["bouncer"], ["sharp_edge"])
	sim.begin_round()
	var enemy := sim.enemies[0]
	var hp_start := enemy.hp
	assert_true(_fire(sim, 0, [&"heart"]))
	assert_eq(enemy.hp, hp_start - 3, "exactly once, not in a loop")


# ---- damage that scales -----------------------------------------------------

func test_the_river_scales_with_abilities_spent_this_turn() -> void:
	var sim := _sim(["bouncer"], ["the_river", "card_sling"])
	sim.begin_round()
	var enemy := sim.enemies[0]
	var hp_start := enemy.hp
	# The River alone: it counts itself, so one ability -> 10.
	assert_true(_fire(sim, 0, [&"heart", &"club"]))
	assert_eq(enemy.hp, hp_start - 10, "one ability spent, 10 damage")

	sim.tray.discard_all()
	sim.end_assignment()
	sim.begin_round()
	var hp_mid := enemy.hp
	assert_true(_fire(sim, 1, [&"club"]))                  # Card Sling: 6
	assert_true(_fire(sim, 0, [&"heart", &"club"]))        # now two spent: 20
	assert_eq(enemy.hp, hp_mid - 6 - 20, "two abilities spent, 20 damage")


func test_all_in_lifts_every_hit_for_the_rest_of_the_turn() -> void:
	var sim := _sim(["bouncer"], ["all_in", "card_sling"])
	sim.begin_round()
	var enemy := sim.enemies[0]
	assert_true(_fire(sim, 0, [&"heart"]))
	assert_eq(sim.hero.damage_bonus_pct, 0.30)
	var hp_start := enemy.hp
	assert_true(_fire(sim, 1, [&"club"]))
	assert_eq(enemy.hp, hp_start - 8, "6 x 1.3 = 7.8, half-up 8")


func test_the_all_in_bonus_expires_with_the_turn() -> void:
	var sim := _sim(["bouncer"], ["all_in", "card_sling"])
	sim.begin_round()
	assert_true(_fire(sim, 0, [&"heart"]))
	assert_gt(sim.hero.damage_bonus_pct, 0.0)
	sim.tray.discard_all()
	sim.end_assignment()
	sim.begin_round()
	assert_eq(sim.hero.damage_bonus_pct, 0.0, "'this turn' means this turn")


func test_slow_playing_converts_weak_stacks_into_rage() -> void:
	var sim := _sim(["bouncer", "server"], ["slow_playing"])
	sim.begin_round()
	# Weak 2 on the target, and Rage counts STACKS across the field.
	assert_true(_fire(sim, 0, [&"heart"]))
	var stacks := 0
	for enemy in sim.enemies:
		stacks += enemy.status_stacks(&"weak")
	assert_eq(sim.hero.status_stacks(&"rage"), stacks, "one Rage per Weak stack")


# ---- suits as conditions ----------------------------------------------------

func test_rainbow_reads_its_two_suits_independently() -> void:
	# Neither suit: the plain 5 to everyone.
	var plain := _sim(["bouncer", "server"], ["rainbow"])
	plain.begin_round()
	var a := plain.enemies[0].hp
	assert_true(_fire(plain, 0, [&"spade", &"diamond"]))
	assert_eq(plain.enemies[0].hp, a - 5, "no Club, no Heart: 5")
	assert_eq(plain.enemies[0].status_stacks(&"weak"), 0)

	# A Club upgrades the damage...
	var clubbed := _sim(["bouncer", "server"], ["rainbow"])
	clubbed.begin_round()
	var b := clubbed.enemies[0].hp
	assert_true(_fire(clubbed, 0, [&"club", &"spade"]))
	assert_eq(clubbed.enemies[0].hp, b - 10, "Club: 10 instead of 5")

	# ...and a Heart adds Weak on top, independently.
	var both := _sim(["bouncer", "server"], ["rainbow"])
	both.begin_round()
	var c := both.enemies[0].hp
	assert_true(_fire(both, 0, [&"club", &"heart"]))
	assert_eq(both.enemies[0].hp, c - 10, "still the Club figure")
	assert_eq(both.enemies[0].status_stacks(&"weak"), 1, "and the Heart's Weak")


func test_bluff_call_pays_more_into_a_weak_target() -> void:
	var sim := _sim(["bouncer"], ["bluff_call"])
	sim.begin_round()
	var enemy := sim.enemies[0]
	var hp_start := enemy.hp
	assert_true(_fire(sim, 0, [&"heart"]))
	assert_eq(enemy.hp, hp_start - 8, "a healthy target takes 8")

	var weakened := _sim(["bouncer"], ["bluff_call"])
	weakened.begin_round()
	var target := weakened.enemies[0]
	target.apply_status(&"weak", 1)
	var before := target.hp
	assert_true(_fire(weakened, 0, [&"heart"]))
	assert_eq(target.hp, before - 12, "a Weak target takes 12 instead")


func test_safe_play_reads_the_whole_field_not_the_target() -> void:
	var sim := _sim(["bouncer", "server"], ["safe_play"])
	sim.begin_round()
	assert_true(_fire(sim, 0, [&"diamond"]))
	assert_eq(sim.hero.block, 6, "nobody Weak: 6")

	var weakened := _sim(["bouncer", "server"], ["safe_play"])
	weakened.begin_round()
	weakened.enemies[1].apply_status(&"weak", 1)      # not the default target
	assert_true(_fire(weakened, 0, [&"diamond"]))
	assert_eq(weakened.hero.block, 10, "ANY Weak enemy is enough: 10")


# ---- the upgrades the sheet spells out --------------------------------------

func test_house_edge_marks_more_as_it_upgrades() -> void:
	assert_eq(int(_db.get_ability(&"house_edge", 0).effects[0].count), 1)
	assert_eq(int(_db.get_ability(&"house_edge", 1).effects[0].count), 2)
	var gold := _db.get_ability(&"house_edge", 2)
	assert_eq(str(gold.effects[0].op), "apply_status", "gold Marks everyone")
	assert_eq(str(gold.effects[0].target), "all_enemies")


func test_color_up_loses_its_limit_as_it_upgrades() -> void:
	assert_eq(_db.get_ability(&"color_up", 0).per_turn, 1)
	assert_eq(_db.get_ability(&"color_up", 1).per_turn, 2)
	assert_eq(_db.get_ability(&"color_up", 2).per_turn, 0, "0 = unlimited")


func test_all_in_scales_its_percentage() -> void:
	var pcts: Array[float] = []
	for tier in 3:
		for effect: Dictionary in _db.get_ability(&"all_in", tier).effects:
			if str(effect.get("op", "")) == "damage_bonus_pct":
				pcts.append(float(effect.pct))
	assert_eq(pcts, [0.30, 0.40, 0.50] as Array[float])
