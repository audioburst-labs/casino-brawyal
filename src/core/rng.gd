class_name GameRng
extends RefCounted
## Seeded master RNG with independent named streams (map, combat, shop, ...),
## so draws in one system never disturb another's sequence.
## Streams are derived deterministically from (master seed, stream name).

var master_seed: int
var _streams: Dictionary = {}


func _init(seed_value: int) -> void:
	master_seed = seed_value


func stream(name: StringName) -> RandomNumberGenerator:
	if not _streams.has(name):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(str(master_seed) + ":" + String(name))
		_streams[name] = rng
	return _streams[name]
