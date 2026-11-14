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


func close(a: float, b: float) -> bool:
	return a == b or absf(a - b) < data.epsilon


func fresh():
	var sim = Traffic.new()
	sim.cart = Motion.new(data.vehicle.duplicate(true))
	sim.config.train = data.train.duplicate()
	sim.rng.seed = int(data.seed)
	return sim


func blocker(sim, source: String, target: String, progress: float):
	var train = sim._entry_train(source)
	train.from_node = source
	train.to_node = target
	train.progress = progress
	train.config.speed = 0.0
	sim.trains.append(train)
	return train


func snapshot(sim) -> Array:
	var result: Array = [sim.elapsed, sim.lost, sim.won, sim.loss_reason, sim.rng.state, sim.cart.rng.state, sim.cart.switches.duplicate(), sim.warnings.duplicate(true), sim._scheduler_at, sim._warning_at, sim._until_warning, sim._announcement_at]
	for vehicle in [sim.cart] + sim.trains:
		result.append([vehicle.from_node, vehicle.to_node, vehicle.progress, vehicle.rear_locks.duplicate(), vehicle.lost, vehicle.config.duplicate(true), vehicle.rng.state])
	return result


func test_pair() -> void:
	var sim = Traffic.new()
	sim.cart.restart(0)
	sim.cart.config.speed = 0.0
	sim.rng.seed = int(data.seed)
	sim.advance(sim.config.first_warning_delay)
	check(sim.warnings.size() == 2, "Default first event creates both indicators together")
	if sim.warnings.size() == 2:
		check(sim.warnings[0].entry != sim.warnings[1].entry, "Indicators have distinct entries")
		check(close(sim.warnings[0].remaining, sim.config.warning_duration), "First warning has full lead")
		check(close(sim.warnings[1].remaining, sim.config.warning_duration + sim.config.warning_stagger), "Second warning has staggered lead")
		check(close(sim._scheduler_at, sim.warnings[0].spawn_at), "Full capacity ignores overdue announcement clock")
		sim.advance(sim.config.warning_duration)
		check(sim.trains.size() == 1 and sim.warnings.size() == 1, "First train arrives at its individual deadline")
		sim.advance(sim.config.warning_stagger)
		check(sim.trains.size() == 2 and sim.warnings.is_empty(), "Second train arrives at its individual deadline")
		for train in sim.trains:
			check(train.config.speed == sim.config.train.speed, "Concurrent traffic never increases speed")
	sim = fresh()
	sim.cart.config.exits = ["L", "R"]
	check(sim._entry_safe("L", sim.config.warning_duration) and sim._entry_safe("R", sim.config.warning_duration + sim.config.warning_stagger), "Opposite entries are individually safe")
	sim.warnings = [{"entry": "L", "remaining": sim.config.warning_duration}]
	var before := snapshot(sim)
	check(not sim._entry_safe("R", sim.config.warning_duration + sim.config.warning_stagger), "Joint head-on plan is rejected")
	check(sim._entry_safe("U", sim.config.warning_duration), "Separated pending plan is safe")
	check(snapshot(sim) == before, "Safe and unsafe joint forecasts preserve all live state and RNG")
	sim.warnings.clear()
	sim.advance(sim.config.first_warning_delay)
	check(sim.warnings.size() == 1, "Only one eligible joint plan is announced")
	before = snapshot(sim)
	check(sim._pressure_weight("U") == sim.config.pressure_weight, "Pressure trace reaches current row through passive merge")
	check(snapshot(sim) == before, "Pressure forecast preserves all live state and RNG")


