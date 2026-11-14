extends TestHarness
## Slice B: Events.generate — determinism, bounds, distinct trains, type rules.

const SEEDS := 50


func test_determinism_and_seed_difference() -> void:
	var network := ConfigData.load_file("network")
	var trains := ConfigData.load_file("trains")
	var events_config := ConfigData.load_file("events")
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 1234
	var first: Array = Events.generate(events_config, network, rng_a)
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 1234
	var second: Array = Events.generate(events_config, network, rng_b)
	eq(first.size(), second.size(), "same seed same count")
	for i in first.size():
		eq(first[i], second[i], "same seed identical event %d" % i)
	var rng_c := RandomNumberGenerator.new()
	rng_c.seed = 4321
	var other: Array = Events.generate(events_config, network, rng_c)
	var identical := first.size() == other.size()
	if identical:
		for i in first.size():
			if first[i] != other[i]:
				identical = false
				break
	ok(not identical, "different seeds produce different events")


func test_count_bounds_and_no_stacking() -> void:
	var network := ConfigData.load_file("network")
	var trains := ConfigData.load_file("trains")
	var events_config := ConfigData.load_file("events")
	var min_events: int = int(events_config["min_events"])
	var max_events: int = int(events_config["max_events"])
	var slots := _all_slots(network, float(events_config["horizon_minutes"]))
	var slot_by_train := {}
	for slot_entry: Dictionary in slots:
		slot_by_train[slot_entry["train_id"]] = slot_entry["slot"]
	for seed_value in SEEDS:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var events: Array = Events.generate(events_config, network, rng)
		ok(events.size() >= min_events and events.size() <= max_events,
			"seed %d count %d in [%d, %d]" % [seed_value, events.size(), min_events, max_events])
		var seen := {}
		for event: Dictionary in events:
			ok(not seen.has(event["train_id"]), "seed %d train %s hit twice" % [seed_value, event["train_id"]])
			seen[event["train_id"]] = true
			ok(slot_by_train.has(event["train_id"]), "seed %d unknown train %s" % [seed_value, event["train_id"]])
		# ids are exactly 0..n-1 (sequential generation order, then sorted).
		var ids: Array = events.map(func(e: Dictionary) -> int: return e["id"])
		ids.sort()
		var expected_ids: Array = []
		for i in events.size():
			expected_ids.append(i)
		eq(ids, expected_ids, "seed %d ids are 0..n-1" % seed_value)
		# Sorted by at_minute, ties broken by id.
		for i in range(1, events.size()):
			var prev: Dictionary = events[i - 1]
			var cur: Dictionary = events[i]
			var ordered := float(prev["at_minute"]) < float(cur["at_minute"]) or (
				float(prev["at_minute"]) == float(cur["at_minute"]) and int(prev["id"]) < int(cur["id"]))
			ok(ordered, "seed %d events not sorted at index %d" % [seed_value, i])


func test_event_fields_and_ranges() -> void:
	var network := ConfigData.load_file("network")
	var trains := ConfigData.load_file("trains")
	var events_config := ConfigData.load_file("events")
	var types_config: Dictionary = events_config["types"]
	var drunk: Dictionary = types_config["drunk_driver"]
	var slow: Dictionary = types_config["slow_down"]
	var cancel: Dictionary = types_config["cancel"]
	var horizon: float = float(events_config["horizon_minutes"])
	var slots := _all_slots(network, horizon)
	var slot_by_train := {}
	for slot_entry: Dictionary in slots:
		slot_by_train[slot_entry["train_id"]] = slot_entry["slot"]
	for seed_value in SEEDS:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var events: Array = Events.generate(events_config, network, rng)
		for event: Dictionary in events:
			var type_name: String = event["type"]
			ok(types_config.has(type_name), "seed %d unknown type %s" % [seed_value, type_name])
			var at_minute: float = event["at_minute"]
			match type_name:
				"drunk_driver":
					var duration: float = event["duration_minutes"]
					ok(duration >= float(drunk["stop_duration_min_minutes"])
						and duration <= float(drunk["stop_duration_max_minutes"]),
						"seed %d drunk duration %f out of range" % [seed_value, duration])
					ok(at_minute >= 0.0 and at_minute < horizon,
						"seed %d drunk at_minute %f out of horizon" % [seed_value, at_minute])
					ok(not event.has("speed_factor"), "drunk event carries speed_factor")
				"slow_down":
					eq(float(event["speed_factor"]), float(slow["speed_factor"]),
						"seed %d slow factor from config" % seed_value)
					ok(at_minute >= 0.0 and at_minute < horizon,
						"seed %d slow at_minute %f out of horizon" % [seed_value, at_minute])
					ok(not event.has("duration_minutes"), "slow event carries duration_minutes")
				"cancel":
					var slot: float = slot_by_train[event["train_id"]]
					var lead: float = slot - at_minute
					ok(lead >= float(cancel["lead_minutes_min"]) - 1e-9
						and lead <= float(cancel["lead_minutes_max"]) + 1e-9,
						"seed %d cancel lead %f outside [%f, %f]" % [seed_value, lead,
						float(cancel["lead_minutes_min"]), float(cancel["lead_minutes_max"])])
					ok(at_minute < slot, "cancel not right before its slot")
					ok(not event.has("duration_minutes") and not event.has("speed_factor"),
						"cancel event carries extra fields")


