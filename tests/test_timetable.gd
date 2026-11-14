extends TestHarness
## Slice A: Timetable generation, event application, queries.
## Mini config: cap 60 km/h = 50/3 m/s, a = b = 0.5 m/s², dwell 2 min.
## d_accel = d_brake = (50/3)²/(2*0.5) = 2500/9 m; t_accel = t_brake = 100/3 s.
## 5 km section: cruise (5000 - 5000/9)/(50/3) = 800/3 s -> total 1000/3 s = 50/9 min.
## 10 km section: cruise (10000 - 5000/9)/(50/3) = 1700/3 s -> total 1900/3 s = 95/9 min.

const EPS := 1e-9


func test_slots_ids_and_horizon_boundary() -> void:
	var tt := _generate([])
	eq(tt.train_ids(), ["T-F-0", "T-R-0", "T-F-1", "T-R-1"],
		"slots 100,130 < 100+60; 160 excluded, F before R per k")
	for train_id in tt.train_ids():
		var stops: Array = tt.base_timetables()[train_id]["stops"]
		var k := int(train_id.get_slice("-", 2))
		eq(float(stops[0]["arrival"]), 100.0 + k * 30.0, "first arrival == slot for " + train_id)
		eq(float(stops[0]["departure"]), 100.0 + k * 30.0 + 2.0, "first departure == slot + dwell for " + train_id)
	# Wider horizon admits slot 160 (160 < 100 + 90).
	var config := _mini_events_config()
	config["horizon_minutes"] = 90.0
	var wider := Timetable.generate(_mini_network(), _mini_trains(), config, [])
	eq(wider.train_ids().size(), 6, "horizon 90 adds slot 160 in both directions")


func test_base_schedule_hand_computed_forward() -> void:
	# T-F-0 slot 100, dwell 2: alpha arr 100 dep 102; beta arr 102+50/9 = 968/9,
	# dep 986/9; gamma arr 986/9+95/9 = 1081/9, dep 1099/9.
	var stops: Array = _generate([]).base_timetables()["T-F-0"]["stops"]
	eq(stops.size(), 3, "three stops")
	var expected := [
		{"station_id": "alpha", "platform": 1, "km": 0.0, "arrival": 100.0, "departure": 102.0},
		{"station_id": "beta", "platform": 2, "km": 5.0, "arrival": 968.0 / 9.0, "departure": 986.0 / 9.0},
		{"station_id": "gamma", "platform": 3, "km": 15.0, "arrival": 1081.0 / 9.0, "departure": 1099.0 / 9.0}]
	for i in stops.size():
		for key in expected[i]:
			if expected[i][key] is float:
				near(float(stops[i][key]), float(expected[i][key]), EPS, "F stop %d %s" % [i, key])
			else:
				eq(stops[i][key], expected[i][key], "F stop %d %s" % [i, key])


func test_base_schedule_hand_computed_reverse() -> void:
	# T-R-0: gamma km 0 first; beta km 10 (15-5) after 95/9; alpha km 15 last.
	# gamma arr 100 dep 102; beta arr 102+95/9 = 1013/9, dep 1031/9;
	# alpha arr 1031/9+50/9 = 1081/9, dep 1099/9.
	var stops: Array = _generate([]).base_timetables()["T-R-0"]["stops"]
	var expected := [
		{"station_id": "gamma", "platform": 1, "km": 0.0, "arrival": 100.0, "departure": 102.0},
		{"station_id": "beta", "platform": 2, "km": 10.0, "arrival": 1013.0 / 9.0, "departure": 1031.0 / 9.0},
		{"station_id": "alpha", "platform": 3, "km": 15.0, "arrival": 1081.0 / 9.0, "departure": 1099.0 / 9.0}]
	for i in stops.size():
		for key in expected[i]:
			if expected[i][key] is float:
				near(float(stops[i][key]), float(expected[i][key]), EPS, "R stop %d %s" % [i, key])
			else:
				eq(stops[i][key], expected[i][key], "R stop %d %s" % [i, key])


func test_dwell_and_monotonicity_all_trains() -> void:
	var tt := _generate([])
	for train_id in tt.train_ids():
		var stops: Array = tt.base_timetables()[train_id]["stops"]
		for i in stops.size():
			var arrival := float(stops[i]["arrival"])
			var departure := float(stops[i]["departure"])
			# Every stop dwells, origin and terminus included (manual boarding
			# and disembark need real windows).
			near(departure - arrival, 2.0, EPS, "%s stop %d dwell == config" % [train_id, i])
			if i + 1 < stops.size():
				ok(float(stops[i + 1]["arrival"]) > departure, "%s section %d positive" % [train_id, i])
				ok(float(stops[i + 1]["km"]) > float(stops[i]["km"]), "%s km increases" % train_id)


