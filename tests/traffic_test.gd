extends SceneTree

const Traffic = preload("res://scripts/traffic_simulation.gd")
const Simulation = preload("res://scripts/cart_simulation.gd")

var cases: Dictionary
var routes: Dictionary
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)


func near(a: float, b: float) -> bool:
	return absf(a - b) < cases.epsilon


func place(vehicle, source: String, target: String, progress: float) -> void:
	vehicle.from_node = source
	vehicle.to_node = target
	vehicle.progress = progress
	vehicle.rear_locks.clear()
	vehicle.lost = false


func fresh():
	var sim = Traffic.new()
	sim.config.spawning_enabled = false
	sim.cart.restart(0)
	return sim


func train_at(sim, source: String, target: String, progress: float):
	var vehicle = Simulation.new(sim.cart.config.duplicate())
	vehicle.config.merge(sim.config.train, true)
	vehicle.switches = sim.cart.switches
	vehicle.exits_safely = true
	place(vehicle, source, target, progress)
	sim.trains.append(vehicle)
	return vehicle


func neighbor(sim, entry: String) -> String:
	for edge in sim.cart.config.edges:
		if entry in edge:
			return edge[1] if edge[0] == entry else edge[0]
	return ""


func park_cart(sim) -> void:
	sim.cart.restart(0)
	sim.cart.config.speed = 0.0


func test_entries_and_scheduler() -> void:
	var sim = fresh()
	park_cart(sim)
	sim.config.spawning_enabled = true
	sim.rng.seed = int(cases.seed)
	var first: float = sim.config.first_warning_delay
	sim.advance(first - cases.epsilon)
	check(sim.warnings.is_empty() and sim.trains.is_empty(), "No warning before configured delay")
	sim.advance(cases.epsilon)
	check(sim.warnings.size() == 1 and sim.trains.is_empty(), "First warning at configured delay")
	check(near(sim.warnings[0].remaining, sim.config.warning_duration), "Warning starts with full duration")
	sim.advance(sim.config.warning_duration)
	check(sim.warnings.is_empty() and sim.trains.size() == 1, "Spawn exactly on warning expiration")
	var original_speed: float = sim.cart.config.speed
	check(near(sim.trains[0].config.speed, sim.config.train.speed), "Independent train speed")
	check(near(sim.cart.config.cart_length, Simulation.new().config.cart_length), "Train dimensions do not mutate cart")
	check(is_same(sim.cart.switches, sim.trains[0].switches), "Actual shared switch reference")
	check(is_same(sim.cart.config.nodes, sim.trains[0].config.nodes) and is_same(sim.cart.config.edges, sim.trains[0].config.edges), "Topology shared without deep copies")
	var expected: float = lerpf(sim.config.initial_interval, sim.config.final_interval, sim.elapsed / sim.config.scaling_horizon)
	check(near(sim._until_warning, expected), "Next warning interval scales at successful spawn")
	check(near(sim.cart.config.speed, original_speed), "Scheduler does not increase cart speed")
	var seen := {}
	for draw in range(int(cases.random_draws)):
		sim.restart()
		sim.advance(first)
		seen[sim.warnings[0].entry] = true
	check(seen.size() == sim.cart.config.exits.size(), "Uniform entry selection reaches all eight exits")
	for entry in sim.cart.config.exits:
		sim = fresh()
		park_cart(sim)
		sim.config.spawning_enabled = true
		sim.warnings = [{"entry": entry, "remaining": 0.0}]
		sim.advance(cases.small_step)
		check(sim.trains.size() == 1, "Spawn at entry " + entry)
		if sim.trains.size() == 1:
			var train = sim.trains[0]
			check(train.from_node == entry and train.to_node == neighbor(sim, entry), "Inward heading " + entry)
			check(train.heading().dot(train.point(train.to_node) - train.point(entry)) > 0.0, "Train points inward " + entry)
	# Beyond the scaling horizon, there is no win state and the interval clamps.
	sim = fresh()
	park_cart(sim)
	sim.elapsed = sim.config.scaling_horizon + cases.long_time
	sim.config.spawning_enabled = true
	sim.warnings = [{"entry": cases.busy_entry, "remaining": 0.0}]
	sim.advance(cases.small_step)
	check(not sim.lost and near(sim._until_warning + cases.small_step, sim.config.final_interval), "Horizon only clamps spawn frequency, never ends play")
	check(near(sim.trains[0].config.speed, sim.config.train.speed), "Elapsed time does not increase train speed")


