extends SceneTree

const Simulation = preload("res://scripts/cart_simulation.gd")
const Game = preload("res://scene/game.tscn")
const GameUI = preload("res://config/game_ui.tscn")

var cases: Dictionary
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func place(sim, source: String, target: String, distance: float) -> void:
	sim.from_node = source
	sim.to_node = target
	sim.progress = distance
	sim.rear_locks.clear()
	sim.lost = false


func near(a: float, b: float) -> bool:
	return absf(a - b) < cases.epsilon


func click(position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)


func neighbors(config: Dictionary, id: String) -> Array:
	var result := []
	for edge in config.edges:
		if id in edge:
			result.append(edge[1] if edge[0] == id else edge[0])
	return result


func test_topology(sim) -> void:
	var config: Dictionary = sim.config
	check(config.tracks.size() == cases.track_y.size(), "Exactly six full-length tracks")
	check(config.buffers.size() == int(cases.buffer_count), "Eight buffers")
	check(config.exits.size() == int(cases.exit_count), "Four main-track exits")
	check(config.approach_tracks.size() == cases.approaches.size(), "Two approach tracks")
	check(config.tracks.size() + config.approach_tracks.size() == int(cases.total_track_count), "Eight total tracks")
	check(config.switches.size() == int(cases.switch_count), "Ten active switches")
	check(config.merges.size() == int(cases.merge_count), "Twelve passive merges")
	check(sim.switches.size() == config.switches.size(), "Runtime state contains only active switches")
	sim.restart(0)
	for id in config.switches:
		check(config.switches[id].initial == 0 or config.switches[id].initial == 1, "Binary initial switch setting: " + id)
		check(int(config.switches[id].initial) == (1 if id in ["T3_102", "T4_52"] else 0), "Only requested main switches start diverted: " + id)
		check(sim.switches[id] == int(config.switches[id].initial), "Initial restart matches config: " + id)
	for id in cases.removed_nodes:
		check(not config.nodes.has(id) and not config.switches.has(id) and not config.merges.has(id) and id not in config.exits, "Removed node absent from topology: " + id)
		for edge in config.edges:
			check(id not in edge, "No obsolete edge endpoint: " + id)
		for switch in config.switches.values():
			check(id not in switch.ports, "No obsolete switch port: " + id)
		for merge in config.merges.values():
			check(id not in merge.ports, "No obsolete merge port: " + id)
	var covered := {}
	var expected_buffers := []
	var expected_exits := []
	var siding_count := 0
	for index in range(config.tracks.size()):
		var track: Dictionary = config.tracks[index]
		var nodes: Array = track.nodes
		var is_main: bool = float(index) in cases.main_indices
		check(track.kind == ("main" if is_main else "siding"), "Only middle two tracks are main")
		if not is_main:
			siding_count += 1
		check(near(sim.point(nodes[0]).x, cases.left_x), "Track reaches left end")
		check(near(sim.point(nodes[-1]).x, cases.right_x), "Track reaches right end")
		if index > 0:
			check(sim.point(nodes[0]).y > sim.point(config.tracks[index - 1].nodes[0]).y, "Tracks ordered top to bottom")
		for end in [nodes[0], nodes[-1]]:
			if is_main:
				expected_exits.append(end)
			else:
				expected_buffers.append(end)
		for i in range(nodes.size()):
			var id: String = nodes[i]
			check(not covered.has(id), "Parallel tracks do not share nodes")
			covered[id] = true
			check(near(sim.point(id).y, cases.track_y[index]), "Full track is horizontal at its configured y")
			if i > 0:
				check(sim.point(id).x > sim.point(nodes[i - 1]).x, "Track nodes ordered left to right")
				check(id in neighbors(config, nodes[i - 1]), "Continuous horizontal track edge")
			if i > 0 and i < nodes.size() - 1:
				if config.switches.has(id):
					sim.switches[id] = 0
				check(sim.route(id, nodes[i - 1]) == nodes[i + 1], "Straight route continues rightward")
				check(sim.route(id, nodes[i + 1]) == nodes[i - 1], "Straight route continues leftward")
	check(siding_count == int(cases.siding_count), "Four complete sidings")
	var expected_entries := expected_exits.duplicate()
	for index in range(config.approach_tracks.size()):
		var approach: Dictionary = config.approach_tracks[index]
		var expected: Dictionary = cases.approaches[index]
		check(approach.kind == "approach" and approach.nodes == [expected.exit, expected.junction], "Explicit named angled approach")
		var end: String = approach.nodes[0]
		var junction: String = approach.nodes[1]
		expected_entries.append(end)
		covered[end] = true
		check(sim.point(end).distance_to(Vector2(expected.position[0], expected.position[1])) < cases.epsilon, "Approach exit position: " + end)
		check(sim.point(junction).distance_to(Vector2(expected.junction_position[0], expected.junction_position[1])) < cases.epsilon, "Approach junction position: " + junction)
		var offset: Vector2 = sim.point(end) - sim.point(junction)
		check(near(rad_to_deg(atan2(absf(offset.y), absf(offset.x))), cases.approach_angle_degrees), "Approach is thirty degrees to horizontal: " + end)
		check(signf(offset.x) == expected.side, "Approach extends outward left/right: " + end)
		var outer: Dictionary = config.tracks[int(expected.row)]
		check(junction in outer.nodes and end in neighbors(config, junction), "Approach joins outermost siding")
		check(offset.y < 0.0 if int(expected.row) == 0 else offset.y > 0.0, "Approach extends outside outer row")
	check(covered.size() == config.nodes.size(), "Metadata covers every node")
	expected_buffers.sort()
	expected_exits.sort()
	var actual_buffers: Array = config.buffers.duplicate()
	var actual_exits: Array = config.exits.duplicate()
	var actual_entries: Array = config.entries.duplicate()
	actual_buffers.sort()
	actual_exits.sort()
	check(actual_buffers == expected_buffers, "Both ends of each siding buffered, and no others")
	check(actual_exits == expected_exits, "Only main-track ends are exits")
	expected_entries.sort()
	actual_entries.sort()
	check(actual_entries == expected_entries, "Main and approach ends accept arrivals")
	for id in config.nodes:
		var adjacent := neighbors(config, id)
		if id in config.buffers or id in config.entries:
			check(adjacent.size() == 1 and not config.switches.has(id) and not config.merges.has(id), "Terminal has exactly one neighbor and no routing metadata")
		else:
			check(adjacent.size() == 3 and config.switches.has(id) != config.merges.has(id), "Every junction has exactly one routing kind")
			var metadata: Dictionary = config.switches[id] if config.switches.has(id) else config.merges[id]
			var ports: Array = metadata.ports.duplicate()
			ports.sort()
			adjacent.sort()
			check(ports == adjacent, "Ports cover exactly the incident edges")
	var visited := {}
	var pending: Array = [config.tracks[0].nodes[0]]
	while not pending.is_empty():
		var id: String = pending.pop_back()
		if visited.has(id):
			continue
		visited[id] = true
		pending.append_array(neighbors(config, id))
	check(visited.size() == config.nodes.size(), "Entire graph is one connected network")
	for i in range(config.edges.size()):
		var edge: Array = config.edges[i]
		var unique := true
		var clear := true
		for j in range(i + 1, config.edges.size()):
			var other: Array = config.edges[j]
			unique = unique and edge != other and edge != [other[1], other[0]]
			if edge[0] in other or edge[1] in other:
				continue
			clear = clear and Geometry2D.segment_intersects_segment(sim.point(edge[0]), sim.point(edge[1]), sim.point(other[0]), sim.point(other[1])) == null
		check(unique, "No duplicate edge: " + str(edge))
		check(clear, "Tracks intersect only at explicit junctions: " + str(edge))
	# Each crossover can be selected only from its active end.
	for index in range(config.tracks.size() - 1):
		var upper: Array = config.tracks[index].nodes
		var lower: Array = config.tracks[index + 1].nodes
		var crossovers := []
		for edge in config.edges:
			if edge[0] in upper and edge[1] in lower:
				crossovers.append(edge)
			elif edge[1] in upper and edge[0] in lower:
				crossovers.append([edge[1], edge[0]])
		check(crossovers.size() == int(cases.crossovers_per_pair), "Two crossovers per neighboring pair")
		if crossovers.size() != int(cases.crossovers_per_pair):
			continue
		crossovers.sort_custom(func(a, b): return sim.point(a[0]).x < sim.point(b[0]).x)
		for crossover in crossovers:
			var offset: Vector2 = sim.point(crossover[1]) - sim.point(crossover[0])
			check(not near(offset.x, 0.0) and offset.y > 0.0, "Crossover is diagonal between neighboring rows")
			var group := 0 if crossover in cases.crossover_groups[0] else 1
			check(crossover == cases.crossover_groups[group][index], "Explicit crossover pair IDs")
			check(near(sim.point(crossover[0]).x, cases.crossover_upper_x[group][index]) and near(sim.point(crossover[1]).x, cases.crossover_lower_x[group][index]), "Explicit staggered crossover coordinates")
			check(offset.x > 0.0 if group == 0 else offset.x < 0.0, "Opposite backslash and slash groups")
			var active: String = crossover[group]
			var passive: String = crossover[1 - group]
			check(config.switches.has(active) and config.merges.has(passive), "Each crossover has one active and one passive endpoint")
			var active_ports: Array = config.switches[active].ports
			var passive_ports: Array = config.merges[passive].ports
			check(sim.point(active_ports[0]).x < sim.point(active).x and sim.point(passive_ports[0]).x > sim.point(passive).x, "Crossover active stem left, passive stem right")
			var path: Array = [active_ports[0], active, passive, passive_ports[0]]
			follow_path(sim, path)
	for track in config.tracks:
		var path: Array = track.nodes.duplicate()
		follow_path(sim, path)
		path.reverse()
		follow_path(sim, path)
	for segment in cases.merged_segments:
		check(segment in config.edges or [segment[1], segment[0]] in config.edges, "Merged straight segment is one full edge")
		for direction in [segment, [segment[1], segment[0]]]:
			sim.restart(0)
			place(sim, direction[0], direction[1], 0.0)
			var heading: Vector2 = sim.heading()
			var distance: float = sim.edge_length()
			sim.advance((distance - cases.epsilon) / config.speed)
			check(sim.from_node == direction[0] and sim.to_node == direction[1] and near(sim.progress, distance - cases.epsilon), "Full merged segment traversed without intermediate junction: " + str(direction))
			sim.advance(cases.epsilon * 2.0 / config.speed)
			check(sim.from_node == direction[1] and heading.dot(sim.heading()) > 0.0, "Merged segment reaches far switch without reversing: " + str(direction))
	var circuit_rows := {}
	for id in cases.buffer_circuit:
		for index in range(config.tracks.size()):
			if id in config.tracks[index].nodes:
				circuit_rows[index] = true
	check(circuit_rows.size() == config.tracks.size(), "Buffer-assisted circuit crosses all six rows")
	follow_path(sim, cases.buffer_circuit, -1, Simulation.new())
	check(not sim.lost, "Buffer-assisted cross-station return circuit stays inside the network")


