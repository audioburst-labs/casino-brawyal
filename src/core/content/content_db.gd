class_name ContentDB
extends RefCounted
## Loads every JSON file under a data root, parses it into Defs classes,
## and validates all cross-references. Fails loudly: the unit test suite
## runs load_all() so malformed content never reaches a build.
##
## File format: {"type": "abilities"|"enemies"|"heroes"|"statuses", "items": [...]}

const SUITS: Array[StringName] = [&"spade", &"club", &"heart", &"diamond"]
const COST_SUITS: Array[StringName] = [&"spade", &"club", &"heart", &"diamond", &"any"]
const KNOWN_OPS: Array[String] = [
	"damage", "apply_status", "gain_block", "heal_pct", "add_chips",
	"convert_chips", "respin_reel", "gain_coins", "grant_relic",
	"lose_hp", "lose_coins", "gain_max_hp",
	"cash_in", "damage_missing_pct", "block_per_enemy",
	"mark_random_unmarked", "block_per_chip",
]
const KNOWN_CONDITIONS: Array[String] = [
	"no_enemy_marked", "solo_ability_this_round", "spin_has_triple",
]
const BOSS_STAGE := 6
const KNOWN_TRIGGERS: Array[StringName] = [
	&"combat_started", &"round_started", &"spin_resolved", &"chips_generated",
	&"ability_activated", &"damage_dealt", &"damage_taken", &"enemy_killed",
	&"round_ended", &"combat_won", &"coins_gained", &"shop_entered", &"rest_taken",
]

var errors: Array[String] = []

var _abilities: Dictionary = {}
var _enemies: Dictionary = {}
var _heroes: Dictionary = {}
var _statuses: Dictionary = {}
var _relics: Dictionary = {}
var _lineups: Array[Dictionary] = []
var _story_events: Dictionary = {}
var _keywords: Dictionary = {}


func load_all(root: String) -> bool:
	errors.clear()
	_abilities.clear()
	_enemies.clear()
	_heroes.clear()
	_statuses.clear()
	_relics.clear()
	_lineups.clear()
	_story_events.clear()
	_keywords.clear()

	var docs: Array[Dictionary] = []
	_scan_dir(root, docs)

	# Statuses and keywords first: abilities and enemies reference them.
	for doc in docs:
		match doc.get("type"):
			"statuses":
				for item: Dictionary in doc.get("items", []):
					_parse_status(item)
			"keywords":
				for item: Dictionary in doc.get("items", []):
					_parse_keyword(item)
	for doc in docs:
		match doc.get("type"):
			"abilities":
				for item: Dictionary in doc.get("items", []):
					_parse_ability(item)
			"enemies":
				for item: Dictionary in doc.get("items", []):
					_parse_enemy(item)
			"relics":
				for item: Dictionary in doc.get("items", []):
					_parse_relic(item)
	for doc in docs:
		match doc.get("type"):
			"heroes":
				for item: Dictionary in doc.get("items", []):
					_parse_hero(item)
			"lineups":
				for item: Dictionary in doc.get("items", []):
					_parse_lineup(item)
			"events":
				for item: Dictionary in doc.get("items", []):
					_parse_story_event(item)

	_validate_summons()
	return errors.is_empty()


func get_ability(id: StringName) -> Defs.AbilityDef:
	return _abilities.get(id)


func get_enemy(id: StringName) -> Defs.EnemyDef:
	return _enemies.get(id)


func get_hero(id: StringName) -> Defs.HeroDef:
	return _heroes.get(id)


func get_status(id: StringName) -> Defs.StatusDef:
	return _statuses.get(id)


func get_keyword(id: StringName) -> Defs.KeywordDef:
	return _keywords.get(id)


func get_relic(id: StringName) -> Defs.RelicDef:
	return _relics.get(id)


func all_ability_ids() -> Array:
	return _abilities.keys()


func all_relic_ids() -> Array:
	return _relics.keys()


func lineups_for_stage(stage: int) -> Array[Dictionary]:
	return _lineups.filter(func(l: Dictionary) -> bool: return int(l.stage) == stage)


func get_story_event(id: StringName) -> Defs.StoryEventDef:
	return _story_events.get(id)


func all_story_event_ids() -> Array:
	return _story_events.keys()


func _scan_dir(path: String, docs: Array[Dictionary]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		errors.append("cannot open data dir: " + path)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := path.path_join(entry)
		if dir.current_is_dir():
			_scan_dir(full, docs)
		elif entry.ends_with(".json"):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(full))
			if parsed is Dictionary:
				docs.append(parsed)
			else:
				errors.append("invalid JSON: " + full)
		entry = dir.get_next()
	dir.list_dir_end()


