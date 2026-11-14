extends SceneTree

const Traffic = preload("res://scripts/traffic_simulation.gd")
const Motion = preload("res://scripts/cart_simulation.gd")
var data: Dictionary
var layout: Dictionary
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
	sim.config.spawning_enabled = false
	sim.cart = Motion.new(layout.vehicle.duplicate(true))
	sim.cart.config.merges = {}
	sim.config.train = layout.train.duplicate()
	return sim


func place(vehicle, source: String, target: String, progress: float) -> void:
	vehicle.from_node = source
	vehicle.to_node = target
	vehicle.progress = progress
	vehicle.rear_locks.clear()


func test_clock() -> void:
	var sim = fresh()
	var duration: float = sim.config.round_duration
	check(duration == 67.0 and sim.remaining_time() == duration and not sim.won, "Production round starts at 67 seconds")
	sim.advance(duration - data.boundary_offset)
	check(not sim.won and not sim.lost and sim.remaining_time() > 0.0, "No early victory immediately before deadline")
	sim.advance(data.large_delta)
	check(sim.won and not sim.lost and sim.elapsed == duration and sim.remaining_time() == 0.0, "Large delta clips exactly to round deadline")
	var progress: float = sim.cart.progress
	var rng_state: int = sim.rng.state
	check(not sim.toggle("J"), "Victory blocks switch input")
	sim.advance(data.large_delta)
	check(sim.elapsed == duration and sim.cart.progress == progress and sim.rng.state == rng_state, "Victory freezes time, positions and scheduler RNG")
	sim.restart()
	check(not sim.won and not sim.lost and sim.elapsed == 0.0 and sim.remaining_time() == duration, "Restart after victory resets clock and outcome")
	check(sim.trains.is_empty() and sim.warnings.is_empty() and sim._warning_at == INF and sim._scheduler_at == sim.config.first_warning_delay and sim._announcement_at == sim.config.first_warning_delay and sim._until_warning == sim.config.first_warning_delay, "Restart clears every prediction retry and warning scheduler clock")


func test_ties() -> void:
	for kind in ["exit", "collision"]:
		for offset in [-data.boundary_offset, 0.0, data.boundary_offset]:
			var sim = fresh()
			var event_time: float = sim.config.round_duration + offset
			if kind == "exit":
				place(sim.cart, "J", "R", 0.0)
				sim.cart.config.speed = data.speed
				sim.cart.progress = sim.cart.distance_to_event() - event_time * data.speed
			else:
				place(sim.cart, "P", "Q", data.stationary_cart_progress)
				var train = sim._entry_train("L")
				place(train, "P", "Q", data.stationary_cart_progress - sim.cart.config.cart_length / 2.0 - train.config.cart_length / 2.0 - event_time * data.speed)
				train.config.speed = data.speed
				sim.trains.append(train)
			var small = fresh()
			small.cart.from_node = sim.cart.from_node
			small.cart.to_node = sim.cart.to_node
			small.cart.progress = sim.cart.progress
			small.cart.config.speed = sim.cart.config.speed
			for train in sim.trains:
				var copy = small._entry_train("L")
				place(copy, train.from_node, train.to_node, train.progress)
				copy.config.speed = train.config.speed
				small.trains.append(copy)
			while not small.lost and not small.won:
				var before: float = small.elapsed
				small.advance(data.small_step)
				if small.elapsed <= before and not small.lost and not small.won:
					check(false, "Deadline simulation must advance or finish")
					break
			sim.advance(data.large_delta)
			check(sim.lost == small.lost and sim.won == small.won and absf(sim.elapsed - small.elapsed) < data.epsilon, "Bulk/small deadline outcomes agree: %s %.12f" % [kind, offset])
			check(sim.lost == (offset <= 0.0) and sim.won == (offset > 0.0), "%s immediately before/at/after deadline respects exact ordering: %.12f" % [kind, offset])
			check(absf(sim.elapsed - minf(event_time, sim.config.round_duration)) < data.epsilon, "Tie scenario stops at earliest event")
			if sim.lost:
				check(sim.loss_reason == ("cart_exit" if kind == "exit" else "cart_train"), "Tie reports actual loss reason")
				var progress: float = sim.cart.progress
				var elapsed: float = sim.elapsed
				check(not sim.toggle("J"), "Loss blocks switch input")
				sim.advance(data.large_delta)
				check(sim.cart.progress == progress and sim.elapsed == elapsed, "Loss freezes motion and time")
				sim.restart()
				check(not sim.lost and not sim.won and sim.loss_reason.is_empty() and sim.trains.is_empty(), "Restart after loss clears state")