func follow_path(sim, path: Array, start_index: int = -1, small = null) -> void:
	sim.restart(maxi(start_index, 0))
	if start_index < 0:
		place(sim, path[0], path[1], 0.0)
	else:
		check(sim.from_node == path[0] and sim.to_node == path[1], "Path uses actual configured start")
	if small != null:
		small.restart(0)
		place(small, sim.from_node, sim.to_node, sim.progress)
	for i in range(1, path.size() - 1):
		var current: String = path[i]
		var next: String = path[i + 1]
		if sim.config.switches.has(current):
			var expected: Array = cases.routes[current][path[i - 1]]
			check(next in expected, "Fixture route permits path at " + current)
			if next not in expected:
				return
			var setting := expected.find(next)
			if sim.switches[current] != setting:
				check(sim.toggle(current), "Path switch is clear before entry: " + current)
			if small != null and small.switches[current] != setting:
				check(small.toggle(current), "Small-step path switch is clear before entry: " + current)
		elif sim.config.merges.has(current):
			check(cases.merge_routes[current][path[i - 1]] == next, "Fixed merge permits path at " + current)
		var incoming: Vector2 = sim.heading()
		var distance: float = sim.distance_to_event()
		var duration: float = (distance + cases.epsilon) / sim.config.speed
		sim.advance(duration)
		if small != null:
			while duration > 0.0:
				var step := minf(duration, cases.small_step)
				small.advance(step)
				duration -= step
			check_same_simulations(sim, small, "Circuit at " + current)
		check(not sim.lost and sim.from_node == current and sim.to_node == next, "Actual traversal: %s -> %s -> %s" % [path[i - 1], current, next])
		if current in sim.config.buffers:
			check(sim.to_node == path[i - 1] and incoming.dot(sim.heading()) < 0.0, "Only buffer reverses on path: " + current)
		else:
			check(sim.to_node != path[i - 1] and incoming.dot(sim.heading()) > 0.0 and incoming.x * sim.heading().x > 0.0, "Switch traversal preserves forward direction: " + current)
	var remaining: float = sim.edge_length() - sim.progress
	var final_distance: float = remaining if sim.to_node in sim.config.exits else remaining - sim.config.cart_length / 2.0 - cases.epsilon
	var final_duration: float = final_distance / sim.config.speed
	sim.advance(final_duration)
	if sim.to_node in sim.config.exits:
		check(sim.lost and sim.to_node == path[-1], "Path reaches chosen open exit: " + str(path[-1]))
	else:
		# Finish before the last node so a terminal buffer does not start a new leg.
		check(not sim.lost and sim.to_node == path[-1], "Path reaches final edge")
	if small != null:
		var duration: float = final_duration
		while duration > 0.0:
			var step := minf(duration, cases.small_step)
			small.advance(step)
			duration -= step
		check_same_simulations(sim, small, "Circuit final edge")