func test_busy_entry() -> void:
	var sim = fresh()
	park_cart(sim)
	var entry: String = cases.busy_entry
	var blocker = train_at(sim, entry, neighbor(sim, entry), cases.busy_progress)
	blocker.config.speed = 0.0
	sim.config.spawning_enabled = true
	sim.warnings = [{"entry": entry, "remaining": 0.0}]
	sim.advance(cases.long_time)
	check(not sim.lost and sim.trains.size() == 1 and sim.warnings.size() == 1, "Busy entry waits without collision or announcement queue")
	check(near(sim.warnings[0].remaining, 0.0), "Expired warning remains visible")
	blocker.config.speed = sim.config.train.speed
	var clear_distance: float = sim.config.train.cart_length - blocker.progress
	sim.advance((clear_distance + sim.config.spawn_clearance * 2.0) / blocker.config.speed)
	check(not sim.lost and sim.warnings.is_empty() and sim.trains.size() == 2, "Spawn occurs within a large frame once footprint clears")
	# An outward train's rear still occupies the entry even after its center passes it.
	sim = fresh()
	park_cart(sim)
	blocker = train_at(sim, neighbor(sim, entry), entry, 0.0)
	blocker.progress = blocker.edge_length() + blocker.config.cart_length / 4.0
	blocker.config.speed = 0.0
	sim.config.spawning_enabled = true
	sim.warnings = [{"entry": entry, "remaining": 0.0}]
	sim.advance(cases.small_step)
	check(sim.trains.size() == 1 and sim.warnings.size() == 1, "Outward rear footprint blocks entry")
	# Non-collinear vehicle body overlaps an angled spawn even on another edge.
	sim = fresh()
	park_cart(sim)
	sim.config.train.cart_length = cases.geometry_train_length
	entry = cases.crossing_entry
	var junction := neighbor(sim, entry)
	var ports: Array = sim.cart.config.switches[junction].ports
	blocker = train_at(sim, ports[0], junction, 0.0)
	blocker.progress = blocker.edge_length()
	blocker.config.cart_width = cases.crossing_blocker_width
	blocker.config.speed = 0.0
	sim.config.spawning_enabled = true
	sim.warnings = [{"entry": entry, "remaining": 0.0}]
	sim.advance(cases.small_step)
	check(sim.trains.size() == 1 and sim.warnings.size() == 1, "Angled entry checks full OBB, not edge identity")
	sim = fresh()
	park_cart(sim)
	entry = cases.busy_entry
	blocker = train_at(sim, entry, neighbor(sim, entry), sim.config.train.cart_length)
	blocker.config.speed = 0.0
	sim.config.spawning_enabled = true
	sim.warnings = [{"entry": entry, "remaining": 0.0}]
	sim.advance(cases.small_step)
	check(not sim.lost and sim.trains.size() == 1 and sim.warnings.size() == 1, "Touching-only spawn footprint remains occupied")
	blocker.progress += cases.rotation.gap
	sim.advance(cases.rotation.gap / sim.config.train.speed / 2.0)
	check(not sim.lost and sim.trains.size() == 2 and sim.warnings.is_empty(), "Spawn succeeds once touching footprints separate")