func test_platforms_fixed_per_direction() -> void:
	var tt := _generate([])
	for k in 2:
		var forward: Array = tt.base_timetables()["T-F-%d" % k]["stops"]
		var reverse: Array = tt.base_timetables()["T-R-%d" % k]["stops"]
		for i in forward.size():
			eq(int(forward[i]["platform"]), i + 1, "F platform = 1-based index")
			eq(int(reverse[i]["platform"]), i + 1, "R platform = stop_count + 1 - forward_index")
		# The same station swaps platform numbers between directions; the
		# middle stop of an odd-length line keeps its number (3+1-2 == 2).
		ok(int(forward[0]["platform"]) != int(reverse[2]["platform"]),
			"alpha platforms differ between directions")
		ok(int(forward[2]["platform"]) != int(reverse[0]["platform"]),
			"gamma platforms differ between directions")


func test_train_numbers_and_info() -> void:
	var tt := _generate([])
	# Running index per category in generation order: F 10, F 11, F 12, F 13.
	var expected_numbers := {"T-F-0": "F 10", "T-R-0": "F 11", "T-F-1": "F 12", "T-R-1": "F 13"}
	for train_id in expected_numbers:
		eq(tt.train_info(train_id)["train_number"], expected_numbers[train_id],
			"number for " + train_id)
	var info: Dictionary = tt.train_info("T-R-0")
	eq(info["line_id"], "T", "line_id")
	eq(info["line_name"], "Test line", "line_name")
	eq(info["color"], "#123456", "color")
	eq(info["category"], "fast", "category")
	eq(info["direction"], "R", "direction")
	eq(info["destination"], "Alpha", "reverse destination is origin name")
	eq(tt.train_info("T-F-0")["destination"], "Gamma", "forward destination name")
	eq(info["stops"], [{"station_id": "gamma", "platform": 1},
		{"station_id": "beta", "platform": 2}, {"station_id": "alpha", "platform": 3}],
		"info stops carry station and platform only")


func test_train_state_phase_boundaries() -> void:
	var tt := _generate([])
	var before := tt.train_state("T-F-0", 99.0)
	eq(before["phase"], "before", "before slot")
	eq(before["km"], 0.0, "before km 0")
	eq(before["delay"], 0.0, "before delay 0")
	eq(before["station_id"], "", "before no station")
	# Exact arrival instant is dwelling (manager ruling).
	var at_start := tt.train_state("T-F-0", 100.0)
	eq(at_start["phase"], "dwelling", "slot instant dwells at origin")
	eq(at_start["station_id"], "alpha", "dwelling station")
	eq(at_start["platform"], 1, "dwelling platform")
	# t = 105: origin dwell is [100, 102); elapsed from departure 102 is
	# 3 min = 180 s, cruise: covered = 2500/9 + (50/3)*(180 - 100/3)
	# = 2500/9 + 22000/9 = 24500/9 m -> progress (24500/9)/5000 = 49/90.
	var moving := tt.train_state("T-F-0", 105.0)
	eq(moving["phase"], "moving", "mid-section moving")
	eq(moving["from_station"], "alpha", "section from")
	eq(moving["to_station"], "beta", "section to")
	near(moving["progress"], 49.0 / 90.0, EPS, "cruise progress 49/90")
	near(moving["km"], 5.0 * 49.0 / 90.0, EPS, "km = progress * section length")
	eq(moving["station_id"], "", "moving has no dwelling station")
	eq(moving["platform"], 0, "moving platform 0")
	var at_beta := tt.train_state("T-F-0", 968.0 / 9.0)
	eq(at_beta["phase"], "dwelling", "arrival instant at beta dwells")
	eq(at_beta["station_id"], "beta", "beta station")
	near(at_beta["km"], 5.0, EPS, "beta km")
	var leaving_beta := tt.train_state("T-F-0", 986.0 / 9.0)
	eq(leaving_beta["phase"], "moving", "departure instant is moving")
	eq(leaving_beta["progress"], 0.0, "progress 0 at departure")
	var at_gamma := tt.train_state("T-F-0", 1081.0 / 9.0)
	eq(at_gamma["phase"], "dwelling", "terminus arrival dwells (disembark window)")
	eq(at_gamma["station_id"], "gamma", "terminus station")
	eq(at_gamma["platform"], 3, "terminus platform")
	var finished := tt.train_state("T-F-0", 1099.0 / 9.0)
	eq(finished["phase"], "finished", "finished only at last departure")
	near(finished["km"], 15.0, EPS, "finished km = total")
	eq(tt.train_state("T-F-0", 500.0)["phase"], "finished", "long after still finished")


