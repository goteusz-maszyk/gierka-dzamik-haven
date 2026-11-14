extends TestHarness
## Run on the real config: deadline fixed point, clock rates, rewind
## drain/floor/meter, player restoration, board/disembark legality, finish
## clamping, determinism. Expectations come from config or the schedules.
##
## Caller-bug preconditions are asserts. In Godot 4.7 headless a failed assert
## logs a SCRIPT ERROR and returns from the guarded function but does NOT abort
## the caller, so these tests invoke the illegal call and verify state is
## unchanged (the SCRIPT ERROR log is expected noise).
##
## Boarding/disembark instants: effective_arrival(train, station) + dwell/2.
## Events only ever push arrivals later and extend dwells, so this midpoint
## is always inside the effective dwell window [arrival, departure) — legal
## to board/disembark regardless of the event draw. The terminus dwells too
## (departure = arrival + dwell), so disembarking at Kraków is legal.

const EPS := 1e-6

var _network: Dictionary
var _time_config: Dictionary
var _trains_config: Dictionary


func _setup() -> void:
	if _network.is_empty():
		_network = ConfigData.load_file("network")
		_time_config = ConfigData.load_file("time")
		_trains_config = ConfigData.load_file("trains")


func _dwell_time(run: Run, train_id: String, station: String) -> float:
	var arrival := run.world.effective_arrival(train_id, station)
	assert(is_finite(arrival), "train never stops (or is cancelled) at " + station)
	return arrival + _trains_config["dwell_minutes"] / 2.0


## Earliest base departure at a station at or after t, scanning all trains.
func _earliest_departure(run: Run, station: String, t: float) -> float:
	var earliest := INF
	var timetables := run.world.base_timetables()
	for train_id in timetables:
		for stop in timetables[train_id]["stops"]:
			if stop["station_id"] == station:
				var dep: float = stop["departure"]
				if dep >= t:
					earliest = minf(earliest, dep)
	return earliest


## A train dwelling at `station`, chosen by earliest effective arrival >= after.
## Returns {train_id, time, stop_index}; time is mid-dwell (safe to board).
## With need_next_stop, only trains that still have a stop after this one
## (and that next stop is not the destination when avoid_destination is set).
func _boarding(run: Run, station: String, after: float,
		need_next_stop: bool = false, avoid_destination: bool = false) -> Dictionary:
	var best: Dictionary = {}
	for train_id in run.world.train_ids():
		var arrival := run.world.effective_arrival(train_id, station)
		if not is_finite(arrival) or arrival < after:
			continue
		if not best.is_empty() and arrival >= best["arrival"]:
			continue
		var stops: Array = run.world.base_timetables()[train_id]["stops"]
		var stop_index := -1
		for i in stops.size():
			if stops[i]["station_id"] == station:
				stop_index = i
				break
		if need_next_stop and stop_index + 1 >= stops.size():
			continue
		if avoid_destination and stop_index + 1 < stops.size() \
				and stops[stop_index + 1]["station_id"] == _network["destination_station"]:
			continue
		best = {"train_id": train_id, "arrival": arrival, "stop_index": stop_index}
	assert(not best.is_empty(), "no boardable train at " + station)
	best["time"] = best["arrival"] + _trains_config["dwell_minutes"] / 2.0
	return best


## Earliest-departing train (effective origin arrival >= after) whose path
## ends at the destination and has at least one stop before it.
func _destination_train(run: Run, after: float) -> Dictionary:
	var best: Dictionary = {}
	for train_id in run.world.train_ids():
		var stops: Array = run.world.base_timetables()[train_id]["stops"]
		if stops.size() < 2 or stops[stops.size() - 1]["station_id"] != _network["destination_station"]:
			continue
		var origin: String = stops[0]["station_id"]
		var arrival := run.world.effective_arrival(train_id, origin)
		if not is_finite(arrival) or arrival < after:
			continue
		if best.is_empty() or arrival < best["arrival"]:
			best = {"train_id": train_id, "origin": origin, "arrival": arrival}
	assert(not best.is_empty(), "no destination-bound train")
	best["time"] = best["arrival"] + _trains_config["dwell_minutes"] / 2.0
	return best


func test_advance_clock_rates() -> void:
	_setup()
	var run := Run.create(42)
	var start := run.start_time
	run.advance(10.0, "map")
	near(run.clock, start + 10.0 * _time_config["map_view_minutes_per_real_second"], EPS, "map view rate")
	run.advance(10.0, "station")
	near(run.clock, start + 10.0 * _time_config["map_view_minutes_per_real_second"]
		+ 10.0 * _time_config["station_view_minutes_per_real_second"], EPS, "station view rate")
	eq(run.finished, false, "advancing in a station does not finish the run")


