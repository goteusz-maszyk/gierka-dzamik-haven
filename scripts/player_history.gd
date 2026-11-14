class_name PlayerHistory
extends RefCounted
## Monotonic log of where the player was — the rewind backbone. The world is
## pure f(timetable, events, time); only the player needs recorded history.

var _records: Array[Dictionary] = []


func record_station(t: float, station_id: String) -> void:
	_append(t, {"kind": "station", "station_id": station_id, "train_id": ""})


func record_train(t: float, train_id: String, stop_index: int) -> void:
	_append(t, {"kind": "train", "station_id": "", "train_id": train_id, "stop_index": stop_index})


## Latest record at or before t; before the first record, the first record.
func state_at(t: float) -> Dictionary:
	assert(not _records.is_empty(), "PlayerHistory.state_at: empty history")
	for i in range(_records.size() - 1, -1, -1):
		if _records[i]["time"] <= t:
			return _state_of(_records[i])
	return _state_of(_records[0])


## Drops records strictly after t.
func truncate_after(t: float) -> void:
	var kept: Array[Dictionary] = []
	for record in _records:
		if record["time"] <= t:
			kept.append(record)
	_records = kept


func _append(t: float, state: Dictionary) -> void:
	assert(_records.is_empty() or t >= float(_records.back()["time"]),
		"PlayerHistory: record time goes backwards")
	var record := state.duplicate()
	record["time"] = t
	_records.append(record)


func _state_of(record: Dictionary) -> Dictionary:
	return {
		"kind": record["kind"],
		"station_id": record["station_id"],
		"train_id": record["train_id"],
		"stop_index": int(record.get("stop_index", -1)),
	}
