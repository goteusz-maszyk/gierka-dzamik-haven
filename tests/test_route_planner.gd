extends TestHarness
## Slice B: RoutePlanner.fastest_arrival on synthetic mini-networks.
## World/Timetable come from slice A; all expectations below are hand-computed.
## Section times use the contract's closed form (arithmetic in comments).

const EPS := 1e-6


func test_direct_train() -> void:
	# L: a->b 10 km local (80 km/h, a=0.7, b=0.45), slots 10,40,70,100.
	# Section: v=22.222 m/s, v²=493.827; accel dist v²/(2a)=352.73 m,
	# brake dist v²/(2b)=548.70 m, total 901.43 m < 10000 m -> cruise
	# 9098.57 m / 22.222 = 409.44 s + accel 31.75 s + brake 49.38 s
	# = 490.56 s = 8.176 min.
	# Origin dwell 2: dep = slot + 2, arr b = slot + 2 + section.
	# Start 0: board slot 10 (dep 12) -> arr 20.176. Start 12: same train
	# (dep >= 12). Start 12+eps: dep 12 missed, next dep 42 -> arr 50.176.
	var world := _world(_direct_network())
	var section: float = TrainPhysics.section_time(10.0, 80.0, 0.7, 0.45)
	near(section, 8.176073, 1e-4, "hand-computed section time")
	near(RoutePlanner.fastest_arrival(world, _direct_network(), "a", 0.0),
		10.0 + 2.0 + section, EPS, "direct from 0")
	near(RoutePlanner.fastest_arrival(world, _direct_network(), "a", 12.0),
		10.0 + 2.0 + section, EPS, "board at exact departure")
	near(RoutePlanner.fastest_arrival(world, _direct_network(), "a", 12.0 + EPS),
		40.0 + 2.0 + section, EPS, "missed slot takes next train")
	ok(is_inf(RoutePlanner.fastest_arrival(world, _direct_network(), "a", 102.0 + EPS)),
		"no train left after last departure -> INF")


func test_transfer_beats_waiting() -> void:
	# L1 a->x slots 10,70 (10 km = 8.176 min); L2 x->b slots 25,85 (10 km);
	# L3 a->b slots 0,60 (40 km direct = 30.676 min). Origin dwell 2: every
	# origin dep = slot + 2, so arr b = slot + 2 + section.
	# From 0: direct dep 2 -> b 32.676. Transfer: L1 dep 12 -> x 20.176,
	# L2 dep 27 -> b 35.176 > 32.676, so the direct wins.
	# From 2+eps: direct slot 0 missed, next dep 62 -> b 92.676; transfer
	# still makes L2 dep 27 -> b 35.176. Transfer beats waiting.
	# L3 40 km section: cruise 39098.57 m / 22.222 = 1759.44 s + 81.13 s
	# = 1840.56 s = 30.676 min.
	var network := _transfer_network()
	var world := _world(network)
	var short: float = TrainPhysics.section_time(10.0, 80.0, 0.7, 0.45)
	var long: float = TrainPhysics.section_time(40.0, 80.0, 0.7, 0.45)
	near(long, 30.676073, 1e-4, "hand-computed 40 km section")
	near(RoutePlanner.fastest_arrival(world, network, "a", 0.0), 2.0 + long, EPS,
		"direct beats transfer when boardable at start")
	near(RoutePlanner.fastest_arrival(world, network, "a", 2.0 + EPS), 25.0 + 2.0 + short, EPS,
		"transfer beats waiting after missed direct")


func test_missed_connection_takes_next_train() -> void:
	# L1 a->x slots 10,70: dep a 12 -> x arr 12 + 8.176 = 20.176. L2 x->b
	# first slot 5 (dep 7), then 65 (dep 67): arr 20.176 misses dep 7,
	# next dep 67 -> b at 75.176. (L3 direct removed: transfer is the only route.)
	var network := _transfer_network()
	network["lines"] = [network["lines"][0], network["lines"][1]]
	network["lines"][1]["first_departure_minutes"] = 5.0
	var world := _world(network)
	var short: float = TrainPhysics.section_time(10.0, 80.0, 0.7, 0.45)
	near(RoutePlanner.fastest_arrival(world, network, "a", 0.0), 65.0 + 2.0 + short, EPS,
		"missed connection waits for next train")


func test_unreachable() -> void:
	# Only a<->x service; b is never served.
	var network := _direct_network()
	network["lines"][0]["stops"][1]["station"] = "x"
	network["stations"].append({"id": "x", "name": "X", "map_pos": [2, 0], "start_city": false})
	var world := _world(network)
	eq(RoutePlanner.fastest_arrival(world, network, "a", 0.0), INF, "unreachable -> INF")
	eq(RoutePlanner.fastest_arrival(world, network, "x", 0.0), INF, "no outgoing service -> INF")


func test_same_station() -> void:
	var network := _direct_network()
	var world := _world(network)
	near(RoutePlanner.fastest_arrival(world, network, "b", 123.5), 123.5, EPS,
		"already at destination -> start_time")