func test_rotation() -> void:
	var sim = Traffic.new()
	sim.config.spawning_enabled = false
	sim.cart.restart(0)
	sim.cart.config.speed = 0.0
	sim.config.train.cart_length = data.rotation.length
	var moving = sim._entry_train("T3_left")
	place(moving, data.rotation.from, data.rotation.node, 0.0)
	var blocker = sim._entry_train("T3_left")
	place(blocker, data.rotation.blocker_from, data.rotation.blocker_to, data.rotation.blocker_progress)
	blocker.config.speed = 0.0
	sim.trains = [moving, blocker]
	var incoming = sim._copy_vehicle(moving, sim.cart.switches)
	incoming.progress = incoming.edge_length()
	check(sim._contact_interval(incoming, blocker, Vector2.ZERO, Vector2.ZERO, 0.0)[0] == INF, "Deadline fixture is clear immediately before passive node rotation")
	incoming.advance_distance(0.0)
	check(sim._contact_interval(incoming, blocker, Vector2.ZERO, Vector2.ZERO, 0.0)[0] == 0.0, "Deadline fixture actually contacts after passive node rotation")
	sim.elapsed = sim.config.round_duration - moving.distance_to_event() / moving.config.speed
	sim.advance(data.large_delta)
	check(sim.lost and not sim.won and sim.loss_reason == "train_train" and sim.elapsed == sim.config.round_duration, "Node rotation contact exactly at deadline precedes victory")


func test_scheduler_deadline() -> void:
	for warning in [false, true]:
		var sim = fresh()
		sim.config.spawning_enabled = true
		sim._announcement_at = sim.config.round_duration
		if warning:
			for entry in data.deadline_entries:
				sim.warnings.append({"entry": entry, "remaining": sim.config.round_duration})
			sim.advance(data.small_step)
			check(sim.warnings.size() == 2, "Default scheduler retains both deadline warnings")
			for pending in sim.warnings:
				check(pending.spawn_at == sim.config.round_duration and pending.check_at == sim.config.round_duration, "Injected deadline warning is normalized without shifting its event")
		var rng_state: int = sim.rng.state
		sim.advance(data.large_delta)
		check(sim.won and sim.trains.is_empty() and sim.warnings.is_empty() and sim.rng.state == rng_state, "No spawn or warning starts at deadline; pending warning clears")
		check(sim._announcement_at == INF and sim._scheduler_at == INF and sim._warning_at == INF and sim._until_warning == INF, "Victory disables every scheduler clock")
		check(not sim.toggle("J"), "Two-warning deadline rejects switch input")
		var progress: float = sim.cart.progress
		sim.advance(data.large_delta)
		check(sim.elapsed == sim.config.round_duration and sim.cart.progress == progress and sim.rng.state == rng_state, "Deadline freezes clock, motion and selection")
	var sim = fresh()
	sim.elapsed = sim.config.round_duration - data.boundary_offset
	var train = sim._entry_train("L")
	place(train, "J", "L", 0.0)
	sim.trains.append(train)
	check(sim._entry_safe("L", 0.0), "Forecast ignores collisions after actual round end")
	check(sim._entry_safe("R", sim.config.warning_duration), "Forecast lead clips to round end without future candidate")
	sim = Traffic.new()
	sim.config.spawning_enabled = false
	sim.cart.restart(0)
	sim.cart.config.speed = 0.0
	train = sim._entry_train("T3_left")
	train.progress = train.edge_length() - sim.config.safety_duration * train.config.speed / 2.0
	sim.trains.append(train)
	sim.elapsed = sim.config.round_duration - sim.config.safety_duration
	var progress: float = train.progress
	var rng_state: int = sim.rng.state
	check(sim._entry_safe("lower_left_approach_exit", 0.0), "Safe real-entry forecast crosses a passive merge before deadline")
	check(train.from_node == "T3_left" and train.to_node == "T3_72" and train.progress == progress and sim.rng.state == rng_state, "Deadline passive-merge forecast leaves live motion and RNG untouched")
	sim.trains.append(sim._entry_train("lower_left_approach_exit"))
	sim.advance(data.large_delta)
	check(sim.won and not sim.lost and train.from_node == "T3_52" and train.to_node == "T3_122", "Actual safe entry and passive through-route survive exactly to deadline")


func run() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string("res://config/round_test_cases.json"))
	layout = JSON.parse_string(FileAccess.get_file_as_string("res://config/spawn_safety_test_cases.json"))
	test_clock()
	test_ties()
	test_rotation()
	test_scheduler_deadline()
	print("Round core: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
