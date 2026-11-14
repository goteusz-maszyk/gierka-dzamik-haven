extends TestHarness
## Cross-module integration: Run + World + Events + RoutePlanner on the real config.
## Expected ride times below are hand-computed from DESIGN.md category numbers
## (closed-form accel/cruise/brake), independent of the implementation.

const SEEDS: Array[int] = [1, 7, 42, 1234, 99999]

var _station_rate: float = ConfigData.load_file("time").station_view_minutes_per_real_second
var _map_rate: float = ConfigData.load_file("time").map_view_minutes_per_real_second


func _make_run(seed_value: int) -> Run:
	return Run.create(seed_value)


func test_deadline_construction_all_seeds() -> void:
	var time_cfg := ConfigData.load_file("time")
	for seed_value in SEEDS:
		var run := _make_run(seed_value)
		near(run.deadline, time_cfg.perfect_arrival_minutes, 1e-6, "deadline is 09:00 (seed %d)" % seed_value)
		ok(run.start_time < run.deadline, "start before deadline (seed %d)" % seed_value)
		near(run.clock, run.start_time, 1e-9, "clock starts at start_time (seed %d)" % seed_value)
		ok(run.rewind_meter > 0.0, "meter full at start (seed %d)" % seed_value)
		eq(run.player_station, run.start_station, "player at start station (seed %d)" % seed_value)
		eq(run.player_train, "", "not riding at start (seed %d)" % seed_value)


func test_fastest_route_matches_hand_computation() -> void:
	# Ride DURATION (arrival - actual departure) is independent of origin
	# dwell. Hand-computed from DESIGN.md physics, dwell 2 at intermediates:
	# L1 intercity Warszawa->Krakow: 32.160 + 2 + 26.160 + 2 + 44.160 = 106.481
	# L2 regional Lodz->Krakow: 66.061 + 2 + 61.061 = 129.121
	# L4 local Katowice->Krakow: 60.676
	# L3 express Poznan->Krakow direct: 65.246+2+38.996+2+35.246+2+31.496 = 176.983
	# L3 express Wroclaw->Krakow direct: 38.996+2+35.246+2+31.496 = 109.737
	#   (direct beats the Katowice transfer, so the router must pick it)
	# Each city boards its own tuned FORWARD first departure (slot + dwell);
	# the network-wide earliest departure can be a reverse train going away.
	var cases := [
		{"city": "warszawa", "dep": 406.0, "duration": 106.481},
		{"city": "lodz", "dep": 383.0, "duration": 129.121},
		{"city": "katowice", "dep": 452.0, "duration": 60.676},
		{"city": "poznan", "dep": 363.0, "duration": 176.983},
		{"city": "wroclaw", "dep": 310.245726, "duration": 109.737},
	]
	var net := ConfigData.load_file("network")
	var trains_cfg := ConfigData.load_file("trains")
	var events_cfg := ConfigData.load_file("events")
	var world := World.create(net, trains_cfg, events_cfg, [])
	for case in cases:
		var arrival := RoutePlanner.fastest_arrival(world, net, case.city, case.dep)
		near(arrival - case.dep, case.duration, 0.02, "fastest ride from " + case.city)


func test_start_time_consistency() -> void:
	var time_cfg := ConfigData.load_file("time")
	var net := ConfigData.load_file("network")
	for seed_value in SEEDS:
		var run := _make_run(seed_value)
		# start_time = 09:00 - (ride duration + buffer); recompute duration from base world
		var dep := INF
		for train_id in run.world.base_timetables():
			for stop in run.world.base_timetables()[train_id].stops:
				if stop.station_id == run.start_station and stop.departure >= run.start_time and stop.departure < dep:
					dep = stop.departure
		var arrival := RoutePlanner.fastest_arrival(run.world, net, run.start_station, dep)
		var duration := arrival - dep
		near(run.start_time, time_cfg.perfect_arrival_minutes - duration - time_cfg.deadline_buffer_minutes, 1e-4, "start time formula (seed %d, %s)" % [seed_value, run.start_station])
		ok(dep - run.start_time < 60.0, "first usable train within an hour of start (seed %d)" % seed_value)


func test_determinism_same_seed() -> void:
	var a := _make_run(2026)
	var b := _make_run(2026)
	eq(a.start_station, b.start_station, "same start city")
	near(a.start_time, b.start_time, 1e-9, "same start time")
	eq(a.events.size(), b.events.size(), "same event count")
	for i in a.events.size():
		eq(a.events[i], b.events[i], "event %d identical" % i)
	eq(a.world.train_ids(), b.world.train_ids(), "same trains")
	var t := a.start_time + 90.0
	for train_id in a.world.train_ids():
		eq(a.world.train_state(train_id, t), b.world.train_state(train_id, t), "state identical for " + train_id)


func test_different_seeds_differ() -> void:
	var a := _make_run(1)
	var b := _make_run(2)
	var differs := a.start_station != b.start_station or a.events != b.events
	ok(differs, "different seeds produce different runs")


