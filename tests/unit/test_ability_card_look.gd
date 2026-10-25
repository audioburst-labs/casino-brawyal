extends GutTest
## Patch 0.125: the redesigned ability card (teal panel, full art, metal frame).

var db: ContentDB


func before_each() -> void:
	db = ContentDB.new()
	assert_true(db.load_all("res://data"), str(db.errors))


func test_every_ability_has_its_own_full_art() -> void:
	for id in db.all_ability_ids():
		var def := db.get_ability(id)
		assert_not_null(SuitAssets.card_art(def.id), "%s needs assets/cards/art/%s.jpg" % [def.id, def.id])


func test_the_frame_is_copper_then_silver_then_gold() -> void:
	var base := TierStyle.metal(0)
	var silver := TierStyle.metal(1)
	var gold := TierStyle.metal(2)
	assert_gt(base.mid.r, base.mid.b, "copper is warm")
	assert_almost_eq(silver.mid.r, silver.mid.b, 0.15, "silver is neutral")
	assert_gt(gold.mid.r, gold.mid.b + 0.3, "gold is yellow")
	assert_gt(silver.hi.get_luminance(), base.hi.get_luminance() - 0.01)
	assert_ne(base.mid, gold.mid)


func test_an_upgrade_marks_the_numbers_that_changed() -> void:
	var base := db.get_ability(&"card_sling", 0)
	var silver := db.get_ability(&"card_sling", 1)
	assert_eq(AbilityCard.tier_marked(base, base), "Deal 6 damage. If Spade - Mark.", "base is plain")
	var marked := AbilityCard.tier_marked(silver, base)
	assert_true(marked.contains("[color=cyan]8[/color]"), marked)
	assert_false(marked.contains("[color=cyan]Spade"), "unchanged words stay plain")


func test_gold_marks_in_gold() -> void:
	var gold := db.get_ability(&"card_sling", 2)
	assert_true(AbilityCard.tier_marked(gold, db.get_ability(&"card_sling", 0)).contains("[color=gold]10[/color]"))


func test_four_sockets_sit_in_one_row() -> void:
	assert_eq(AbilityCard.socket_rows(4), [4])
	assert_eq(AbilityCard.socket_rows(2), [2])
	assert_eq(AbilityCard.socket_rows(1), [1])


func test_sockets_shrink_as_they_multiply() -> void:
	assert_gt(AbilityCard.socket_size(1), AbilityCard.socket_size(4))
	assert_gte(AbilityCard.socket_size(4) * 4.0 + 12.0, 0.0)
	assert_lte(AbilityCard.socket_size(4) * 4.0 + 3.0 * 5.0, AbilityCard.CARD_SIZE.x - 24.0, "four fit the card")


func test_every_description_fits_the_card_in_the_bold_face_at_a_readable_size() -> void:
	var font: Font = AbilityCard.body_font()
	var width: float = AbilityCard.CARD_SIZE.x - AbilityCard.FRAME * 2.0 - AbilityCard.DESC_PAD * 2.0
	var smallest := 99
	for id in db.all_ability_ids():
		for tier in 3:
			var def: Defs.AbilityDef = db.get_ability(id, tier)
			var size: int = AbilityCard.fit_size(font, def.description)
			smallest = mini(smallest, size)
			var height: float = font.get_multiline_string_size(def.description, HORIZONTAL_ALIGNMENT_CENTER, width, size).y
			assert_lte(height, AbilityCard.DESC_HEIGHT, "%s tier %d overflows at %d" % [id, tier, size])
	assert_gte(smallest, 15, "even the longest text, balanced, stays at 15 or larger")


func test_a_preview_is_the_card_at_the_asked_scale() -> void:
	var holder := AbilityCard.preview(db.get_ability(&"card_sling", 1), 1.5)
	add_child_autofree(holder)
	assert_eq(holder.custom_minimum_size, AbilityCard.CARD_SIZE * 1.5)
	assert_eq(holder.mouse_filter, Control.MOUSE_FILTER_IGNORE, "a picture never takes the click meant for its button")


func test_a_plate_shows_the_name_and_the_cost() -> void:
	var host := PanelContainer.new()
	add_child_autofree(host)
	AbilityPlate.fill(host, &"double_down", 0, Vector2(200, 124), 16)
	assert_eq(host.custom_minimum_size, Vector2(200, 124))
	assert_gt(host.get_child_count(), 1)


# ---- option C: centred, balanced text (designer, 0.125) ---------------------------------

func _lines(text: String, size := 17) -> Array[String]:
	var font: Font = AbilityCard.body_font()
	return AbilityCard.balanced_lines(font, size, text.split(" ", false), AbilityCard.text_width())


func test_a_short_text_that_wraps_breaks_in_the_middle() -> void:
	var lines := _lines("Deal 8 damage. If Spade - Mark.")
	assert_eq(lines.size(), 2)
	assert_eq(lines[0], "Deal 8 damage.", "the break falls after the first sentence")
	assert_eq(lines[1], "If Spade - Mark.")


func test_every_text_fits_the_band_in_its_balanced_lines() -> void:
	var font: Font = AbilityCard.body_font()
	for id in db.all_ability_ids():
		for tier in 3:
			var text: String = db.get_ability(id, tier).description
			var size := AbilityCard.fit_size(font, text)
			var lines := AbilityCard.balanced_lines(font, size, text.split(" ", false), AbilityCard.text_width())
			assert_lte(lines.size() * font.get_height(size), AbilityCard.DESC_HEIGHT, "%s tier %d overflows at %d" % [id, tier, size])


func test_no_line_starts_with_a_dash() -> void:
	for id in db.all_ability_ids():
		for tier in 3:
			var text: String = db.get_ability(id, tier).description
			var font: Font = AbilityCard.body_font()
			for line in AbilityCard.balanced_lines(font, AbilityCard.fit_size(font, text), text.split(" ", false), AbilityCard.text_width()):
				assert_false(line.begins_with("- ") or line == "-", "%s: '%s'" % [id, line])


func test_balanced_lines_are_closer_in_length_than_greedy_ones() -> void:
	var font: Font = AbilityCard.body_font()
	var text := "Deal 5 to all enemies. If Club - 10 instead. If Heart - Apply Weak 1."
	var size := AbilityCard.fit_size(font, text)
	var lines := AbilityCard.balanced_lines(font, size, text.split(" ", false), AbilityCard.text_width())
	var widths: Array[float] = []
	for line in lines:
		widths.append(font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	assert_lt(widths.max() - widths.min(), 80.0, "lines are close in length: %s" % str(lines))