func test_routes_and_locks() -> void:
	var sim = fresh()
	for id in sim.cart.config.switches:
		for setting in [0, 1]:
			for incoming in routes[id]:
				var train = train_at(sim, incoming, id, 0.0)
				sim.cart.switches[id] = setting
				var before: Vector2 = train.heading()
				train.advance_distance(train.distance_to_event())
				check(train.from_node == id and train.to_node == routes[id][incoming][setting], "Train shares route " + id)
				check(before.dot(train.heading()) > 0.0 and before.x * train.heading().x > 0.0, "Train switch never reverses " + id)
				sim.trains.clear()
	var lock: Dictionary = cases.lock
	var a = train_at(sim, lock.id, lock.to, 0.0)
	var b = train_at(sim, lock.id, lock.to, 0.0)
	a.rear_locks[lock.id] = cases.lock.rear_short
	b.rear_locks[lock.id] = cases.lock.rear_long
	a.advance_distance(cases.lock.rear_short + cases.epsilon)
	check(sim.is_locked(lock.id) and not sim.toggle(lock.id), "One vehicle clearing does not release another rear lock")
	b.advance_distance(cases.lock.rear_long + cases.epsilon)
	check(not sim.is_locked(lock.id) and sim.toggle(lock.id), "Unlock after every rear clears")
	place(a, lock.from, lock.id, 0.0)
	a.progress = a.edge_length() - a.config.cart_length / 2.0
	check(sim.is_locked(lock.id) and not sim.toggle(lock.id), "Any train front contact locks shared switch")


func test_terminals() -> void:
	var sim = fresh()
	for entry in sim.cart.config.exits:
		sim = fresh()
		park_cart(sim)
		var train = train_at(sim, neighbor(sim, entry), entry, 0.0)
		var tail: float = train.edge_length() + train.config.cart_length / 2.0
		sim.advance((tail - cases.epsilon) / train.config.speed)
		check(not sim.lost and sim.trains.size() == 1, "Keep train until rear clears " + entry)
		check(train.progress > train.edge_length(), "Exit rendering extrapolates beyond endpoint " + entry)
		sim.advance(cases.epsilon * 2.0 / train.config.speed)
		check(not sim.lost and sim.trains.is_empty(), "Safe removal at exit " + entry)
		train = train_at(sim, neighbor(sim, entry), entry, 0.0)
		var started: float = sim.elapsed
		var duration: float = train.distance_to_event() / train.config.speed
		sim.advance(duration)
		check(not sim.lost and sim.trains.is_empty() and near(sim.elapsed - started, duration), "Remove exactly at rear-clear event " + entry)
		sim = fresh()
		place(sim.cart, neighbor(sim, entry), entry, 0.0)
		sim.advance(sim.cart.distance_to_event() / sim.cart.config.speed)
		check(sim.lost and sim.loss_reason == "cart_exit", "Cart front contact loses " + entry)
	for buffer in sim.cart.config.buffers:
		sim = fresh()
		var train = train_at(sim, neighbor(sim, buffer), buffer, 0.0)
		var before: Vector2 = train.heading()
		train.advance_distance(train.edge_length())
		check(not train.lost and train.from_node == buffer and near(before.dot(train.heading()), -1.0), "Train reverses at buffer " + buffer)


func collision_setup(kind: String):
	var sim = fresh()
	var head: Dictionary = cases.head_on
	if kind == "cart_train":
		place(sim.cart, head.from, head.to, head.cart_progress)
		train_at(sim, head.to, head.from, head.train_progress)
	elif kind == "train_train":
		park_cart(sim)
		train_at(sim, head.from, head.to, head.cart_progress)
		train_at(sim, head.to, head.from, head.train_progress)
	elif kind == "catch_up":
		park_cart(sim)
		var data: Dictionary = cases.catch_up
		var a = train_at(sim, data.from, data.to, data.leader_progress)
		var b = train_at(sim, data.from, data.to, data.follower_progress)
		a.config.speed = data.leader_speed
		b.config.speed = data.follower_speed
	else:
		park_cart(sim)
		var data: Dictionary = cases.junction
		var a = train_at(sim, data.a, data.id, 0.0)
		var b = train_at(sim, data.b, data.id, 0.0)
		a.progress = a.edge_length() - data.distance
		b.progress = b.edge_length() - data.distance
	return sim