func test_cross_station(sim) -> void:
	for approach in cases.approaches:
		var classified: Array = approach.reachable_exits + approach.unreachable_exits
		var other_exits: Array = sim.config.exits.duplicate()
		classified.sort()
		other_exits.sort()
		check(classified == other_exits, "Reachability fixtures classify every exit exactly once: " + approach.exit)
		for destination in cases.approaches:
			check(find_path(sim, [approach.exit, approach.junction], destination.exit).is_empty(), "Neither approach is reachable outbound")
		for target in approach.reachable_exits:
			var path := find_path(sim, [approach.exit, approach.junction], target)
			check(not path.is_empty(), "Approach reaches declared exit: %s -> %s" % [approach.exit, target])
			if not path.is_empty():
				follow_path(sim, path, -1, Simulation.new())
		for target in approach.unreachable_exits:
			check(find_path(sim, [approach.exit, approach.junction], target).is_empty(), "One-sided crossovers prevent approach reaching left main exit: %s -> %s" % [approach.exit, target])
	for path in cases.main_through_paths:
		follow_path(sim, path, -1, Simulation.new())
	for index in range(sim.config.starts.size()):
		var start: Dictionary = sim.config.starts[index]
		for track in sim.config.tracks:
			if track.kind != "siding":
				continue
			var target: String = track.nodes[-1]
			var path := find_path(sim, [start.from, start.to], target)
			check(not path.is_empty(), "Every start reaches every siding: %s -> %s" % [index, target])
			if not path.is_empty():
				follow_path(sim, path, index, Simulation.new())


