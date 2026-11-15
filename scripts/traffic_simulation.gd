extends RefCounted

signal switch_changed
signal warning_created
signal train_spawned(train)

const Simulation = preload("res://scripts/cart_simulation.gd")
const CONFIG_PATH = "res://config/traffic.json"

var cart
var trains: Array = []
var config: Dictionary
var elapsed := 0.0
var lost := false
var won := false
var loss_reason := ""
var loss_position := Vector2.ZERO
var warnings: Array = []
var rng := RandomNumberGenerator.new()
var _until_warning: float
var _scheduler_at := 0.0
var _warning_at := INF
var _announcement_at := INF
var _admitted_total := 0
var _admitted_threats := 0
var _candidate_train
var _loss_candidate := false


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
	loss_position = Vector2.ZERO
	_admitted_total = 0
	_admitted_threats = 0
	_candidate_train = null
	_loss_candidate = false
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
	switch_changed.emit()
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
		var copy = _copy_vehicle(train, forecast.cart.switches)
		forecast.trains.append(copy)
		if train == _candidate_train:
			forecast._candidate_train = copy
	return forecast


func _entry_safe(entry: String, lead: float, defer_conflicting: bool = false) -> bool:
	return _entry_assessment(entry, lead, defer_conflicting).safe


func _entry_assessment(entry: String, lead: float, defer_conflicting: bool = false) -> Dictionary:
	var unsafe := {"safe": false, "threatening": false}
	if elapsed + lead >= config.round_duration:
		return unsafe
	var budget := {"remaining": int(config.guard_motion_events), "exhausted": false}
	var forecast = _forecast()
	var plans: Array = [{"entry": entry, "at": elapsed + lead, "candidate": true}]
	var admitted: Array = []
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
		forecast._advance_to(plan.at, false, budget)
		if forecast.lost or budget.exhausted:
			return unsafe
		if forecast.won:
			return unsafe
		var candidate = forecast._entry_train(plan.entry)
		if forecast._footprint_clear(candidate):
			if defer_conflicting and not plan.candidate:
				# A due spawn has priority over an incompatible hypothetical arrival.
				# Its later retry will see the admitted train as actual traffic.
				var joint = forecast._forecast()
				joint.trains.append(joint._entry_train(plan.entry))
				joint._advance_to(latest + config.safety_duration, false, budget)
				if budget.exhausted:
					return unsafe
				if joint.lost:
					continue
			forecast.trains.append(candidate)
			if plan.candidate:
				forecast._candidate_train = candidate
			admitted.append(plan)
		elif plan.candidate or not defer_conflicting:
			return unsafe
	forecast._advance_to(latest + config.safety_duration, false, budget)
	if forecast.lost or budget.exhausted:
		return unsafe
	return _maneuver_assessment(admitted, latest, budget)


func _guard_itinerary(vehicle, start: float, deadline: float, react_at: float, extend_first: bool = false, after_choice: float = -INF) -> Dictionary:
	if vehicle.config.speed <= 0.0:
		return {}
	var probe = _copy_vehicle(vehicle, vehicle.switches.duplicate())
	var at := start
	var decisions: Array = []
	var found_first := false
	for iteration in range(int(config.guard_route_iterations)):
		var distance: float = probe.distance_to_event()
		if not is_finite(distance) or distance < 0.0:
			return {}
		var arrival: float = at + distance / probe.config.speed
		if probe.switches.has(probe.to_node):
			var ports: Array = probe.config.switches[probe.to_node].ports
			if probe.from_node == ports[0]:
				var front_at: float = arrival - probe.config.cart_length / (2.0 * probe.config.speed)
				var click_at: float = front_at - config.guard_reaction_time
				if click_at >= react_at + config.guard_reaction_time and click_at > after_choice:
					var clear_at: float = arrival + probe.config.cart_length / (2.0 * probe.config.speed)
					decisions.append({"id": probe.to_node, "at": click_at, "clear_at": clear_at})
					if extend_first and not found_first:
						deadline = maxf(deadline, clear_at + config.safety_duration)
					found_first = true
		if arrival >= deadline and (not extend_first or not decisions.is_empty()):
			return {"deadline": deadline, "decisions": decisions}
		at = arrival
		probe.advance_distance(distance)
		if probe.lost:
			return {"deadline": maxf(deadline, at) if extend_first else deadline, "decisions": decisions}
	return {}


func _guard_replay(forecast, plans: Array, deadline: float, budget: Dictionary) -> bool:
	while not plans.is_empty() and plans[0].at <= deadline:
		var plan: Dictionary = plans.pop_front()
		forecast._advance_to(plan.at, false, budget)
		if forecast.lost or budget.exhausted:
			return false
		if forecast.won:
			return true
		var train = forecast._entry_train(plan.entry)
		if not forecast._footprint_clear(train):
			return false
		forecast.trains.append(train)
		if plan.candidate:
			forecast._candidate_train = train
	forecast._advance_to(deadline, false, budget)
	return not forecast.lost and not budget.exhausted