func test_events_present_and_valid() -> void:
	var events_cfg := ConfigData.load_file("events")
	for seed_value in SEEDS:
		var run := _make_run(seed_value)
		ok(run.events.size() >= events_cfg.min_events, "15+ events (seed %d)" % seed_value)
		ok(run.events.size() <= events_cfg.max_events, "event cap (seed %d)" % seed_value)
		var seen := {}
		for event in run.events:
			ok(not seen.has(event.train_id), "no stacked events (seed %d)" % seed_value)
			seen[event.train_id] = true
			ok(run.world.train_ids().has(event.train_id), "event targets a real train (seed %d)" % seed_value)


func test_board_ride_disembark_cycle() -> void:
	# Board a dwelling train, ride to its next stop, disembark there.
	for seed_value in SEEDS:
		var run := _make_run(seed_value)
		for row in run.world.departures(run.start_station, run.clock, 10):
			if row.cancelled:
				continue
			var info := run.world.train_info(row.train_id)
			if (info.stops as Array).size() < 3:
				continue  # need an intermediate stop to disembark at
			var board_at: float = row.departure - 1.0
			if board_at < run.clock:
				continue
			var state := run.world.train_state(row.train_id, board_at)
			if state.phase != "dwelling" or state.station_id != run.start_station:
				continue
			run.advance((board_at - run.clock) / _station_rate, "station")
			run.board(row.train_id)
			eq(run.player_train, row.train_id, "boarded")
			eq(run.player_station, "", "no longer in station")
			# advance to 1 min into the dwell at the next stop
			var next_stop: Dictionary = info.stops[1]
			var arrival := run.world.effective_arrival(row.train_id, next_stop.station_id)
			ok(arrival != INF, "effective arrival known for next stop")
			run.advance((arrival + 1.0 - run.clock) / _map_rate, "map")
			ok(not run.finished, "not at destination yet")
			var st := run.world.train_state(run.player_train, run.clock)
			eq(st.phase, "dwelling", "train dwelling at next stop")
			run.disembark()
			eq(run.player_station, next_stop.station_id, "disembarked at next stop")
			eq(run.player_train, "", "no longer riding")
			return
	ok(false, "no seed produced a boardable train — check departures logic")


func test_rewind_restores_train_and_station() -> void:
	for seed_value in SEEDS:
		var run := _make_run(seed_value)
		for row in run.world.departures(run.start_station, run.clock, 10):
			if row.cancelled:
				continue
			var board_at: float = row.departure - 1.0
			if board_at < run.clock:
				continue
			if run.world.train_state(row.train_id, board_at).phase != "dwelling":
				continue
			run.advance((board_at - run.clock) / _station_rate, "station")
			var board_time := run.clock
			run.board(row.train_id)
			run.advance(30.0, "map")  # 18 in-game minutes forward
			if run.finished:
				continue
			var meter_before := run.rewind_meter
			var clock_before := run.clock
			# 5 real s requests 60 min, but the run-start floor may clamp it.
			var expected_move: float = minf(60.0, clock_before - run.start_time)
			var moved := run.rewind(5.0)
			near(moved, expected_move, 1e-6, "rewind clamped by floor")
			near(run.clock, clock_before - expected_move, 1e-6, "clock moved back")
			near(run.rewind_meter, meter_before - expected_move, 1e-6, "meter drained 1:1")
			if run.clock >= board_time:
				eq(run.player_train, row.train_id, "still on train after rewind")
			else:
				eq(run.player_station, run.start_station, "back at start station after rewind")
				eq(run.player_train, "", "not riding")
			return
	ok(false, "no seed produced a boardable train for rewind test")


func test_rewind_floor_and_empty_meter() -> void:
	var run := _make_run(42)
	run.advance(10.0, "map")  # 6 minutes past start
	var moved := run.rewind(100.0)  # would go 1200 min back
	near(moved, 6.0, 1e-6, "clamped at run start")
	near(run.clock, run.start_time, 1e-9, "clock at floor")
	var meter_after_floor := run.rewind_meter
	var again := run.rewind(10.0)
	near(again, 0.0, 1e-9, "no rewind past floor")
	near(run.rewind_meter, meter_after_floor, 1e-9, "no drain while blocked")
	# drain the rest
	run.advance(1000.0, "map")
	run.rewind(10000.0)
	near(run.rewind_meter, 0.0, 1e-6, "meter empty")
	var empty_move := run.rewind(10.0)
	near(empty_move, 0.0, 1e-9, "empty meter no-op")