func test_board_mid_route() -> void:
	# L a->x->b, slots 0,60. Origin dwell 2: dep a 2 -> x arr 10.176, dwell 2
	# -> x dep 12.176 -> b arr 20.352. From x at 11 (mid-dwell [10.176,12.176)):
	# boardable -> 20.352. From x at 12.176+eps: missed, next slot 60
	# (dep a 62 -> x dep 72.176) -> b arr 80.352.
	var network := _three_stop_network()
	var world := _world(network)
	var section: float = TrainPhysics.section_time(10.0, 80.0, 0.7, 0.45)
	var dwell: float = 2.0
	near(RoutePlanner.fastest_arrival(world, network, "x", 11.0),
		section + dwell + dwell + section, EPS, "board dwelling train mid-route")
	near(RoutePlanner.fastest_arrival(world, network, "x", 2.0 + section + dwell + EPS),
		60.0 + 2.0 + section + dwell + section, EPS, "missed mid-route departure -> next slot")


func test_reverse_direction() -> void:
	# Destination a. Reverse R-0: dep b 2 -> x arr 10.176, dwell 2 -> dep
	# 12.176 -> a arr 20.352. From x at 11: board the dwelling reverse train
	# -> 20.352 (the forward train at x goes to b, away from the destination).
	# From b at 3 (> R-0 origin dep 2): missed, next reverse slot 60 (dep 62)
	# -> a arr 80.352.
	var network := _three_stop_network()
	network["destination_station"] = "a"
	var world := _world(network)
	var section: float = TrainPhysics.section_time(10.0, 80.0, 0.7, 0.45)
	var dwell: float = 2.0
	near(RoutePlanner.fastest_arrival(world, network, "x", 11.0),
		section + dwell + dwell + section, EPS, "reverse train boarding mid-route")
	near(RoutePlanner.fastest_arrival(world, network, "b", 3.0),
		60.0 + 2.0 + section + dwell + section, EPS, "missed reverse slot -> next")


func test_real_network_end_to_end() -> void:
	# Real configs, no events. Every start city must reach Kraków, and the
	# result must be consistent when departing later (later start can never
	# arrive earlier than an earlier start's best).
	var network := ConfigData.load_file("network")
	var trains := ConfigData.load_file("trains")
	var events_config := ConfigData.load_file("events")
	var world := World.create(network, trains, events_config, [])
	for station: Dictionary in network["stations"]:
		if not station["start_city"]:
			continue
		var early: float = RoutePlanner.fastest_arrival(world, network, station["id"], 0.0)
		ok(early < INF, "start city %s reaches destination" % station["id"])
		var late: float = RoutePlanner.fastest_arrival(world, network, station["id"], early)
		ok(late >= early - EPS, "later start never arrives earlier (%s)" % station["id"])
	# Kraków -> Rzeszów only via L6: retarget the destination, then from
	# krakow at 0 the earliest arrival is first L6 slot + origin dwell 2
	# + 160 km regional: 480 + 2 + 81.060606 = 563.060606.
	network["destination_station"] = "rzeszow"
	var regional: Dictionary = trains["categories"]["regional"]
	var expected: float = float(network["lines"][5]["first_departure_minutes"]) + float(trains["dwell_minutes"]) + TrainPhysics.section_time(
		160.0, float(regional["max_speed_kmh"]), float(regional["accel_mps2"]), float(regional["brake_mps2"]))
	near(RoutePlanner.fastest_arrival(world, network, "krakow", 0.0), expected, 1e-4,
		"krakow -> rzeszow via first L6 slot")


func _world(network: Dictionary) -> World:
	return World.create(network, _trains_config(), _events_config(), [])


func _trains_config() -> Dictionary:
	return {
		"dwell_minutes": 2.0,
		"categories": {
			"local": {"max_speed_kmh": 80.0, "accel_mps2": 0.7, "brake_mps2": 0.45,
				"number_prefix": "O", "number_start": 200},
		},
	}


func _events_config() -> Dictionary:
	return {
		"min_events": 0, "max_events": 0, "horizon_minutes": 120.0,
		"types": {
			"drunk_driver": {"weight": 1.0, "stop_duration_min_minutes": 30.0, "stop_duration_max_minutes": 60.0},
			"slow_down": {"weight": 1.0, "speed_factor": 0.5},
			"cancel": {"weight": 1.0, "lead_minutes_min": 1.0, "lead_minutes_max": 5.0},
		},
	}


func _station(id: String) -> Dictionary:
	return {"id": id, "name": id.to_upper(), "map_pos": [0, 0], "start_city": id == "a"}


func _line(id: String, stops: Array, first: float, frequency: float) -> Dictionary:
	return {"id": id, "name": id, "color": "#000000", "category": "local",
		"frequency_minutes": frequency, "first_departure_minutes": first, "stops": stops}


func _direct_network() -> Dictionary:
	return {
		"destination_station": "b",
		"stations": [_station("a"), _station("b")],
		"lines": [_line("L", [{"station": "a", "km": 0.0}, {"station": "b", "km": 10.0}], 10.0, 30.0)],
	}


func _transfer_network() -> Dictionary:
	return {
		"destination_station": "b",
		"stations": [_station("a"), _station("x"), _station("b")],
		"lines": [
			_line("L1", [{"station": "a", "km": 0.0}, {"station": "x", "km": 10.0}], 10.0, 60.0),
			_line("L2", [{"station": "x", "km": 0.0}, {"station": "b", "km": 10.0}], 25.0, 60.0),
			_line("L3", [{"station": "a", "km": 0.0}, {"station": "b", "km": 40.0}], 0.0, 60.0),
		],
	}


func _three_stop_network() -> Dictionary:
	return {
		"destination_station": "b",
		"stations": [_station("a"), _station("x"), _station("b")],
		"lines": [_line("L", [
			{"station": "a", "km": 0.0}, {"station": "x", "km": 10.0}, {"station": "b", "km": 20.0},
		], 0.0, 60.0)],
	}
