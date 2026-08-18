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
	"damage", "apply_status", "gain_block", "heal_pct",
	"convert_chips", "respin_reel", "gain_coins", "grant_relic",
]

var errors: Array[String] = []

var _abilities: Dictionary = {}
var _enemies: Dictionary = {}
var _heroes: Dictionary = {}
var _statuses: Dictionary = {}


func load_all(root: String) -> bool:
	errors.clear()
	_abilities.clear()
	_enemies.clear()
	_heroes.clear()
	_statuses.clear()

	var docs: Array[Dictionary] = []
	_scan_dir(root, docs)

	# Statuses first: abilities and enemies reference them.
	for doc in docs:
		if doc.get("type") == "statuses":
			for item: Dictionary in doc.get("items", []):
				_parse_status(item)
	for doc in docs:
		match doc.get("type"):
			"abilities":
				for item: Dictionary in doc.get("items", []):
					_parse_ability(item)
			"enemies":
				for item: Dictionary in doc.get("items", []):
					_parse_enemy(item)
	for doc in docs:
		if doc.get("type") == "heroes":
			for item: Dictionary in doc.get("items", []):
				_parse_hero(item)

	return errors.is_empty()


func get_ability(id: StringName) -> Defs.AbilityDef:
	return _abilities.get(id)


func get_enemy(id: StringName) -> Defs.EnemyDef:
	return _enemies.get(id)


func get_hero(id: StringName) -> Defs.HeroDef:
	return _heroes.get(id)


func get_status(id: StringName) -> Defs.StatusDef:
	return _statuses.get(id)


func all_ability_ids() -> Array:
	return _abilities.keys()


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
	if ability.bonus_suit != &"" and not SUITS.has(ability.bonus_suit):
		errors.append("ability %s: unknown bonus_suit '%s'" % [ability.id, ability.bonus_suit])
	for effect: Dictionary in item.get("bonus_effects", []):
		_validate_effect(effect, "ability %s (bonus)" % ability.id)
		ability.bonus_effects.append(effect)

	_abilities[ability.id] = ability


func _validate_effect(effect: Dictionary, context: String) -> void:
	var op := str(effect.get("op", ""))
	if not KNOWN_OPS.has(op):
		errors.append("%s: unknown effect op '%s'" % [context, op])
	if op == "apply_status" and not _statuses.has(StringName(str(effect.get("status", "")))):
		errors.append("%s: unknown status '%s'" % [context, effect.get("status", "")])


func _parse_enemy(item: Dictionary) -> void:
	var enemy := Defs.EnemyDef.new()
	enemy.id = StringName(item.get("id", ""))
	if enemy.id == &"":
		errors.append("enemy with missing id")
		return
	enemy.name = item.get("name", "")
	enemy.hp = int(item.get("hp", 0))
	enemy.stage = int(item.get("stage", 1))
	enemy.brain = item.get("brain", {})
	enemy.moves = item.get("moves", {})

	if enemy.hp <= 0:
		errors.append("enemy %s: hp must be positive" % enemy.id)
	if enemy.moves.is_empty():
		errors.append("enemy %s: no moves" % enemy.id)
	for move_id: String in enemy.moves:
		var move: Dictionary = enemy.moves[move_id]
		var intent: Dictionary = move.get("intent", {})
		for debuff: Dictionary in intent.get("debuffs", []):
			var status := StringName(str(debuff.get("status", "")))
			if not _statuses.has(status):
				errors.append("enemy %s move %s: unknown status '%s'" % [enemy.id, move_id, status])

	var brain_steps: Array = enemy.brain.get("steps", [])
	for step in brain_steps:
		if not enemy.moves.has(str(step)):
			errors.append("enemy %s: brain step '%s' is not a move" % [enemy.id, step])

	_enemies[enemy.id] = enemy


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
