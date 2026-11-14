extends RefCounted

const CONFIG_PATH = "res://config/cart_prototype.json"

var config: Dictionary
var switches: Dictionary = {}
var rear_locks: Dictionary = {}
var from_node: String
var to_node: String
var progress: float
var lost := false
var exits_safely := false
var start_index: int
var rng := RandomNumberGenerator.new()


func _init(vehicle_config: Dictionary = {}) -> void:
	config = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH)) if vehicle_config.is_empty() else vehicle_config
	rng.randomize()
	restart()


func point(id: String) -> Vector2:
	var xy: Array = config.nodes[id]
	return Vector2(xy[0], xy[1])


func edge_length() -> float:
	return point(from_node).distance_to(point(to_node))


func cart_position() -> Vector2:
	return point(from_node).lerp(point(to_node), progress / edge_length())


func heading() -> Vector2:
	return (point(to_node) - point(from_node)).normalized()


func restart(chosen_start: int = -1) -> void:
	switches.clear()
	for id in config.switches:
		switches[id] = int(config.switches[id].initial)
	rear_locks.clear()
	lost = false
	start_index = rng.randi_range(0, config.starts.size() - 1) if chosen_start < 0 else chosen_start
	var start: Dictionary = config.starts[start_index]
	from_node = start.from
	to_node = start.to
	progress = start.progress


func is_locked(id: String) -> bool:
	return rear_locks.has(id) or (to_node == id and edge_length() - progress <= config.cart_length / 2.0)


func toggle(id: String) -> bool:
	if lost or not switches.has(id) or is_locked(id):
		return false
	switches[id] = 1 - switches[id]
	return true


func route(id: String, incoming: String) -> String:
	# Ports are [stem, straight, branch]. Both trailing entries go to the stem;
	# the selected setting only chooses the stem's departure, never a U-turn.
	var ports: Array = config.switches[id].ports
	if incoming == ports[0]:
		return ports[1 + switches[id]]
	return ports[0]


func advance(delta: float) -> void:
	if lost or delta <= 0.0 or not is_finite(delta):
		return
	advance_distance(delta * config.speed)


func distance_to_event() -> float:
	var end_progress := edge_length()
	if to_node in config.exits:
		end_progress += config.cart_length / 2.0 * (1.0 if exits_safely else -1.0)
	return maxf(0.0, end_progress - progress)


func advance_distance(remaining: float) -> void:
	if lost or remaining < 0.0 or not is_finite(remaining):
		return
	while not lost:
		var is_exit: bool = to_node in config.exits
		var distance := distance_to_event()
		var travel := minf(remaining, distance)
		progress += travel
		remaining -= travel
		for id in rear_locks.keys():
			rear_locks[id] -= travel
			if rear_locks[id] <= 0.0:
				rear_locks.erase(id)
		if travel < distance:
			break
		if is_exit:
			lost = true
			break
		var arrived := to_node
		if arrived in config.buffers:
			to_node = from_node
		else:
			to_node = route(arrived, from_node)
			rear_locks[arrived] = config.cart_length / 2.0
		from_node = arrived
		progress = 0.0
		if remaining <= 0.0:
			break
