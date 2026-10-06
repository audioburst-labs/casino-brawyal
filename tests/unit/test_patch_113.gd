extends GutTest
## Patch 0.113, the designer's numbered notes:
##   1. "Face Reader block gain math looks completely wrong, recheck it."
##   3. "Dealer's passive should be an icon showing the number 21 that counts
##      down as they take damage, triggering at 0."
##   4. "Mr. Moneybags should heal himself too."
##   5. "Enemy passives should appear as permanent buffs they have."
##   6. "Ensure encounters match what's written in the file."

var _db: ContentDB


func before_all() -> void:
	_db = ContentDB.new()
	assert_true(_db.load_all("res://data"), str(_db.errors))


func _sim(enemies: Array, abilities: Array = ["card_sling"],
		seed_value: int = 5) -> CombatSim:
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


# ---- 1. Face Reader ---------------------------------------------------------

## The first half of the bug: two chips bought nothing on the turn they were
## spent, because a passive only paid from the NEXT round start.
func test_face_reader_pays_the_turn_it_is_played() -> void:
	var sim := _sim(["bouncer", "server", "dealer"], ["face_reader"])
	sim.begin_round()
	assert_true(_fire(sim, 0, [&"club", &"diamond"]))
	assert_eq(sim.hero.block, 6, "2 Block per living enemy, three of them")


## The second half: Frail taxes the figure the CARD SHOWS, once, and the total
## is that figure times the count. Taxing the total instead paid 6 for four
## enemies where the card promised 8 (designer's call, patch 0.113).
func test_frail_taxes_the_per_enemy_figure_not_the_total() -> void:
	var sim := _sim(["bouncer", "server", "dealer", "manager"], ["face_reader"])
	sim.begin_round()
	sim.hero.apply_status(&"frail", 2)
	assert_true(_fire(sim, 0, [&"club", &"diamond"]))
	# 2 Block taxed to 2 (25% of 2 rounds to 1 lost... half-up leaves 2 -> 2),
	# four enemies: the reading the card promises, per enemy.
	assert_eq(sim.hero.block, StatusRules.block_gained(2, sim.hero) * 4)


func test_the_passive_keeps_paying_every_round_start() -> void:
	# Two Bouncers rather than a Server, so no Frail lands mid-test and the
	# figure being checked is the untaxed one.
	var sim := _sim(["bouncer", "bouncer"], ["face_reader"])
	sim.begin_round()
	assert_true(_fire(sim, 0, [&"club", &"diamond"]))
	for round_index in 3:
		sim.tray.discard_all()
		sim.end_assignment()
		if sim.phase == CombatSim.Phase.ENDED:
			break
		sim.begin_round()
		assert_eq(sim.hero.block, 4, "2 per living enemy, round %d" % round_index)


# ---- 3 & 5. the Dealer's 21, worn as a permanent buff ----------------------

func test_the_bust_counter_starts_at_twenty_one_on_every_dealer() -> void:
	var sim := _sim(["dealer", "dealer"])
	for enemy in sim.enemies:
		assert_eq(enemy.passive_counter, 21, "the icon shows 21 before a hit")
	# A unit with no passive carries no number at all.
	var plain := _sim(["bouncer"])
	assert_eq(plain.enemies[0].passive_counter, -1)


func test_the_counter_runs_down_with_damage_and_is_announced() -> void:
	var sim := _sim(["dealer"], ["card_sling"])
	sim.begin_round()
	var dealer := sim.enemies[0]
	sim.drain_events()
	assert_true(_fire(sim, 0, [&"club"]))
	assert_eq(dealer.passive_counter, 21 - 6, "counts DOWN from 21, not up")
	var announced := sim.drain_events().filter(
		func(e: CombatEvent) -> bool: return e.type == &"passive_counter")
	assert_eq(announced.size(), 1, "the presenter is told, so the icon can tick")
	assert_eq(int(announced[0].data.value), 15)


func test_the_bust_fires_at_zero_and_the_count_resets() -> void:
	var sim := _sim(["dealer"])
	sim.begin_round()
	var dealer := sim.enemies[0]
	dealer.apply_status(&"strength", 3)
	sim.drain_events()
	sim.on_enemy_damaged(dealer, 21)
	assert_eq(dealer.passive_counter, 21, "back to a fresh 21")
	assert_eq(dealer.status_stacks(&"stun"), 1, "it busts and loses its turn")
	assert_eq(dealer.status_stacks(&"strength"), 0, "and its Strength with it")
	var types := sim.drain_events().map(
		func(e: CombatEvent) -> StringName: return e.type)
	assert_has(types, &"enemy_busted")
	assert_has(types, &"passive_counter")


## Overshooting 21 in one blow must not leave a negative reading on the icon.
func test_a_single_huge_hit_leaves_a_sane_number() -> void:
	var sim := _sim(["dealer"])
	sim.begin_round()
	var dealer := sim.enemies[0]
	sim.on_enemy_damaged(dealer, 40)
	assert_eq(dealer.passive_counter, 21)


