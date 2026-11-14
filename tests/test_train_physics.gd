extends TestHarness
## Slice A: TrainPhysics closed-form profiles, hand-computed expectations.

const EPS := 1e-9


func test_trapezoidal_symmetric() -> void:
	# 10 km, cap 100 km/h = 250/9 m/s, a = b = 1 m/s².
	# d_accel = d_brake = (250/9)²/2 = 31250/81 m (~385.80 m);
	# cruise = 10000 - 62500/81 = 747500/81 m (~9228.40 m).
	# t_accel = t_brake = 250/9 s; t_cruise = (747500/81)/(250/9) = 2990/9 s.
	# total = (250 + 2990 + 250)/9 = 3490/9 s -> 349/54 min.
	var minutes := TrainPhysics.section_time(10.0, 100.0, 1.0, 1.0)
	near(minutes, 349.0 / 54.0, EPS, "trapezoidal total 349/54 min")


func test_triangular_symmetric() -> void:
	# 0.5 km, cap 100 km/h, a = b = 1: reaching cap needs
	# d_accel+d_brake = 2*(250/9)²/2 = 62500/81 m (~771.6 m) > 500 m -> triangular.
	# peak = sqrt(2*500*1*1/(1+1)) = sqrt(500) m/s;
	# total = peak/1 + peak/1 = 2*sqrt(500) s -> sqrt(500)/30 min.
	var minutes := TrainPhysics.section_time(0.5, 100.0, 1.0, 1.0)
	near(minutes, sqrt(500.0) / 30.0, EPS, "triangular total sqrt(500)/30 min")
	ok(2.0 * sqrt(500.0) < 250.0 / 9.0 * 2.0,
		"peak sqrt(500) m/s below cap 250/9 m/s")


func test_trapezoidal_asymmetric() -> void:
	# 5 km, cap 120 km/h = 100/3 m/s, a = 0.5, b = 0.55.
	# d_accel = (100/3)²/(2*0.5) = 10000/9 m; d_brake = (100/3)²/(2*0.55) = 100000/99 m.
	# sum = 210000/99 m (~2121.21 m) < 5000 m -> trapezoidal.
	# t_accel = (100/3)/0.5 = 200/3 s; t_brake = (100/3)/0.55 = 2000/33 s.
	# cruise = (5000 - 210000/99)/(100/3) = 285000/99 * 3/100 = 950/11 s.
	# total = 200/3 + 2000/33 + 950/11 = (2200 + 2000 + 2850)/33 = 7050/33 s
	#       = 2350/11 s -> 235/66 min.
	var minutes := TrainPhysics.section_time(5.0, 120.0, 0.5, 0.55)
	near(minutes, 235.0 / 66.0, EPS, "asymmetric trapezoidal 235/66 min")


func test_triangular_asymmetric() -> void:
	# 2 km, cap 160 km/h = 400/9 m/s, a = 0.4, b = 0.65.
	# d_accel+d_brake at cap = (400/9)²/2 * (1/0.4 + 1/0.65)
	#   = 80000/81 * (2.5 + 20/13) = 80000/81 * 105/26 ~ 3988 m > 2000 m.
	# peak = sqrt(2*2000*0.4*0.65/(0.4+0.65)) = sqrt(1040/1.05) m/s.
	# total = peak*(1/0.4 + 1/0.65) = peak*105/26 s -> peak*7/104 min.
	var peak := sqrt(1040.0 / 1.05)
	var minutes := TrainPhysics.section_time(2.0, 160.0, 0.4, 0.65)
	near(minutes, peak * 7.0 / 104.0, EPS, "asymmetric triangular peak*7/104 min")
	ok(peak < 400.0 / 9.0, "peak below cap")


func test_speed_factor_scales_cap_only_trapezoidal() -> void:
	# Case 1 with factor 0.5: cap 50 km/h = 125/9 m/s, a = b = 1.
	# d_accel = d_brake = (125/9)²/2 = 15625/162 m;
	# cruise = 10000 - 31250/162 = 1588750/162 m.
	# t_accel = t_brake = 125/9 s; t_cruise = (1588750/162)/(125/9) = 6355/9 s.
	# total = (125 + 6355 + 125)/9 = 6605/9 s -> 6605/540 = 1321/108 min.
	var minutes := TrainPhysics.section_time(10.0, 100.0, 1.0, 1.0, 0.5)
	near(minutes, 1321.0 / 108.0, EPS, "half cap trapezoidal 1321/108 min")
	# Accel/brake rates unchanged, so halving the cap less than doubles total
	# time (the accel/brake phases shrink too), but strictly increases it.
	var full := TrainPhysics.section_time(10.0, 100.0, 1.0, 1.0)
	ok(minutes > full and minutes < 2.0 * full, "half cap between 1x and 2x full time")


func test_speed_factor_no_effect_on_triangular() -> void:
	# 0.02 km (20 m) triangular at both caps: peak = sqrt(2*20*1*1/2) = sqrt(20)
	# ~ 4.47 m/s, below both the full cap (250/9 ~ 27.8 m/s) and the half cap
	# (125/9 ~ 13.9 m/s), so the factor cannot change the profile.
	# total = 2*sqrt(20)/1 s -> sqrt(20)/30 min.
	var full := TrainPhysics.section_time(0.02, 100.0, 1.0, 1.0)
	var half := TrainPhysics.section_time(0.02, 100.0, 1.0, 1.0, 0.5)
	near(full, sqrt(20.0) / 30.0, EPS, "triangular total sqrt(20)/30 min")
	eq(half, full, "speed_factor irrelevant while cap is never reached")


