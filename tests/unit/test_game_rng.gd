extends GutTest
## GameRng: seeded master RNG with independent named streams,
## so map generation, combat, and shop rolls never disturb each other.


func test_same_seed_same_stream_gives_identical_sequences() -> void:
	var a := GameRng.new(12345)
	var b := GameRng.new(12345)
	for i in 20:
		assert_eq(a.stream(&"combat").randi(), b.stream(&"combat").randi())


func test_different_seeds_diverge() -> void:
	var a := GameRng.new(1)
	var b := GameRng.new(2)
	var same := true
	for i in 5:
		if a.stream(&"combat").randi() != b.stream(&"combat").randi():
			same = false
	assert_false(same)


func test_streams_are_independent() -> void:
	# Draining one stream must not change another stream's sequence.
	var a := GameRng.new(777)
	var b := GameRng.new(777)
	for i in 50:
		a.stream(&"map").randi()
	assert_eq(a.stream(&"combat").randi(), b.stream(&"combat").randi())