## The Chip Golem wears the same kind of number: health to its next free chip.
func test_the_golem_counts_down_to_its_next_chip() -> void:
	var sim := _sim(["chip_golem"])
	sim.begin_round()
	var golem := sim.enemies[0]
	assert_eq(golem.passive_counter, 30, "30 on the sheet since v0.122")
	sim.on_enemy_damaged(golem, 35)
	assert_eq(golem.passive_counter, 25, "one chip paid, 25 to the next")


## The number the intent panel publishes is the one on the actor, so the UI
## cannot drift from the sim.
func test_the_intent_entry_carries_the_same_number() -> void:
	var sim := _sim(["dealer"])
	sim.begin_round()
	var dealer := sim.enemies[0]
	sim.on_enemy_damaged(dealer, 5)
	var entry := sim.intent_display(dealer.id)
	assert_eq(int(entry.passive_count), 16)
	assert_eq(str(entry.passive.type), "bust")


# ---- 4. Mr. Moneybags heals himself ----------------------------------------

func test_the_boss_heals_himself_along_with_his_crew() -> void:
	var sim := _sim(["mr_moneybags"])
	sim.begin_round()
	var boss := sim.enemies[0]
	boss.hp = 40
	sim._intents[boss.id] = {"intent": _db.get_enemy(&"mr_moneybags").moves["bonuses"].intent}
	sim._execute_move(boss, false)
	assert_eq(boss.hp, 60, "heal_allies includes the boss himself")
	assert_eq(boss.status_stacks(&"strength"), 3, "sheet v0.121: Strength 3")


func test_the_boss_heal_never_overshoots_his_maximum() -> void:
	var sim := _sim(["mr_moneybags"])
	sim.begin_round()
	var boss := sim.enemies[0]
	boss.hp = boss.max_hp - 3
	sim._intents[boss.id] = {"intent": _db.get_enemy(&"mr_moneybags").moves["bonuses"].intent}
	sim._execute_move(boss, false)
	assert_eq(boss.hp, boss.max_hp)


# ---- 6. the encounters match the sheet -------------------------------------

## The sheet's Encounters tab, transcribed. Nine of the sixteen lineups had
## drifted from it before this patch.
const SHEET_LINEUPS := {
	"door_duty": ["bouncer"],
	"double_shift": ["server", "server"],
	"happy_hour": ["drunk_patreon", "drunk_patreon", "drunk_patreon", "drunk_patreon"],
	"muscle_and_service": ["bouncer", "server"],
	"pit_backup": ["dealer", "server"],
	"rowdy_tables": ["drunk_patreon", "drunk_patreon", "server", "server"],
	"twin_tables": ["dealer", "dealer"],
	"mixed_floor": ["bouncer", "dealer"],
	"the_manager": ["manager"],
	"managers_pet": ["drunk_patreon", "manager"],
	"bar_brawl": ["bouncer", "server", "drunk_patreon", "drunk_patreon"],
	"last_call": ["dealer", "server", "drunk_patreon", "drunk_patreon"],
	"floor_check": ["bouncer", "manager"],
	"the_pit": ["dealer", "manager"],
	"closing_shift": ["server", "server", "manager"],
}
const SHEET_STAGE_GOLD := {1: [27, 33], 2: [37, 43], 3: [47, 53], 4: [57, 63], 5: [67, 73]}


func test_every_shipped_lineup_is_one_of_the_sheets() -> void:
	var seen := {}
	for lineup: Dictionary in _db.all_lineups():
		var id := String(lineup.id)
		if int(lineup.stage) == 6 or bool(lineup.elite):
			continue
		assert_true(SHEET_LINEUPS.has(id), "%s is not on the sheet" % id)
		var enemies: Array = []
		for enemy: StringName in lineup.enemies:
			enemies.append(String(enemy))
		assert_eq(enemies, SHEET_LINEUPS.get(id, []), id)
		seen[id] = true
	for id: String in SHEET_LINEUPS:
		assert_true(seen.has(id), "%s is on the sheet but not shipped" % id)


func test_gold_matches_the_sheets_band_for_each_stage() -> void:
	for lineup: Dictionary in _db.all_lineups():
		var band := [int(lineup.gold_min), int(lineup.gold_max)]
		if bool(lineup.elite):
			assert_eq(band, [77, 83], String(lineup.id))
		elif int(lineup.stage) == 6:
			assert_eq(band, [0, 0], "the boss pays none")
		else:
			assert_eq(band, SHEET_STAGE_GOLD.get(int(lineup.stage), []),
				String(lineup.id))


func test_enemy_health_matches_the_sheet() -> void:
	# Sheet v0.122 (patch 0.114) put health up across the board.
	var sheet := {
		"bouncer": [56, 60], "server": [25, 30], "dealer": [51, 55],
		"manager": [61, 65], "drunk_patreon": [12, 15], "chip_golem": [100, 109], "loan_shark": [100, 109],
	}
	for id: String in sheet:
		var def := _db.get_enemy(StringName(id))
		assert_eq([def.hp_min, def.hp_max], sheet[id], id)