func test_base_state_matches_effective_without_events() -> void:
	var tt := _generate([])
	for t in [99.0, 100.0, 105.0, 968.0 / 9.0, 1081.0 / 9.0, 1099.0 / 9.0, 500.0]:
		eq(tt.train_state("T-F-0", t), tt.base_train_state("T-F-0", t),
			"no events: effective == base at t=%f" % t)
		eq(tt.departures("alpha", t, 10), tt.base_departures("alpha", t, 10),
			"no events: boards equal at t=%f" % t)


func test_cancel_never_moves() -> void:
	var tt := _generate([{"id": 0, "type": "cancel", "train_id": "T-F-0", "at_minute": 98.0}])
	for t in [99.0, 100.0, 105.0, 130.0, 500.0]:
		var state := tt.train_state("T-F-0", t)
		eq(state["phase"], "cancelled", "cancelled at t=%f" % t)
		eq(state["km"], 0.0, "cancelled km stays 0")
		eq(state["delay"], 0.0, "cancelled delay 0")
	# Base schedule kept for display; base state unaffected.
	eq(tt.base_train_state("T-F-0", 100.0)["phase"], "dwelling", "base still dwells")
	eq(tt.effective_arrival("T-F-0", "gamma"), INF, "cancelled never arrives")
	eq(tt.effective_arrival("T-F-0", "alpha"), INF, "cancelled origin arrival INF")
	var rows := tt.departures("alpha", 0.0, 10)
	var cancelled_rows := rows.filter(func(r: Dictionary) -> bool: return r["cancelled"])
	eq(cancelled_rows.size(), 1, "cancelled train on the board")
	eq(cancelled_rows[0]["train_id"], "T-F-0", "cancelled row id")
	eq(cancelled_rows[0]["departure"], 102.0, "cancelled row keeps base departure")
	eq(cancelled_rows[0]["delay"], 0.0, "cancelled row delay 0")


func test_drunk_during_dwell_shifts_later_stops() -> void:
	# at 108 inside beta dwell [968/9, 986/9) ~ [107.56, 109.56), duration 10:
	# beta dep 986/9+10 = 1076/9; gamma arr 1081/9+10 = 1171/9, dep 1189/9.
	var tt := _generate([{"id": 0, "type": "drunk_driver", "train_id": "T-F-0",
		"at_minute": 108.0, "duration_minutes": 10.0}])
	var stops: Array = tt.base_timetables()["T-F-0"]["stops"]  # base untouched
	near(float(stops[1]["departure"]), 986.0 / 9.0, EPS, "base beta departure unchanged")
	near(tt.effective_arrival("T-F-0", "alpha"), 100.0, EPS, "alpha arrival unchanged")
	near(tt.effective_arrival("T-F-0", "beta"), 968.0 / 9.0, EPS, "beta arrival unchanged")
	near(tt.effective_arrival("T-F-0", "gamma"), 1171.0 / 9.0, EPS, "gamma arrival +10")
	# At the original beta departure the train now still dwells.
	var still := tt.train_state("T-F-0", 986.0 / 9.0)
	eq(still["phase"], "dwelling", "extended dwell covers old departure")
	eq(still["delay"], 0.0, "delay at beta arrival still 0")
	var moving := tt.train_state("T-F-0", 120.0)
	eq(moving["phase"], "moving", "moving after extended dwell")
	near(moving["delay"], 10.0, EPS, "moving delay = shift of next arrival")
	var finished := tt.train_state("T-F-0", 500.0)
	near(finished["delay"], 10.0, EPS, "finished delay = last arrival shift")
	var rows := tt.departures("gamma", 0.0, 10)
	var row: Dictionary = rows.filter(func(r: Dictionary) -> bool: return r["train_id"] == "T-F-0")[0]
	near(float(row["departure"]), 1189.0 / 9.0, EPS, "board departure shifted")
	near(row["delay"], 10.0, EPS, "board delay 10")


