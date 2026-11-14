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
	check(config.exits.size() == int(cases.exit_count), "Eight open exits")
	check(config.approach_tracks.size() == cases.approaches.size(), "Four approach tracks")
	check(config.tracks.size() + config.approach_tracks.size() == int(cases.total_track_count), "Ten total tracks")
	check(config.switches.size() == int(cases.switch_count), "Twenty-four switches")
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
				sim.switches[id] = 0
				check(sim.route(id, nodes[i - 1]) == nodes[i + 1], "Straight route continues rightward")
				check(sim.route(id, nodes[i + 1]) == nodes[i - 1], "Straight route continues leftward")
				check(int(config.switches[id].initial) == 0, "All switches initially straight")
	check(siding_count == int(cases.siding_count), "Four complete sidings")
	for index in range(config.approach_tracks.size()):
		var approach: Dictionary = config.approach_tracks[index]
		var expected: Dictionary = cases.approaches[index]
		check(approach.kind == "approach" and approach.nodes == [expected.exit, expected.junction], "Explicit named angled approach")
		var end: String = approach.nodes[0]
		var junction: String = approach.nodes[1]
		expected_exits.append(end)
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
	actual_buffers.sort()
	actual_exits.sort()
	check(actual_buffers == expected_buffers, "Both ends of each siding buffered, and no others")
	check(actual_exits == expected_exits, "Only main and approach ends are open")
	for id in config.nodes:
		var adjacent := neighbors(config, id)
		if id in config.buffers or id in config.exits:
			check(adjacent.size() == 1 and not config.switches.has(id), "Terminal has exactly one neighbor")
		else:
			check(adjacent.size() == 3 and config.switches.has(id), "Every junction is a three-port switch")
			var ports: Array = config.switches[id].ports.duplicate()
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
	# Traverse both crossovers of every neighboring pair in both directions.
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
			var direction := int(signf(sim.point(crossover[1]).x - sim.point(crossover[0]).x))
			var path: Array = [upper[upper.find(crossover[0]) - direction], crossover[0], crossover[1], lower[lower.find(crossover[1]) + direction]]
			follow_path(sim, path)
			path.reverse()
			follow_path(sim, path)
	for track in config.tracks:
		var path: Array = track.nodes.duplicate()
		follow_path(sim, path)
		path.reverse()
		follow_path(sim, path)
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
		var incoming: Vector2 = sim.heading()
		var distance: float = sim.edge_length() - sim.progress
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
	if sim.to_node in sim.config.exits:
		sim.advance(remaining / sim.config.speed)
		check(sim.lost and sim.to_node == path[-1], "Path reaches chosen open exit: " + str(path[-1]))
	else:
		# Finish before the last node so a terminal buffer does not start a new leg.
		sim.advance((remaining - sim.config.cart_length / 2.0) / sim.config.speed)
		check(not sim.lost and sim.to_node == path[-1], "Path reaches final edge")
	if small != null:
		var duration: float = (remaining - sim.config.cart_length / 2.0) / sim.config.speed
		while duration > 0.0:
			var step := minf(duration, cases.small_step)
			small.advance(step)
			duration -= step
		check_same_simulations(sim, small, "Circuit final edge")


func test_cross_station(sim) -> void:
	for approach in cases.approaches:
		for target in sim.config.exits:
			if target == approach.exit:
				continue
			var path := find_path(sim, [approach.exit, approach.junction], target)
			check(not path.is_empty(), "Every approach reaches every other exit: %s -> %s" % [approach.exit, target])
			if not path.is_empty():
				follow_path(sim, path)
	for index in range(sim.config.starts.size()):
		var start: Dictionary = sim.config.starts[index]
		for track in sim.config.tracks:
			if track.kind != "siding":
				continue
			var target: String = track.nodes[-1]
			var path := find_path(sim, [start.from, start.to], target)
			check(not path.is_empty(), "Every start reaches every siding: %s -> %s" % [index, target])
			if not path.is_empty():
				follow_path(sim, path, index)


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
		for setting in [0, 1]:
			var next: String = previous
			if current not in config.buffers:
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
			check(sim.is_locked(path[index + 1]), "Comparison retains rear lock at diagonal endpoint")