func test_board_disembark_intermediate_and_rewind_restores_station() -> void:
	_setup()
	var run := Run.create(42)
	var opportunity := _boarding(run, run.start_station, run.start_time, true, true)
	var train_id: String = opportunity["train_id"]
	run.clock = opportunity["time"]
	run.board(train_id)
	eq(run.player_train, train_id, "board sets the train")
	eq(run.player_station, "", "board clears the station")
	var recorded := run.history.state_at(run.clock)
	eq(recorded["kind"], "train", "history records the boarding")
	eq(recorded["train_id"], train_id, "history records the boarded train")
	# Ride to the next stop and disembark mid-dwell there.
	var stops: Array = run.world.base_timetables()[train_id]["stops"]
	var next_stop: Dictionary = stops[opportunity["stop_index"] + 1]
	ok(next_stop["station_id"] != _network["destination_station"], "next stop is not the destination")
	run.clock = _dwell_time(run, train_id, next_stop["station_id"])
	var state := run.world.train_state(train_id, run.clock)
	eq(state["phase"], "dwelling", "train dwelling mid-dwell at the next stop")
	eq(state["station_id"], next_stop["station_id"], "dwelling at the expected station")
	run.disembark()
	eq(run.player_station, next_stop["station_id"], "disembark places the player at the stop")
	eq(run.player_train, "", "disembark clears the train")
	eq(run.finished, false, "intermediate disembark does not finish")
	recorded = run.history.state_at(run.clock)
	eq(recorded["kind"], "station", "history records the disembark")
	eq(recorded["station_id"], next_stop["station_id"], "history records the station")
	# Rewind one minute: still riding (the next stop is > dwell + section time
	# ahead of the boarding), so the player must be back on the train.
	var actual := run.rewind(1.0 / _time_config["rewind_minutes_per_real_second"])
	near(actual, 1.0, EPS, "rewind moved one minute")
	eq(run.player_train, train_id, "rewind restores the train")
	eq(run.player_station, "", "rewind clears the station while riding")


func test_board_precondition_not_dwelling_here() -> void:
	_setup()
	var run := Run.create(42)
	# A train moving between two stations neither of which is the player's
	# station fails board()'s dwelling-at-player-station precondition.
	var candidate := ""
	for train_id in run.world.train_ids():
		var state := run.world.train_state(train_id, run.clock)
		if state["phase"] == "moving" and state["from_station"] != run.player_station \
				and state["to_station"] != run.player_station:
			candidate = train_id
			break
	ok(candidate != "", "a moving train elsewhere exists at run start")
	# Actually attempt the illegal board; the assert must reject it.
	run.board(candidate)
	eq(run.player_train, "", "illegal board rejected: player not on a train")
	eq(run.player_station, run.start_station, "illegal board rejected: station unchanged")


func test_create_deadline_fixed_point() -> void:
	_setup()
	for seed_value in [11, 42, 777]:
		var run := Run.create(seed_value)
		eq(run.deadline, _time_config["perfect_arrival_minutes"], "deadline == perfect_arrival")
		eq(run.clock, run.start_time, "clock starts at start_time")
		# The fixed point must have converged: one more iteration from the
		# chosen start_time reproduces the same ride duration.
		var departure := _earliest_departure(run, run.start_station, run.start_time)
		ok(is_finite(departure), "a usable departure exists at start_time")
		var arrival := RoutePlanner.fastest_arrival(run.world, _network, run.start_station, departure)
		ok(is_finite(arrival), "destination reachable from start city")
		var duration := arrival - departure
		near(run.start_time, _time_config["perfect_arrival_minutes"]
			- (duration + _time_config["deadline_buffer_minutes"]), EPS,
			"start_time == perfect - (ride duration + buffer)")
		ok(run.start_time <= departure, "start_time no later than the first usable departure")
		# Perfect play boards that departure and rides the fastest route:
		# arrival = deadline - buffer + wait for the first train.
		near(arrival, run.deadline - _time_config["deadline_buffer_minutes"]
			+ (departure - run.start_time), EPS, "perfect arrival == deadline - buffer + wait")
		ok(arrival <= run.deadline, "perfect play arrives no later than the deadline")


func test_create_initial_state() -> void:
	_setup()
	var run := Run.create(42)
	near(run.rewind_meter, _time_config["rewind_meter_minutes"], EPS, "meter starts at config value")
	eq(run.player_station, run.start_station, "player starts at the start station")
	eq(run.player_train, "", "player starts off any train")
	eq(run.finished, false, "run starts unfinished")
	var start_cities: Array[String] = []
	for station in _network["stations"]:
		if station["start_city"]:
			start_cities.append(station["id"])
	ok(start_cities.has(run.start_station), "start station is a configured start city")
	var state := run.history.state_at(run.clock)
	eq(state["kind"], "station", "history seeded with a station record")
	eq(state["station_id"], run.start_station, "history seeded at the start station")


