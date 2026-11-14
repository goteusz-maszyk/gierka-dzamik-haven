extends TestHarness
## Slice A: World facade delegation + real-config end-to-end runs.

const EPS := 1e-9


func test_facade_matches_timetable() -> void:
	var network := ConfigData.load_file("network")
	var trains := ConfigData.load_file("trains")
	var events_config := ConfigData.load_file("events")
	var events := _hand_events()
	var world := World.create(network, trains, events_config, events)
	var tt := Timetable.generate(network, trains, events_config, events)
	eq(world.train_ids(), tt.train_ids(), "train_ids delegated")
	eq(world.base_timetables(), tt.base_timetables(), "base_timetables delegated")
	for train_id in world.train_ids():
		eq(world.train_info(train_id), tt.train_info(train_id), "train_info " + train_id)
	for train_id in ["L1-F-0", "L1-R-0", "L4-F-2", "L6-R-1"]:
		for t in [300.0, 480.0, 540.0, 700.0]:
			eq(world.train_state(train_id, t), tt.train_state(train_id, t),
				"train_state %s at %f" % [train_id, t])
			eq(world.base_train_state(train_id, t), tt.base_train_state(train_id, t),
				"base_train_state %s at %f" % [train_id, t])
		for station: Dictionary in network["stations"]:
			eq(world.effective_arrival(train_id, station["id"]),
				tt.effective_arrival(train_id, station["id"]),
				"effective_arrival %s at %s" % [train_id, station["id"]])
	for station: Dictionary in network["stations"]:
		var station_id: String = station["id"]
		for t in [400.0, 540.0]:
			eq(world.departures(station_id, t, 8), tt.departures(station_id, t, 8),
				"departures %s at %f" % [station_id, t])
			eq(world.base_departures(station_id, t, 8), tt.base_departures(station_id, t, 8),
				"base_departures %s at %f" % [station_id, t])
			for platform in range(1, 7):
				eq(world.platform_next(station_id, platform, t),
					tt.platform_next(station_id, platform, t),
					"platform_next %s %d at %f" % [station_id, platform, t])


func test_real_config_no_events() -> void:
	var network := ConfigData.load_file("network")
	var trains := ConfigData.load_file("trains")
	var events_config := ConfigData.load_file("events")
	var world := World.create(network, trains, events_config, [])
	eq(world.train_ids().size(), 104, "104 trains from real config")
	var dwell := float(trains["dwell_minutes"])
	var tables := world.base_timetables()
	for train_id in world.train_ids():
		var stops: Array = tables[train_id]["stops"]
		for i in stops.size():
			near(float(stops[i]["departure"]) - float(stops[i]["arrival"]), dwell, EPS,
				"%s stop %d dwell" % [train_id, i])
			if i + 1 < stops.size():
				ok(float(stops[i + 1]["arrival"]) > float(stops[i]["departure"]),
					"%s monotone section %d" % [train_id, i])
		var info: Dictionary = world.train_info(train_id)
		var last_station: String = stops[stops.size() - 1]["station_id"]
		eq(info["destination"], _station_name(network, last_station),
			"%s destination name" % train_id)
	# Without events effective == base everywhere sampled.
	for train_id in ["L1-F-0", "L2-R-3", "L3-F-1", "L4-R-15", "L5-F-7", "L6-R-0"]:
		for t in [350.0, 480.0, 540.0, 900.0]:
			eq(world.train_state(train_id, t), world.base_train_state(train_id, t),
				"no events: %s state at %f" % [train_id, t])
		var terminus: String = tables[train_id]["stops"][tables[train_id]["stops"].size() - 1]["station_id"]
		near(world.effective_arrival(train_id, terminus),
			float(tables[train_id]["stops"][tables[train_id]["stops"].size() - 1]["arrival"]), EPS,
			"no events: %s terminus arrival" % train_id)
	# Origin dwell window: L1-F-0 slots at 404, dwells [404, 406).
	var at_slot := world.train_state("L1-F-0", 404.0)
	eq(at_slot["phase"], "dwelling", "slot instant boardable at origin")
	eq(at_slot["station_id"], "warszawa", "origin station")
	eq(at_slot["platform"], 1, "origin platform")
	eq(world.train_state("L1-F-0", 405.9)["phase"], "dwelling", "still dwelling before departure")
	eq(world.train_state("L1-F-0", 406.0)["phase"], "moving", "moving at departure instant")
	eq(world.train_state("L1-F-0", 403.9)["phase"], "before", "before the slot")
	# Every board row is well-formed and sorted.
	for station: Dictionary in network["stations"]:
		var rows := world.departures(station["id"], 480.0, 12)
		var previous := -INF
		for row: Dictionary in rows:
			ok(float(row["departure"]) >= 480.0, "row departure >= t")
			ok(float(row["departure"]) >= previous, "rows sorted")
			previous = float(row["departure"])
			eq(row["cancelled"], false, "no cancellations without events")
			eq(row["delay"], 0.0, "no delays without events")
			eq(row["destination"], _station_name(network,
				tables[row["train_id"]]["stops"][tables[row["train_id"]]["stops"].size() - 1]["station_id"]),
				"row destination name")