func test_nonpositive_distance() -> void:
	eq(TrainPhysics.section_time(0.0, 100.0, 1.0, 1.0), 0.0, "zero distance -> 0")
	eq(TrainPhysics.section_time(-3.0, 100.0, 1.0, 1.0), 0.0, "negative distance -> 0")


func test_zero_speed_cap_is_infinite() -> void:
	eq(TrainPhysics.section_time(5.0, 0.0, 1.0, 1.0), INF, "zero max speed -> INF")
	eq(TrainPhysics.section_time(5.0, 100.0, 1.0, 1.0, 0.0), INF, "zero factor -> INF")


func test_monotone_in_distance() -> void:
	var previous := 0.0
	for step in range(1, 61):
		var distance := step * 0.25
		var minutes := TrainPhysics.section_time(distance, 140.0, 0.45, 0.6)
		ok(minutes >= previous, "time monotone at %f km" % distance)
		previous = minutes


func test_progress_trapezoidal_hand_computed() -> void:
	# Case 1 profile: t_accel = 250/9 s, total = 3490/9 s, dist 10000 m.
	# elapsed 0.25 min = 15 s (accel): covered = 0.5*15² = 112.5 m -> 0.01125.
	var p_accel := TrainPhysics.section_progress(10.0, 100.0, 1.0, 1.0, 1.0, 0.25)
	near(p_accel, 112.5 / 10000.0, EPS, "progress during acceleration")
	# elapsed 0.75 min = 45 s (cruise): covered = 31250/81 + (250/9)*(45 - 250/9)
	#   = 31250/81 + 38750/81 = 70000/81 m -> 7/81.
	var p_cruise := TrainPhysics.section_progress(10.0, 100.0, 1.0, 1.0, 1.0, 0.75)
	near(p_cruise, 7.0 / 81.0, EPS, "progress during cruise")
	# elapsed 340/54 min = 3400/9 s leaves 3490/9 - 3400/9 = 10 s of braking:
	# remaining = 0.5*1*10² = 50 m -> covered 9950 m -> 0.995.
	var p_brake := TrainPhysics.section_progress(10.0, 100.0, 1.0, 1.0, 1.0, 340.0 / 54.0)
	near(p_brake, 0.995, EPS, "progress during braking")


func test_progress_triangular_hand_computed() -> void:
	# 0.5 km, a = b = 1: peak sqrt(500) m/s at t = sqrt(500) s, total 2*sqrt(500) s.
	# At half the total time the peak is reached: covered = 0.5*500 = 250 m -> 0.5.
	var half_time := sqrt(500.0) / 60.0
	near(TrainPhysics.section_progress(0.5, 100.0, 1.0, 1.0, 1.0, half_time), 0.5, EPS,
		"triangular midpoint is peak")
	# At quarter time (sqrt(500)/2 s, still accelerating):
	# covered = 0.5*(sqrt(500)/2)² = 62.5 m -> 0.125 (distance grows with t²).
	near(TrainPhysics.section_progress(0.5, 100.0, 1.0, 1.0, 1.0, half_time / 2.0), 0.125, EPS,
		"triangular quarter-time progress")


func test_progress_endpoints_and_clamping() -> void:
	var total := TrainPhysics.section_time(6.0, 110.0, 0.5, 0.6)
	eq(TrainPhysics.section_progress(6.0, 110.0, 0.5, 0.6, 1.0, 0.0), 0.0, "progress at start")
	near(TrainPhysics.section_progress(6.0, 110.0, 0.5, 0.6, 1.0, total), 1.0, EPS,
		"progress at section end")
	eq(TrainPhysics.section_progress(6.0, 110.0, 0.5, 0.6, 1.0, -1.0), 0.0,
		"negative elapsed clamps to 0")
	near(TrainPhysics.section_progress(6.0, 110.0, 0.5, 0.6, 1.0, total + 10.0), 1.0, EPS,
		"overshoot clamps to 1")
	eq(TrainPhysics.section_progress(0.0, 110.0, 0.5, 0.6, 1.0, 3.0), 1.0,
		"zero-distance section is trivially complete")


func test_progress_monotone_and_consistent() -> void:
	for distance in [0.3, 2.0, 9.0, 40.0]:
		var total := TrainPhysics.section_time(distance, 130.0, 0.55, 0.5)
		var previous := 0.0
		for step in range(0, 21):
			var elapsed := total * step / 20.0
			var progress := TrainPhysics.section_progress(distance, 130.0, 0.55, 0.5, 1.0, elapsed)
			ok(progress >= previous - EPS, "progress monotone at %f km step %d" % [distance, step])
			previous = progress
		near(previous, 1.0, EPS, "progress reaches 1 at %f km" % distance)
	# speed_factor slows progress at a fixed elapsed time (cap-limited section).
	var normal := TrainPhysics.section_progress(10.0, 100.0, 1.0, 1.0, 1.0, 1.0)
	var slowed := TrainPhysics.section_progress(10.0, 100.0, 1.0, 1.0, 0.5, 1.0)
	ok(slowed < normal, "half cap covers less distance in the same time")


func test_real_config_categories() -> void:
	var trains := ConfigData.load_file("trains")
	for category_name in trains["categories"]:
		var category: Dictionary = trains["categories"][category_name]
		var vmax: float = float(category["max_speed_kmh"])
		var minutes := TrainPhysics.section_time(100.0, vmax,
			float(category["accel_mps2"]), float(category["brake_mps2"]))
		# Lower bound: 100 km at full cap without accel/brake overhead.
		ok(minutes > 100.0 * 60.0 / vmax, "%s 100 km slower than cap-only bound" % category_name)
		var slowed := TrainPhysics.section_time(100.0, vmax,
			float(category["accel_mps2"]), float(category["brake_mps2"]), 0.5)
		ok(slowed > minutes, "%s half cap increases section time" % category_name)