func test_disembark_at_destination_finishes() -> void:
	_setup()
	var run := Run.create(42)
	var chosen := _destination_train(run, run.start_time)
	run.clock = chosen["time"]
	run.player_station = chosen["origin"]
	run.board(chosen["train_id"])
	var arrival := run.world.effective_arrival(chosen["train_id"], _network["destination_station"])
	ok(is_finite(arrival), "effective destination arrival is finite")
	run.clock = arrival + _trains_config["dwell_minutes"] / 2.0
	var state := run.world.train_state(chosen["train_id"], run.clock)
	eq(state["phase"], "dwelling", "train dwelling at the destination (terminus dwells)")
	eq(state["station_id"], _network["destination_station"], "dwelling at the destination station")
	run.disembark()
	eq(run.finished, true, "disembark at the destination finishes the run")
	near(run.arrival_time, arrival, EPS, "arrival_time is the exact schedule arrival, not the disembark clock")


func test_disembark_preconditions() -> void:
	_setup()
	var run := Run.create(42)
	# In a station: disembark()'s riding precondition fails.
	eq(run.player_train, "", "setup: player not riding")
	# Riding but moving: board a train that still has a stop ahead, then find
	# its first moving instant.
	var opportunity := _boarding(run, run.start_station, run.start_time, true)
	run.clock = opportunity["time"]
	run.board(opportunity["train_id"])
	var dwell: float = _trains_config["dwell_minutes"]
	var t := run.clock + dwell
	var state := run.world.train_state(run.player_train, t)
	var steps := 0
	while state["phase"] != "moving" and steps < 1000:
		t += dwell
		state = run.world.train_state(run.player_train, t)
		steps += 1
	eq(state["phase"], "moving", "train is moving between stops")
	# Actually attempt the illegal disembark while moving; assert must reject it.
	run.clock = t
	run.disembark()
	eq(run.player_train, opportunity["train_id"], "illegal disembark rejected: still riding")
	eq(run.player_station, "", "illegal disembark rejected: not placed in a station")


func test_finish_clamps_to_arrival_instant() -> void:
	_setup()
	var run := Run.create(42)
	var chosen := _destination_train(run, run.start_time)
	run.clock = chosen["time"]
	run.player_station = chosen["origin"]
	run.board(chosen["train_id"])
	var arrival := run.world.effective_arrival(chosen["train_id"], _network["destination_station"])
	ok(is_finite(arrival), "effective destination arrival is finite")
	var seconds: float = (arrival - run.clock + 100.0) / _time_config["map_view_minutes_per_real_second"]
	run.advance(seconds, "map")
	eq(run.finished, true, "riding past the destination finishes the run")
	near(run.arrival_time, arrival, EPS, "arrival_time is the exact effective arrival")
	near(run.clock, arrival, EPS, "clock clamped to the arrival instant, not the overshoot")
	near(run.minutes_late(), arrival - run.deadline, EPS, "minutes_late == arrival - deadline")
	run.advance(10.0, "map")
	near(run.clock, arrival, EPS, "advance after finish is a no-op")
	eq(run.finished, true, "still finished after further advance")


func test_rewind_drain_one_to_one() -> void:
	_setup()
	var run := Run.create(42)
	run.advance(100.0, "map")
	var meter_before := run.rewind_meter
	var clock_before := run.clock
	var requested: float = _time_config["rewind_minutes_per_real_second"]
	var actual := run.rewind(1.0)
	near(actual, requested, EPS, "rewind returns the requested minutes")
	near(run.clock, clock_before - requested, EPS, "clock moved back 1:1")
	near(run.rewind_meter, meter_before - requested, EPS, "meter drained 1:1")


func test_rewind_empty_meter_noop() -> void:
	_setup()
	var run := Run.create(42)
	run.advance(1000.0, "map")
	run.rewind_meter = 0.0
	var clock_before := run.clock
	var actual := run.rewind(1.0)
	near(actual, 0.0, EPS, "empty meter returns 0")
	near(run.clock, clock_before, EPS, "empty meter: clock unchanged")
	near(run.rewind_meter, 0.0, EPS, "empty meter stays empty")


func test_rewind_floor_no_drain() -> void:
	_setup()
	var run := Run.create(42)
	run.advance(10.0, "map")
	var elapsed := run.clock - run.start_time
	ok(elapsed < _time_config["rewind_minutes_per_real_second"], "setup: less than one rewind second elapsed")
	var meter_before := run.rewind_meter
	var actual := run.rewind(1.0)
	near(actual, elapsed, EPS, "rewind clamps to the time since start")
	near(run.clock, run.start_time, EPS, "clock floored at start_time")
	near(run.rewind_meter, meter_before - elapsed, EPS, "only actual movement drains the meter")
	var blocked := run.rewind(1.0)
	near(blocked, 0.0, EPS, "blocked at the floor returns 0")
	near(run.clock, run.start_time, EPS, "clock stays at the floor")
	near(run.rewind_meter, meter_before - elapsed, EPS, "no drain while blocked")


