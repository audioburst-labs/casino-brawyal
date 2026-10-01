class_name GameRng
extends RefCounted
## Seeded master RNG with independent named streams (map, combat, shop, ...),
## so draws in one system never disturb another's sequence.
## Streams are derived deterministically from (master seed, stream name).

var master_seed: int
var _streams: Dictionary = {}


func _init(seed_value: int) -> void:
	master_seed = seed_value


## Every stream's position, for an undo snapshot. A stream that did not exist
## at snapshot time is dropped on restore, so it re-derives from the seed as
## if it had never been asked for.
func snapshot() -> Dictionary:
	var out := {}
	for name: StringName in _streams:
		var rng: RandomNumberGenerator = _streams[name]
		out[name] = {"seed": rng.seed, "state": rng.state}
	return out


func restore(snap: Dictionary) -> void:
	for name: StringName in _streams.keys():
		if not snap.has(name):
			_streams.erase(name)
	for name: StringName in snap:
		var rng := stream(name)
		rng.seed = int(snap[name].seed)
		rng.state = int(snap[name].state)


func stream(name: StringName) -> RandomNumberGenerator:
	if not _streams.has(name):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(str(master_seed) + ":" + String(name))
		_streams[name] = rng
	return _streams[name]
