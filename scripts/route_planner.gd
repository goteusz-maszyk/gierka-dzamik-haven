class_name RoutePlanner
extends RefCounted
## Earliest arrival over the base timetable; events are ignored (per DESIGN).


static func fastest_arrival(world: World, network: Dictionary,
		from_station: String, start_time: float) -> float:
	var destination: String = network["destination_station"]
	if from_station == destination:
		return start_time
	var timetables: Dictionary = world.base_timetables()
	# station_id -> [{train_id, index, departure}], sorted by departure.
	var departures: Dictionary = {}
	var train_ids: Array = timetables.keys()
	train_ids.sort()
	for train_id in train_ids:
		var stops: Array = timetables[train_id]["stops"]
		for index in stops.size():
			var stop: Dictionary = stops[index]
			var station_id: String = stop["station_id"]
			if not departures.has(station_id):
				departures[station_id] = []
			departures[station_id].append({
				"train_id": train_id, "index": index, "departure": float(stop["departure"])})
	for station_id in departures:
		departures[station_id].sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool: return a["departure"] < b["departure"])
	# Time-expanded Dijkstra: a label is (station, earliest arrival time there).
	# Riding a train pushes one label per later stop; transfers are instant, so
	# any departure >= the label time is boardable. Labels only ever improve,
	# and there are finitely many stop events, so this terminates.
	var best: Dictionary = {from_station: start_time}
	var frontier: Array = [{"time": start_time, "station": from_station}]
	while not frontier.is_empty():
		var pop_index: int = 0
		for i in frontier.size():
			if frontier[i]["time"] < frontier[pop_index]["time"]:
				pop_index = i
		var current: Dictionary = frontier[pop_index]
		frontier.remove_at(pop_index)
		var station: String = current["station"]
		var now: float = current["time"]
		if now > best[station]:
			continue  # stale label, a better one was already processed
		if station == destination:
			return now
		if not departures.has(station):
			continue
		for departure in departures[station]:
			if departure["departure"] < now:
				continue
			var stops: Array = timetables[departure["train_id"]]["stops"]
			var board_index: int = departure["index"]
			for index in range(board_index + 1, stops.size()):
				var arrival: float = float(stops[index]["arrival"])
				var next_station: String = stops[index]["station_id"]
				if arrival < best.get(next_station, INF):
					best[next_station] = arrival
					frontier.append({"time": arrival, "station": next_station})
	return INF
