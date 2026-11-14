class_name Run
extends RefCounted
## One run: seeded generation, the shared clock, the rewind meter and player
## state. The world never reacts to the player; rewind only moves the clock
## and restores the player from history.

const MAX_DEADLINE_ITERATIONS := 5
const DEADLINE_EPSILON := 1e-6

var seed_value: int
var start_station: String
var start_time: float
var deadline: float
var clock: float
var world: World
var events: Array
var history: PlayerHistory
var player_station: String
var player_train: String
var rewind_meter: float
var finished: bool
var arrival_time: float

var _destination: String
var _map_rate: float
var _station_rate: float
var _rewind_rate: float
var _board_stop_index: int = -1


static func create(seed_value: int) -> Run:
	var network := ConfigData.load_file("network")
	var trains_config := ConfigData.load_file("trains")
	var events_config := ConfigData.load_file("events")
	var time_config := ConfigData.load_file("time")
	var run := Run.new()
	run.seed_value = seed_value
	run._destination = network["destination_station"]
	run._map_rate = time_config["map_view_minutes_per_real_second"]
	run._station_rate = time_config["station_view_minutes_per_real_second"]
	run._rewind_rate = time_config["rewind_minutes_per_real_second"]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var start_cities: Array[String] = []
	for station in network["stations"]:
		if station["start_city"]:
			start_cities.append(station["id"])
	assert(not start_cities.is_empty(), "Run.create: no start_city stations in network")
	run.start_station = start_cities[rng.randi_range(0, start_cities.size() - 1)]
	run.events = Events.generate(events_config, network, rng)
	run.world = World.create(network, trains_config, events_config, run.events)
	# Deadline fixed point: start_time = perfect - (duration + buffer), but
	# duration is the ride time from the first usable departure, which itself
	# depends on start_time. The buffer absorbs the wait for that first train;
	# counting the wait into duration would make the iteration diverge.
	var perfect: float = time_config["perfect_arrival_minutes"]
	var buffer: float = time_config["deadline_buffer_minutes"]
	var duration := 0.0
	for _i in MAX_DEADLINE_ITERATIONS:
		run.start_time = perfect - (duration + buffer)
		var departure := run._earliest_departure(run.start_time)
		var arrival := RoutePlanner.fastest_arrival(run.world, network, run.start_station, departure)
		var new_duration := arrival - departure
		var converged := absf(new_duration - duration) < DEADLINE_EPSILON
		duration = new_duration
		if converged:
			break
	# Recompute with the converged duration so start_time is consistent with it.
	run.start_time = perfect - (duration + buffer)
	run.deadline = perfect
	run.clock = run.start_time
	run.history = PlayerHistory.new()
	run.history.record_station(run.start_time, run.start_station)
	run.player_station = run.start_station
	run.player_train = ""
	run.rewind_meter = time_config["rewind_meter_minutes"]
	run.finished = false
	return run


func advance(real_seconds: float, view: String) -> void:
	assert(real_seconds >= 0.0, "Run.advance: negative real_seconds")
	if finished:
		return
	clock += real_seconds * _view_rate(view)
	if player_train == "":
		return
	# Finish only on a Kraków arrival AFTER the boarding stop. A train whose
	# origin is Kraków (reverse services) must not count its past origin slot.
	var arrival := world.effective_arrival_after(player_train, _destination, _board_stop_index)
	if arrival <= clock:
		finished = true
		arrival_time = arrival
		clock = arrival


## Scrubs the clock backwards; drains the meter 1:1 for actual movement only.
func rewind(real_seconds: float) -> float:
	assert(real_seconds >= 0.0, "Run.rewind: negative real_seconds")
	if finished:
		return 0.0
	var requested := real_seconds * _rewind_rate
	var actual := minf(minf(requested, rewind_meter), maxf(0.0, clock - start_time))
	clock -= actual
	rewind_meter -= actual
	var state := history.state_at(clock)
	if state["kind"] == "train":
		player_train = state["train_id"]
		player_station = ""
		_board_stop_index = state["stop_index"]
	else:
		player_station = state["station_id"]
		player_train = ""
		_board_stop_index = -1
	history.truncate_after(clock)
	return actual


func board(train_id: String) -> void:
	assert(player_station != "", "Run.board: player is not in a station")
	var state := world.train_state(train_id, clock)
	assert(state["phase"] == "dwelling" and state["station_id"] == player_station,
		"Run.board: train is not dwelling at the player's station")
	_board_stop_index = world.stop_index(train_id, player_station)
	player_train = train_id
	player_station = ""
	history.record_train(clock, train_id, _board_stop_index)


func disembark() -> void:
	assert(player_train != "", "Run.disembark: player is not on a train")
	var state := world.train_state(player_train, clock)
	assert(state["phase"] == "dwelling", "Run.disembark: train is not dwelling")
	var station_id: String = state["station_id"]
	if station_id == _destination:
		finished = true
		arrival_time = world.effective_arrival_after(player_train, _destination, _board_stop_index)
		return
	player_station = station_id
	player_train = ""
	history.record_station(clock, station_id)


func time_remaining() -> float:
	return maxf(0.0, deadline - clock)


func minutes_late() -> float:
	assert(finished, "Run.minutes_late: run is not finished")
	return arrival_time - deadline


## Earliest base departure from the start station at or after t.
func _earliest_departure(t: float) -> float:
	var earliest := INF
	var timetables := world.base_timetables()
	for train_id in timetables:
		for stop in timetables[train_id]["stops"]:
			if stop["station_id"] != start_station:
				continue
			var departure: float = stop["departure"]
			if departure >= t:
				earliest = minf(earliest, departure)
	return earliest


func _view_rate(view: String) -> float:
	if view == "map":
		return _map_rate
	assert(view == "station", "Run.advance: unknown view " + view)
	return _station_rate