func find_path(sim, source: Array, target: String) -> Array:
	var config: Dictionary = sim.config
	var pending: Array = [[source[0], source[1]]]
	var visited := {}
	while not pending.is_empty():
		var candidate: Array = pending.pop_front()
		var current: String = candidate[-1]
		var previous: String = candidate[-2]
		if current == target:
			return candidate
		var state := previous + ":" + current
		if visited.has(state):
			continue
		visited[state] = true
		if current in config.exits:
			continue
		for setting in ([0, 1] if config.switches.has(current) else [0]):
			var next: String = previous
			if current not in config.buffers:
				if config.switches.has(current):
					sim.switches[current] = setting
				next = sim.route(current, previous)
			pending.append(candidate + [next])
	return []


func check_same_simulations(sim, small, context: String) -> void:
	check(sim.from_node == small.from_node and sim.to_node == small.to_node, context + ": frame-independent directed edge")
	check(near(sim.progress, small.progress) and sim.lost == small.lost, context + ": frame-independent progress and loss")
	check(sim.cart_position().distance_to(small.cart_position()) < cases.epsilon, context + ": frame-independent position")
	check(sim.switches == small.switches, context + ": same switch settings")
	for id in sim.config.switches:
		check(sim.is_locked(id) == small.is_locked(id), context + ": frame-independent lock: " + id)
	check(sim.rear_locks.keys() == small.rear_locks.keys(), context + ": frame-independent rear lock membership")
	for id in sim.rear_locks:
		check(near(sim.rear_locks[id], small.rear_locks[id]), context + ": frame-independent rear clearance: " + id)


func test_T1_52_diversion_preserves_eastbound_heading(sim) -> void:
	sim.restart(0)
	sim.switches.T1_52 = 1
	place(sim, "T1_left", "T1_52", 0.0)
	var incoming: Vector2 = sim.heading()
	sim.advance((sim.edge_length() + cases.epsilon) / sim.config.speed)
	check(sim.from_node == "T1_52" and sim.to_node == "T2_72", "T1_52 regression: west entry diverts down-right, not back left")
	check(incoming.dot(sim.heading()) > 0.0 and sim.heading().x > 0.0, "T1_52 regression: diversion retains eastbound travel")
	var previous: Vector2 = sim.cart_position()
	sim.advance(cases.small_step)
	check(sim.cart_position().x > previous.x, "T1_52 regression: actual diagonal travel increases x")


func test_diagonal_step_equivalence(sim) -> void:
	var small = Simulation.new()
	var path: Array = cases.diagonal_path
	var first_leg: float = sim.point(path[0]).distance_to(sim.point(path[1]))
	var diagonal: float = sim.point(path[1]).distance_to(sim.point(path[2]))
	var overlap: float = sim.config.cart_length / 4.0
	var durations: Array = [(first_leg + overlap) / sim.config.speed, (first_leg + diagonal + overlap) / sim.config.speed, cases.comparison_time]
	for index in range(durations.size()):
		for model in [sim, small]:
			model.restart(0)
			place(model, path[0], path[1], 0.0)
			for i in range(1, path.size() - 1):
				if model.config.switches.has(path[i]):
					var options: Array = cases.routes[path[i]][path[i - 1]]
					model.switches[path[i]] = options.find(path[i + 1])
		var duration: float = durations[index]
		sim.advance(duration)
		while duration > 0.0:
			var step := minf(duration, cases.small_step)
			small.advance(step)
			duration -= step
		check_same_simulations(sim, small, "Diagonal")
		if index < durations.size() - 1:
			check(sim.from_node == path[index + 1] and sim.to_node == path[index + 2], "Comparison actually crosses diagonal endpoint")
			check(sim.is_locked(path[index + 1]) == sim.config.switches.has(path[index + 1]), "Only active diagonal endpoint retains rear lock")