func _parse_keyword(item: Dictionary) -> void:
	var keyword := Defs.KeywordDef.new()
	keyword.id = StringName(item.get("id", ""))
	if keyword.id == &"":
		errors.append("keyword with missing id")
		return
	keyword.name = item.get("name", "")
	keyword.text = item.get("text", "")
	_keywords[keyword.id] = keyword


func _parse_status(item: Dictionary) -> void:
	var status := Defs.StatusDef.new()
	status.id = StringName(item.get("id", ""))
	status.name = item.get("name", "")
	status.stack_mode = item.get("stack_mode", "duration")
	status.description = item.get("description", "")
	if status.id == &"":
		errors.append("status with missing id")
		return
	_statuses[status.id] = status


func _parse_ability(item: Dictionary) -> void:
	var ability := Defs.AbilityDef.new()
	ability.id = StringName(item.get("id", ""))
	if ability.id == &"":
		errors.append("ability with missing id")
		return
	ability.name = item.get("name", "")
	ability.description = item.get("description", "")
	ability.rarity = item.get("rarity", "common")
	ability.pool = item.get("pool", "reward")

	for slot: Dictionary in item.get("cost", []):
		var suit := StringName(str(slot.get("suit", "")))
		if not COST_SUITS.has(suit):
			errors.append("ability %s: unknown suit '%s' in cost" % [ability.id, suit])
		ability.cost.append(suit)
	if ability.cost.is_empty():
		errors.append("ability %s: empty cost" % ability.id)

	for effect: Dictionary in item.get("effects", []):
		_validate_effect(effect, "ability %s" % ability.id)
		ability.effects.append(effect)
	if ability.effects.is_empty():
		errors.append("ability %s: no effects" % ability.id)

	ability.bonus_suit = StringName(str(item.get("bonus_suit", "")))
	ability.bonus_condition = item.get("bonus_condition", "")
	ability.bonus_mode = item.get("bonus_mode", "extra")
	if ability.bonus_suit != &"" and not SUITS.has(ability.bonus_suit):
		errors.append("ability %s: unknown bonus_suit '%s'" % [ability.id, ability.bonus_suit])
	for effect: Dictionary in item.get("bonus_effects", []):
		_validate_effect(effect, "ability %s (bonus)" % ability.id)
		ability.bonus_effects.append(effect)

	ability.per_turn = int(item.get("per_turn", 0))
	ability.passive = bool(item.get("passive", false))
	for keyword_id in item.get("keywords", []):
		var id := StringName(str(keyword_id))
		if not _keywords.has(id):
			errors.append("ability %s: unknown keyword '%s'" % [ability.id, id])
		ability.keywords.append(id)

	_abilities[ability.id] = ability


func _validate_effect(effect: Dictionary, context: String) -> void:
	var op := str(effect.get("op", ""))
	if not KNOWN_OPS.has(op):
		errors.append("%s: unknown effect op '%s'" % [context, op])
	if op == "apply_status" and not _statuses.has(StringName(str(effect.get("status", "")))):
		errors.append("%s: unknown status '%s'" % [context, effect.get("status", "")])
	if effect.has("condition") and not KNOWN_CONDITIONS.has(str(effect.condition)):
		errors.append("%s: unknown condition '%s'" % [context, effect.condition])


func _parse_relic(item: Dictionary) -> void:
	var relic := Defs.RelicDef.new()
	relic.id = StringName(item.get("id", ""))
	if relic.id == &"":
		errors.append("relic with missing id")
		return
	relic.name = item.get("name", "")
	relic.description = item.get("description", "")
	relic.rarity = item.get("rarity", "common")
	relic.price_min = int(item.get("price_min", 20))
	relic.price_max = int(item.get("price_max", 30))
	relic.trigger = StringName(str(item.get("trigger", "")))
	if not KNOWN_TRIGGERS.has(relic.trigger):
		errors.append("relic %s: unknown trigger '%s'" % [relic.id, relic.trigger])
	for effect: Dictionary in item.get("effects", []):
		_validate_effect(effect, "relic %s" % relic.id)
		relic.effects.append(effect)
	# Empty effects are allowed: some relics (High Stakes, Emblems, Lucky Foot)
	# are implemented directly in CombatSim rather than as ops.
	_relics[relic.id] = relic


