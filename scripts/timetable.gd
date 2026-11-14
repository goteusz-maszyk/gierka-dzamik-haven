class_name Timetable
extends RefCounted
## Pure timetable: base schedules plus effective schedules after events.
## state = f(timetable, events, time); nothing mutates after generate().
## Times are in-game minutes since midnight; distances km along the direction
## path (reverse km mirrored so both directions start at 0).


static func generate(network: Dictionary, trains_config: Dictionary,
		events_config: Dictionary, events: Array) -> Timetable:
	var timetable := Timetable.new()
	timetable._dwell = float(trains_config["dwell_minutes"])
	for station: Dictionary in network["stations"]:
		timetable._station_names[station["id"]] = station["name"]
	for category_name: String in trains_config["categories"]:
		var category: Dictionary = trains_config["categories"][category_name]
		timetable._category_physics[category_name] = {
			"max_speed_kmh": float(category["max_speed_kmh"]),
			"accel_mps2": float(category["accel_mps2"]),
			"brake_mps2": float(category["brake_mps2"])}
	var horizon := float(events_config["horizon_minutes"])
	var number_counters: Dictionary = {}  # category -> running display index
	for line: Dictionary in network["lines"]:
		var physics: Dictionary = timetable._category_physics[line["category"]]
		var category_config: Dictionary = trains_config["categories"][line["category"]]
		var line_stops: Array = line["stops"]
		var total_km := float(line_stops[line_stops.size() - 1]["km"])
		var first := float(line["first_departure_minutes"])
		var frequency := float(line["frequency_minutes"])
		var k := 0
		var slot := first
		while slot < first + horizon:
			for direction: String in ["F", "R"]:
				var train_id := "%s-%s-%d" % [line["id"], direction, k]
				var number_index: int = number_counters.get(line["category"], 0)
				number_counters[line["category"]] = number_index + 1
				var train_number := "%s %d" % [category_config["number_prefix"],
					int(category_config["number_start"]) + number_index]
				var ordered: Array = []  # {station_id, km, platform} in travel order
				if direction == "F":
					for index in line_stops.size():
						ordered.append({"station_id": line_stops[index]["station"],
							"km": float(line_stops[index]["km"]), "platform": index + 1})
				else:
					for index in range(line_stops.size() - 1, -1, -1):
						ordered.append({"station_id": line_stops[index]["station"],
							"km": total_km - float(line_stops[index]["km"]),
							"platform": line_stops.size() - index})
				var base_stops := timetable._build_schedule(ordered, slot, physics)
				var info := {
					"train_number": train_number,
					"line_id": line["id"],
					"line_name": line["name"],
					"color": line["color"],
					"category": line["category"],
					"direction": direction,
					"stops": [],
					"destination": timetable._station_names[ordered[ordered.size() - 1]["station_id"]]}
				for stop: Dictionary in ordered:
					info["stops"].append({"station_id": stop["station_id"], "platform": stop["platform"]})
				var factors: Array = []  # per-section speed factors, effective only
				for i in ordered.size() - 1:
					factors.append(1.0)
				timetable._base[train_id] = {"info": info, "stops": base_stops, "factor_by_section": factors}
				timetable._effective[train_id] = {"info": info,
					"stops": base_stops.duplicate(true), "cancelled": false,
					"factor_by_section": factors.duplicate()}
				timetable._order.append(train_id)
			k += 1
			slot = first + k * frequency
	timetable._apply_events(events)
	return timetable


var _base: Dictionary = {}  # train_id -> {info, stops, factor_by_section}
var _effective: Dictionary = {}  # train_id -> {info, stops, cancelled, factor_by_section}
var _order: Array[String] = []  # train ids in generation order
var _dwell := 0.0
var _category_physics: Dictionary = {}  # category -> {max_speed_kmh, accel_mps2, brake_mps2}
var _station_names: Dictionary = {}  # station_id -> display name


func train_state(train_id: String, t: float) -> Dictionary:
	var entry: Dictionary = _effective[train_id]
	if entry["cancelled"]:
		return {"phase": "cancelled", "station_id": "", "platform": 0,
			"from_station": "", "to_station": "", "progress": 0.0, "km": 0.0, "delay": 0.0}
	var physics: Dictionary = _category_physics[entry["info"]["category"]]
	return _state_from_stops(entry["stops"], _base[train_id]["stops"], physics,
		entry["factor_by_section"], t)