func _maneuver_assessment(plans: Array, latest: float, budget: Dictionary) -> Dictionary:
	var unsafe := {"safe": false, "threatening": false}
	var deadline: float = latest + config.pressure_horizon
	# Choices passed before the candidate arrives cannot excuse an already boxed cart.
	var at_spawn = _forecast()
	var pending: Array = plans.duplicate()
	var spawn_at := elapsed
	for plan in plans:
		if plan.candidate:
			spawn_at = plan.at
	if not _guard_replay(at_spawn, pending, spawn_at, budget):
		return unsafe
	deadline = _guard_deadline(at_spawn.cart, spawn_at, plans, deadline, budget)
	if not is_finite(deadline):
		return unsafe
	var noop = _forecast()
	if _guard_replay(noop, plans.duplicate(), deadline, budget):
		return {"safe": true, "threatening": false}
	if budget.exhausted:
		return unsafe
	var conflict_at: float = noop.elapsed
	var attempts := {"remaining": int(config.guard_attempts) - 1}
	var safe := _guard_witness(_forecast(), plans, conflict_at, conflict_at + config.safety_duration, int(config.guard_max_changes), attempts, budget, [])
	return {"safe": safe, "threatening": safe and noop.loss_reason == "cart_train" and noop._loss_candidate}


func _guard_deadline(vehicle, start: float, plans: Array, deadline: float, budget: Dictionary) -> float:
	var after_choice := -INF
	for iteration in range(int(config.guard_route_iterations)):
		var itinerary := _guard_itinerary(vehicle, start, deadline, elapsed, true, after_choice)
		if itinerary.is_empty():
			return INF
		deadline = itinerary.deadline
		if itinerary.decisions.is_empty():
			# The shared replay must reject the cart exit (unless the round wins first).
			return deadline
		var decision: Dictionary = itinerary.decisions[0]
		var probe = _forecast()
		if not _guard_replay(probe, plans.duplicate(), decision.at, budget):
			# A conflict before the choice requires a witness, not a no-op approval.
			return INF if budget.exhausted else deadline
		if not probe.is_locked(decision.id):
			return deadline
		after_choice = decision.at
	return INF


func _guard_decisions(plans: Array, deadline: float, budget: Dictionary) -> Dictionary:
	var decisions: Array = []
	for vehicle in [cart] + trains:
		var itinerary := _guard_itinerary(vehicle, elapsed, deadline, elapsed)
		if itinerary.is_empty():
			return {}
		decisions.append_array(itinerary.decisions)
	var arrivals = _forecast()
	var pending: Array = plans.duplicate()
	for plan in plans:
		if plan.at >= deadline:
			break
		if not _guard_replay(arrivals, pending, plan.at, budget):
			if budget.exhausted:
				return {}
			break
		var train = arrivals._entry_train(plan.entry)
		var itinerary := _guard_itinerary(train, plan.at, deadline, elapsed)
		if itinerary.is_empty():
			return {}
		decisions.append_array(itinerary.decisions)
	decisions.sort_custom(func(a, b): return a.at < b.at)
	return {"decisions": decisions}