func test_default_main_diversions(sim) -> void:
	var starts: Array = sim.config.starts.duplicate(true)
	for route in [["T3_left", "T3_72", "T3_102", "T2_122", "T2_102"], ["T4_left", "T4_72", "T4_52", "T5_72", "T5_102"]]:
		var vehicle = Simulation.new()
		place(vehicle, route[0], route[1], 0.0)
		var initial_switches: Dictionary = vehicle.switches.duplicate()
		check(vehicle.switches[route[2]] == 1, "Production main diversion is initially selected: " + route[2])
		var distance: float = vehicle.point(route[0]).distance_to(vehicle.point(route[2]))
		vehicle.advance((distance + cases.epsilon) / vehicle.config.speed)
		check(not vehicle.lost and vehicle.from_node == route[2] and vehicle.to_node == route[3], "Default main-left movement takes selected diversion: " + route[2])
		var before: Vector2 = vehicle.cart_position()
		vehicle.advance(cases.small_step)
		var movement: Vector2 = vehicle.cart_position() - before
		var diagonal: Vector2 = vehicle.point(route[3]) - vehicle.point(route[2])
		check(movement.x > 0.0 and movement.y * diagonal.y > 0.0, "Default diversion physically moves toward inner siding: " + route[2])
		vehicle.advance((vehicle.edge_length() - vehicle.progress + cases.epsilon) / vehicle.config.speed)
		check(not vehicle.lost and vehicle.from_node == route[3] and vehicle.to_node == route[4], "Default main traffic enters inner siding: " + route[2])
		check(vehicle.switches == initial_switches, "Default traffic never auto-toggles switches: " + route[2])
		check(vehicle.config.starts == starts and sim.config.starts == starts, "Default traffic leaves curated cart starts unchanged")
		for index in range(starts.size()):
			sim.restart(index)
			check(sim.from_node == starts[index].from and sim.to_node == starts[index].to and near(sim.progress, starts[index].progress), "Cart retains configured start alongside default traffic: " + str(index))


func test_circuit_step_equivalence(sim) -> void:
	var small = Simulation.new()
	# T5_102 must be straight on descent and diverted on ascent.
	follow_path(sim, cases.buffer_circuit, -1, small)
	for start in range(sim.config.starts.size()):
		sim.restart(start)
		small.restart(start)
		sim.advance(cases.large_delta)
		var remaining: float = cases.large_delta
		while remaining > 0.0:
			var step := minf(remaining, cases.small_step)
			small.advance(step)
			remaining -= step
		check(not sim.lost and not small.lost, "Initial siding remains closed across large delta")
		check_same_simulations(sim, small, "Large delta siding " + str(start))