func test_drunk_while_moving_delays_next_arrival() -> void:
	# at 103 in section alpha->beta [102, 968/9), duration 5:
	# beta arr 968/9+5 = 1013/9, dep 1031/9; gamma arr 1081/9+5 = 1126/9.
	var tt := _generate([{"id": 0, "type": "drunk_driver", "train_id": "T-F-0",
		"at_minute": 103.0, "duration_minutes": 5.0}])
	near(tt.effective_arrival("T-F-0", "beta"), 1013.0 / 9.0, EPS, "beta arrival +5")
	near(tt.effective_arrival("T-F-0", "gamma"), 1126.0 / 9.0, EPS, "gamma arrival +5")
	# t=100 is inside the origin dwell [100, 102); the event hit section 0,
	# so the origin arrival itself is unshifted.
	eq(tt.train_state("T-F-0", 100.0)["phase"], "dwelling", "origin dwells at slot")
	eq(tt.train_state("T-F-0", 100.0)["delay"], 0.0, "origin delay 0")
	near(tt.train_state("T-F-0", 104.0)["delay"], 5.0, EPS, "moving delay 5")
	near(tt.train_state("T-F-0", 500.0)["delay"], 5.0, EPS, "finished delay 5")


func test_drunk_before_first_departure() -> void:
	# at 95 < slot 100, duration 7: whole schedule +7 (alpha arr 107, dep 109).
	var tt := _generate([{"id": 0, "type": "drunk_driver", "train_id": "T-F-0",
		"at_minute": 95.0, "duration_minutes": 7.0}])
	near(tt.effective_arrival("T-F-0", "alpha"), 107.0, EPS, "origin delayed")
	near(tt.effective_arrival("T-F-0", "gamma"), 1081.0 / 9.0 + 7.0, EPS, "terminus +7")
	var before := tt.train_state("T-F-0", 100.0)
	eq(before["phase"], "before", "old slot now before start")
	eq(before["delay"], 0.0, "before events hit delay 0")
	eq(tt.train_state("T-F-0", 107.0)["phase"], "dwelling", "new slot dwells")
	var rows := tt.departures("alpha", 0.0, 10)
	var row: Dictionary = rows.filter(func(r: Dictionary) -> bool: return r["train_id"] == "T-F-0")[0]
	near(row["departure"], 109.0, EPS, "board origin departure delayed")
	near(row["delay"], 7.0, EPS, "board delay 7")
	eq(tt.base_departures("alpha", 0.0, 10)[0]["departure"], 102.0, "base board unchanged")


func test_slow_down_mid_section() -> void:
	# at 103 in alpha->beta (5 km), factor 0.5: cap 30 km/h = 25/3 m/s.
	# t_accel = t_brake = 50/3 s; cruise (5000 - 1250/9)/(25/3) = 1750/3 s;
	# new total 1850/3 s = 185/18 min; old 50/9 = 100/18 -> delta 85/18.
	# beta arr 968/9 + 85/18 = 2021/18; gamma arr 1081/9 + 85/18 = 2247/18.
	var tt := _generate([{"id": 0, "type": "slow_down", "train_id": "T-F-0",
		"at_minute": 103.0, "speed_factor": 0.5}])
	var delta := 85.0 / 18.0
	near(tt.effective_arrival("T-F-0", "alpha"), 100.0, EPS, "origin unchanged")
	near(tt.effective_arrival("T-F-0", "beta"), 2021.0 / 18.0, EPS, "beta arrival + delta")
	near(tt.effective_arrival("T-F-0", "gamma"), 2247.0 / 18.0, EPS, "gamma arrival + delta")
	# Later section keeps its base duration: gamma arr - beta dep == 95/9.
	var moving := tt.train_state("T-F-0", 104.0)
	eq(moving["phase"], "moving", "still in slowed section")
	near(moving["delay"], delta, EPS, "delay equals section delta")
	# elapsed from departure 102 = 2 min = 120 s at half cap:
	# covered = 625/9 + (25/3)*(120 - 50/3) = 8375/9 m -> progress 67/360.
	near(moving["progress"], 67.0 / 360.0, EPS, "progress uses slowed profile")
	near(moving["km"], 5.0 * 67.0 / 360.0, EPS, "km uses slowed progress")
	near(tt.train_state("T-F-0", 500.0)["delay"], delta, EPS, "finished delay = delta")