func base_train_state(train_id: String, t: float) -> Dictionary:
	var entry: Dictionary = _base[train_id]
	var physics: Dictionary = _category_physics[entry["info"]["category"]]
	return _state_from_stops(entry["stops"], entry["stops"], physics,
		entry["factor_by_section"], t)


func departures(station_id: String, t: float, count: int) -> Array:
	return _board(station_id, t, count, false)


func base_departures(station_id: String, t: float, count: int) -> Array:
	return _board(station_id, t, count, true)


func platform_next(station_id: String, platform: int, t: float) -> Dictionary:
	var best: Dictionary = {}
	for train_id in _order:
		var entry: Dictionary = _effective[train_id]
		var stops: Array = entry["stops"]
		for index in stops.size():
			var stop: Dictionary = stops[index]
			if stop["station_id"] != station_id or int(stop["platform"]) != platform:
				continue
			var departure := float(stop["departure"])
			if departure < t:
				continue
			if best.is_empty() or departure < float(best["departure"]):
				best = _board_row(train_id, entry, index)
	return best


func effective_arrival(train_id: String, station_id: String) -> float:
	var entry: Dictionary = _effective[train_id]
	if entry["cancelled"]:
		return INF
	for stop: Dictionary in entry["stops"]:
		if stop["station_id"] == station_id:
			return float(stop["arrival"])
	return INF


## Effective arrival at station_id at a stop AFTER after_index (the boarding
## stop). INF if the train never reaches it later, or is cancelled. Used so a
## train whose ORIGIN is the destination does not count as an arrival.
func effective_arrival_after(train_id: String, station_id: String, after_index: int) -> float:
	var entry: Dictionary = _effective[train_id]
	if entry["cancelled"]:
		return INF
	var stops: Array = entry["stops"]
	for index in range(after_index + 1, stops.size()):
		if stops[index]["station_id"] == station_id:
			return float(stops[index]["arrival"])
	return INF


func base_timetables() -> Dictionary:
	var result := {}
	for train_id in _order:
		var entry: Dictionary = _base[train_id]
		result[train_id] = {"info": entry["info"].duplicate(true), "stops": entry["stops"].duplicate(true)}
	return result


func train_ids() -> Array[String]:
	return _order.duplicate()


func train_info(train_id: String) -> Dictionary:
	return _base[train_id]["info"].duplicate(true)


## Every stop dwells, origin and terminus included: arrival at the origin is
## the slot, departure = arrival + dwell; the first section starts at slot + dwell.
func _build_schedule(ordered: Array, slot: float, physics: Dictionary) -> Array:
	var stops: Array = []
	var time := slot
	for index in ordered.size():
		var arrival := time
		var departure := time + _dwell
		stops.append({"station_id": ordered[index]["station_id"],
			"platform": ordered[index]["platform"], "km": ordered[index]["km"],
			"arrival": arrival, "departure": departure})
		if index + 1 < ordered.size():
			var distance := float(ordered[index + 1]["km"]) - float(ordered[index]["km"])
			time = departure + TrainPhysics.section_time(distance,
				float(physics["max_speed_kmh"]), float(physics["accel_mps2"]),
				float(physics["brake_mps2"]))
	return stops


func _apply_events(events: Array) -> void:
	# Input is sorted by at_minute (slice B contract); each event locates the
	# train on its already-shifted schedule.
	for event: Dictionary in events:
		var train_id: String = event["train_id"]
		assert(_effective.has(train_id), "Timetable: event for unknown train " + train_id)
		var entry: Dictionary = _effective[train_id]
		match event["type"]:
			"cancel":
				entry["cancelled"] = true
			"drunk_driver":
				_apply_drunk(entry, float(event["at_minute"]), float(event["duration_minutes"]))
			"slow_down":
				_apply_slow(entry, float(event["at_minute"]), float(event["speed_factor"]))
			_:
				assert(false, "Timetable: unknown event type " + str(event["type"]))


func _apply_drunk(entry: Dictionary, at_minute: float, duration: float) -> void:
	var stops: Array = entry["stops"]
	if at_minute < float(stops[0]["arrival"]):
		_shift_stops(stops, 0, duration)
		return
	for index in stops.size():
		var arrival := float(stops[index]["arrival"])
		var departure := float(stops[index]["departure"])
		if at_minute < departure:
			if at_minute >= arrival:
				# Dwelling: extend this dwell, shift everything later.
				stops[index]["departure"] = departure + duration
				_shift_stops(stops, index + 1, duration)
			else:
				# Moving in section index-1 -> index: delay its arrival onward.
				_shift_stops(stops, index, duration)
			return
	# At or after the last departure: the train is finished, nothing to shift.


