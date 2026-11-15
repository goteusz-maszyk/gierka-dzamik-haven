extends RefCounted

const Simulation = preload("res://scripts/cart_simulation.gd")
const CONFIG_PATH = "res://config/traffic.json"

var cart
var trains: Array = []
var config: Dictionary
var elapsed := 0.0
var lost := false
var won := false
var loss_reason := ""
var warnings: Array = []
var rng := RandomNumberGenerator.new()
var _until_warning: float
var _scheduler_at := 0.0
var _warning_at := INF
var _announcement_at := INF


func _init(initialize: bool = true) -> void:
	if not initialize:
		return
	cart = Simulation.new()
	config = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	rng.randomize()
	restart()


func restart() -> void:
	trains.clear()
	warnings.clear()
	elapsed = 0.0
	lost = false
	won = false
	loss_reason = ""
	_until_warning = config.first_warning_delay
	_scheduler_at = _until_warning
	_announcement_at = _scheduler_at
	_warning_at = INF
	cart.restart()


func is_locked(id: String) -> bool:
	if cart.is_locked(id):
		return true
	for train in trains:
		if train.is_locked(id):
			return true
	return false


func remaining_time() -> float:
	return maxf(0.0, config.round_duration - elapsed)


func is_clearing() -> bool:
	return elapsed >= config.round_duration


func toggle(id: String) -> bool:
	if lost or won or not cart.switches.has(id) or is_locked(id):
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
	# Keep longitudinal arithmetic in doubles, not Vector2's single precision.
	var ax: float = a.point(a.from_node).x + ah.x * a.progress
	var ay: float = a.point(a.from_node).y + ah.y * a.progress
	var bx: float = b.point(b.from_node).x + bh.x * b.progress
	var by: float = b.point(b.from_node).y + bh.y * b.progress
	var velocity := velocity_b - velocity_a
	var enter := 0.0
	var leave := duration
	for axis in [ah, ap, bh, bp]:
		var radius: float = (absf(axis.dot(ah)) * a.config.cart_length + absf(axis.dot(ap)) * a.config.cart_width + absf(axis.dot(bh)) * b.config.cart_length + absf(axis.dot(bp)) * b.config.cart_width) / 2.0 + margin
		var separation: float = (bx - ax) * axis.x + (by - ay) * axis.y
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


func _copy_vehicle(vehicle, switches: Dictionary):
	var copy = Simulation.new(vehicle.config.duplicate())
	copy.switches = switches
	copy.rear_locks = vehicle.rear_locks.duplicate()
	copy.from_node = vehicle.from_node
	copy.to_node = vehicle.to_node
	copy.progress = vehicle.progress
	copy.lost = vehicle.lost
	copy.exits_safely = vehicle.exits_safely
	return copy


func _footprint_clear(candidate) -> bool:
	for vehicle in [cart] + trains:
		if _contact_interval(candidate, vehicle, Vector2.ZERO, Vector2.ZERO, 0.0)[0] == 0.0:
			return false
	return true


func _forecast():
	var forecast = get_script().new(false)
	forecast.config = config.duplicate()
	forecast.elapsed = elapsed
	forecast.cart = _copy_vehicle(cart, cart.switches.duplicate())
	for train in trains:
		forecast.trains.append(_copy_vehicle(train, forecast.cart.switches))
	return forecast


func _entry_safe(entry: String, lead: float, defer_conflicting: bool = false) -> bool:
	if elapsed + lead >= config.round_duration:
		return false
	var forecast = _forecast()
	var plans: Array = [{"entry": entry, "at": elapsed + lead, "candidate": true}]
	var latest := elapsed + lead
	for warning in warnings:
		if warning.entry == entry:
			continue
		var at: float = maxf(elapsed, warning.get("check_at", elapsed + warning.remaining))
		if at >= config.round_duration:
			continue
		plans.append({"entry": warning.entry, "at": at, "candidate": false})
		latest = maxf(latest, at)
	plans.sort_custom(func(a, b): return a.at < b.at or (a.at == b.at and a.candidate and not b.candidate))
	for plan in plans:
		forecast._advance_to(plan.at, false)
		if forecast.lost:
			return false
		if forecast.won:
			return true
		var candidate = forecast._entry_train(plan.entry)
		if forecast._footprint_clear(candidate):
			if defer_conflicting and not plan.candidate:
				# A due spawn has priority over an incompatible hypothetical arrival.
				# Its later retry will see the admitted train as actual traffic.
				var joint = forecast._forecast()
				joint.trains.append(joint._entry_train(plan.entry))
				joint._advance_to(latest + config.safety_duration, false)
				if joint.lost:
					continue
			forecast.trains.append(candidate)
		elif plan.candidate:
			return false
	forecast._advance_to(latest + config.safety_duration, false)
	return not forecast.lost