func test_slow_down_while_dwelling_hits_next_section() -> void:
	# at 108 dwelling at beta [968/9, 986/9) -> section beta->gamma (10 km) slowed.
	# new total: t_accel = t_brake = 50/3, cruise (10000 - 1250/9)/(25/3) = 3550/3
	# -> 3650/3 s = 365/18 min; old 95/9 = 190/18 -> delta 175/18.
	# beta unchanged; gamma arr 1081/9 + 175/18 = 2337/18.
	var tt := _generate([{"id": 0, "type": "slow_down", "train_id": "T-F-0",
		"at_minute": 108.0, "speed_factor": 0.5}])
	var delta := 175.0 / 18.0
	near(tt.effective_arrival("T-F-0", "beta"), 968.0 / 9.0, EPS, "beta arrival unchanged")
	near(tt.effective_arrival("T-F-0", "gamma"), 2337.0 / 18.0, EPS, "gamma arrival + delta")
	var dwelling := tt.train_state("T-F-0", 108.0)
	eq(dwelling["phase"], "dwelling", "still dwelling at event time")
	eq(dwelling["delay"], 0.0, "dwelling delay 0 (arrival not shifted)")
	near(tt.train_state("T-F-0", 120.0)["delay"], delta, EPS, "next section carries delta")


func test_slow_down_before_start_hits_first_section() -> void:
	var tt := _generate([{"id": 0, "type": "slow_down", "train_id": "T-F-0",
		"at_minute": 95.0, "speed_factor": 0.5}])
	near(tt.effective_arrival("T-F-0", "alpha"), 100.0, EPS, "origin unchanged")
	near(tt.effective_arrival("T-F-0", "beta"), 2021.0 / 18.0, EPS, "first section slowed")
	eq(tt.train_state("T-F-0", 99.0)["phase"], "before", "still before start")


func test_events_locate_on_shifted_schedule() -> void:
	# drunk at 108 (beta dwell) +10, then slow at 125: on the shifted schedule
	# the train is moving beta->gamma [1076/9, 1171/9) ~ [119.56, 130.11),
	# so section 1 slows: delta 175/18 on top of the +10.
	# gamma arr 1171/9 + 175/18 = 2517/18; total delay 10 + 175/18 = 355/18.
	var tt := _generate([
		{"id": 0, "type": "drunk_driver", "train_id": "T-F-0",
			"at_minute": 108.0, "duration_minutes": 10.0},
		{"id": 1, "type": "slow_down", "train_id": "T-F-0",
			"at_minute": 125.0, "speed_factor": 0.5}])
	near(tt.effective_arrival("T-F-0", "beta"), 968.0 / 9.0, EPS, "beta arrival untouched")
	near(tt.effective_arrival("T-F-0", "gamma"), 2517.0 / 18.0, EPS, "both shifts stack")
	near(tt.train_state("T-F-0", 500.0)["delay"], 355.0 / 18.0, EPS, "stacked final delay")


func test_departures_sorted_filtered_counted() -> void:
	var tt := _generate([])
	# alpha departures: F trains start there at slot + dwell (platform 1);
	# R trains terminate there: dep 1099/9 (k=0) and 1099/9+30 (k=1), platform 3.
	var rows := tt.departures("alpha", 0.0, 10)
	eq(rows.size(), 4, "all four trains depart alpha once")
	var expected_departures := [102.0, 1099.0 / 9.0, 132.0, 1099.0 / 9.0 + 30.0]
	var expected_ids := ["T-F-0", "T-R-0", "T-F-1", "T-R-1"]
	var expected_platforms := [1, 3, 1, 3]
	for i in rows.size():
		eq(rows[i]["train_id"], expected_ids[i], "board order %d" % i)
		near(float(rows[i]["departure"]), expected_departures[i], EPS, "board departure %d" % i)
		eq(rows[i]["platform"], expected_platforms[i], "alpha platform per direction")
		eq(rows[i]["line_id"], "T", "row line_id")
		eq(rows[i]["cancelled"], false, "row not cancelled")
		eq(rows[i]["delay"], 0.0, "row delay 0")
	eq(rows[0]["train_number"], "F 10", "row train_number")
	eq(rows[0]["destination"], "Gamma", "F destination name")
	eq(rows[1]["destination"], "Alpha", "R destination name")
	eq(tt.departures("alpha", 0.0, 2).size(), 2, "count limits rows")
	eq(tt.departures("alpha", 0.0, 2), rows.slice(0, 2), "count takes earliest")
	var filtered := tt.departures("alpha", 110.0, 10)
	eq(filtered.size(), 3, "departures < t filtered out")
	eq(filtered[0]["train_id"], "T-R-0", "first departure >= 110")
	eq(tt.departures("alpha", 102.0, 10)[0]["train_id"], "T-F-0", "departure == t included")
	eq(tt.departures("nowhere", 0.0, 10), [], "unknown station empty board")
	eq(tt.departures("alpha", 0.0, 0), [], "count 0 empty")