func test_real_config_hand_events() -> void:
	var network := ConfigData.load_file("network")
	var trains := ConfigData.load_file("trains")
	var events_config := ConfigData.load_file("events")
	var world := World.create(network, trains, events_config, _hand_events())
	var tables := world.base_timetables()
	# --- cancel: L1-R-0 cancelled at 402 (right before its 404 slot).
	for t in [300.0, 404.0, 500.0, 900.0]:
		eq(world.train_state("L1-R-0", t)["phase"], "cancelled", "cancelled at %f" % t)
	eq(world.effective_arrival("L1-R-0", "warszawa"), INF, "cancelled never arrives")
	var base_stops: Array = tables["L1-R-0"]["stops"]
	var rows := world.departures("krakow", 0.0, 200)
	var cancelled_row: Dictionary = {}
	for row: Dictionary in rows:
		if row["train_id"] == "L1-R-0":
			cancelled_row = row
	eq(cancelled_row["cancelled"], true, "cancelled train on Kraków board")
	eq(cancelled_row["departure"], float(base_stops[0]["departure"]),
		"cancelled row keeps base departure")
	eq(cancelled_row["delay"], 0.0, "cancelled row delay 0")
	# --- drunk driver: L1-F-0 at 450 (section radom->kielce), duration 35.
	# Everything from kielce onward shifts +35; earlier stops untouched.
	var f0: Array = tables["L1-F-0"]["stops"]
	near(world.effective_arrival("L1-F-0", "warszawa"), float(f0[0]["arrival"]), EPS,
		"origin untouched")
	near(world.effective_arrival("L1-F-0", "radom"), float(f0[1]["arrival"]), EPS,
		"radom untouched")
	near(world.effective_arrival("L1-F-0", "kielce"), float(f0[2]["arrival"]) + 35.0, EPS,
		"kielce +35")
	near(world.effective_arrival("L1-F-0", "krakow"), float(f0[3]["arrival"]) + 35.0, EPS,
		"krakow +35")
	var moving := world.train_state("L1-F-0", 490.0)
	eq(moving["phase"], "moving", "still moving after drunk event")
	near(moving["delay"], 35.0, EPS, "moving delay 35")
	eq(world.base_train_state("L1-F-0", 490.0)["delay"], 0.0, "base delay stays 0")
	near(world.base_train_state("L1-F-0", 900.0)["delay"], 0.0, EPS, "base finished delay 0")
	# --- slow down: L4-F-0 at 460 (section katowice->krakow, 80 km, local),
	# factor 0.5. delta = section_time(80, ..., 0.5) - section_time(80, ...).
	var local: Dictionary = trains["categories"]["local"]
	var full_time := TrainPhysics.section_time(80.0, float(local["max_speed_kmh"]),
		float(local["accel_mps2"]), float(local["brake_mps2"]))
	var slow_time := TrainPhysics.section_time(80.0, float(local["max_speed_kmh"]),
		float(local["accel_mps2"]), float(local["brake_mps2"]), 0.5)
	var delta := slow_time - full_time
	ok(delta > 0.0, "slowing an 80 km section takes longer")
	var l4: Array = tables["L4-F-0"]["stops"]
	near(world.effective_arrival("L4-F-0", "katowice"), float(l4[0]["arrival"]), EPS,
		"local origin untouched")
	near(world.effective_arrival("L4-F-0", "krakow"), float(l4[1]["arrival"]) + delta, EPS,
		"local terminus + delta")
	near(world.train_state("L4-F-0", 900.0)["delay"], delta, EPS, "local finished delay")
	# Board at Katowice shows the delayed departure.
	var katowice_rows := world.departures("katowice", 450.0, 50)
	var delayed_row: Dictionary = {}
	for row: Dictionary in katowice_rows:
		if row["train_id"] == "L4-F-0":
			delayed_row = row
	near(float(delayed_row["departure"]), float(l4[0]["departure"]), EPS,
		"origin departure unshifted by mid-section slow")
	var krakow_rows := world.departures("krakow", 0.0, 200)
	for row: Dictionary in krakow_rows:
		if row["train_id"] == "L4-F-0":
			near(float(row["departure"]), float(l4[1]["departure"]) + delta, EPS,
				"terminus board departure shifted")
			near(float(row["delay"]), delta, EPS, "terminus board delay")
	# --- unaffected trains stay pristine.
	var l2: Array = tables["L2-F-0"]["stops"]
	near(world.effective_arrival("L2-F-0", "krakow"), float(l2[2]["arrival"]), EPS,
		"other line untouched")
	eq(world.train_state("L2-F-0", 500.0)["delay"], 0.0, "other line delay 0")
	# --- purity: earlier queries after later ones are identical.
	var early := world.train_state("L1-F-0", 470.0)
	var early_board := world.departures("radom", 450.0, 10)
	world.train_state("L1-F-0", 700.0)
	world.departures("krakow", 600.0, 10)
	eq(world.train_state("L1-F-0", 470.0), early, "state pure after later query")
	eq(world.departures("radom", 450.0, 10), early_board, "board pure after later query")


