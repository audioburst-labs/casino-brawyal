class_name StoryPicker
extends RefCounted
## Which Story encounter comes up (designer, 0.121: "it should pick a random
## story the player hasn't seen yet"). The sheet has five and a run visits two
## or three, so "unseen" has to reach across runs or every run would start from
## the same pool and feel like the same few stories. Preference order:
##   1. not seen in this run and not seen on this machine,
##   2. not seen in this run (every story has been seen on this machine),
##   3. any story (a run that has somehow used them all).


static func pick(all_ids: Array, seen_in_run: Array, seen_ever: Array,
		rng: RandomNumberGenerator) -> StringName:
	var pool: Array = all_ids.filter(func(id: Variant) -> bool:
		return not seen_in_run.has(StringName(str(id))) \
			and not seen_ever.has(str(id)))
	if pool.is_empty():
		pool = all_ids.filter(func(id: Variant) -> bool:
			return not seen_in_run.has(StringName(str(id))))
	if pool.is_empty():
		pool = all_ids.duplicate()
	if pool.is_empty():
		return &""
	return StringName(str(pool[rng.randi_range(0, pool.size() - 1)]))


## The machine-wide list after `picked` was shown: once every story has been
## seen the list starts over with just this one, so the next run is fresh.
static func remember(all_ids: Array, seen_ever: Array, picked: StringName) -> Array[String]:
	var out: Array[String] = []
	for id: Variant in seen_ever:
		if all_ids.has(StringName(str(id))) and not out.has(str(id)):
			out.append(str(id))
	if not out.has(String(picked)):
		out.append(String(picked))
	if out.size() >= all_ids.size():
		out = [String(picked)]
	return out