func test_platform_next() -> void:
	var tt := _generate([])
	var first := tt.platform_next("alpha", 1, 0.0)
	eq(first["train_id"], "T-F-0", "earliest at platform")
	eq(first["departure"], 102.0, "platform row departure")
	var next := tt.platform_next("alpha", 1, 102.5)
	eq(next["train_id"], "T-F-1", "next F departure after origin leaves")
	eq(tt.platform_next("alpha", 3, 101.0)["train_id"], "T-R-0", "terminating R train at platform 3")
	eq(tt.platform_next("alpha", 2, 0.0), {}, "no platform 2 at alpha")
	# gamma platform 3 serves arriving F trains only; R starts at platform 1.
	eq(tt.platform_next("gamma", 3, 0.0)["train_id"], "T-F-0", "F terminus platform")
	eq(tt.platform_next("gamma", 1, 0.0)["train_id"], "T-R-0", "R origin platform")
	eq(tt.platform_next("gamma", 3, 1099.0 / 9.0)["train_id"], "T-F-0", "departure == t included")
	eq(tt.platform_next("gamma", 3, 1099.0 / 9.0 + 0.001)["train_id"], "T-F-1", "next F arrival")
	eq(tt.platform_next("beta", 2, 0.0)["train_id"], "T-F-0", "beta platform 2 earliest")


func test_effective_arrival_queries() -> void:
	var tt := _generate([])
	near(tt.effective_arrival("T-F-0", "beta"), 968.0 / 9.0, EPS, "beta arrival")
	near(tt.effective_arrival("T-R-0", "beta"), 1013.0 / 9.0, EPS, "reverse beta arrival")
	eq(tt.effective_arrival("T-F-0", "nowhere"), INF, "never stops -> INF")
	eq(tt.effective_arrival("T-R-0", "gamma"), 100.0, "origin arrival is the slot")


func test_base_timetables_shape() -> void:
	var tt := _generate([{"id": 0, "type": "cancel", "train_id": "T-F-0", "at_minute": 98.0}])
	var tables := tt.base_timetables()
	eq(tables.keys().size(), 4, "one entry per train")
	for train_id in tt.train_ids():
		ok(tables.has(train_id), "entry for " + train_id)
		eq(tables[train_id]["info"], tt.train_info(train_id), "info matches train_info")
		eq(tables[train_id]["stops"].size(), 3, "full stop list")
	# Base stays pristine despite the cancel event.
	near(float(tables["T-F-0"]["stops"][2]["arrival"]), 1081.0 / 9.0, EPS,
		"cancelled train keeps base schedule")


func test_purity_out_of_order_queries() -> void:
	var tt := _generate([
		{"id": 0, "type": "drunk_driver", "train_id": "T-F-0",
			"at_minute": 108.0, "duration_minutes": 10.0},
		{"id": 1, "type": "slow_down", "train_id": "T-R-0",
			"at_minute": 112.0, "speed_factor": 0.5},
		{"id": 2, "type": "cancel", "train_id": "T-F-1", "at_minute": 128.0}])
	var early := tt.train_state("T-F-0", 105.0)
	var early_board := tt.departures("beta", 100.0, 10)
	tt.train_state("T-F-0", 140.0)
	tt.departures("beta", 130.0, 10)
	tt.train_state("T-R-0", 500.0)
	eq(tt.train_state("T-F-0", 105.0), early, "state(t1) unchanged after later queries")
	eq(tt.departures("beta", 100.0, 10), early_board, "board(t1) unchanged after later queries")
	eq(tt.base_train_state("T-F-0", 105.0), tt.base_train_state("T-F-0", 105.0),
		"base state repeatable")


