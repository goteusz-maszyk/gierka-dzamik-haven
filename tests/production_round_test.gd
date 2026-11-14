extends SceneTree

const Traffic = preload("res://scripts/traffic_simulation.gd")
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


func fresh(seed_value: int, start: int, elapsed: float):
	var r = Traffic.new()
	r.rng.seed = seed_value
	r.cart.rng.seed = int(data.cart_seed)
	r.cart.restart(start)
	# Late-phase fixtures shift time, not geometry, motion, safety or spawn settings.
	r.elapsed = elapsed
	r._announcement_at = elapsed + r.config.first_warning_delay
	r._sync_schedule()
	return r


func vehicle_state(vehicle) -> Dictionary:
	var position: Vector2 = vehicle.cart_position()
	return {
		"from": vehicle.from_node, "to": vehicle.to_node,
		"progress": vehicle.progress, "position": [position.x, position.y],
		"rear_locks": vehicle.rear_locks.duplicate(), "lost": vehicle.lost,
		"exits_safely": vehicle.exits_safely,
		"switches": vehicle.switches.duplicate()
	}


func snapshot(r) -> Dictionary:
	var vehicles: Array = [vehicle_state(r.cart)]
	for train in r.trains:
		vehicles.append(vehicle_state(train))
	var locks: Dictionary = {}
	for id in r.cart.switches:
		locks[id] = r.is_locked(id)
	# Train constructors randomize unused motion RNGs; only cart and traffic RNGs
	# belong to the reproducibly seeded fixture and are used in this comparison.
	return {
		"lost": r.lost, "won": r.won, "reason": r.loss_reason,
		"elapsed": r.elapsed, "remaining": r.remaining_time(),
		"warnings": r.warnings.duplicate(true), "vehicles": vehicles,
		"switches": r.cart.switches.duplicate(), "global_locks": locks,
		"traffic_rng": r.rng.state, "cart_rng": r.cart.rng.state,
		"start": r.cart.start_index, "scheduler": r._scheduler_at,
		"warning_at": r._warning_at, "announcement_at": r._announcement_at,
		"until_warning": r._until_warning
	}


func compare(actual: Variant, expected: Variant, path: String, tolerance: float) -> void:
	if actual is Dictionary and expected is Dictionary:
		check(actual.size() == expected.size(), path + " dictionary size")
		for key in expected:
			check(actual.has(key), path + " missing " + str(key))
			if actual.has(key):
				compare(actual[key], expected[key], path + "." + str(key), tolerance)
	elif actual is Array and expected is Array:
		check(actual.size() == expected.size(), path + " array size")
		for i in range(mini(actual.size(), expected.size())):
			compare(actual[i], expected[i], path + "[%d]" % i, tolerance)
	elif actual is float and expected is float:
		check(actual == expected or absf(actual - expected) <= tolerance,
			"%s: %.12f != %.12f (tolerance %.12f)" % [path, actual, expected, tolerance])
	else:
		check(actual == expected, "%s: %s != %s" % [path, actual, expected])


func frozen(r, label: String) -> void:
	var before := snapshot(r)
	for id in r.cart.switches:
		check(not r.toggle(id), label + " terminal toggle blocked: " + id)
	r.advance(data.bulk_delta)
	compare(snapshot(r), before, label + " frozen", 0.0)