func test_rewind_restores_train() -> void:
	_setup()
	var run := Run.create(42)
	var opportunity := _boarding(run, run.start_station, run.start_time)
	var train_id: String = opportunity["train_id"]
	run.clock = opportunity["time"]
	run.board(train_id)
	run.clock += 1.0
	eq(run.player_train, train_id, "riding after board")
	# 0.5 real s requests 6 min; the clock is only 1 min past boarding, so the
	# rewind lands at or before the boarding instant -> back in the station.
	var actual := run.rewind(0.5)
	ok(actual > 1.0, "rewind moved past the boarding instant")
	eq(run.player_station, run.start_station, "rewind before boarding restores the station")
	eq(run.player_train, "", "rewind before boarding clears the train")


func test_same_seed_determinism() -> void:
	_setup()
	var a := Run.create(2026)
	var b := Run.create(2026)
	eq(a.start_station, b.start_station, "same seed: start station")
	eq(a.start_time, b.start_time, "same seed: start time")
	eq(a.deadline, b.deadline, "same seed: deadline")
	eq(a.clock, b.clock, "same seed: clock")
	eq(a.rewind_meter, b.rewind_meter, "same seed: meter")
	eq(a.events, b.events, "same seed: identical events")
	var ids_a := a.world.train_ids()
	eq(ids_a, b.world.train_ids(), "same seed: identical train ids")
	for train_id in ids_a:
		eq(a.world.train_state(train_id, a.clock), b.world.train_state(train_id, b.clock),
			"same seed: identical world state for " + train_id)


func test_time_remaining_clamps() -> void:
	_setup()
	var run := Run.create(42)
	near(run.time_remaining(), run.deadline - run.start_time, EPS, "time remaining at start")
	run.clock = run.deadline + 100.0
	near(run.time_remaining(), 0.0, EPS, "time remaining clamps at 0 after the deadline")


func test_boarding_reverse_train_does_not_finish() -> void:
	# Regression (review B1): a reverse train whose ORIGIN is Kraków must not
	# finish the run when boarded — its Kraków stop is in the past. Boarding it
	# is legal; the run continues and the clock never jumps backwards.
	_setup()
	var dest: String = _network["destination_station"]
	var found := false
	for seed_value in range(1, 40):
		var run := Run.create(seed_value)
		# Find a reverse train dwelling at the player's station whose origin is
		# the destination (so effective_arrival would return a past slot).
		for train_id in run.world.train_ids():
			var info := run.world.train_info(train_id)
			if info.direction != "R" or info.stops[0].station_id != dest:
				continue
			var origin_stop: Dictionary = info.stops[0]
			# Board at the origin dwell of this reverse train.
			var arrival := run.world.effective_arrival(train_id, dest)
			if not is_finite(arrival):
				continue
			var board_time: float = arrival + _trains_config["dwell_minutes"] / 2.0
			run.clock = board_time
			run.player_station = dest
			run.board(train_id)
			var clock_before := run.clock
			run.advance(1.0, "map")
			eq(run.finished, false, "seed %d: boarding reverse origin train must not finish" % seed_value)
			ok(run.clock >= clock_before, "seed %d: clock never jumps backwards" % seed_value)
			found = true
			break
		if found:
			break
	ok(found, "found a reverse origin-at-destination train to board")


func test_rewind_after_finish_is_noop() -> void:
	# Regression (review M1): once finished, rewind must not move the clock or
	# drain the meter (advance is already a no-op; rewind must match).
	_setup()
	var run := Run.create(42)
	var chosen := _destination_train(run, run.start_time)
	ok(not chosen.is_empty(), "a destination-bound train exists")
	run.clock = chosen["time"]
	run.player_station = chosen["origin"]
	run.board(chosen["train_id"])
	var arrival := run.world.effective_arrival(chosen["train_id"], _network["destination_station"])
	run.advance((arrival - run.clock + 50.0) / _time_config["map_view_minutes_per_real_second"], "map")
	eq(run.finished, true, "run finished")
	var clock_before := run.clock
	var meter_before := run.rewind_meter
	var actual := run.rewind(5.0)
	near(actual, 0.0, EPS, "rewind after finish returns 0")
	near(run.clock, clock_before, EPS, "clock unchanged after finish")
	near(run.rewind_meter, meter_before, EPS, "meter unchanged after finish")
	eq(run.finished, true, "still finished")