func test_finish_clamps_to_krakow_arrival() -> void:
	# Ride a direct train to Krakow and overshoot; arrival must clamp.
	for seed_value in SEEDS:
		var run := _make_run(seed_value)
		var net := ConfigData.load_file("network")
		var dest: String = net.destination_station
		# find a non-cancelled train from start station that stops at destination
		var chosen := ""
		for row in run.world.departures(run.start_station, run.clock, 30):
			if row.cancelled:
				continue
			var info := run.world.train_info(row.train_id)
			var stops_here := false
			for stop in info.stops:
				if stop.station_id == dest:
					stops_here = true
			if stops_here:
				chosen = row.train_id
				break
		if chosen == "":
			continue
		var arrival := run.world.effective_arrival(chosen, dest)
		if arrival == INF:
			continue
		var dep_state := run.world.train_state(chosen, run.clock)
		# wait until dwelling at start station
		var rows := run.world.departures(run.start_station, run.clock, 30)
		var departure := INF
		for row in rows:
			if row.train_id == chosen:
				departure = row.departure
		if departure == INF or departure - 1.0 < run.clock:
			continue
		run.advance((departure - 1.0 - run.clock) / _station_rate, "station")
		if run.world.train_state(chosen, run.clock).phase != "dwelling":
			continue
		run.board(chosen)
		run.advance((arrival + 30.0 - run.clock) / _map_rate, "map")  # overshoot 30 min
		ok(run.finished, "run finished on Krakow arrival")
		near(run.arrival_time, arrival, 1e-6, "arrival clamped to schedule instant")
		near(run.clock, arrival, 1e-6, "clock clamped too")
		near(run.minutes_late(), arrival - run.deadline, 1e-6, "minutes late computed")
		return
	ok(false, "no seed produced a direct Krakow train")


func test_time_remaining_clamps() -> void:
	var run := _make_run(7)
	ok(run.time_remaining() > 0.0, "remaining positive at start")
	run.advance(100000.0, "map")  # far past deadline
	near(run.time_remaining(), 0.0, 1e-9, "remaining clamps at zero")


func test_world_purity_under_requery() -> void:
	var run := _make_run(42)
	var ids := run.world.train_ids()
	var t1 := run.start_time + 30.0
	var t2 := run.start_time + 200.0
	var snap := {}
	for train_id in ids:
		snap[train_id] = run.world.train_state(train_id, t1)
	for train_id in ids:
		run.world.train_state(train_id, t2)
	for train_id in ids:
		eq(run.world.train_state(train_id, t1), snap[train_id], "state(t1) unchanged after later queries: " + train_id)


func test_multi_leg_journey_with_transfer() -> void:
	# Force a Wroclaw start (L3 -> Katowice, transfer to L4 -> Krakow) by
	# scanning seeds. Exercises board/ride/disembark/re-board across lines.
	var net := ConfigData.load_file("network")
	var dest: String = net.destination_station
	for seed_value in range(1, 60):
		var run := _make_run(seed_value)
		if run.start_station != "wroclaw":
			continue
		# Leg 1: first non-cancelled L3 departure towards Katowice/Krakow.
		var leg1 := {}
		for row in run.world.departures(run.start_station, run.clock, 20):
			if row.cancelled or row.line_id != "L3":
				continue
			var info := run.world.train_info(row.train_id)
			if info.direction != "F":
				continue
			leg1 = row
			break
		if leg1.is_empty():
			continue
		var wait: float = leg1.departure - run.clock - 1.0
		if wait < 0.0:
			continue
		run.advance(wait / _station_rate, "station")
		if run.world.train_state(leg1.train_id, run.clock).phase != "dwelling":
			continue
		run.board(leg1.train_id)
		var kat_arrival := run.world.effective_arrival(leg1.train_id, "katowice")
		ok(kat_arrival != INF, "L3 reaches Katowice")
		run.advance((kat_arrival + 1.0 - run.clock) / _map_rate, "map")
		ok(not run.finished, "Katowice is not the destination")
		run.disembark()
		eq(run.player_station, "katowice", "transferred at Katowice")
		# Leg 2: any L4 train whose dwell we can reach (skip cancelled or
		# already-departing ones; events may delay arrivals past a dwell).
		for row in run.world.departures("katowice", run.clock, 20):
			if row.cancelled or row.line_id != "L4":
				continue
			var board_at: float = row.departure - 1.0
			if board_at < run.clock:
				continue
			# check dwell without moving the clock (failed candidates must not
			# advance time for later ones)
			if run.world.train_state(row.train_id, board_at).phase != "dwelling":
				continue
			run.advance((board_at - run.clock) / _station_rate, "station")
			run.board(row.train_id)
			var krk_arrival := run.world.effective_arrival(row.train_id, dest)
			run.advance((krk_arrival + 5.0 - run.clock) / _map_rate, "map")
			ok(run.finished, "journey finished at Krakow")
			near(run.arrival_time, krk_arrival, 1e-6, "arrival clamped on final leg")
			eq(run.history.state_at(run.clock).kind, "train", "history ends on the final train")
			return
		# no boardable L4 this seed — try another Wroclaw seed
	ok(false, "no Wroclaw seed produced a workable two-leg journey")