func compare(a, b, context: String) -> void:
	check(a.lost == b.lost and a.loss_reason == b.loss_reason and near(a.elapsed, b.elapsed), context + " loss and event time")
	check(a.trains.size() == b.trains.size(), context + " train count")
	var av: Array = [a.cart] + a.trains
	var bv: Array = [b.cart] + b.trains
	for i in range(mini(av.size(), bv.size())):
		check(av[i].from_node == bv[i].from_node and av[i].to_node == bv[i].to_node and near(av[i].progress, bv[i].progress), context + " synchronized movement")
		for id in a.cart.config.switches:
			check(av[i].is_locked(id) == bv[i].is_locked(id), context + " vehicle lock " + id)


func small_advance(sim, duration: float) -> void:
	while duration > 0.0 and not sim.lost:
		var step := minf(duration, cases.small_step)
		sim.advance(step)
		duration -= step


func test_collisions_and_frame_independence() -> void:
	for kind in ["cart_train", "train_train", "catch_up", "junction"]:
		var big = collision_setup(kind)
		var small = collision_setup(kind)
		var expected := -1.0
		var starting_progress: Array = []
		var moving: Array = [big.cart, big.trains[0]] if kind == "cart_train" else big.trains
		for vehicle in moving:
			starting_progress.append(vehicle.progress)
		if kind in ["cart_train", "train_train", "catch_up"]:
			var gap: float = moving[0].cart_position().distance_to(moving[1].cart_position()) - (moving[0].config.cart_length + moving[1].config.cart_length) / 2.0
			var closing_speed: float = moving[1].config.speed - moving[0].config.speed if kind == "catch_up" else moving[0].config.speed + moving[1].config.speed
			expected = gap / closing_speed
		big.advance(cases.comparison_time)
		small_advance(small, cases.comparison_time)
		check(big.lost and big.loss_reason == ("cart_train" if kind == "cart_train" else "train_train"), "Swept contact loses: " + kind)
		check(big.elapsed < cases.comparison_time, "Stops at first collision, not frame end: " + kind)
		if expected >= 0.0:
			check(near(big.elapsed, expected), "Independent analytic first-contact time: " + kind)
			for i in range(moving.size()):
				check(near(moving[i].progress, starting_progress[i] + expected * moving[i].config.speed), "Independent first-contact progress: " + kind)
		compare(big, small, kind)
	var big = fresh()
	var small = fresh()
	for sim in [big, small]:
		train_at(sim, "T5_72", "T5_left", cases.busy_progress)
	big.advance(cases.long_time)
	small_advance(small, cases.long_time)
	check(not big.lost, "Separate siding vehicles survive many buffer/node events")
	compare(big, small, "Noncolliding large delta")
	# Spawn footprint overlap is not exempt from normal collision detection.
	big = collision_setup("train_train")
	place(big.trains[1], big.trains[0].from_node, big.trains[0].to_node, big.trains[0].progress)
	big.advance(cases.small_step)
	check(big.lost and near(big.elapsed, 0.0), "Initial stationary overlap loses immediately")


func test_restart_and_invalid_delta() -> void:
	var sim = collision_setup("cart_train")
	for delta in [0.0, -cases.long_time, INF, -INF, NAN]:
		sim.advance(delta)
	check(near(sim.elapsed, 0.0) and not sim.lost, "Invalid deltas ignored without hanging")
	sim.advance(cases.long_time)
	check(sim.lost and not sim.toggle(cases.lock.id), "Loss rejects switching")
	sim.warnings.append({"entry": cases.busy_entry, "remaining": 0.0})
	sim.cart.rear_locks[cases.lock.id] = cases.lock.rear_long
	sim.cart.switches[cases.lock.id] = 1
	sim.restart()
	check(not sim.lost and sim.loss_reason.is_empty() and near(sim.elapsed, 0.0), "Restart resets loss and elapsed")
	check(sim.trains.is_empty() and sim.warnings.is_empty() and sim.cart.rear_locks.is_empty(), "Restart clears trains, pending warning and locks")
	check(near(sim._until_warning, sim.config.first_warning_delay), "Restart resets scheduler")
	for id in sim.cart.config.switches:
		check(sim.cart.switches[id] == int(sim.cart.config.switches[id].initial), "Restart resets switch " + id)