func test_circuit_step_equivalence(sim) -> void:
	var small = Simulation.new()
	var path: Array = cases.buffer_circuit
	var circuit_distance := 0.0
	for i in range(1, path.size() - 1):
		circuit_distance += sim.point(path[i - 1]).distance_to(sim.point(path[i]))
	for duration in [(circuit_distance + cases.epsilon) / sim.config.speed, cases.large_delta]:
		sim.restart(0)
		place(sim, path[0], path[1], 0.0)
		# This specific circuit also permits fixed settings for an uninterrupted advance.
		for i in range(1, path.size() - 1):
			if sim.config.switches.has(path[i]):
				var options: Array = cases.routes[path[i]][path[i - 1]]
				if options[sim.switches[path[i]]] != path[i + 1]:
					sim.switches[path[i]] = options.find(path[i + 1])
		for i in range(1, path.size() - 1):
			if sim.config.switches.has(path[i]):
				check(cases.routes[path[i]][path[i - 1]][sim.switches[path[i]]] == path[i + 1], "Fixed circuit settings permit every visit: " + str(path[i]))
		small.restart(0)
		small.switches = sim.switches.duplicate()
		place(small, path[0], path[1], 0.0)
		sim.advance(duration)
		var remaining: float = duration
		while remaining > 0.0:
			var step := minf(remaining, cases.small_step)
			small.advance(step)
			remaining -= step
		check(not sim.lost and not small.lost, "Six-row buffer circuit remains closed across large delta")
		check_same_simulations(sim, small, "Whole six-row circuit")


func run() -> void:
	cases = JSON.parse_string(FileAccess.get_file_as_string("res://config/cart_test_cases.json"))
	var sim = Simulation.new()
	var config: Dictionary = sim.config
	var half: float = config.cart_length / 2.0
	var speed: float = config.speed
	test_topology(sim)
	test_cross_station(sim)
	test_T1_52_diversion_preserves_eastbound_heading(sim)
	for id in config.switches:
		for neighbor in config.switches[id].ports:
			check([id, neighbor] in config.edges or [neighbor, id] in config.edges, "Switch ports match graph edges")
	check(cases.routes.size() == config.switches.size(), "Independent route fixtures cover every switch")
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
	# All eight buffers reflect, including the four not used by starts.
	for buffer in config.buffers:
		var neighbor: String = neighbors(config, buffer)[0]
		sim.restart()
		place(sim, neighbor, buffer, 0.0)
		var incoming_heading: Vector2 = sim.heading()
		var distance: float = sim.edge_length()
		sim.advance((distance + half) / speed)
		check(sim.from_node == buffer and sim.to_node == neighbor, "Buffer reverses direction: " + buffer)
		check(near(incoming_heading.dot(sim.heading()), -1.0), "Buffer exactly reverses heading: " + buffer)
		check(near(sim.progress, half), "Buffer carries leftover distance: " + buffer)
		check(sim.rear_locks.is_empty(), "Buffer does not leave a stale rear lock: " + buffer)
		check(sim.is_locked(neighbor) == (sim.edge_length() - sim.progress <= half), "Buffer return locks switch only on front contact: " + buffer)
	# Starts cover exactly the four distinct sidings, with safe straight routing.
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
	# Geometry keeps switches and UI targets disjoint in the actual 320x180 viewport.
	for id in config.switches:
		for other in config.switches:
			if id != other:
				check(sim.point(id).distance_to(sim.point(other)) > config.visual.click_radius * 2.0, "Disjoint switch hit areas")
	var visual: Dictionary = config.visual
	var bounds: Array[Rect2] = []
	for edge in config.edges:
		bounds.append(Rect2(sim.point(edge[0]), Vector2.ZERO).expand(sim.point(edge[1])).grow(visual.track_width / 2.0))
	for id in config.nodes:
		var extent: Vector2
		if id in config.buffers:
			extent = Vector2(visual.buffer_width / 2.0, visual.buffer_half_width + visual.buffer_width / 2.0)
		elif id in config.exits:
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
	check(game.status.text.contains("Elapsed: %.1fs" % game.traffic.elapsed) and game.status.text.contains("Trains: 0"), "Scene status shows elapsed time and train count")
	check(not game.loss_overlay.visible and not game.restart_button.is_visible_in_tree() and not game.menu_button.is_visible_in_tree(), "Loss controls stay hidden during play")
	var hud_controls: Array = game.status.get_parent().get_children()
	hud_controls.append_array(game.get_node("CanvasLayer").get_children())
	for control in hud_controls:
		if control is Control and control != game.status.get_parent() and control != game.loss_overlay:
			var ui_rect: Rect2 = control.get_global_rect()
			if control is Label:
				# Labels retain a taller pre-font minimum size; only their text is drawn.
				ui_rect.size.y = control.get_line_height() * control.get_line_count()
			for rect in bounds:
				check(not ui_rect.intersects(rect), "Tracks, markers and hit areas clear UI: %s %s vs %s" % [control.text, ui_rect, rect])
	var ui_switch: String = cases.ui_switch
	var ui_incoming: String = cases.ui_incoming
	var ui_exit: String = cases.ui_exit
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
	place(game.simulation, ui_switch, ui_exit, game.simulation.point(ui_switch).distance_to(game.simulation.point(ui_exit)) - half - cases.epsilon)
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
	place(game.simulation, ui_switch, ui_exit, game.simulation.point(ui_switch).distance_to(game.simulation.point(ui_exit)) - half - cases.epsilon)
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