func run() -> void:
	cases = JSON.parse_string(FileAccess.get_file_as_string("res://config/cart_test_cases.json"))
	var sim = Simulation.new()
	var config: Dictionary = sim.config
	var half: float = config.cart_length / 2.0
	var speed: float = config.speed
	test_topology(sim)
	test_cross_station(sim)
	test_T1_52_diversion_preserves_eastbound_heading(sim)
	test_default_main_diversions(sim)
	for id in config.switches:
		for neighbor in config.switches[id].ports:
			check([id, neighbor] in config.edges or [neighbor, id] in config.edges, "Switch ports match graph edges")
	check(cases.routes.size() == config.switches.size(), "Independent route fixtures cover every switch")
	var active_routes := 0
	for id in config.switches:
		var ports: Array = config.switches[id].ports
		var left := ""
		var right := ""
		var branch := ""
		for neighbor in neighbors(config, id):
			var offset: Vector2 = sim.point(neighbor) - sim.point(id)
			if not near(offset.y, 0.0):
				branch = neighbor
			elif offset.x < 0.0:
				left = neighbor
			else:
				right = neighbor
		check(not left.is_empty() and not right.is_empty() and not branch.is_empty(), "Switch has two horizontal legs and a diagonal branch")
		var stem: String = left if sim.point(branch).x > sim.point(id).x else right
		var straight: String = left if stem == right else right
		check(ports == [stem, straight, branch], "Ports have geometrically correct stem orientation: " + id)
		check(cases.routes[id].size() == ports.size(), "Three independent entry fixtures: " + id)
		for setting in [0, 1]:
			sim.switches[id] = setting
			for incoming in cases.routes[id]:
				active_routes += 1
				var expected: String = cases.routes[id][incoming][setting]
				check(sim.route(id, incoming) == expected, "Route table: " + id)
				place(sim, incoming, id, sim.point(incoming).distance_to(sim.point(id)) - half - cases.epsilon)
				check(not sim.is_locked(id) and sim.toggle(id), "Switch remains usable before front contact: " + id)
				sim.switches[id] = setting
				place(sim, incoming, id, sim.point(incoming).distance_to(sim.point(id)) - half)
				check(sim.is_locked(id), "Front locks: " + id)
				check(not sim.toggle(id), "Reject occupied click: " + id)
				var incoming_heading: Vector2 = sim.heading()
				sim.advance((half + cases.epsilon) / speed)
				check(sim.from_node == id and sim.to_node == expected, "Traverse route: " + id)
				check(sim.to_node != incoming, "No immediate same-node backtrack: " + id)
				check(incoming_heading.dot(sim.heading()) > 0.0, "Switch outgoing heading remains forward: " + id)
				check(incoming_heading.x * sim.heading().x > 0.0, "Switch preserves horizontal direction: " + id)
				var before_position: Vector2 = sim.cart_position()
				check(sim.is_locked(id), "Rear locks: " + id)
				sim.advance((half - cases.epsilon * 2.0) / speed)
				check((sim.cart_position().x - before_position.x) * signf(incoming_heading.x) >= 0.0, "Actual outgoing travel makes nonnegative horizontal progress: " + id)
				check(sim.is_locked(id) and not sim.toggle(id), "Rear stays locked until clear: " + id)
				sim.advance(cases.epsilon * 2.0 / speed)
				check(not sim.is_locked(id), "Rear releases: " + id)
				check(sim.toggle(id), "Can switch after clearing: " + id)
				sim.switches[id] = setting
	check(active_routes == int(cases.active_route_count), "All active routes covered")
	check(cases.merge_routes.size() == config.merges.size(), "Independent fixed fixtures cover every merge")
	var merge_routes := 0
	for id in config.merges:
		var ports: Array = config.merges[id].ports
		check(config.merges[id].keys() == ["ports"], "Passive metadata has ports only: " + id)
		check(cases.merge_routes[id].size() == ports.size(), "Three fixed entry fixtures: " + id)
		var stem_side := signf(sim.point(ports[0]).x - sim.point(id).x)
		check(stem_side != 0.0 and signf(sim.point(ports[1]).x - sim.point(id).x) == -stem_side and signf(sim.point(ports[2]).x - sim.point(id).x) == -stem_side, "Passive stem opposite straight and branch: " + id)
		for incoming in cases.merge_routes[id]:
			merge_routes += 1
			sim.restart(0)
			var expected: String = cases.merge_routes[id][incoming]
			check(sim.route(id, incoming) == expected, "Fixed route table: " + id)
			place(sim, incoming, id, sim.point(incoming).distance_to(sim.point(id)) - half)
			var before: Dictionary = sim.switches.duplicate()
			check(not sim.is_locked(id) and not sim.toggle(id), "Passive front contact is neither locked nor selectable: " + id)
			var incoming_heading: Vector2 = sim.heading()
			sim.advance((half + cases.epsilon) / speed)
			check(sim.from_node == id and sim.to_node == expected and sim.to_node != incoming, "Traverse fixed merge: " + id)
			check(incoming_heading.dot(sim.heading()) > 0.0 and incoming_heading.x * sim.heading().x > 0.0, "Passive traversal preserves forward horizontal heading: " + id)
			check(not sim.is_locked(id) and not sim.rear_locks.has(id) and not sim.toggle(id), "Passive rear contact never creates lock or accepts toggle: " + id)
			check(sim.switches == before and not sim.switches.has(id), "Passive routing adds no selectable state: " + id)
	check(merge_routes == int(cases.merge_route_count), "All fixed merge routes covered")
	# All eight buffers reflect, including the four not used by starts.
	for buffer in config.buffers:
		var neighbor: String = neighbors(config, buffer)[0]
		sim.restart()
		place(sim, neighbor, buffer, 0.0)
		var incoming_heading: Vector2 = sim.heading()
		sim.advance_distance(sim.distance_to_event())
		check(sim.from_node == buffer and sim.to_node == neighbor, "Buffer reverses direction: " + buffer)
		check(near(incoming_heading.dot(sim.heading()), -1.0), "Buffer exactly reverses heading: " + buffer)
		check(near(sim.progress, half), "Buffer reflects at front contact: " + buffer)
		check(sim.rear_locks.is_empty(), "Buffer does not leave a stale rear lock: " + buffer)
		check(sim.is_locked(neighbor) == (config.switches.has(neighbor) and sim.edge_length() - sim.progress <= half), "Buffer return locks only active switch on front contact: " + buffer)
	# Starts cover exactly the four distinct sidings with production initial routing.
	var start_tracks := {}
	for index in range(config.starts.size()):
		sim.restart(index)
		check(sim.to_node in neighbors(config, sim.from_node), "Configured start is on a real edge")
		check(sim.to_node in config.buffers, "Start faces buffer")
		var start_from: String = sim.from_node
		var buffer: String = sim.to_node
		var to_buffer: float = sim.edge_length() - sim.progress
		check(to_buffer > half, "Start has buffer clearance")
		check(sim.progress > half, "Start has rear clearance")
		for track_index in range(config.tracks.size()):
			var track: Dictionary = config.tracks[track_index]
			if sim.from_node in track.nodes and sim.to_node in track.nodes:
				check(track.kind == "siding", "Start lies on a siding")
				start_tracks[track_index] = true
		sim.advance((to_buffer + half) / speed)
		check(sim.from_node == buffer and sim.to_node == start_from, "Buffer reverses direction")
		check(near(sim.progress, half), "Buffer carries leftover distance")
		check(not sim.is_locked(start_from), "Buffer does not trap a switch lock")
		sim.advance(cases.large_delta)
		check(not sim.lost, "Initial switches keep cart safely bouncing on siding")
	check(start_tracks.size() == int(cases.siding_count) and config.starts.size() == int(cases.siding_count), "Starts cover all four sidings exactly once")
	# Every open end loses, stops and is recoverable by restart.
	for exit_id in config.exits:
		for edge in config.edges:
			if exit_id not in edge:
				continue
			var neighbor: String = edge[1] if edge[0] == exit_id else edge[0]
			place(sim, neighbor, exit_id, 0.0)
			var exit_threshold: float = sim.edge_length() - half
			sim.advance((exit_threshold - cases.epsilon) / speed)
			check(not sim.lost, "No loss before front reaches exit: " + exit_id)
			sim.advance(cases.epsilon * 2.0 / speed)
			check(sim.lost, "Exit loss: " + exit_id)
			check(near(sim.progress, exit_threshold), "Front stops at station boundary: " + exit_id)
			var stopped: Vector2 = sim.cart_position()
			sim.advance(cases.large_delta)
			check(sim.cart_position() == stopped, "Lost cart stays stopped")
			check(not sim.toggle(neighbor), "No switches after loss")
			sim.restart()
			check(not sim.lost and sim.rear_locks.is_empty(), "Restart clears loss and locks")
			for id in config.switches:
				check(sim.switches[id] == int(config.switches[id].initial), "Restart resets switch " + id)
	test_diagonal_step_equivalence(sim)
	test_circuit_step_equivalence(sim)
	var seen := {}
	for i in range(int(cases.random_restarts)):
		sim.restart()
		seen[sim.start_index] = true
	check(seen.size() == config.starts.size(), "Random restart covers all safe sidings")
	if "--cart-only" in OS.get_cmdline_user_args():
		print("Cart prototype (cart only): %d checks, %d failures" % [checks, failures])
		quit(1 if failures else 0)
		return
	# Geometry keeps switches and UI targets disjoint in the actual 320x180 viewport.
	for id in config.switches:
		for other in config.switches:
			if id != other:
				check(sim.point(id).distance_to(sim.point(other)) > config.visual.click_radius * 2.0, "Disjoint switch hit areas")
		for passive in config.merges:
			check(sim.point(id).distance_to(sim.point(passive)) > config.visual.click_radius, "Passive nodes outside active click radius")
	var visual: Dictionary = config.visual
	var bounds: Array[Rect2] = []
	for edge in config.edges:
		bounds.append(Rect2(sim.point(edge[0]), Vector2.ZERO).expand(sim.point(edge[1])).grow(visual.track_width / 2.0))
	for id in config.nodes:
		var extent: Vector2
		if id in config.buffers:
			extent = Vector2(visual.buffer_width / 2.0, visual.buffer_half_width + visual.buffer_width / 2.0)
		elif id in config.entries:
			extent = Vector2.ONE * float(visual.exit_radius)
		else:
			extent = Vector2.ONE * maxf(visual.click_radius, maxf(visual.switch_radius, visual.route_arm + visual.route_width / 2.0))
		bounds.append(Rect2(sim.point(id) - extent, extent * 2.0))
	var viewport := Rect2(Vector2.ZERO, Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height")))
	for rect in bounds:
		check(viewport.encloses(rect), "Drawn tracks, markers and hit areas fit viewport")
	var ui_state: SceneState = GameUI.get_state()
	var authored_labels := []
	for index in range(ui_state.get_node_count()):
		if ui_state.get_node_type(index) == &"Label":
			authored_labels.append(str(ui_state.get_node_path(index)).trim_prefix("./"))
	for path in ["HUDTitle", "Status", "Help", "LossOverlay/Panel/Title", "LossOverlay/Panel/Reason"]:
		check(path in authored_labels, "PackedScene contains editor-authored label: " + path)
	check(not FileAccess.get_file_as_string("res://scripts/game.gd").contains("Label.new("), "Game does not create runtime labels")
	var game = Game.instantiate()
	game.traffic.config.spawning_enabled = false
	game.traffic.restart()
	game.simulation.restart(0)
	root.add_child(game)
	var initial_position: Vector2 = game.simulation.cart_position()
	await process_frame
	await process_frame
	check(game.simulation.cart_position() != initial_position, "Scene automatically advances cart")
	game.set_process(false)
	await process_frame
	check(game.simulation == game.traffic.cart, "Scene exposes the traffic cart as simulation")
	check(game.traffic.elapsed > 0.0 and game.traffic.trains.is_empty() and game.traffic.warnings.is_empty(), "Automatic scene movement runs without train spawning")
	check(game.status.text.contains("Left: %ds" % ceili(game.traffic.remaining_time())) and game.status.text.contains("Trains: 0"), "Scene status shows remaining time and train count")
	check(not game.loss_overlay.visible and not game.restart_button.is_visible_in_tree() and not game.menu_button.is_visible_in_tree(), "Loss controls stay hidden during play")
	var hud_controls: Array = game.status.get_parent().get_children()
	hud_controls.append_array(game.get_node("CanvasLayer").get_children())
	for control in hud_controls:
		if control is Control and control != game.status.get_parent() and control != game.loss_overlay and control != game.win_overlay:
			var ui_rect: Rect2 = control.get_global_rect()
			if control is Label:
				# Labels retain a taller pre-font minimum size; only their text is drawn.
				ui_rect.size.y = control.get_line_height() * control.get_line_count()
			for rect in bounds:
				check(not ui_rect.intersects(rect), "Tracks, markers and hit areas clear UI: %s %s vs %s" % [control.text, ui_rect, rect])
	var ui_switch: String = cases.ui_switch
	var ui_incoming: String = cases.ui_incoming
	var ui_exit: String = cases.ui_exit
	var ui_exit_neighbor: String = neighbors(config, ui_exit)[0]
	for id in cases.removed_nodes:
		game.restart()
		game.simulation.restart(0)
		var before_click: Dictionary = game.simulation.switches.duplicate()
		var position: Array = cases.removed_nodes[id]
		click(Vector2(position[0], position[1]))
		check(game.simulation.switches == before_click, "Obsolete node position is not clickable: " + id)
		check(not game.traffic.toggle(id), "Obsolete node cannot be toggled: " + id)
	for id in config.merges:
		game.restart()
		game.simulation.restart(0)
		var before_click: Dictionary = game.simulation.switches.duplicate()
		click(game.simulation.point(id))
		check(game.simulation.switches == before_click, "Passive viewport click changes no switches: " + id)
		check(not game.simulation.toggle(id) and not game.traffic.toggle(id), "Passive node rejects simulation and traffic toggles: " + id)
	for id in config.switches:
		game.restart()
		game.simulation.restart(0)
		check(not game.simulation.is_locked(id), "Deterministic UI start leaves target unlocked: " + id)
		var initial: int = game.simulation.switches[id]
		for setting in [1 - initial, initial]:
			var before_click: Dictionary = game.simulation.switches.duplicate()
			click(game.simulation.point(id))
			check(game.simulation.switches[id] == setting, "Viewport click changes switch both ways: " + id)
			before_click[id] = setting
			check(game.simulation.switches == before_click, "Click changes only intended switch: " + id)
	place(game.simulation, ui_incoming, ui_switch, game.simulation.point(ui_incoming).distance_to(game.simulation.point(ui_switch)) - half)
	var before: int = game.simulation.switches[ui_switch]
	click(game.simulation.point(ui_switch))
	check(game.simulation.switches[ui_switch] == before, "Mouse click respects overlap lock")
	place(game.simulation, ui_exit_neighbor, ui_exit, game.simulation.point(ui_exit_neighbor).distance_to(game.simulation.point(ui_exit)) - half - cases.epsilon)
	game.set_process(true)
	await process_frame
	await process_frame
	check(game.simulation.lost and game.traffic.lost and game.traffic.loss_reason == "cart_exit" and game.loss_overlay.visible, "Automatic cart exit ends traffic round and shows loss overlay")
	for button in [game.restart_button, game.menu_button]:
		check(button.is_visible_in_tree(), "Loss button appears after actual loss")
		check(button.size.x >= button.get_minimum_size().x, "Button text fits")
		check(viewport.encloses(button.get_global_rect()), "Nested loss button fits viewport")
	var stopped_position: Vector2 = game.simulation.cart_position()
	var stopped_elapsed: float = game.traffic.elapsed
	await process_frame
	check(game.simulation.cart_position() == stopped_position and game.traffic.elapsed == stopped_elapsed, "Lost scene stops cart movement and timer")
	game.set_process(false)
	game.simulation.switches[ui_switch] = 1
	click(game.restart_button.get_global_rect().get_center())
	check(not game.simulation.lost and not game.traffic.lost and not game.loss_overlay.visible, "Restart button resets loss and hides overlay")
	check(game.traffic.elapsed == 0.0 and game.traffic.trains.is_empty() and game.traffic.warnings.is_empty(), "Restart resets traffic round state")
	check(game.simulation.switches.size() == config.switches.size(), "Restart preserves all switches")
	for id in config.switches:
		check(game.simulation.switches[id] == int(config.switches[id].initial), "Retry resets switch: " + id)
	game.simulation.restart(0)
	place(game.simulation, ui_exit_neighbor, ui_exit, game.simulation.point(ui_exit_neighbor).distance_to(game.simulation.point(ui_exit)) - half - cases.epsilon)
	game.set_process(true)
	await process_frame
	await process_frame
	game.set_process(false)
	check(game.traffic.lost and game.loss_overlay.visible and game.menu_button.is_visible_in_tree(), "Menu is available after another actual cart exit")
	current_scene = game
	click(game.menu_button.get_global_rect().get_center())
	await process_frame
	await process_frame
	check(current_scene != null and current_scene.scene_file_path == "res://scene/main_menu.tscn", "Menu button returns to existing menu")
	current_scene.get_node("TomekIPrzyjaciele").stop()
	await create_timer(cases.audio_cleanup_delay).timeout
	var start_button: Control = current_scene.get_node("StartBtn")
	check(start_button.size.x > 0.0 and start_button.size.y > 0.0, "Menu Start has a clickable area")
	click(start_button.get_global_rect().get_center())
	await process_frame
	await process_frame
	check(current_scene != null and current_scene.scene_file_path == "res://scene/game.tscn", "Menu Start opens prototype again")
	current_scene.queue_free()
	await process_frame
	print("Cart prototype: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
