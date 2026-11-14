class_name Events
extends RefCounted
## Seeded per-run event generation. Deterministic given the injected rng.


static func generate(events_config: Dictionary, network: Dictionary,
		rng: RandomNumberGenerator) -> Array:
	var min_events: int = int(events_config["min_events"])
	var max_events: int = int(events_config["max_events"])
	assert(min_events >= 0 and max_events >= min_events, "Events.generate: invalid event count bounds")
	var horizon: float = float(events_config["horizon_minutes"])
	var types_config: Dictionary = events_config["types"]
	# Sorted keys: never depend on Dictionary iteration order.
	var type_names: Array = types_config.keys()
	type_names.sort_custom(func(a: String, b: String) -> bool: return a < b)
	var slots: Array = _all_slots(network, horizon)
	assert(slots.size() >= max_events, "Events.generate: fewer trains than max_events")
	var count: int = rng.randi_range(min_events, max_events)
	# Partial Fisher-Yates: draw `count` distinct slots uniformly without replacement.
	for i in count:
		var j: int = rng.randi_range(i, slots.size() - 1)
		var tmp: Dictionary = slots[i]
		slots[i] = slots[j]
		slots[j] = tmp
	var events: Array = []
	for i in count:
		var chosen: Dictionary = slots[i]
		var type_name: String = _pick_type(types_config, type_names, rng)
		var type_config: Dictionary = types_config[type_name]
		var event: Dictionary = {"id": i, "type": type_name, "train_id": chosen["train_id"]}
		var at_minute: float = 0.0
		if type_name == "drunk_driver":
			event["duration_minutes"] = rng.randf_range(
				float(type_config["stop_duration_min_minutes"]),
				float(type_config["stop_duration_max_minutes"]))
			at_minute = rng.randf_range(0.0, horizon)
		elif type_name == "slow_down":
			event["speed_factor"] = float(type_config["speed_factor"])
			at_minute = rng.randf_range(0.0, horizon)
		elif type_name == "cancel":
			var lead: float = rng.randf_range(
				float(type_config["lead_minutes_min"]),
				float(type_config["lead_minutes_max"]))
			at_minute = float(chosen["slot"]) - lead
		else:
			assert(false, "Events.generate: unknown event type " + type_name)
		event["at_minute"] = at_minute
		events.append(event)
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["at_minute"] != b["at_minute"]:
			return a["at_minute"] < b["at_minute"]
		return a["id"] < b["id"])
	return events


## Every departure slot of every line, both directions, in Timetable generation
## order: slot = first_departure_minutes + k * frequency_minutes while
## slot < first_departure_minutes + horizon_minutes.
static func _all_slots(network: Dictionary, horizon_minutes: float) -> Array:
	var slots: Array = []  # {train_id: String, slot: float}
	for line in network["lines"]:
		var first: float = float(line["first_departure_minutes"])
		var frequency: float = float(line["frequency_minutes"])
		var k: int = 0
		var slot: float = first
		while slot < first + horizon_minutes:
			slots.append({"train_id": "%s-F-%d" % [line["id"], k], "slot": slot})
			slots.append({"train_id": "%s-R-%d" % [line["id"], k], "slot": slot})
			k += 1
			slot = first + k * frequency
	return slots


static func _pick_type(types_config: Dictionary, type_names: Array,
		rng: RandomNumberGenerator) -> String:
	var total_weight: float = 0.0
	for type_name: String in type_names:
		total_weight += float(types_config[type_name]["weight"])
	var roll: float = rng.randf() * total_weight
	var cumulative: float = 0.0
	for type_name: String in type_names:
		cumulative += float(types_config[type_name]["weight"])
		if roll < cumulative:
			return type_name
	return type_names[type_names.size() - 1]