func test_scheduler_frame_independence() -> void:
	for blocked in [false, true]:
		var big = fresh()
		var small = fresh()
		for sim in [big, small]:
			park_cart(sim)
			sim.config.spawning_enabled = true
			sim.rng.seed = int(cases.seed)
			if blocked:
				var entry: String = cases.busy_entry
				train_at(sim, entry, neighbor(sim, entry), cases.busy_progress)
				sim.warnings = [{"entry": entry, "remaining": 0.0}]
		big.advance(cases.comparison_time)
		small_advance(small, cases.comparison_time)
		compare(big, small, "Scheduler frame independence")
		check(big.warnings.size() == small.warnings.size(), "Frame-independent pending warning count")
		if not big.warnings.is_empty() and not small.warnings.is_empty():
			check(big.warnings[0].entry == small.warnings[0].entry and near(big.warnings[0].remaining, small.warnings[0].remaining), "Frame-independent warning entry/countdown")
		check(near(big._until_warning, small._until_warning), "Frame-independent successful-spawn schedule")
		check(big.rng.state == small.rng.state, "Blocked retries consume no additional random entries")


func test_rotation_boundaries() -> void:
	var data: Dictionary = cases.rotation
	for gap in [0.0, cases.rotation.gap]:
		var big = fresh()
		var small = fresh()
		var duration := 0.0
		for sim in [big, small]:
			park_cart(sim)
			sim.config.train.cart_length = cases.geometry_train_length
			var moving = train_at(sim, data.from, data.node, 0.0)
			var blocker = train_at(sim, data.blocker_from, data.blocker_to, data.blocker_progress + gap)
			blocker.config.speed = 0.0
			duration = moving.distance_to_event() / moving.config.speed
		big.advance(duration)
		small_advance(small, duration)
		check(big.lost == (gap == 0.0), "Rotation-only tangency loses; angled near-miss survives")
		check(near(big.elapsed, duration), "Rotation contact occurs exactly at node event")
		compare(big, small, "Node rotation boundary")
	data = cases.warning_rotation
	var big = fresh()
	var small = fresh()
	var duration := 0.0
	for sim in [big, small]:
		park_cart(sim)
		sim.config.train.cart_length = cases.geometry_train_length
		var moving = train_at(sim, data.from, data.node, 0.0)
		sim.cart.switches[data.node] = 1
		duration = moving.distance_to_event() / moving.config.speed
		sim.config.spawning_enabled = true
		sim.warnings = [{"entry": data.entry, "remaining": duration}]
	big.advance(duration)
	small_advance(small, duration)
	check(not big.lost and big.trains.size() == 1 and big.warnings.size() == 1, "Node rotation blocks simultaneous warning expiry before spawning")
	compare(big, small, "Warning/rotation simultaneous boundary")


func test_original_motion() -> void:
	var sim = Simulation.new()
	for index in range(sim.config.starts.size()):
		sim.restart(index)
		sim.advance(cases.long_time)
		check(not sim.lost, "Original cart API retains safe siding motion")
	for entry in sim.config.exits:
		var traffic = fresh()
		var source := neighbor(traffic, entry)
		place(sim, source, entry, 0.0)
		var threshold: float = sim.edge_length() - sim.config.cart_length / 2.0
		sim.advance((threshold - cases.epsilon) / sim.config.speed)
		check(not sim.lost, "Original cart still alive before front exit")
		sim.advance(cases.epsilon * 2.0 / sim.config.speed)
		check(sim.lost and near(sim.progress, threshold), "Original cart front exits unchanged")


func run() -> void:
	cases = JSON.parse_string(FileAccess.get_file_as_string("res://config/traffic_test_cases.json"))
	routes = JSON.parse_string(FileAccess.get_file_as_string("res://config/cart_test_cases.json")).routes
	test_entries_and_scheduler()
	test_busy_entry()
	test_routes_and_locks()
	test_terminals()
	test_collisions_and_frame_independence()
	test_restart_and_invalid_delta()
	test_scheduler_frame_independence()
	test_rotation_boundaries()
	test_original_motion()
	print("Traffic core: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