func test_held() -> void:
	var sim = fresh()
	sim.cart.config.exits = ["L", "U", "W"]
	var stopped = blocker(sim, "L", "J", 0.0)
	sim.warnings = [{"entry": "L", "remaining": 0.0}, {"entry": "U", "remaining": 0.0}]
	sim._schedule()
	check(sim.trains.size() == 2 and sim.warnings.size() == 1 and sim.warnings[0].entry == "L", "Blocked first warning does not block second spawn")
	check(sim.warnings[0].remaining == 0.0 and close(sim.warnings[0].check_at, sim.config.retry_interval), "Held warning keeps original deadline and individual retry")
	var interval: float = sim._announcement_at
	sim.advance(interval)
	check(sim.warnings.size() == 2, "Successful second spawn refills free slot while first waits")
	for warning in sim.warnings:
		if warning.spawn_at > sim.elapsed:
			check(warning.entry != "L", "Waiting entry is never selected twice")
	sim.trains.erase(stopped)
	sim.advance(sim.config.retry_interval)
	var held := false
	for warning in sim.warnings:
		held = held or warning.entry == "L"
	check(not held, "Unblocked warning spawns on its retry event")
	sim = fresh()
	sim.cart.config.exits = ["L"]
	blocker(sim, "J", "R", data.blocker_progress)
	sim.cart.switches.J = 1
	sim.warnings = [{"entry": "L", "remaining": sim.config.warning_duration}]
	sim._schedule()
	sim.cart.switches.J = 0
	sim.advance(sim.config.warning_duration)
	check(sim.warnings.size() == 1 and sim.warnings[0].entry == "L" and sim.warnings[0].remaining == 0.0, "Route change holds same expired entry")
	sim.cart.switches.J = 1
	sim.advance(sim.config.retry_interval)
	check(sim.trains.size() == 2 and sim.warnings.is_empty(), "Restored route releases held warning")
	sim = fresh()
	sim.cart.config.exits = ["L"]
	blocker(sim, "L", "J", 0.0)
	var rng_state: int = sim.rng.state
	sim.advance(sim.config.first_warning_delay + sim.config.warning_duration)
	check(sim.warnings.is_empty() and sim.rng.state == rng_state, "Zero eligible entries consume no random draws")
	sim = fresh()
	sim.cart.config.exits = ["L", "R"]
	sim.warnings = [{"entry": "L", "remaining": 0.0}, {"entry": "R", "remaining": 0.0}]
	check(not sim._entry_safe("L", 0.0), "Changed route can make two pending arrivals jointly unsafe")
	var before := snapshot(sim)
	check(sim._entry_safe("L", 0.0, true), "Admission forecasts and defers incompatible hypothetical train")
	check(snapshot(sim) == before, "Nested admission forecast leaves all live state and RNG untouched")
	sim._schedule()
	check(sim.trains.size() == 1 and sim.warnings.size() == 1 and sim.warnings[0].entry == "R", "Due admission breaks circular pending dependency deterministically")
	check(sim.trains[0].from_node == "L" and not sim._entry_safe("R", 0.0), "Loser of admission cannot ignore the actual admitted train")
	before = snapshot(sim)
	check(not sim._entry_safe("R", 0.0, true) and snapshot(sim) == before, "Rejected admission also preserves live state and actual traffic")
	var due: float = sim._announcement_at
	sim.advance(sim.config.retry_interval)
	check(sim._announcement_at == due, "Failed spawn does not reset global announcement deadline")
	check(sim.warnings[0].entry == "R" and sim.warnings[0].spawn_at == 0.0 and sim.warnings[0].check_at > sim.elapsed, "Deferred warning preserves entry and original deadline while its retry advances")
	sim.config.max_warnings = 1
	sim.advance(sim.config.warning_duration + sim.config.safety_duration)
	check(not sim.lost and sim.warnings.is_empty() and sim.trains.size() == 1 and sim.trains[0].from_node == "R", "Deferred warning eventually spawns after actual traffic clears")


func test_plan_times() -> void:
	var sim = fresh()
	sim.cart.config.nodes.R[0] = data.guard_exit_x
	check(sim._entry_safe("L", 0.0), "Candidate alone is safe for its two-second guard")
	sim.warnings = [{"entry": "R", "remaining": data.later_arrival}]
	check(not sim._entry_safe("L", 0.0), "Candidate precedes pending plan and guard extends two seconds after latest arrival")
	sim.warnings = [{"entry": "L", "remaining": 0.0, "spawn_at": 0.0, "check_at": data.near_retry}]
	check(not sim._entry_safe("R", 0.0), "Expired pending warning is inserted at its near retry time")
	sim.warnings[0].check_at = data.far_retry
	check(sim._entry_safe("R", 0.0), "Far retry waits until actual traffic has safely exited")
	var clipped = fresh()
	clipped.cart.config.nodes.R[0] = data.guard_exit_x
	clipped.elapsed = clipped.config.round_duration - data.later_arrival
	clipped.warnings = [{"entry": "R", "remaining": data.later_arrival}]
	check(clipped._entry_safe("L", 0.0), "Joint forecast ignores insertion and collision beyond round deadline")


func test_geometry() -> void:
	for reversed in [false, true]:
		var sim = fresh()
		var train = blocker(sim, "L", "J", data.tangent_progress)
		if reversed:
			train.from_node = "J"
			train.to_node = "L"
			train.progress = train.edge_length() - data.tangent_progress
		check(not sim._entry_safe("L", 0.0), "Touching spawn footprints reject either heading")
	var sim = fresh()
	sim.cart.switches.J = 1
	sim.cart.from_node = "J"
	sim.cart.to_node = "B"
	sim.cart.progress = data.buffer_progress
	sim.cart.config.speed = sim.config.train.speed
	check(not sim._entry_safe("L", 0.0), "Guard follows buffer reversal")
	sim = fresh()
	sim.warnings = [{"entry": "U", "remaining": 0.0}, {"entry": "L", "remaining": 0.0}]
	sim._schedule()
	check(sim.trains.size() == 2 and not sim.lost, "Double guard inserts both safe trains including passive traversal")
	check(not sim._entry_safe("R", 0.0), "Actual spawned train remains present in next guard")


