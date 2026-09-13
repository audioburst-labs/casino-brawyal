extends GutTest
## Casino minigame per doc v0.120: the one spin is free;
## each of the 3 reels lands a percentage-weighted prize (including the
## Broken Heart penalty and a 1% Extra Reel); three of a kind = free spin.

var _db: ContentDB


func before_all() -> void:
	_db = ContentDB.new()
	assert_true(_db.load_all("res://data"), str(_db.errors))


func _rng(seed_value: int = 8) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func test_spin_costs_nothing_and_never_touches_coins_on_its_own() -> void:
	var run := RunState.new()
	run.record_visit(&"combat")
	run.record_visit(&"casino")  # encounter number = 3
	run.coins = 0
	var result := CasinoGame.spin(_db, run, _rng())
	assert_false(result.is_empty(), "a broke player still gets the house spin")
	assert_false(result.has("cost"), "no entry fee since doc v0.120")


func test_three_of_a_kind_grants_free_respin_flag() -> void:
	var run := RunState.new()
	run.coins = 100000
	var saw_triple := false
	for seed_value in 400:
		var result := CasinoGame.spin(_db, run, _rng(seed_value))
		if result.symbols[0] == result.symbols[1] and result.symbols[1] == result.symbols[2]:
			assert_true(result.free_respin, "triple grants a free spin")
			saw_triple = true
	assert_true(saw_triple)


func test_all_prize_kinds_apply_over_many_spins() -> void:
	var run := RunState.new()
	run.coins = 100000
	run.max_hp = 80
	run.hp = 40
	var reels_before := run.machine.reels.size()
	var lost_hp := false
	var healed := false
	var got_sticker := false
	var got_relic := false
	for seed_value in 400:
		var hp_before := run.hp
		CasinoGame.spin(_db, run, _rng(seed_value))
		lost_hp = lost_hp or run.hp < hp_before
		healed = healed or run.hp > hp_before
		got_sticker = got_sticker or not run.sticker_inventory.is_empty()
		got_relic = got_relic or not run.relic_ids.is_empty()
	assert_true(healed, "heart prize heals")
	assert_true(lost_hp, "broken heart costs health")
	assert_true(got_sticker, "suit sticker prizes land in inventory")
	assert_true(got_relic, "relic prize grants a relic")
	assert_gt(run.machine.reels.size(), reels_before, "1% extra reel hits across 400 spins")


func test_broken_heart_never_kills() -> void:
	var run := RunState.new()
	run.coins = 100000
	run.hp = 1
	for seed_value in 100:
		CasinoGame.spin(_db, run, _rng(seed_value))
		assert_gte(run.hp, 1, "casino misfortune leaves at least 1 HP")

## Patch 0.19: the reel has to draw the relic it actually awarded, so `spin`
## reports the winning id alongside the generic &"relic" symbol. Without this
## every relic showed the same stand-in chip.
func test_spin_reports_which_relic_each_reel_awarded() -> void:
	var checked := 0
	for seed_value in 60:
		var run := RunState.new()
		run.record_visit(&"combat")
		run.coins = 999
		var result := CasinoGame.spin(_db, run, _rng(seed_value))
		if result.is_empty():
			continue
		assert_eq(result.relics.size(), result.symbols.size(),
			"one entry per reel, relic or not")
		for i in result.symbols.size():
			var relic_id: StringName = result.relics[i]
			if result.symbols[i] == &"relic" and relic_id != &"":
				assert_not_null(_db.get_relic(relic_id),
					"a real relic id, not a placeholder")
				assert_not_null(SuitAssets.relic_texture(relic_id),
					"every relic resolves to some art")
				checked += 1
			else:
				assert_eq(relic_id, &"", "non-relic reels report no relic")
	assert_gt(checked, 0, "60 spins should land at least one relic")


func test_every_shipped_relic_has_art() -> void:
	for relic_id: StringName in _db.all_relic_ids():
		var art := SuitAssets.relic_texture(relic_id)
		assert_not_null(art, "%s renders something" % relic_id)
		assert_true(ResourceLoader.exists("res://assets/icons/relic_%s.png" % relic_id),
			"%s has its own icon, not the fallback chip" % relic_id)
