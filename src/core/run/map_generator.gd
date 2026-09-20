class_name MapGenerator
extends RefCounted
## The encounter choice at each step of a run.
##
## Patch 0.114 replaced ten patches of procedural placement rules with the
## doc's new model: "At the start of a run, the system selects one of six
## predefined *Paths*, which determines the pair of choices offered to the
## player at each step." The six paths are transcribed from the sheet's
## Encounter Choices tab into `data/encounters/act1_paths.json`.
##
## Everything the old rules used to enforce — #1 Combat, #10 Boss, Rest only at
## #5 and #9, two Elites with a gap, a Shop before the boss — is now a property
## OF the authored paths rather than code, and `test_map_generator.gd` checks
## the shipped paths against those invariants instead of checking a generator.
## That means the designer can change the shape of a run in the sheet without
## a code change, and a path that breaks an invariant fails the build.

## The path is chosen once per run and remembered on the RunState. A run that
## predates 0.114 (or any run whose path was never rolled) picks one the first
## time it asks for options, so an in-flight save keeps working.
static func path_for(db: ContentDB, run: RunState,
		rng: RandomNumberGenerator) -> Dictionary:
	var paths := db.all_paths()
	if paths.is_empty():
		return {}
	if run.path_id != &"":
		for path: Dictionary in paths:
			if StringName(str(path.id)) == run.path_id:
				return path
	var picked: Dictionary = paths[rng.randi_range(0, paths.size() - 1)]
	run.path_id = StringName(str(picked.id))
	return picked


static func next_options(db: ContentDB, run: RunState,
		rng: RandomNumberGenerator) -> Array[Dictionary]:
	var encounter := run.encounter_number()
	var path := path_for(db, run, rng)
	var options: Array[Dictionary] = []
	var types := _types_at(path, encounter)
	for type: StringName in types:
		options.append({"type": type})
	if options.is_empty():
		# No path data at all: the run still has to be playable, so fall back
		# to the two fixed encounters and plain combat in between.
		options.append({"type": _fallback_type(encounter)})
	# The shop counter still drives the "have I been offered a shop" reading
	# other screens use; it is bookkeeping now, not a placement rule.
	for option in options:
		if option.type == &"shop":
			run.shop_offers += 1
	return options


## The encounter types offered at `encounter` (1-based) on `path`.
static func _types_at(path: Dictionary, encounter: int) -> Array[StringName]:
	var out: Array[StringName] = []
	if path.is_empty():
		return out
	var steps: Array = path.get("encounters", [])
	if encounter < 1 or encounter > steps.size():
		return out
	for name in steps[encounter - 1]:
		out.append(StringName(str(name)))
	return out


static func _fallback_type(encounter: int) -> StringName:
	if encounter >= 10:
		return &"boss"
	return &"combat"