func test_real_config_end_to_end_journey() -> void:
	# Ride L1-F-0 Warszawa -> Kraków with no events: board inside the origin
	# dwell window, finish exactly at the Kraków arrival instant.
	var network := ConfigData.load_file("network")
	var trains := ConfigData.load_file("trains")
	var events_config := ConfigData.load_file("events")
	var world := World.create(network, trains, events_config, [])
	var stops: Array = world.base_timetables()["L1-F-0"]["stops"]
	var slot := float(stops[0]["arrival"])
	var dwell := float(trains["dwell_minutes"])
	var boarding := world.train_state("L1-F-0", slot + dwell / 2.0)
	eq(boarding["phase"], "dwelling", "boardable inside origin dwell")
	eq(boarding["station_id"], "warszawa", "boarding station")
	var arrival := world.effective_arrival("L1-F-0", "krakow")
	near(arrival, float(stops[3]["arrival"]), EPS, "finish instant from schedule")
	var just_before := world.train_state("L1-F-0", arrival - 0.01)
	eq(just_before["phase"], "moving", "still moving just before arrival")
	var at_arrival := world.train_state("L1-F-0", arrival)
	eq(at_arrival["phase"], "dwelling", "disembarkable at arrival instant")
	eq(at_arrival["station_id"], "krakow", "arrived at Kraków")
	eq(at_arrival["platform"], 4, "Kraków platform for L1 forward")
	var at_end := world.train_state("L1-F-0", arrival + dwell)
	eq(at_end["phase"], "finished", "finished after terminus dwell")
	# Same journey with the drunk event: finish instant shifts by exactly 35.
	var delayed := World.create(network, trains, events_config, _hand_events())
	near(delayed.effective_arrival("L1-F-0", "krakow"), arrival + 35.0, EPS,
		"delayed finish instant")
	eq(delayed.train_state("L1-F-0", arrival)["phase"], "moving",
		"not arrived yet at the base instant")
	eq(delayed.train_state("L1-F-0", arrival + 35.0)["phase"], "dwelling",
		"dwelling at the shifted instant")
	eq(delayed.effective_arrival("L1-R-0", "warszawa"), INF, "cancelled train never finishes")


## Hand-built events on real-config trains, sorted by at_minute.
## L1-F-0 slot 404 (warszawa 0, radom 100, kielce 180, krakow 320 km):
## radom arr ~438.2 dep ~440.2, kielce arr ~466.3, so at 450 the train is in
## radom->kielce. L4-F-0 slot 450 (katowice->krakow 80 km local): at 460 it is
## mid-section. L1-R-0 slot 404: cancel at 402.
func _hand_events() -> Array:
	return [
		{"id": 0, "type": "cancel", "train_id": "L1-R-0", "at_minute": 402.0},
		{"id": 1, "type": "drunk_driver", "train_id": "L1-F-0",
			"at_minute": 450.0, "duration_minutes": 35.0},
		{"id": 2, "type": "slow_down", "train_id": "L4-F-0",
			"at_minute": 460.0, "speed_factor": 0.5}]


func _station_name(network: Dictionary, station_id: String) -> String:
	for station: Dictionary in network["stations"]:
		if station["id"] == station_id:
			return station["name"]
	return ""


func test_accessors_return_snapshots_not_live_references() -> void:
	# Regression (bug-hunt minor): base_timetables()/train_info() must not leak
	# live internal state — mutating a returned object must not affect queries.
	var network := ConfigData.load_file("network")
	var trains := ConfigData.load_file("trains")
	var events_config := ConfigData.load_file("events")
	var world := World.create(network, trains, events_config, [])
	var state_before := world.train_state("L1-F-0", 700.0)
	var tables := world.base_timetables()
	tables["L1-F-0"]["stops"][3]["arrival"] = 9999.0
	eq(world.train_state("L1-F-0", 700.0), state_before, "mutating base_timetables stops must not change state")
	var info := world.train_info("L1-F-0")
	info["train_number"] = "HACKED"
	var rows := world.departures("warszawa", 0.0, 50)
	for row in rows:
		if row["train_id"] == "L1-F-0":
			ok(row["train_number"] != "HACKED", "mutating train_info must not change board rows")
