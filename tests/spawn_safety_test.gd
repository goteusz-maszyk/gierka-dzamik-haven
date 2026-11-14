extends SceneTree

const Traffic = preload("res://scripts/traffic_simulation.gd")
const Motion = preload("res://scripts/cart_simulation.gd")
var data: Dictionary
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)


func fresh():
	var sim = Traffic.new()
	sim.cart = Motion.new(data.vehicle.duplicate(true))
	sim.cart.config.merges = {}
	# Restricting spawn entries below must not leave the other terminal unroutable.
	sim.cart.config.buffers.append_array(data.vehicle.exits)
	sim.config.train = data.train.duplicate()
	sim.config.spawning_enabled = false
	var mechanics: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/traffic_test_cases.json"))
	sim.config.merge(mechanics.single_warning, true)
	sim.config.round_duration = mechanics.low_level_round_duration
	sim.rng.seed = int(data.seed)
	return sim


func train_at(sim, source: String, target: String, progress: float, speed: float):
	var train = sim._entry_train(sim.cart.config.exits[0])
	train.from_node = source
	train.to_node = target
	train.progress = progress
	train.config.speed = speed
	sim.trains.append(train)
	return train


func small_advance(sim, duration: float) -> void:
	var target: float = sim.elapsed + duration
	while sim.elapsed < target and not sim.lost and not sim.won:
		var before: float = sim.elapsed
		sim.advance(minf(data.small_step, target - sim.elapsed))
		if sim.elapsed <= before and not sim.lost and not sim.won:
			check(false, "Small-step safety simulation must advance or finish")
			break


func state(sim) -> Array:
	var result: Array = [sim.elapsed, sim.lost, sim.won, sim.loss_reason, sim.rng.state, sim.cart.rng.state, sim.cart.switches.duplicate(), sim.warnings.duplicate(true), sim._announcement_at, sim._scheduler_at, sim._warning_at, sim._until_warning]
	for vehicle in [sim.cart] + sim.trains:
		result.append([vehicle.from_node, vehicle.to_node, vehicle.progress, vehicle.rear_locks.duplicate(), vehicle.lost, vehicle.rng.state])
	return result


