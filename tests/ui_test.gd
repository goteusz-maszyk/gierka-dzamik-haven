extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func click(position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)


func reach_win(game) -> void:
	game.traffic.config.spawning_enabled = false
	game.restart()
	game.simulation.restart(0)
	game._process(game.traffic.config.round_duration * 2.0)
	check(game.traffic.won and not game.traffic.lost, "Automatic deadline produces a win")
	check(game.traffic.elapsed == game.traffic.config.round_duration, "Oversized frame clips to deadline")


func run() -> void:
	root.size = Vector2i(320, 180)
	root.content_scale_size = Vector2i(320, 180)
	var game = load("res://scene/game.tscn").instantiate()
	game.get_node("CanvasLayer/GameUI/Status").text += " | edited"
	game.get_node("CanvasLayer/GameUI/WinOverlay/Panel/Reason").text += " Well done!"
	var authored_nodes: Array = game.find_children("*", "", true, false)
	game.traffic.config.spawning_enabled = false
	root.add_child(game)
	current_scene = game
	game.set_process(false)
	await process_frame
	check(not game.loss_overlay.visible, "Loss overlay must start hidden")
	check(not game.win_overlay.visible, "Win overlay must start hidden")
	check(game.find_children("*", "", true, false) == authored_nodes, "Ready does not create UI nodes")
	for label_name in ["HUDTitle", "Status", "Help"]:
		check(game.get_node("CanvasLayer/GameUI/" + label_name) is Label, "Persistent HUD label: " + label_name)
	check(game.status.text.contains("Left: 67s") and game.status.text.contains("Trains: 0"), "Status starts with the full countdown")
	check(not game.status.text.contains("No timer / trains"), "No obsolete no-trains text")
	check(game.status.text.ends_with(" | edited"), "Scene-authored status template survives runtime updates")
	check(game.restart_button is TextureButton and game.menu_button is TextureButton, "Reuse graphic buttons")
	check(game.win_restart_button is TextureButton and game.win_menu_button is TextureButton, "Win reuses graphic buttons")
	check(game.CART_TEXTURE.resource_path == "res://ciufa.png", "Supplied ciufa texture belongs to the player cart")
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/traffic_test_cases.json"))
	game.simulation.restart(0)
	game.traffic.rng.seed = int(fixtures.seed)
	game.traffic.config.spawning_enabled = true
	check(game.traffic.config.max_warnings == 2 and game.traffic.config.pressure_weight == 6.0 and game.traffic.config.first_warning_delay == 2.0, "UI exercises default two-warning pressure scheduler")
	game._process(game.traffic.config.first_warning_delay)
	check(game.traffic.warnings.size() == 2 and game.traffic.trains.is_empty(), "First real scheduler event exposes two pending warnings")
	var pending: Array = game.traffic.warnings.duplicate(true)
	for warning in pending:
		check(warning.entry in game.simulation.config.exits and warning.remaining > 0.0 and warning.spawn_at == warning.check_at, "Visible warning data names a real entry and future arrival")
	if pending.size() == 2:
		check(pending[0].entry != pending[1].entry and pending[0].spawn_at < pending[1].spawn_at, "Both warnings have independent entries and staggered arrivals")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var warned: Image = root.get_texture().get_image()
		game.traffic.warnings.clear()
		game.queue_redraw()
		await RenderingServer.frame_post_draw
		var clear: Image = root.get_texture().get_image()
		for warning in pending:
			var center: Vector2 = game.get_global_transform_with_canvas() * game.simulation.point(warning.entry)
			var radius: float = game.ui_config.warning_radius + game.ui_config.warning_width
			var changed := false
			for y in range(maxi(0, floori(center.y - radius)), mini(warned.get_height(), ceili(center.y + radius))):
				for x in range(maxi(0, floori(center.x - radius)), mini(warned.get_width(), ceili(center.x + radius))):
					changed = changed or warned.get_pixel(x, y) != clear.get_pixel(x, y)
			check(changed, "Real draw renders warning ring at " + warning.entry)
	else:
		print("Warning ring pixel checks require a rendering display; skipped in headless mode")
	check(game.find_children("*", "", true, false) == authored_nodes, "Two warnings draw without creating UI nodes")
	game.traffic.config.spawning_enabled = false
	game.restart()
	game.simulation.restart(0)
	for id in game.simulation.switches:
		if not game.traffic.is_locked(id):
			var setting: int = game.simulation.switches[id]
			click(game.simulation.point(id))
			check(game.simulation.switches[id] == 1 - setting, "Active board click toggles an unlocked switch")
			break
	var messages := {
		"cart_exit": "The cart left the station.",
		"cart_train": "The cart collided with a train.",
		"train_train": "Two trains collided."
	}
	for reason in messages:
		var train = load("res://scripts/cart_simulation.gd").new()
		train.config = game.simulation.config.duplicate()
		for key in game.traffic.config.train:
			train.config[key] = game.traffic.config.train[key]
		var switch_id: String = game.simulation.switches.keys()[0]
		train.from_node = game.simulation.config.switches[switch_id].ports[0]
		train.to_node = switch_id
		train.progress = train.edge_length() - train.config.cart_length / 2.0
		game.traffic.trains.append(train)
		for entry in game.simulation.config.exits.slice(0, 2):
			game.traffic.warnings.append({"entry": entry, "remaining": game.traffic.config.warning_duration})
		check(game.traffic.warnings.size() == 2, "Core loss begins with both warnings pending")
		var setting: int = game.simulation.switches[switch_id]
		click(game.simulation.point(switch_id))
		check(game.simulation.switches[switch_id] == setting, "Train-locked switch rejects UI click")
		game._update_ui()
		check(game.status.text.contains("Trains: 1"), "Status shows live train count")
		game.queue_redraw()
		await process_frame
		var loss_switch := ""
		for id in game.simulation.switches:
			if not game.traffic.is_locked(id):
				loss_switch = id
				var previous: int = game.simulation.switches[id]
				click(game.simulation.point(id))
				check(game.simulation.switches[id] == 1 - previous, "Loss-input control switch toggles before loss")
				break
		check(not loss_switch.is_empty(), "Loss-input check needs an unlocked switch")
		game.traffic.elapsed = 12.0
		if reason == "cart_exit":
			game.simulation.from_node = game.traffic._entry_train(game.simulation.config.exits[0]).to_node
			game.simulation.to_node = game.simulation.config.exits[0]
			game.simulation.progress = game.simulation.edge_length() - game.simulation.config.cart_length / 2.0
		elif reason == "cart_train":
			train.from_node = game.simulation.from_node
			train.to_node = game.simulation.to_node
			train.progress = game.simulation.progress
		else:
			game.traffic.trains.append(game.traffic._copy_vehicle(train, game.simulation.switches))
		game._process(fixtures.small_step)
		check(game.traffic.lost and game.traffic.loss_reason == reason and game.traffic.warnings.is_empty(), "Core loss clears both warnings: " + reason)
		var stopped_at: float = game.traffic.elapsed
		var stopped_rng: int = game.traffic.rng.state
		var stopped_schedule: Array = [game.traffic._announcement_at, game.traffic._scheduler_at, game.traffic._warning_at, game.traffic._until_warning]
		check(game.loss_overlay.visible, "Loss overlay must show: " + reason)
		check(not game.win_overlay.visible, "Loss displays only one overlay")
		check(root.gui_get_focus_owner() == game.restart_button, "Loss focuses Retry")
		game.menu_button.grab_focus()
		check(game.loss_reason.text == messages[reason], "Correct loss message: " + reason)
		var position: Vector2 = train.cart_position()
		game._process(1.0)
		check(root.gui_get_focus_owner() == game.menu_button, "Loss focus is not stolen on later frames")
		check(game.traffic.elapsed == stopped_at and train.cart_position() == position and game.traffic.rng.state == stopped_rng, "Traffic and selection remain frozen after loss")
		check(stopped_schedule == [INF, INF, INF, INF] and stopped_schedule == [game.traffic._announcement_at, game.traffic._scheduler_at, game.traffic._warning_at, game.traffic._until_warning], "Loss disables and freezes every scheduler clock")
		var before: Dictionary = game.simulation.switches.duplicate()
		click(game.simulation.point(loss_switch))
		check(game.simulation.switches == before, "Overlay must block board clicks")
		check(Rect2(Vector2.ZERO, Vector2(320, 180)).encloses(game.loss_reason.get_global_rect()), "Reason fits viewport")
		check(game.loss_reason.get_line_count() <= 2, "Loss reason fits its label")
		for button in [game.restart_button, game.menu_button]:
			check(Rect2(Vector2.ZERO, Vector2(320, 180)).encloses(button.get_global_rect()), "Loss button fits viewport")
		click(game.restart_button.get_global_rect().get_center())
		check(not game.loss_overlay.visible and not game.win_overlay.visible and not game.traffic.lost and not game.traffic.won, "Retry click resets and hides both results")
		check(root.gui_get_focus_owner() != game.restart_button, "Retry releases hidden loss button focus")
		check(game.traffic.elapsed == 0.0 and game.traffic.trains.is_empty() and game.traffic.warnings.is_empty(), "Retry clears round state")
		check(game.traffic._announcement_at == game.traffic.config.first_warning_delay and game.traffic._scheduler_at == game.traffic.config.first_warning_delay and game.traffic._until_warning == game.traffic.config.first_warning_delay and game.traffic._warning_at == INF, "Loss Retry resets every scheduler clock")
		check(game.simulation == game.traffic.cart, "Simulation alias survives restart")
	game.simulation.restart(0)
	var win_train = load("res://scripts/cart_simulation.gd").new()
	for key in game.traffic.config.train:
		win_train.config[key] = game.traffic.config.train[key]
	win_train.restart(2)
	win_train.switches = game.simulation.switches
	win_train.exits_safely = true
	game.traffic.trains.append(win_train)
	game._process(0.25)
	check(game.status.text.contains("Left: 67s"), "Countdown rounds upward while time remains")
	game._process(game.traffic.config.round_duration - game.traffic.elapsed - 0.01)
	check(not game.traffic.won and game.status.text.contains("Left: 1s"), "Active final fraction never displays zero")
	for entry in game.simulation.config.exits.slice(0, 2):
		game.traffic.warnings.append({"entry": entry, "remaining": game.traffic.config.warning_duration})
	check(game.traffic.warnings.size() == 2, "Victory begins with both warnings pending")
	game._process(1.0)
	check(game.traffic.won and not game.traffic.lost, "Core automatically wins at the deadline")
	check(game.traffic.elapsed == game.traffic.config.round_duration, "UI advances only to the core deadline")
	check(game.status.text.contains("Left: 0s"), "Completed round displays zero remaining")
	check(game.win_overlay.visible and not game.loss_overlay.visible, "Only win overlay is shown")
	check(game.win_overlay.get_node("Panel/Title").text == "ROUND WON", "Win title is scene authored")
	check(game.win_message.text == "You survived %s seconds. Well done!" % str(game.traffic.config.round_duration), "Win message formats config duration and preserves scene edits")
	check(root.gui_get_focus_owner() == game.win_restart_button, "Win initially focuses Retry")
	game.win_menu_button.grab_focus()
	var cart_position: Vector2 = game.simulation.cart_position()
	var train_position: Vector2 = win_train.cart_position()
	var trains: Array = game.traffic.trains.duplicate()
	var elapsed: float = game.traffic.elapsed
	var switches: Dictionary = game.simulation.switches.duplicate()
	game._process(10.0)
	check(root.gui_get_focus_owner() == game.win_menu_button, "Win focus is not stolen on later frames")
	check(game.traffic.elapsed == elapsed and game.simulation.cart_position() == cart_position, "Player and clock freeze after win")
	check(game.traffic.trains == trains and win_train.cart_position() == train_position, "Trains freeze after win")
	check(game.traffic.warnings.is_empty(), "Win clears warnings")
	check([game.traffic._announcement_at, game.traffic._scheduler_at, game.traffic._warning_at, game.traffic._until_warning] == [INF, INF, INF, INF], "Win disables and freezes every scheduler clock")
	click(game.simulation.point("T1_52"))
	for id in switches:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = game.simulation.point(id)
		event.pressed = true
		game._unhandled_input(event)
	check(game.simulation.switches == switches, "Win blocks both GUI and direct board input")
	await process_frame
	for control in [game.win_overlay.get_node("Panel"), game.win_overlay.get_node("Panel/Title"), game.win_message, game.win_restart_button, game.win_menu_button]:
		check(Rect2(Vector2.ZERO, Vector2(320, 180)).encloses(control.get_global_rect()), "Win UI fits viewport: " + control.name)
	check(game.win_message.get_line_count() <= 2, "Win message fits label")
	check(game.find_children("*", "", true, false) == authored_nodes, "Results do not create UI nodes")
	click(game.win_restart_button.get_global_rect().get_center())
	check(not game.win_overlay.visible and not game.loss_overlay.visible and not game.traffic.won and not game.traffic.lost, "Win Retry resets and hides both overlays")
	check(game.traffic.elapsed == 0.0 and game.traffic.remaining_time() == game.traffic.config.round_duration, "Win Retry restores countdown")
	check(game.traffic.trains.is_empty() and game.traffic.warnings.is_empty() and game.traffic.loss_reason.is_empty(), "Win Retry clears complete traffic state")
	check(game.simulation == game.traffic.cart and not game.simulation.lost and game.simulation.rear_locks.is_empty(), "Win Retry restores player and alias")
	for id in game.simulation.switches:
		check(game.simulation.switches[id] == game.simulation.config.switches[id].initial, "Win Retry restores switch: " + id)
	check(game.traffic._until_warning == game.traffic.config.first_warning_delay and game.traffic._announcement_at == game.traffic.config.first_warning_delay and game.traffic._scheduler_at == game.traffic.config.first_warning_delay and game.traffic._warning_at == INF, "Win Retry resets every spawn scheduler clock")
	check(root.gui_get_focus_owner() != game.win_restart_button and root.gui_get_focus_owner() != game.win_menu_button, "Win Retry releases hidden button focus")
	var accept := InputEventAction.new()
	accept.action = "ui_accept"
	accept.pressed = true
	root.push_input(accept)
	accept = accept.duplicate()
	accept.pressed = false
	root.push_input(accept)
	check(not game.win_overlay.visible and not game.loss_overlay.visible, "Keyboard accept cannot activate hidden result buttons")
	reach_win(game)
	game.traffic.lost = true
	game.traffic.loss_reason = "cart_exit"
	game._update_ui()
	check(game.loss_overlay.visible and not game.win_overlay.visible, "Loss takes priority if both result flags are set")
	var button = game.restart_button
	button.text = "Again"
	check(button.get_node("BoxContainer/Label").text == "Again", "Button text setter updates label")
	button.size = Vector2(72, 32)
	await process_frame
	check(button.get_node("Background").size == button.size, "Button artwork follows editor size")
	check(button.get_node("BoxContainer").size == button.size, "Button label layout follows editor size")
	game.traffic.lost = true
	game.traffic.loss_reason = "cart_exit"
	game._update_ui()
	click(game.menu_button.get_global_rect().get_center())
	await process_frame
	await process_frame
	check(current_scene != null and current_scene.scene_file_path == "res://scene/main_menu.tscn", "Menu click returns to menu")
	current_scene.get_node("TomekIPrzyjaciele").stop()
	click(current_scene.get_node("StartBtn").get_global_rect().get_center())
	await process_frame
	await process_frame
	check(current_scene.scene_file_path == "res://scene/game.tscn", "Start click enters shared game scene")
	game = current_scene
	game.set_process(false)
	reach_win(game)
	click(game.win_menu_button.get_global_rect().get_center())
	await process_frame
	await process_frame
	check(current_scene.scene_file_path == "res://scene/main_menu.tscn", "Win Menu click returns to menu")
	current_scene.get_node("TomekIPrzyjaciele").stop()
	click(current_scene.get_node("StartBtn").get_global_rect().get_center())
	await process_frame
	await process_frame
	game = current_scene
	game.set_process(false)
	click(game.get_node("CanvasLayer/GiveUpBtn").get_global_rect().get_center())
	await process_frame
	await process_frame
	check(current_scene != null and current_scene.scene_file_path == "res://scene/main_menu.tscn", "Give Up click returns to menu")
	current_scene.get_node("TomekIPrzyjaciele").stop()
	await create_timer(0.1).timeout
	current_scene.queue_free()
	await process_frame
	print("UI checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