func observe_until(r, deadline: float, counts: Dictionary, label: String) -> void:
	while r.elapsed < deadline and not r.lost and not r.won:
		var previous_trains: Array = r.trains.duplicate()
		var pending: Array = r.warnings.duplicate(true)
		r.advance(minf(data.small_step, deadline - r.elapsed))
		var entries: Array = []
		check(r.warnings.size() <= int(data.expected.max_warnings), label + " pending warning limit")
		counts.max_pending = maxi(counts.get("max_pending", 0), r.warnings.size())
		for warning in r.warnings:
			check(warning.entry in r.cart.config.exits, label + " warning uses real entry")
			check(warning.entry not in entries, label + " distinct pending entries")
			entries.append(warning.entry)
			check(warning.check_at >= warning.spawn_at, label + " independent retry deadline")
			check(absf(warning.remaining - maxf(0.0, warning.spawn_at - r.elapsed)) <= data.epsilon, label + " warning countdown matches spawn deadline")
			var seen := false
			for prior in pending:
				if prior.entry == warning.entry and prior.spawn_at == warning.spawn_at:
					seen = true
					check(prior.spawn_at == warning.spawn_at and warning.check_at >= prior.check_at, label + " pending deadlines preserved")
			if not seen:
				counts.warnings += 1
				if counts.has("gaps") and is_finite(counts.last_spawn):
					counts.gaps.append(r.elapsed - counts.last_spawn)
		for train in r.trains:
			check(is_same(train.switches, r.cart.switches), label + " global switches shared")
			if train not in previous_trains:
				var matched := false
				for prior in pending:
					if prior.entry == train.from_node and prior.check_at <= r.elapsed + data.epsilon:
						matched = true
				check(matched, label + " spawn follows any prior pending entry warning")
				counts.spawns += 1
				counts.last_spawn = r.elapsed


func winning_trace() -> bool:
	var fixture: Dictionary = data.winning_trace
	var label := "full-round trace seed=%d start=%d" % [fixture.seed, fixture.start]
	check(fixture.elapsed == 0.0, label + " starts at elapsed zero")
	var bulk = fresh(int(fixture.seed), int(fixture.start), fixture.elapsed)
	var small = fresh(int(fixture.seed), int(fixture.start), fixture.elapsed)
	for id in bulk.cart.switches:
		var initial := int(bulk.cart.config.switches[id].initial)
		check(bulk.cart.switches[id] == initial and small.cart.switches[id] == initial, label + " configured initial switch: " + id)
	compare(snapshot(bulk), snapshot(small), label + " initial", 0.0)
	var counts := {"warnings": 0, "spawns": 0}
	var previous_time := 0.0
	for event in fixture.events:
		var time: float = event[0]
		var id: String = event[1]
		check(time >= previous_time and time < bulk.config.round_duration, label + " ordered input time")
		bulk.advance(time - bulk.elapsed)
		observe_until(small, time, counts, label)
		check(absf(bulk.elapsed - time) <= data.epsilon and absf(small.elapsed - time) <= data.epsilon, label + " reaches input time")
		compare(snapshot(bulk), snapshot(small), label + " before input " + str(time), data.epsilon)
		for r in [bulk, small]:
			check(not r.lost and not r.won, label + " input before outcome")
			check(r.cart.switches.has(id) and not r.is_locked(id), label + " input available: " + id)
			var before: int = r.cart.switches[id]
			check(r.toggle(id), label + " input accepted: " + id)
			check(r.cart.switches[id] == 1 - before, label + " input changes switch: " + id)
		previous_time = time
	bulk.advance(data.bulk_delta)
	observe_until(small, small.config.round_duration, counts, label)
	compare(snapshot(bulk), snapshot(small), label + " bulk/small final", data.epsilon)
	for r in [bulk, small]:
		check(r.won and not r.lost, label + " actual full-round win")
		check(r.elapsed == 67.0 and r.elapsed == r.config.round_duration and r.remaining_time() == 0.0, label + " full 67-second deadline")
		check(r.warnings.is_empty(), label + " terminal warnings cleared")
		frozen(r, label)
	check(counts.warnings >= counts.spawns and counts.spawns >= data.minimum_spawns, label + " actual warned traffic throughout round")
	check(counts.warnings == int(fixture.warnings), label + " fixture warning count")
	check(counts.spawns == int(fixture.spawns), label + " fixture successful spawn count")
	check(counts.get("max_pending", 0) == int(data.expected.max_warnings), label + " simultaneous pending warnings exercised")
	print("%s: won=%s elapsed=%.12f warnings=%d spawns=%d inputs=%d" % [label, small.won, small.elapsed, counts.warnings, counts.spawns, fixture.events.size()])
	return bulk.won and small.won and fixture.elapsed == 0.0