func _parse_enemy(item: Dictionary) -> void:
	var enemy := Defs.EnemyDef.new()
	enemy.id = StringName(item.get("id", ""))
	if enemy.id == &"":
		errors.append("enemy with missing id")
		return
	enemy.name = item.get("name", "")
	enemy.hp_min = int(item.get("hp_min", item.get("hp", 0)))
	enemy.hp_max = int(item.get("hp_max", item.get("hp", 0)))
	enemy.brain = item.get("brain", {})
	enemy.moves = item.get("moves", {})

	if enemy.hp_min <= 0 or enemy.hp_max < enemy.hp_min:
		errors.append("enemy %s: invalid hp range" % enemy.id)
	if enemy.moves.is_empty():
		errors.append("enemy %s: no moves" % enemy.id)
	for move_id: String in enemy.moves:
		var move: Dictionary = enemy.moves[move_id]
		var intent: Dictionary = move.get("intent", {})
		for debuff: Dictionary in intent.get("debuffs", []):
			var status := StringName(str(debuff.get("status", "")))
			if not _statuses.has(status):
				errors.append("enemy %s move %s: unknown status '%s'" % [enemy.id, move_id, status])
		for buff: Dictionary in intent.get("self_status", []):
			var status := StringName(str(buff.get("status", "")))
			if not _statuses.has(status):
				errors.append("enemy %s move %s: unknown self status '%s'" % [enemy.id, move_id, status])

	match enemy.brain.get("type", ""):
		"sequence":
			for step in enemy.brain.get("steps", []):
				if not enemy.moves.has(str(step)):
					errors.append("enemy %s: brain step '%s' is not a move" % [enemy.id, step])
		"pair_then":
			for move in (enemy.brain.get("pair", []) as Array) + (enemy.brain.get("then", []) as Array):
				if not enemy.moves.has(str(move)):
					errors.append("enemy %s: pair_then move '%s' is not a move" % [enemy.id, move])
			if (enemy.brain.get("pair", []) as Array).size() != 2:
				errors.append("enemy %s: pair_then needs exactly 2 pair moves" % enemy.id)

	_enemies[enemy.id] = enemy


## Summons reference other enemies, so this runs after all enemies are parsed.
func _validate_summons() -> void:
	for enemy_id: StringName in _enemies:
		var enemy: Defs.EnemyDef = _enemies[enemy_id]
		for move_id: String in enemy.moves:
			var summon: Dictionary = enemy.moves[move_id].get("intent", {}).get("summon", {})
			if not summon.is_empty():
				var target := StringName(str(summon.get("enemy", "")))
				if not _enemies.has(target):
					errors.append("enemy %s move %s: unknown summon '%s'" % [enemy_id, move_id, target])


func _parse_lineup(item: Dictionary) -> void:
	var enemies: Array[StringName] = []
	for enemy_id in item.get("enemies", []):
		var id := StringName(str(enemy_id))
		if not _enemies.has(id):
			errors.append("lineup %s: unknown enemy '%s'" % [item.get("id", "?"), id])
		enemies.append(id)
	if enemies.is_empty():
		errors.append("lineup %s: no enemies" % item.get("id", "?"))
	_lineups.append({
		"id": StringName(str(item.get("id", ""))),
		"stage": int(item.get("stage", 1)),
		"enemies": enemies,
		"gold_min": int(item.get("gold_min", 0)),
		"gold_max": int(item.get("gold_max", 0)),
	})


func _parse_story_event(item: Dictionary) -> void:
	var event := Defs.StoryEventDef.new()
	event.id = StringName(item.get("id", ""))
	if event.id == &"":
		errors.append("story event with missing id")
		return
	event.title = item.get("title", "")
	event.description = item.get("description", "")
	event.image = item.get("image", "")
	for choice: Dictionary in item.get("choices", []):
		if not choice.has("label"):
			errors.append("event %s: choice missing label" % event.id)
		for effect: Dictionary in choice.get("effects", []):
			_validate_effect(effect, "event %s" % event.id)
		event.choices.append(choice)
	if event.choices.size() < 2 or event.choices.size() > 4:
		errors.append("event %s: needs 2-4 choices" % event.id)
	_story_events[event.id] = event


func _parse_hero(item: Dictionary) -> void:
	var hero := Defs.HeroDef.new()
	hero.id = StringName(item.get("id", ""))
	if hero.id == &"":
		errors.append("hero with missing id")
		return
	hero.name = item.get("name", "")
	hero.max_hp = int(item.get("max_hp", 0))
	if hero.max_hp <= 0:
		errors.append("hero %s: max_hp must be positive" % hero.id)
	for ability_id in item.get("starting_abilities", []):
		var id := StringName(str(ability_id))
		if not _abilities.has(id):
			errors.append("hero %s: unknown starting ability '%s'" % [hero.id, id])
		hero.starting_abilities.append(id)
	_heroes[hero.id] = hero