func _guard_witness(base, plans: Array, conflict_at: float, deadline: float, changes: int, attempts: Dictionary, budget: Dictionary, selected: Array) -> bool:
	if changes <= 0 or attempts.remaining <= 0 or budget.exhausted:
		return false
	var choices: Dictionary = base._guard_decisions(plans, conflict_at, budget)
	if choices.is_empty():
		return false
	var seen: Dictionary = {}
	for decision in choices.decisions:
		if decision.at >= conflict_at or attempts.remaining <= 0 or budget.exhausted:
			break
		var key: String = decision.id + ":" + str(decision.at)
		if seen.has(key):
			continue
		seen[key] = true
		attempts.remaining -= 1
		var witness = base._forecast()
		var pending: Array = plans.duplicate()
		if not _guard_replay(witness, pending, decision.at, budget):
			continue
		# Shared front/rear locks are checked at the click, never in the live state.
		if not witness.toggle(decision.id):
			continue
		var changed_ids: Array = selected.duplicate()
		changed_ids.append(decision.id)
		var changed = witness._forecast()
		var changed_deadline: float = maxf(deadline, decision.clear_at + config.safety_duration)
		var changed_pending: Array = pending.duplicate()
		var safe := _guard_replay(changed, changed_pending, changed_deadline, budget)
		var locked := false
		for id in changed_ids:
			locked = locked or changed.is_locked(id)
		if safe and locked and not changed.won:
			var clearance := 0.0
			for vehicle in [changed.cart] + changed.trains:
				if vehicle.config.speed <= 0.0:
					return false
				clearance = maxf(clearance, vehicle.config.cart_length / vehicle.config.speed)
			changed_deadline += clearance + config.safety_duration
			safe = _guard_replay(changed, changed_pending, changed_deadline, budget)
			locked = false
			for id in changed_ids:
				locked = locked or changed.is_locked(id)
		if safe and (changed.won or not locked):
			return true
		if not safe and not budget.exhausted and _guard_witness(witness, pending, changed.elapsed, maxf(changed_deadline, changed.elapsed + config.safety_duration), changes - 1, attempts, budget, changed_ids):
			return true
	return false


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
		var assessment := {"safe": false, "threatening": false}
		if _footprint_clear(candidate):
			assessment = _entry_assessment(warning.entry, 0.0, true)
		if assessment.safe:
			trains.append(candidate)
			_admitted_total += 1
			if assessment.threatening:
				_admitted_threats += 1
			warnings.erase(warning)
			_announcement_at = elapsed + lerpf(config.initial_interval, config.final_interval, clampf(elapsed / config.scaling_horizon, 0.0, 1.0))
			train_spawned.emit(candidate)
		else:
			warning.check_at = elapsed + config.retry_interval
	var announced := 0
	while warnings.size() < _warning_limit() and elapsed >= _announcement_at:
		var arrival: float = elapsed + config.warning_duration + announced * config.warning_stagger
		for warning in warnings:
			arrival = maxf(arrival, warning.check_at + config.warning_stagger)
		var reactive: Array = []
		var ambient: Array = []
		var reserved_total := _admitted_total + warnings.size()
		var reserved_threats := _admitted_threats
		for warning in warnings:
			if warning.get("threatening", false):
				reserved_threats += 1
		var prefer_threat: bool = reserved_total == 0 or reserved_threats < config.pressure_target_fraction * reserved_total
		var weights: Array[float] = []
		var total := 0.0
		for entry in cart.config.exits:
			var pending := false
			for warning in warnings:
				if warning.entry == entry:
					pending = true
			if not pending:
				var assessment := _entry_assessment(entry, arrival - elapsed)
				if assessment.safe:
					var record := {"entry": entry, "threatening": assessment.threatening}
					if assessment.threatening:
						reactive.append(record)
					else:
						ambient.append(record)
		var eligible: Array = reactive if prefer_threat else ambient
		if eligible.is_empty():
			eligible = ambient if prefer_threat else reactive
		if eligible.is_empty():
			_announcement_at = elapsed + config.retry_interval
			break
		for record in eligible:
			var weight := _pressure_weight(record.entry)
			weights.append(weight)
			total += weight
		var draw := rng.randf() * total
		var chosen: Dictionary = eligible.back()
		for i in range(eligible.size()):
			draw -= weights[i]
			if draw < 0.0:
				chosen = eligible[i]
				break
		warnings.append({"entry": chosen.entry, "threatening": chosen.threatening, "remaining": arrival - elapsed, "spawn_at": arrival, "check_at": arrival})
		warning_created.emit()
		announced += 1
	_sync_schedule()


func advance(delta: float) -> void:
	if lost or won or delta <= 0.0 or not is_finite(delta):
		return
	_advance_to(elapsed + delta, config.spawning_enabled)


func _advance_to(deadline: float, spawning: bool, budget: Dictionary = {}) -> void:
	while not lost and not won:
		if not budget.is_empty():
			if budget.remaining <= 0:
				budget.exhausted = true
				return
			budget.remaining -= 1
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
		var collision_candidate := false
		var collision_pair: Array = []
		for i in range(vehicles.size()):
			for j in range(i + 1, vehicles.size()):
				var interval := _contact_interval(vehicles[i], vehicles[j], _velocity(vehicles[i]), _velocity(vehicles[j]), step)
				if interval[0] <= step:
					step = interval[0]
					event_at = elapsed + step
					collision = "cart_train" if i == 0 else "train_train"
					collision_candidate = vehicles[i] == _candidate_train or vehicles[j] == _candidate_train
					collision_pair = [vehicles[i], vehicles[j]]
		for vehicle in vehicles:
			var distance: float = vehicle.distance_to_event()
			var travel: float = step * vehicle.config.speed
			if vehicle.config.speed > 0.0 and elapsed + distance / vehicle.config.speed <= event_at:
				travel = distance
			vehicle.advance_distance(travel)
		elapsed = event_at
		if spawning:
			_sync_schedule()
		if not collision.is_empty():
			lost = true
			loss_reason = collision
			_loss_candidate = collision_candidate
			loss_position = (collision_pair[0].cart_position() + collision_pair[1].cart_position()) / 2.0
		# Check node rotations even when the caller's delta ends at this event.
		vehicles = [cart] + trains
		if not lost:
			for i in range(vehicles.size()):
				for j in range(i + 1, vehicles.size()):
					if _contact_interval(vehicles[i], vehicles[j], Vector2.ZERO, Vector2.ZERO, 0.0)[0] == 0.0:
						lost = true
						loss_reason = "cart_train" if i == 0 else "train_train"
						_loss_candidate = vehicles[i] == _candidate_train or vehicles[j] == _candidate_train
						loss_position = (vehicles[i].cart_position() + vehicles[j].cart_position()) / 2.0
		if not lost and cart.lost:
			lost = true
			loss_reason = "cart_exit"
			_loss_candidate = false
			loss_position = cart.point(cart.to_node)
		if not lost:
			for i in range(trains.size() - 1, -1, -1):
				if trains[i].lost:
					trains.remove_at(i)
	if lost:
		_sync_schedule()