func _apply_slow(entry: Dictionary, at_minute: float, speed_factor: float) -> void:
	var stops: Array = entry["stops"]
	var section := -1
	if at_minute < float(stops[0]["departure"]):
		section = 0
	else:
		for index in stops.size():
			var arrival := float(stops[index]["arrival"])
			var departure := float(stops[index]["departure"])
			if at_minute < departure:
				# Dwelling (or at the arrival instant): the next section.
				section = index if at_minute >= arrival else index - 1
				break
	if section < 0 or section >= stops.size() - 1:
		return  # finished or dwelling at the terminus: no section left
	var distance := float(stops[section + 1]["km"]) - float(stops[section]["km"])
	var physics: Dictionary = _category_physics[entry["info"]["category"]]
	var old_time := TrainPhysics.section_time(distance, float(physics["max_speed_kmh"]),
		float(physics["accel_mps2"]), float(physics["brake_mps2"]),
		float(entry["factor_by_section"][section]))
	var new_time := TrainPhysics.section_time(distance, float(physics["max_speed_kmh"]),
		float(physics["accel_mps2"]), float(physics["brake_mps2"]), speed_factor)
	entry["factor_by_section"][section] = speed_factor
	_shift_stops(stops, section + 1, new_time - old_time)


static func _shift_stops(stops: Array, from_index: int, delta: float) -> void:
	for index in range(from_index, stops.size()):
		stops[index]["arrival"] = float(stops[index]["arrival"]) + delta
		stops[index]["departure"] = float(stops[index]["departure"]) + delta


## Phase boundaries: dwelling on [arrival, departure), moving on
## [departure, next arrival), finished only at t >= last departure.
func _state_from_stops(stops: Array, base_stops: Array, physics: Dictionary,
		factors: Array, t: float) -> Dictionary:
	var state := {"phase": "before", "station_id": "", "platform": 0,
		"from_station": "", "to_station": "", "progress": 0.0, "km": 0.0, "delay": 0.0}
	var last: Dictionary = stops[stops.size() - 1]
	if t < float(stops[0]["arrival"]):
		return state
	for index in stops.size():
		var stop: Dictionary = stops[index]
		var arrival := float(stop["arrival"])
		var departure := float(stop["departure"])
		if t < departure:
			if t >= arrival:
				state["phase"] = "dwelling"
				state["station_id"] = stop["station_id"]
				state["platform"] = int(stop["platform"])
				state["km"] = float(stop["km"])
				state["delay"] = arrival - float(base_stops[index]["arrival"])
			else:
				var section := index - 1
				var from_stop: Dictionary = stops[section]
				var distance := float(stop["km"]) - float(from_stop["km"])
				var elapsed := t - float(from_stop["departure"])
				var progress := TrainPhysics.section_progress(distance,
					float(physics["max_speed_kmh"]), float(physics["accel_mps2"]),
					float(physics["brake_mps2"]), float(factors[section]), elapsed)
				state["phase"] = "moving"
				state["from_station"] = from_stop["station_id"]
				state["to_station"] = stop["station_id"]
				state["progress"] = progress
				state["km"] = float(from_stop["km"]) + progress * distance
				state["delay"] = arrival - float(base_stops[index]["arrival"])
			return state
	state["phase"] = "finished"
	state["km"] = float(last["km"])
	state["delay"] = float(last["arrival"]) - float(base_stops[base_stops.size() - 1]["arrival"])
	return state


func _board(station_id: String, t: float, count: int, use_base: bool) -> Array:
	var rows: Array = []
	for train_id in _order:
		var entry: Dictionary = _base[train_id] if use_base else _effective[train_id]
		var stops: Array = entry["stops"]
		for index in stops.size():
			var stop: Dictionary = stops[index]
			if stop["station_id"] != station_id or float(stop["departure"]) < t:
				continue
			rows.append(_board_row(train_id, entry, index))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["departure"]) < float(b["departure"]))
	return rows.slice(0, maxi(count, 0))


func _board_row(train_id: String, entry: Dictionary, stop_index: int) -> Dictionary:
	var stop: Dictionary = entry["stops"][stop_index]
	var info: Dictionary = entry["info"]
	return {
		"train_id": train_id,
		"train_number": info["train_number"],
		"line_id": info["line_id"],
		"destination": info["destination"],
		"platform": int(stop["platform"]),
		"departure": float(stop["departure"]),
		"delay": float(stop["arrival"]) - float(_base[train_id]["stops"][stop_index]["arrival"]),
		"cancelled": bool(entry.get("cancelled", false))}