func test_real_config_generation() -> void:
	var network := ConfigData.load_file("network")
	var trains := ConfigData.load_file("trains")
	var events_config := ConfigData.load_file("events")
	var tt := Timetable.generate(network, trains, events_config, [])
	# Slots per line: horizon 480 / frequency -> L1 8, L2 8, L3 4, L4 16,
	# L5 8, L6 8; both directions -> 16+16+8+32+16+16 = 104 trains.
	eq(tt.train_ids().size(), 104, "real config train count")
	var dwell := float(trains["dwell_minutes"])
	var slot_by_line := {}
	for line: Dictionary in network["lines"]:
		slot_by_line[line["id"]] = float(line["first_departure_minutes"])
	for train_id in tt.train_ids():
		var entry: Dictionary = tt.base_timetables()[train_id]
		var stops: Array = entry["stops"]
		var info: Dictionary = entry["info"]
		var line_id: String = info["line_id"]
		var k := int(train_id.get_slice("-", 2))
		var line: Dictionary = {}
		for candidate: Dictionary in network["lines"]:
			if candidate["id"] == line_id:
				line = candidate
		var frequency := float(line["frequency_minutes"])
		near(float(stops[0]["arrival"]), slot_by_line[line_id] + k * frequency, EPS,
			"%s slot from config" % train_id)
		for i in range(1, stops.size()):
			near(float(stops[i]["departure"]) - float(stops[i]["arrival"]), dwell, EPS,
				"%s stop %d dwell from config" % [train_id, i])
			ok(float(stops[i]["arrival"]) > float(stops[i - 1]["departure"]),
				"%s monotone at stop %d" % [train_id, i])
			var platform := int(stops[i]["platform"])
			ok(platform >= 1 and platform <= stops.size(), "%s platform in range" % train_id)
	# Category number counters run across lines in config order:
	# L1 intercity 16 (IC 100..115), L2 regional 16 (R 300..315), L3 express 8
	# (E 100..107), L4 local 32 (O 200..231), L5 regional 16 (R 316..331),
	# L6 regional 16 (R 332..347).
	eq(tt.train_info("L1-F-0")["train_number"], "IC 100", "first intercity number")
	eq(tt.train_info("L1-R-7")["train_number"], "IC 115", "last L1 number")
	eq(tt.train_info("L3-R-3")["train_number"], "E 107", "last express number")
	eq(tt.train_info("L4-F-0")["train_number"], "O 200", "first local number")
	eq(tt.train_info("L5-F-0")["train_number"], "R 316", "regional counter continues across lines")
	eq(tt.train_info("L6-R-7")["train_number"], "R 347", "last regional number")
	eq(tt.train_info("L1-F-0")["destination"], "Kraków", "destination display name")
	eq(tt.train_info("L1-R-0")["destination"], "Warszawa", "reverse destination display name")


func _generate(events: Array) -> Timetable:
	return Timetable.generate(_mini_network(), _mini_trains(), _mini_events_config(), events)


func _mini_network() -> Dictionary:
	return {
		"destination_station": "gamma",
		"stations": [
			{"id": "alpha", "name": "Alpha", "map_pos": [0, 0], "start_city": true},
			{"id": "beta", "name": "Beta", "map_pos": [1, 0], "start_city": false},
			{"id": "gamma", "name": "Gamma", "map_pos": [2, 0], "start_city": false}],
		"lines": [{
			"id": "T", "name": "Test line", "color": "#123456", "category": "fast",
			"frequency_minutes": 30.0, "first_departure_minutes": 100.0,
			"stops": [{"station": "alpha", "km": 0.0}, {"station": "beta", "km": 5.0},
				{"station": "gamma", "km": 15.0}]}],
	}


func _mini_trains() -> Dictionary:
	return {
		"dwell_minutes": 2.0,
		"categories": {
			"fast": {"max_speed_kmh": 60.0, "accel_mps2": 0.5, "brake_mps2": 0.5,
				"number_prefix": "F", "number_start": 10.0}},
	}


func _mini_events_config() -> Dictionary:
	return {
		"min_events": 0, "max_events": 0, "horizon_minutes": 60.0,
		"types": {
			"drunk_driver": {"weight": 1.0, "stop_duration_min_minutes": 30.0,
				"stop_duration_max_minutes": 60.0},
			"slow_down": {"weight": 1.0, "speed_factor": 0.5},
			"cancel": {"weight": 1.0, "lead_minutes_min": 1.0, "lead_minutes_max": 5.0}},
	}