func test_forecasts() -> void:
	var sim = fresh()
	train_at(sim, "J", "L", data.head_on_progress, data.train.speed)
	check(sim._footprint_clear(sim._entry_train("L")), "Head-on entry is free now")
	var before := state(sim)
	check(not sim._entry_safe("L", 0.0), "Swept head-on approach is rejected")
	check(sim._entry_safe("R", 0.0), "Separated entry is eligible")
	check(state(sim) == before, "Both forecasts leave live motion, locks, switches, RNG and scheduling untouched")
	check(sim._entry_safe("L", sim.config.warning_duration), "Candidate is absent during lead while outward traffic clears")
	sim.trains[0].config.speed = data.slow_speed
	sim.config.spawning_enabled = true
	sim._announcement_at = sim.elapsed
	sim.advance(data.small_step)
	check(sim.warnings.size() == 1 and sim.warnings[0].entry == "R", "Warning selects only safe entries")
	sim = fresh()
	train_at(sim, "L", "J", data.catch_up_progress, data.slow_speed)
	check(sim._footprint_clear(sim._entry_train("L")) and not sim._entry_safe("L", 0.0), "Clear footprint still rejects a forecast catch-up collision")
	sim = fresh()
	train_at(sim, "J", "L", data.departing_tail_progress, 0.0)
	check(not sim._footprint_clear(sim._entry_train("L")) and not sim._entry_safe("L", 0.0), "Departing tail blocks spawn after its center leaves")
	sim = fresh()
	train_at(sim, "J", "R", data.junction_blocker_progress, 0.0)
	check(not sim._entry_safe("L", 0.0), "Blocked junction is unsafe despite empty entry")
	sim.cart.switches.J = 1
	check(sim._entry_safe("L", 0.0), "Switch branch avoids blocked straight route")
	sim = fresh()
	sim.cart.switches.J = 1
	sim.cart.from_node = "J"
	sim.cart.to_node = "B"
	sim.cart.progress = data.buffer_cart_progress
	sim.cart.config.speed = data.train.speed
	check(sim._footprint_clear(sim._entry_train("L")), "Buffer scenario starts with a clear footprint")
	check(not sim._entry_safe("L", 0.0), "Forecast follows cart buffer reversal into entering train")
	sim = fresh()
	train_at(sim, "L", "J", data.junction_blocker_progress, 0.0)
	check(not sim._entry_safe("L", sim.config.warning_duration), "Candidate does not move during warning lead time")
	sim = fresh()
	train_at(sim, "J", "L", data.head_on_progress, data.train.speed)
	sim.cart.from_node = "L"
	sim.cart.to_node = "J"
	sim.cart.progress = 0.0
	sim.cart.config.speed = data.train.speed
	check(not sim._entry_safe("R", sim.config.warning_duration), "Preexisting collision during lead rejects even remote entry")
	sim = fresh()
	var blocker = train_at(sim, "J", "R", data.late_collision_distance, 0.0)
	check(sim._entry_safe("L", 0.0), "No guarantee beyond configured two seconds")
	sim.trains.append(sim._entry_train("L"))
	sim.advance(data.comparison_time)
	check(sim.lost and sim.elapsed > sim.config.safety_duration and blocker in sim.trains, "Actual collision after protection remains a loss")
	var geometry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/traffic_test_cases.json"))
	var rotation: Dictionary = geometry.rotation
	sim = Traffic.new()
	sim.config.spawning_enabled = false
	sim.cart.restart(0)
	sim.cart.config.speed = 0.0
	sim.config.train.cart_length = geometry.geometry_train_length
	train_at(sim, rotation.from, rotation.node, 0.0, sim.config.train.speed)
	train_at(sim, rotation.blocker_from, rotation.blocker_to, rotation.blocker_progress, 0.0)
	check("lower_left_approach_exit" in sim.cart.config.exits, "Rotation forecast uses a real remote entry")
	check(not sim._entry_safe("lower_left_approach_exit", sim.config.warning_duration), "Forecast catches node-rotation tangency in existing traffic")
	sim = Traffic.new()
	sim.config.spawning_enabled = false
	sim.cart.restart(0)
	sim.cart.config.speed = 0.0
	var through = train_at(sim, "T3_left", "T3_72", 0.0, sim.config.train.speed)
	through.progress = through.edge_length() - sim.config.safety_duration * through.config.speed / 2.0
	before = state(sim)
	check(sim._entry_safe("lower_left_approach_exit", 0.0), "Real remote entry stays safe while existing train crosses a passive merge")
	check(state(sim) == before, "Safe passive-merge forecast preserves the complete live snapshot")
	sim.trains.append(sim._entry_train("lower_left_approach_exit"))
	sim.advance(sim.config.safety_duration)
	check(not sim.lost and through.from_node == "T3_52" and through.to_node == "T3_122", "Actual protected motion crosses passive merge and continues forward through active junction")


func test_waiting() -> void:
	var sim = fresh()
	train_at(sim, "J", "R", data.junction_blocker_progress, 0.0)
	sim.cart.switches.J = 1
	check(sim._entry_safe("L", 0.0), "Warning route initially safe")
	sim.warnings = [{"entry": "L", "remaining": sim.config.warning_duration}]
	sim.config.spawning_enabled = true
	sim.advance(data.hold_time)
	check(sim.toggle("J"), "Route can change during warning")
	var rng_state: int = sim.rng.state
	sim.advance(sim.config.warning_duration)
	check(sim.warnings.size() == 1 and sim.warnings[0].entry == "L" and sim.trains.size() == 1, "Unsafe spawn retains same expired warning after route change")
	check(sim.rng.state == rng_state, "Pending warning retries never reroll")
	check(sim.toggle("J"), "Safe route can be restored")
	sim.advance(sim.config.retry_interval)
	check(sim.warnings.is_empty() and sim.trains.size() == 2 and not sim.lost, "Held spawn resumes on deterministic retry")
	sim = fresh()
	sim.cart.config.exits = ["L"]
	var blocker = train_at(sim, "J", "R", data.junction_blocker_progress, 0.0)
	sim.config.spawning_enabled = true
	rng_state = sim.rng.state
	sim.advance(sim.config.first_warning_delay + data.hold_time)
	check(sim.warnings.is_empty() and sim.trains.size() == 1 and sim.rng.state == rng_state, "All unsafe entries wait silently without forced spawn or RNG consumption")
	sim.trains.erase(blocker)
	sim.advance(sim.config.retry_interval)
	check(sim.warnings.size() == 1 and sim.warnings[0].entry == "L", "Silent wait resumes when an entry becomes safe")


