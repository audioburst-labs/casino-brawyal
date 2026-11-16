class_name PathPicker
extends RefCounted
## Which of the six authored Paths a run is given (designer, 1.26: "the game
## remembers which option of encounter choices the player gets, and can't use
## that option for the next 2 runs after it, so there will be more controlled
## variety"). The memory lives on the machine, beside the stories already seen
## (`AppSettings.recent_paths`), because a run on its own cannot know what the
## last one was.
##
## The last `COOLDOWN_RUNS` paths are closed: a path used by one run stays
## closed for the two runs after it, so with six paths four are always open.

const COOLDOWN_RUNS := 2


## A path that is not in `recent`. With nothing open (fewer paths than the
## cooldown, which the shipped six never are) every path is open again, so a
## run can always start.
static func pick(all_ids: Array, recent: Array, rng: RandomNumberGenerator) -> StringName:
	if all_ids.is_empty():
		return &""
	var pool: Array = all_ids.filter(func(id: Variant) -> bool:
		return not recent.has(str(id)))
	if pool.is_empty():
		pool = all_ids.duplicate()
	return StringName(str(pool[rng.randi_range(0, pool.size() - 1)]))


## The machine-wide list once `picked` has been given to a run: the newest
## `COOLDOWN_RUNS` paths, oldest first.
static func remember(recent: Array, picked: StringName) -> Array[String]:
	var out: Array[String] = []
	for id: Variant in recent:
		out.append(str(id))
	out.append(String(picked))
	while out.size() > COOLDOWN_RUNS:
		out.remove_at(0)
	return out
