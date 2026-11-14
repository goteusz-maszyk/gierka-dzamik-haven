class_name World
extends RefCounted
## The only thing Run/views touch: a thin facade over one Timetable.
## All state is derived from the clock; nothing mutates after create().

var _timetable: Timetable


static func create(network: Dictionary, trains_config: Dictionary,
		events_config: Dictionary, events: Array) -> World:
	var world := World.new()
	world._timetable = Timetable.generate(network, trains_config, events_config, events)
	return world


func train_state(train_id: String, t: float) -> Dictionary:
	return _timetable.train_state(train_id, t)


func base_train_state(train_id: String, t: float) -> Dictionary:
	return _timetable.base_train_state(train_id, t)


func departures(station_id: String, t: float, count: int) -> Array:
	return _timetable.departures(station_id, t, count)


func base_departures(station_id: String, t: float, count: int) -> Array:
	return _timetable.base_departures(station_id, t, count)


func platform_next(station_id: String, platform: int, t: float) -> Dictionary:
	return _timetable.platform_next(station_id, platform, t)


func effective_arrival(train_id: String, station_id: String) -> float:
	return _timetable.effective_arrival(train_id, station_id)


func effective_arrival_after(train_id: String, station_id: String, after_index: int) -> float:
	return _timetable.effective_arrival_after(train_id, station_id, after_index)


## Index of the stop where station_id appears in the train's travel order.
func stop_index(train_id: String, station_id: String) -> int:
	var stops: Array = _timetable.base_timetables()[train_id]["stops"]
	for index in stops.size():
		if stops[index]["station_id"] == station_id:
			return index
	return -1


func base_timetables() -> Dictionary:
	return _timetable.base_timetables()


func train_ids() -> Array[String]:
	return _timetable.train_ids()


func train_info(train_id: String) -> Dictionary:
	return _timetable.train_info(train_id)