func test_type_coverage_across_seeds() -> void:
	var network := ConfigData.load_file("network")
	var trains := ConfigData.load_file("trains")
	var events_config := ConfigData.load_file("events")
	var seen := {}
	for seed_value in SEEDS:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var events: Array = Events.generate(events_config, network, rng)
		for event: Dictionary in events:
			seen[event["type"]] = true
	for type_name in events_config["types"]:
		ok(seen.has(type_name), "type %s never generated across %d seeds" % [type_name, SEEDS])


func test_weighted_type_selection() -> void:
	var network := _mini_network()
	var events_config := _mini_events_config()
	var trains := {"dwell_minutes": 2.0}
	# Only slow_down has nonzero weight: every event must be slow_down.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var events: Array = Events.generate(events_config, network, rng)
	eq(events.size(), 6, "mini config count fixed at 6")
	for event: Dictionary in events:
		eq(event["type"], "slow_down", "zero-weight types never chosen")
		eq(float(event["speed_factor"]), 0.5, "factor from config")


func test_count_uses_full_train_pool() -> void:
	# max_events larger than the first slot per direction: the generator must
	# draw from later slots too (8 trains total in the mini network).
	var network := _mini_network()
	var events_config := _mini_events_config()
	events_config["min_events"] = 8
	events_config["max_events"] = 8
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var events: Array = Events.generate(events_config, network, rng)
	eq(events.size(), 8, "one event per train when count equals pool")
	var ids := {}
	for event: Dictionary in events:
		ids[event["train_id"]] = true
	eq(ids.size(), 8, "all 8 trains distinct")
	var expected := ["M-F-0", "M-R-0", "M-F-1", "M-R-1", "M-F-2", "M-R-2", "M-F-3", "M-R-3"]
	for train_id in expected:
		ok(ids.has(train_id), "pool includes %s" % train_id)


func test_cancel_timing_hand_computed() -> void:
	# Single line, one slot at 100, lead fixed at 3 -> at_minute == 97 exactly.
	var network := _mini_network()
	network["lines"] = [{
		"id": "M", "name": "Mini", "color": "#000000", "category": "local",
		"frequency_minutes": 100.0, "first_departure_minutes": 100.0,
		"stops": [{"station": "a", "km": 0.0}, {"station": "b", "km": 10.0}],
	}]
	var events_config := _mini_events_config()
	events_config["min_events"] = 1
	events_config["max_events"] = 1
	events_config["horizon_minutes"] = 100.0
	events_config["types"] = {"cancel": {"weight": 1.0, "lead_minutes_min": 3.0, "lead_minutes_max": 3.0}}
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var events: Array = Events.generate(events_config, network, rng)
	eq(events.size(), 1, "single event")
	var event: Dictionary = events[0]
	eq(event["type"], "cancel", "type cancel")
	eq(float(event["at_minute"]), 97.0, "cancel at slot 100 minus lead 3")
	ok(event["train_id"] == "M-F-0" or event["train_id"] == "M-R-0", "train is the slot-0 train")


## Recomputes slots exactly as the contract's Timetable formula (independent
## of Events' own implementation).
func _all_slots(network: Dictionary, horizon_minutes: float) -> Array:
	var slots: Array = []
	for line: Dictionary in network["lines"]:
		var first: float = float(line["first_departure_minutes"])
		var frequency: float = float(line["frequency_minutes"])
		var k: int = 0
		while first + k * frequency < first + horizon_minutes:
			slots.append({"train_id": "%s-F-%d" % [line["id"], k], "slot": first + k * frequency})
			slots.append({"train_id": "%s-R-%d" % [line["id"], k], "slot": first + k * frequency})
			k += 1
	return slots


func _mini_network() -> Dictionary:
	return {
		"destination_station": "b",
		"stations": [
			{"id": "a", "name": "A", "map_pos": [0, 0], "start_city": true},
			{"id": "b", "name": "B", "map_pos": [1, 0], "start_city": false},
		],
		"lines": [{
			"id": "M", "name": "Mini", "color": "#000000", "category": "local",
			"frequency_minutes": 30.0, "first_departure_minutes": 10.0,
			"stops": [{"station": "a", "km": 0.0}, {"station": "b", "km": 10.0}],
		}],
	}


func _mini_events_config() -> Dictionary:
	return {
		"min_events": 6, "max_events": 6, "horizon_minutes": 120.0,
		"types": {
			"drunk_driver": {"weight": 0.0, "stop_duration_min_minutes": 30.0, "stop_duration_max_minutes": 60.0},
			"slow_down": {"weight": 1.0, "speed_factor": 0.5},
			"cancel": {"weight": 0.0, "lead_minutes_min": 1.0, "lead_minutes_max": 5.0},
		},
	}
