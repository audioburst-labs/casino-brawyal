extends ScreenBase
## Encounter choice: two option cards (one for #1 auto-combat and #10 boss).

const TYPE_LABELS := {
	&"combat": "Combat",
	&"hard_combat": "Hard Combat",
	&"story": "Story",
	&"rest": "Rest",
	&"treasure": "Treasure",
	&"shop": "Shop",
	&"boss": "BOSS: Mr. Moneyman",
}
const TYPE_FLAVOR := {
	&"combat": "The house always sends someone.",
	&"hard_combat": "Greater risk, greater reward.",
	&"story": "Something is happening here...",
	&"rest": "A quiet corner to catch your breath.",
	&"treasure": "Something glitters in the dark.",
	&"shop": "Spend your winnings.",
	&"boss": "Time to settle the score.",
}


func _ready() -> void:
	build_screen("Encounter %d of 10" % Game.run.encounter_number(),
		"res://assets/backgrounds/bg_map.png")

	var status := Label.new()
	status.text = "❤ %d / %d      🪙 %d" % [Game.run.hp, Game.run.max_hp, Game.run.coins]
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.theme_type_variation = &"SubtitleLabel"
	content.add_child(status)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)
	content.add_child(row)

	for option: Dictionary in Game.map_options():
		var title: String = TYPE_LABELS.get(option.type, String(option.type))
		var lines: Array[String] = []
		if option.has("variant"):
			lines.append("Variant: %s" % option.variant)
		lines.append(TYPE_FLAVOR.get(option.type, ""))
		var card := make_card(title, lines,
			func() -> void: Game.choose_encounter(option))
		card.custom_minimum_size = Vector2(400, 190)
		row.add_child(card)