func _pressure_weight(entry: String) -> float:
	var rows: Array = []
	for track in cart.config.get("tracks", []):
		if cart.from_node in track.nodes or cart.to_node in track.nodes:
			rows.append(track.nodes)
	var candidate = _entry_train(entry)
	candidate.switches = cart.switches.duplicate()
	# The horizon is train travel time, excluding the warning lead.
	var remaining: float = config.pressure_horizon * candidate.config.speed
	while not candidate.lost:
		for row in rows:
			if candidate.from_node in row:
				return config.pressure_weight
		if remaining <= 0.0:
			break
		var distance: float = candidate.distance_to_event()
		var travel := minf(remaining, distance)
		candidate.advance_distance(travel)
		remaining -= travel
		if travel < distance:
			break
	return 1.0


func _warning_limit() -> int:
	return int(config.initial_max_warnings) if elapsed < config.double_warning_after else int(config.max_warnings)


func _sync_schedule() -> void:
	if lost or won or is_clearing():
		warnings.clear()
		_announcement_at = INF
		_warning_at = INF
		_scheduler_at = INF
		_until_warning = INF
		return
	_warning_at = INF
	_scheduler_at = _announcement_at if warnings.size() < _warning_limit() else INF
	if not lost and not won and elapsed < config.double_warning_after:
		_scheduler_at = minf(_scheduler_at, config.double_warning_after)
	for warning in warnings:
		warning.remaining = maxf(0.0, warning.spawn_at - elapsed)
		_warning_at = minf(_warning_at, warning.spawn_at)
		_scheduler_at = minf(_scheduler_at, warning.check_at)
	_until_warning = maxf(0.0, _scheduler_at - elapsed)


func _schedule() -> void:
	if lost or won or is_clearing():
		_sync_schedule()
		return
	for warning in warnings:
		if not warning.has("spawn_at"):
			warning.spawn_at = elapsed + warning.remaining
		if not warning.has("check_at"):
			warning.check_at = warning.spawn_at
	for warning in warnings.duplicate():
		if elapsed < warning.check_at:
			continue
		var candidate = _entry_train(warning.entry)
		if _footprint_clear(candidate) and _entry_safe(warning.entry, 0.0, true):
			trains.append(candidate)
			warnings.erase(warning)
			_announcement_at = elapsed + lerpf(config.initial_interval, config.final_interval, clampf(elapsed / config.scaling_horizon, 0.0, 1.0))
		else:
			warning.check_at = elapsed + config.retry_interval
	var announced := 0
	while warnings.size() < _warning_limit() and elapsed >= _announcement_at:
		var arrival: float = elapsed + config.warning_duration + announced * config.warning_stagger
		for warning in warnings:
			arrival = maxf(arrival, warning.check_at + config.warning_stagger)
		var eligible: Array = []
		var weights: Array[float] = []
		var total := 0.0
		for entry in cart.config.exits:
			var pending := false
			for warning in warnings:
				if warning.entry == entry:
					pending = true
			if not pending and _entry_safe(entry, arrival - elapsed):
				eligible.append(entry)
				var weight := _pressure_weight(entry)
				weights.append(weight)
				total += weight
		if eligible.is_empty():
			_announcement_at = elapsed + config.retry_interval
			break
		var draw := rng.randf() * total
		var chosen: String = eligible.back()
		for i in range(eligible.size()):
			draw -= weights[i]
			if draw < 0.0:
				chosen = eligible[i]
				break
		warnings.append({"entry": chosen, "remaining": arrival - elapsed, "spawn_at": arrival, "check_at": arrival})
		announced += 1
	_sync_schedule()


func advance(delta: float) -> void:
	if lost or won or delta <= 0.0 or not is_finite(delta):
		return
	_advance_to(elapsed + delta, config.spawning_enabled)


func _advance_to(deadline: float, spawning: bool) -> void:
	while not lost and not won:
		if is_clearing():
			_sync_schedule()
			if trains.is_empty():
				won = true
				break
		elif spawning:
			_schedule()
		if elapsed >= deadline:
			break
		var vehicles: Array = [cart] + trains
		var event_at := deadline
		if not is_clearing():
			event_at = minf(event_at, config.round_duration)
		for vehicle in vehicles:
			if vehicle.config.speed > 0.0:
				event_at = minf(event_at, elapsed + vehicle.distance_to_event() / vehicle.config.speed)
		if spawning:
			event_at = minf(event_at, _scheduler_at)
		var step := maxf(0.0, event_at - elapsed)
		var collision := ""
		for i in range(vehicles.size()):
			for j in range(i + 1, vehicles.size()):
				var interval := _contact_interval(vehicles[i], vehicles[j], _velocity(vehicles[i]), _velocity(vehicles[j]), step)
				if interval[0] <= step:
					step = interval[0]
					event_at = elapsed + step
					collision = "cart_train" if i == 0 else "train_train"
		for vehicle in vehicles:
			var distance: float = vehicle.distance_to_event()
			var travel: float = step * vehicle.config.speed
			if vehicle.config.speed > 0.0 and elapsed + distance / vehicle.config.speed <= event_at:
				travel = distance
			vehicle.advance_distance(travel)
		elapsed = event_at
		if spawning:
			_sync_schedule()
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
	if lost:
		_sync_schedule()