func run() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string("res://config/production_round_test_cases.json"))
	var production = Traffic.new()
	for key in data.expected:
		check(production.config[key] == data.expected[key], "Production setting: " + key)
	check(production.cart.config.exits.size() == 6, "All six real entries available")
	check(production.cart.config.starts.size() == 4, "All four production starts covered")
	check(data.bulk_delta > production.config.round_duration, "Bulk delta exceeds entire round")
	check(data.small_step < production.config.retry_interval, "Observation step resolves retry cadence")
	check(data.small_step <= data.maximum_observation_step, "Observation resolves simultaneous callbacks")
	var wins := 0
	var late_phase_wins := 0
	var full_round_wins := 0
	var losses := 0
	var multi_spawn_runs := 0
	var early_gaps: Array = []
	var late_gaps: Array = []
	for group in data.groups:
		for start in group.starts:
			var label := "seed=%d start=%d phase=%.2f" % [group.seed, start, group.elapsed]
			var bulk = fresh(int(group.seed), int(start), group.elapsed)
			var small = fresh(int(group.seed), int(start), group.elapsed)
			compare(snapshot(bulk), snapshot(small), label + " initial", 0.0)
			bulk.advance(data.bulk_delta)
			var counts := {"warnings": 0, "spawns": 0, "last_spawn": -INF,
				"gaps": early_gaps if group.elapsed == 0.0 else late_gaps}
			observe_until(small, small.config.round_duration, counts, label)
			var warnings: int = counts.warnings
			var spawns: int = counts.spawns
			check(small.lost != small.won, label + " reaches exactly one terminal outcome")
			check(warnings >= spawns, label + " observed warnings precede successful spawns")
			check(spawns == int(group.spawns[group.starts.find(start)]), label + " fixture successful spawn count")
			var outcome: String = "win" if small.won else small.loss_reason
			check(outcome == group.outcomes[group.starts.find(start)], label + " fixture terminal outcome")
			check(absf(small.elapsed - group.terminal_times[group.starts.find(start)]) <= data.epsilon, label + " fixture terminal event time")
			if spawns >= data.minimum_spawns:
				multi_spawn_runs += 1
			compare(snapshot(bulk), snapshot(small), label + " bulk/small", data.epsilon)
			if small.won:
				wins += 1
				if group.elapsed == 0.0:
					full_round_wins += 1
				if group.elapsed > 0.0:
					late_phase_wins += 1
				check(small.elapsed == small.config.round_duration and small.remaining_time() == 0.0, label + " win at deadline")
			else:
				losses += 1
				check(small.loss_reason in ["cart_exit", "cart_train", "train_train"], label + " actual loss reason")
			check(small.warnings.is_empty() and bulk.warnings.is_empty(), label + " terminal warnings cleared")
			frozen(bulk, label + " bulk")
			frozen(small, label + " small")
			print("%s: %s at %.12f, warnings=%d spawns=%d" % [label, ("late-phase win" if group.elapsed > 0.0 else "full-round win") if small.won else small.loss_reason, small.elapsed, warnings, spawns])
	check(multi_spawn_runs > 0, "At least two actual spawns in series observed")
	check(not early_gaps.is_empty() and not late_gaps.is_empty(), "Observed early and late spawn-to-warning intervals")
	if not early_gaps.is_empty() and not late_gaps.is_empty():
		check(late_gaps.max() < early_gaps.min(), "Actual late spawning cadence faster than early cadence")
	if winning_trace():
		full_round_wins += 1
		wins += 1
	check(wins > 0 and losses > 0, "Production losses and actual deadline wins exercised")
	check(full_round_wins > 0, "At least one actual full-round win from elapsed zero, independently of late-phase wins")
	print("Production round: %d checks, %d failures; full-round wins=%d late-phase wins=%d losses=%d" % [checks, failures, full_round_wins, late_phase_wins, losses])
	quit(1 if failures else 0)
