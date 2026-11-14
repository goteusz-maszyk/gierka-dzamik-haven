extends TestHarness
## Pins config data to DESIGN.md numbers and validates network structure.


func test_time_values_match_design() -> void:
	var cfg := ConfigData.load_file("time")
	near(cfg.map_view_minutes_per_real_second, 0.6, 1e-9, "map clock: 3h per 5 real min")
	near(cfg.station_view_minutes_per_real_second, 0.15, 1e-9, "station clock: 4x slower than map")
	near(cfg.rewind_minutes_per_real_second, 12.0, 1e-9, "rewind: 1h per 5 real s")
	near(cfg.rewind_meter_minutes, 180.0, 1e-9, "rewind meter: 3 in-game hours")
	eq(cfg.perfect_arrival_minutes, 540, "perfect arrival is 09:00")
	ok(cfg.deadline_buffer_minutes > 0, "deadline buffer is positive")


func test_train_categories_match_design() -> void:
	var cfg := ConfigData.load_file("trains")
	eq(cfg.dwell_minutes, 2, "2-minute dwell at every stop")
	var expected := {
		"local": [80, 0.7, 0.45],
		"regional": [120, 0.5, 0.55],
		"express": [160, 0.4, 0.65],
		"intercity": [200, 0.3, 0.75],
	}
	for category_name in expected:
		var category: Dictionary = cfg.categories[category_name]
		eq(category.max_speed_kmh, expected[category_name][0], category_name + " max speed")
		near(category.accel_mps2, expected[category_name][1], 1e-9, category_name + " acceleration")
		near(category.brake_mps2, expected[category_name][2], 1e-9, category_name + " braking")


func test_train_number_config() -> void:
	var cfg := ConfigData.load_file("trains")
	var expected_prefix := {"local": "O", "regional": "R", "express": "E", "intercity": "IC"}
	for category_name in expected_prefix:
		var category: Dictionary = cfg.categories[category_name]
		eq(category.number_prefix, expected_prefix[category_name], category_name + " number prefix")
		ok(category.number_start > 0 and category.number_start == floorf(category.number_start), category_name + " number start is a positive whole number")


func test_network_structure() -> void:
	var net := ConfigData.load_file("network")
	var trains_cfg := ConfigData.load_file("trains")
	var station_ids := {}
	for station in net.stations:
		ok(not station_ids.has(station.id), "duplicate station id: " + str(station.id))
		station_ids[station.id] = true
		ok(station.name is String and not (station.name as String).is_empty(), "station has a name")
		eq((station.map_pos as Array).size(), 2, "map_pos is an [x, y] pair")
	eq(net.destination_station, "krakow", "destination is Kraków")
	ok(station_ids.has(net.destination_station), "destination station exists")
	var start_cities := 0
	for station in net.stations:
		if station.start_city:
			start_cities += 1
	ok(start_cities >= 2, "multiple start cities for random runs")
	for line in net.lines:
		ok(trains_cfg.categories.has(line.category), "line category exists: " + str(line.category))
		ok((line.stops as Array).size() >= 2, "line has at least two stops: " + str(line.id))
		ok(line.frequency_minutes > 0, "positive frequency: " + str(line.id))
		ok(line.first_departure_minutes >= 0, "non-negative first departure: " + str(line.id))
		var previous_km := -1.0
		for stop in line.stops:
			ok(station_ids.has(stop.station), "line references known station: " + str(stop.station))
			ok(stop.km > previous_km, "km strictly increasing along line: " + str(line.id))
			previous_km = stop.km


func test_polish_names_survive_json() -> void:
	var net := ConfigData.load_file("network")
	var names := {}
	for station in net.stations:
		names[station.id] = station.name
	eq(names.lodz, "Łódź", "Łódź diacritics")
	eq(names.krakow, "Kraków", "Kraków diacritics")
	eq(names.czestochowa, "Częstochowa", "Częstochowa diacritics")
	eq(names.rzeszow, "Rzeszów", "Rzeszów diacritics")
	eq(names.wroclaw, "Wrocław", "Wrocław diacritics")


func test_events_config() -> void:
	var cfg := ConfigData.load_file("events")
	ok(cfg.min_events >= 15, "design requires 15+ events per run")
	ok(cfg.max_events >= cfg.min_events, "max_events >= min_events")
	ok(cfg.horizon_minutes > 0, "positive event horizon")
	for type_name in ["drunk_driver", "slow_down", "cancel"]:
		ok(cfg.types.has(type_name), "event type configured: " + type_name)
		ok(cfg.types[type_name].weight > 0, "positive weight: " + type_name)
	var drunk: Dictionary = cfg.types.drunk_driver
	ok(drunk.stop_duration_max_minutes >= drunk.stop_duration_min_minutes, "drunk driver duration range ordered")
	ok(drunk.stop_duration_min_minutes >= 30 and drunk.stop_duration_max_minutes <= 60, "design example: 30-60 min hold")
	near(cfg.types.slow_down.speed_factor, 0.5, 1e-9, "slow down: 50% speed")


func test_first_departures_tuned_for_start_cities() -> void:
	# Offsets tuned so a perfect run from every start city arrives ~08:30
	# (deadline 09:00 minus the 30-min buffer). See DESIGN.md "Time"/"Deadline".
	# If you retune the network, update these AND re-verify the ~5-min run target.
	var net := ConfigData.load_file("network")
	var expected := {"L1": 404, "L2": 381, "L3": 241, "L4": 450, "L5": 381, "L6": 480}
	for line in net.lines:
		eq(line.first_departure_minutes, expected[line.id], "tuned first departure for " + str(line.id))
