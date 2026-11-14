extends RefCounted

const Simulation = preload("res://scripts/cart_simulation.gd")
const CONFIG_PATH = "res://config/traffic.json"

var cart = Simulation.new()
var trains: Array = []
var config: Dictionary
var elapsed := 0.0
var lost := false
var loss_reason := ""
var warnings: Array = []
var rng := RandomNumberGenerator.new()
var _until_warning: float


func _init() -> void:
	config = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	rng.randomize()
	restart()


func restart() -> void:
	trains.clear()
	warnings.clear()
	elapsed = 0.0
	lost = false
	loss_reason = ""
	_until_warning = config.first_warning_delay
	cart.restart()


func is_locked(id: String) -> bool:
	if cart.is_locked(id):
		return true
	for train in trains:
		if train.is_locked(id):
			return true
	return false


func toggle(id: String) -> bool:
	if lost or not cart.switches.has(id) or is_locked(id):
		return false
	cart.switches[id] = 1 - cart.switches[id]
	return true


func _entry_train(entry: String):
	# Only the scalar vehicle settings differ; topology dictionaries/arrays stay shared.
	var train = Simulation.new(cart.config.duplicate())
	for key in config.train:
		train.config[key] = config.train[key]
	train.switches = cart.switches
	train.exits_safely = true
	train.from_node = entry
	for edge in cart.config.edges:
		if entry in edge:
			train.to_node = edge[1] if edge[0] == entry else edge[0]
			break
	train.progress = 0.0
	train.rear_locks.clear()
	return train


# SAT intervals are exact while headings are fixed. As in the cart prototype,
# a rigid vehicle rotates instantly at a node, rather than bending along its route.
func _contact_interval(a, b, velocity_a: Vector2, velocity_b: Vector2, duration: float, margin: float = 0.0) -> Array[float]:
	var ah: Vector2 = a.heading()
	var bh: Vector2 = b.heading()
	var ap := ah.orthogonal()
	var bp := bh.orthogonal()
	var offset: Vector2 = b.cart_position() - a.cart_position()
	var velocity := velocity_b - velocity_a
	var enter := 0.0
	var leave := duration
	for axis in [ah, ap, bh, bp]:
		var radius: float = (absf(axis.dot(ah)) * a.config.cart_length + absf(axis.dot(ap)) * a.config.cart_width + absf(axis.dot(bh)) * b.config.cart_length + absf(axis.dot(bp)) * b.config.cart_width) / 2.0 + margin
		var separation: float = offset.dot(axis)
		var speed: float = velocity.dot(axis)
		if speed == 0.0:
			if absf(separation) > radius:
				return [INF, -INF]
			continue
		var first: float = (-radius - separation) / speed
		var last: float = (radius - separation) / speed
		enter = maxf(enter, minf(first, last))
		leave = minf(leave, maxf(first, last))
		if enter > leave:
			return [INF, -INF]
	return [enter, leave]


func _velocity(vehicle) -> Vector2:
	return vehicle.heading() * vehicle.config.speed


func advance(delta: float) -> void:
	if lost or delta <= 0.0 or not is_finite(delta):
		return
	var remaining := delta
	while not lost:
		var vehicles: Array = [cart] + trains
		var step := remaining
		for vehicle in vehicles:
			if vehicle.config.speed > 0.0:
				step = minf(step, vehicle.distance_to_event() / vehicle.config.speed)
		var spawning: bool = config.spawning_enabled
		if spawning:
			if warnings.is_empty():
				step = minf(step, maxf(0.0, _until_warning))
			elif warnings[0].remaining > 0.0:
				step = minf(step, warnings[0].remaining)
			else:
				var candidate = _entry_train(warnings[0].entry)
				var occupied := false
				var clearance := 0.0
				for vehicle in vehicles:
					if _contact_interval(candidate, vehicle, Vector2.ZERO, Vector2.ZERO, 0.0)[0] == 0.0:
						occupied = true
						var interval := _contact_interval(candidate, vehicle, Vector2.ZERO, _velocity(vehicle), step, config.spawn_clearance)
						clearance = maxf(clearance, interval[1])
				if not occupied:
					trains.append(candidate)
					warnings.clear()
					_until_warning = lerpf(config.initial_interval, config.final_interval, clampf(elapsed / config.scaling_horizon, 0.0, 1.0))
					continue
				if clearance > 0.0:
					step = minf(step, clearance)
		if remaining <= 0.0:
			break
		var collision := ""
		for i in range(vehicles.size()):
			for j in range(i + 1, vehicles.size()):
				var interval := _contact_interval(vehicles[i], vehicles[j], _velocity(vehicles[i]), _velocity(vehicles[j]), step)
				if interval[0] <= step:
					step = interval[0]
					collision = "cart_train" if i == 0 else "train_train"
		for vehicle in vehicles:
			var distance: float = vehicle.distance_to_event()
			var travel: float = step * vehicle.config.speed
			if vehicle.config.speed > 0.0 and distance / vehicle.config.speed <= step:
				travel = distance
			vehicle.advance_distance(travel)
		elapsed += step
		remaining -= step
		if spawning:
			if warnings.is_empty():
				_until_warning -= step
				if _until_warning <= 0.0:
					warnings.append({"entry": cart.config.exits[rng.randi_range(0, cart.config.exits.size() - 1)], "remaining": config.warning_duration})
			else:
				warnings[0].remaining = maxf(0.0, warnings[0].remaining - step)
		if not collision.is_empty() or cart.lost:
			lost = true
			loss_reason = collision if not collision.is_empty() else "cart_exit"
		for i in range(trains.size() - 1, -1, -1):
			if trains[i].lost:
				trains.remove_at(i)
		# Check node rotations even when the caller's delta ends at this event.
		vehicles = [cart] + trains
		if not lost:
			for i in range(vehicles.size()):
				for j in range(i + 1, vehicles.size()):
					if _contact_interval(vehicles[i], vehicles[j], Vector2.ZERO, Vector2.ZERO, 0.0)[0] == 0.0:
						lost = true
						loss_reason = "cart_train" if i == 0 else "train_train"
