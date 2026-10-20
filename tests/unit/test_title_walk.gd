extends GutTest
## Patch 0.125: the walkers on the title screen. A real walk cycle, tied to the
## distance walked so the feet stay on the ground.


func test_there_are_seventeen_people_and_the_cast_is_deterministic() -> void:
	var a := TitleWalk.make_people()
	var b := TitleWalk.make_people()
	assert_eq(a.size(), 17, "13 in the mock plus 30%")
	for i in a.size():
		assert_eq(a[i].off, b[i].off)
		assert_eq(a[i].lane, b[i].lane)


func test_all_four_gaits_are_in_use() -> void:
	var seen := {}
	for p in TitleWalk.make_people():
		seen[p.gait] = true
	assert_eq(seen.size(), 4)


func test_the_people_spread_across_the_width_of_the_pavement() -> void:
	var lo := 9.0
	var hi := -9.0
	for p in TitleWalk.make_people():
		lo = minf(lo, p.lane)
		hi = maxf(hi, p.lane)
	assert_gt(hi - lo, 1.2, "lanes cover most of the pavement, not a single file")


func test_a_leg_flexes_at_heel_strike_and_extends_at_toe_off() -> void:
	var g := TitleWalk.GAITS[0]
	assert_gt(TitleWalk.leg_angles(0.0, g, false).hip, 0.2, "forward at heel strike")
	assert_lt(TitleWalk.leg_angles(0.5, g, false).hip, -0.05, "behind at toe-off")


func test_the_knee_folds_in_the_swing_and_is_nearly_straight_in_stance() -> void:
	var g := TitleWalk.GAITS[0]
	var swing: float = TitleWalk.leg_angles(0.72, g, false).knee
	var stance: float = TitleWalk.leg_angles(0.3, g, false).knee
	assert_gt(swing, 0.8, "about 55 degrees or more")
	assert_lt(stance, 0.2)


func test_every_gait_has_a_real_stride() -> void:
	for g in TitleWalk.GAITS:
		assert_gt(TitleWalk.stride_units(g), 0.3, str(g.name))


func test_the_lowest_foot_stands_on_the_ground_throughout_the_cycle() -> void:
	var person := TitleWalk.make_people()[0]
	for i in 20:
		var polys := TitleWalk.silhouette(person, 100.0, i / 20.0)
		var low := -1e9
		for poly: PackedVector2Array in polys:
			for pt in poly:
				low = maxf(low, pt.y)
		assert_almost_eq(low, 0.0, 3.0, "phase %d: the body rests on its lowest foot" % i)


func test_the_planted_foot_does_not_skate() -> void:
	# Over the stance phase the foot should stay put on the ground while the body moves over it.
	var g := TitleWalk.GAITS[0]
	var stride := TitleWalk.stride_units(g)
	var xs: Array[float] = []
	for i in range(8, 48):
		var phi := i / 100.0
		var an := TitleWalk.leg_angles(phi, g, false)
		var ankle_x := sin(an.hip) * .25 + sin(an.hip - an.knee) * .25
		xs.append(phi * stride + ankle_x)
	assert_lt(xs.max() - xs.min(), 0.16, "ground position of the stance foot varies by well under a fifth of a body height")


func test_the_path_runs_from_the_lower_left_to_the_gates() -> void:
	var start := TitleWalk.path_point(0.0)
	var gate := TitleWalk.path_point(1.0)
	assert_lt(start.x, 0.0)
	assert_gt(start.y, 950.0)
	assert_gt(gate.x, 800.0)
	assert_lt(gate.y, 760.0)
	assert_gt(start.h, gate.h * 4.0, "perspective: tiny at the gates")


func test_a_person_fades_in_at_the_start_and_out_at_the_gates() -> void:
	var p := TitleWalk.make_people()[0]
	assert_almost_eq(TitleWalk.envelope(0.0), 0.0, 0.001)
	assert_almost_eq(TitleWalk.envelope(0.5), 1.0, 0.001)
	assert_almost_eq(TitleWalk.envelope(1.0), 0.0, 0.001)
	assert_not_null(p)


func test_the_leg_phase_advances_with_distance_walked() -> void:
	var p := TitleWalk.make_people()[3]
	var a := TitleWalk.phase(p, 0.3)
	var b := TitleWalk.phase(p, 0.35)
	assert_ne(a, b)
	assert_gte(a, 0.0)
	assert_lt(a, 1.0)