func test_pressure() -> void:
	var totals: Array = []
	for weight in [1.0, Traffic.new().config.pressure_weight]:
		var sim = fresh()
		sim.config.max_warnings = 1
		sim.config.pressure_weight = weight
		sim.cart.config.exits = ["L", "U"]
		var targeted := 0
		for draw in range(int(data.draws)):
			sim.warnings.clear()
			sim._announcement_at = sim.elapsed
			sim._schedule()
			if sim.warnings[0].entry == "U":
				targeted += 1
		totals.append(targeted)
		check(targeted > 0 and targeted < data.draws, "Both target and non-target remain possible")
		var repeat = fresh()
		repeat.config.max_warnings = 1
		repeat.config.pressure_weight = weight
		repeat.cart.config.exits = ["L", "U"]
		for draw in range(int(data.draws)):
			repeat.warnings.clear()
			repeat._announcement_at = repeat.elapsed
			repeat._schedule()
		check(sim.rng.state == repeat.rng.state and sim.warnings == repeat.warnings, "Weighted sampling is seeded and deterministic")
	check(totals[1] > totals[0] + data.minimum_pressure_gain, "Weight six meaningfully increases same-row warnings")
	var sim = fresh()
	sim.cart.config.exits = ["L", "U"]
	blocker(sim, "U", "M", 0.0)
	sim.advance(sim.config.first_warning_delay)
	check(sim.warnings.size() == 1 and sim.warnings[0].entry == "L", "Safety excludes higher-ranked blocked route")
	sim = Traffic.new()
	sim.cart.restart(1)
	check(sim._pressure_weight("T3_left") == sim.config.pressure_weight, "Default main T3 left reaches cart row T2")
	sim.cart.restart(2)
	check(sim._pressure_weight("T4_left") == sim.config.pressure_weight, "Default main T4 left reaches cart row T5")
	sim.cart.switches.T4_52 = 0
	check(sim._pressure_weight("T4_left") == 1.0, "Pressure follows selected switch, not graph reachability")
	sim.cart.from_node = "T4_52"
	sim.cart.to_node = "T5_72"
	check(sim._pressure_weight("T4_left") == sim.config.pressure_weight, "Diagonal cart segment targets both adjacent rows")
	sim.cart.switches.T6_right_switch = 1
	check(sim._pressure_weight("lower_left_approach_exit") == sim.config.pressure_weight, "Diagonal cart segment also targets route visiting only its lower row")
	check(sim._pressure_weight("upper_right_approach_exit") == 1.0, "Diagonal cart segment does not target unrelated row")
	sim.cart.from_node = "T4_left"
	sim.cart.to_node = "T4_72"
	check(sim._pressure_weight("lower_left_approach_exit") == 1.0, "Lower-only route stops being targeted when cart is entirely on upper row")
	sim.cart.restart(1)
	sim.cart.switches.T3_102 = 0
	sim.cart.switches.T2_52 = 1
	check(sim._pressure_weight("T3_left") == 1.0, "Passive endpoint does not allow reverse branch routing")
	sim = Traffic.new()
	sim.cart.restart(1)
	var route = sim._entry_train("T3_left")
	var travel := 0.0
	var target: Array = sim.cart.config.tracks[1].nodes
	while not route.lost and route.from_node not in target:
		var distance: float = route.distance_to_event()
		travel += distance
		route.advance_distance(distance)
	check(not route.lost, "Initial main route really reaches T2 via shared motion kernel")
	sim.config.pressure_horizon = travel / route.config.speed - data.epsilon
	check(sim._pressure_weight("T3_left") == 1.0, "Row just beyond travel horizon is not ranked")
	sim.config.pressure_horizon += data.epsilon * 2.0
	check(sim._pressure_weight("T3_left") == sim.config.pressure_weight, "Row just inside travel horizon is ranked without warning lead")
	sim.config.pressure_horizon = sim.config.round_duration
	sim.cart.switches.T1_52 = 1
	check(sim._pressure_weight("upper_right_approach_exit") == sim.config.pressure_weight, "Pressure route follows buffer reversal before selected switch and passive merge")