func test_frame_independence() -> void:
	for blocked in [false, true]:
		var big = fresh()
		var small = fresh()
		for sim in [big, small]:
			sim.config.spawning_enabled = true
			if blocked:
				sim.cart.config.exits = ["L"]
				train_at(sim, "J", "R", data.junction_blocker_progress, 0.0)
		big.advance(data.comparison_time)
		small_advance(small, data.comparison_time)
		check(big.lost == small.lost and big.won == small.won and absf(big.elapsed - small.elapsed) < data.epsilon, "Bulk/small forecast event times agree")
		check(big.rng.state == small.rng.state and big.trains.size() == small.trains.size(), "Bulk/small safety choices and train counts agree")
		check(absf(big._scheduler_at - small._scheduler_at) < data.epsilon and big.warnings.size() == small.warnings.size(), "Retries use event times rather than frame times")
		for field in ["_announcement_at", "_warning_at", "_until_warning"]:
			check(big.get(field) == small.get(field) or absf(big.get(field) - small.get(field)) < data.epsilon, "Bulk/small scheduler agrees: " + field)
		for i in range(mini(big.trains.size(), small.trains.size())):
			check(big.trains[i].from_node == small.trains[i].from_node and big.trains[i].to_node == small.trains[i].to_node and absf(big.trains[i].progress - small.trains[i].progress) < data.epsilon, "Bulk/small train movement agrees")
		for i in range(mini(big.warnings.size(), small.warnings.size())):
			check(big.warnings[i].entry == small.warnings[i].entry, "Bulk/small warning entries agree")
			for field in ["remaining", "spawn_at", "check_at"]:
				check(absf(big.warnings[i][field] - small.warnings[i][field]) < data.epsilon, "Bulk/small warning agrees: " + field)
	var intervals: Array = []
	var counts: Array = []
	for time in [data.rate_early_time, data.rate_late_time]:
		var sim = fresh()
		sim.config.round_duration = data.rate_round_duration
		sim.elapsed = time
		sim._announcement_at = time + sim.config.first_warning_delay
		sim.config.spawning_enabled = true
		sim.cart.config.exits = ["L", "R"]
		sim.warnings = [{"entry": "L", "remaining": 0.0}]
		sim.advance(data.small_step)
		check(sim.trains.size() == 1 and not sim.lost, "Clear entry spawns at each scaling sample")
		intervals.append(sim._scheduler_at - time)
		# Keep every subsequent entry on the same clear, long, outbound route.
		sim.cart.config.exits = ["L"]
		sim.advance(data.rate_window - data.small_step)
		check(not sim.lost, "Clear scaling sample survives the observation window")
		counts.append(sim.trains.size())
	check(intervals[1] < intervals[0], "Successful spawn schedules a higher rate later in round")
	check(counts[1] > counts[0], "Clear conditions produce more actual trains later in round")


func run() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string("res://config/spawn_safety_test_cases.json"))
	check(Traffic.new().config.safety_duration == 2.0, "Production forecast protection defaults to two seconds")
	test_forecasts()
	test_waiting()
	test_frame_independence()
	print("Spawn safety: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