func test_clocks() -> void:
	for held in [false, true]:
		var big = fresh()
		var small = fresh()
		for sim in [big, small]:
			sim.cart.config.exits = ["L", "U", "W"]
			sim.cart.config.speed = sim.config.train.speed
			sim.cart.from_node = "Q"
			sim.cart.to_node = "P"
			sim.cart.progress = sim.cart.edge_length() - data.buffer_progress
			if held:
				blocker(sim, "L", "J", 0.0)
				sim.warnings = [{"entry": "L", "remaining": 0.0}, {"entry": "U", "remaining": sim.config.warning_stagger}]
		big.advance(data.comparison_time)
		while small.elapsed < data.comparison_time and not small.lost and not small.won:
			small.advance(minf(data.step, data.comparison_time - small.elapsed))
		check(big.rng.state == small.rng.state and big.trains.size() == small.trains.size() and big.warnings.size() == small.warnings.size(), "Bulk and small steps choose identical concurrent traffic")
		check(big.lost == small.lost and big.won == small.won and big.loss_reason == small.loss_reason, "Bulk and small outcomes agree")
		check(big.cart.from_node == small.cart.from_node and big.cart.to_node == small.cart.to_node and close(big.cart.progress, small.cart.progress) and big.cart.rear_locks == small.cart.rear_locks and big.cart.switches == small.cart.switches, "Bulk and small moving cart agrees through buffer reversal")
		for field in ["elapsed", "_scheduler_at", "_warning_at", "_until_warning", "_announcement_at"]:
			check(close(big.get(field), small.get(field)), "Bulk and small aggregate clock agrees: " + field)
		for i in range(mini(big.warnings.size(), small.warnings.size())):
			check(big.warnings[i].entry == small.warnings[i].entry, "Bulk and small warning entry agrees")
			for field in ["spawn_at", "check_at", "remaining"]:
				check(close(big.warnings[i][field], small.warnings[i][field]), "Bulk and small individual clock agrees: " + field)
		for i in range(mini(big.trains.size(), small.trains.size())):
			check(big.trains[i].from_node == small.trains[i].from_node and big.trains[i].to_node == small.trains[i].to_node and close(big.trains[i].progress, small.trains[i].progress), "Bulk and small train motion agrees")
	var sim = fresh()
	sim.elapsed = sim.config.round_duration - sim.config.warning_stagger
	sim._announcement_at = INF
	sim.warnings = [{"entry": "U", "remaining": sim.config.warning_stagger}, {"entry": "W", "remaining": sim.config.warning_stagger}]
	sim.advance(sim.config.warning_stagger)
	check(sim.won and sim.trains.is_empty() and sim.warnings.is_empty(), "Round deadline suppresses both arrivals and clears warnings")
	check(sim._scheduler_at == INF and sim._warning_at == INF and sim._announcement_at == INF and sim._until_warning == INF, "Outcome clears all pending clocks")
	var before := snapshot(sim)
	sim.advance(data.comparison_time)
	check(snapshot(sim) == before, "Win freezes all state")
	sim.restart()
	check(not sim.won and not sim.lost and sim.elapsed == 0.0 and sim.warnings.is_empty() and sim.trains.is_empty(), "Restart clears outcome and both warnings")
	check(sim._announcement_at == sim.config.first_warning_delay and sim._scheduler_at == sim.config.first_warning_delay and sim._warning_at == INF, "Restart resets announcement and aggregate clocks")
	sim = fresh()
	blocker(sim, "L", "J", 0.0)
	blocker(sim, "L", "J", 0.0)
	sim.warnings = [{"entry": "U", "remaining": sim.config.warning_duration}, {"entry": "W", "remaining": sim.config.warning_duration}]
	sim.advance(data.step)
	check(sim.lost and sim.warnings.is_empty() and sim._scheduler_at == INF and sim._announcement_at == INF, "Collision clears both pending warnings and retries")
	before = snapshot(sim)
	sim.advance(data.comparison_time)
	sim._schedule()
	check(snapshot(sim) == before, "Loss freezes motion, warnings and scheduler")
	for small_steps in [false, true]:
		sim = fresh()
		blocker(sim, "J", "R", data.blocker_progress)
		var moving = sim._entry_train("L")
		moving.progress = data.tangent_progress
		sim.trains.append(moving)
		sim.elapsed = sim.config.round_duration - data.deadline_window
		sim._announcement_at = INF
		sim.warnings = [{"entry": "U", "remaining": data.deadline_window}, {"entry": "W", "remaining": data.deadline_window}]
		if small_steps:
			while not sim.lost and not sim.won:
				sim.advance(minf(data.step, sim.remaining_time()))
		else:
			sim.advance(data.deadline_window)
		check(sim.lost and not sim.won and sim.loss_reason == "train_train" and close(sim.elapsed, sim.config.round_duration), "Exact-deadline collision wins over both warnings and victory in either stepping mode")
		check(sim.warnings.is_empty() and sim._scheduler_at == INF and sim.trains.size() == 2, "Deadline collision clears both warnings without inserting trains")


func run() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string("res://config/traffic_pressure_test_cases.json"))
	test_pair()
	test_held()
	test_plan_times()
	test_geometry()
	test_pressure()
	test_clocks()
	print("Traffic pressure: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
