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
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)


func run() -> void:
	root.size = Vector2i(320, 180)
	root.content_scale_size = Vector2i(320, 180)
	var game = load("res://scene/game.tscn").instantiate()
	game.get_node("CanvasLayer/GameUI/Status").text += " | edited"
	root.add_child(game)
	current_scene = game
	game.set_process(false)
	await process_frame
	check(not game.loss_overlay.visible, "Loss overlay must start hidden")
	for label_name in ["HUDTitle", "Status", "Help"]:
		check(game.get_node("CanvasLayer/GameUI/" + label_name) is Label, "Persistent HUD label: " + label_name)
	check(game.status.text.contains("Elapsed:") and game.status.text.contains("Trains:"), "Status must describe traffic")
	check(not game.status.text.contains("No timer / trains"), "No obsolete no-trains text")
	check(game.status.text.ends_with(" | edited"), "Scene-authored status template survives runtime updates")
	check(game.restart_button is TextureButton and game.menu_button is TextureButton, "Reuse graphic buttons")
	check(game.CART_TEXTURE.resource_path == "res://ciufa.png", "Supplied ciufa texture belongs to the player cart")
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
		game.traffic.warnings.append({"entry": game.simulation.config.exits[0], "remaining": 1.0})
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
		game.traffic.lost = true
		game.traffic.loss_reason = reason
		game.traffic.elapsed = 12.0
		game._process(0.0)
		check(game.loss_overlay.visible, "Loss overlay must show: " + reason)
		check(game.loss_reason.text == messages[reason], "Correct loss message: " + reason)
		var position: Vector2 = train.cart_position()
		game._process(1.0)
		check(game.traffic.elapsed == 12.0 and train.cart_position() == position, "Traffic remains frozen after loss")
		var before: Dictionary = game.simulation.switches.duplicate()
		click(game.simulation.point(loss_switch))
		check(game.simulation.switches == before, "Overlay must block board clicks")
		check(Rect2(Vector2.ZERO, Vector2(320, 180)).encloses(game.loss_reason.get_global_rect()), "Reason fits viewport")
		check(game.loss_reason.get_line_count() <= 2, "Loss reason fits its label")
		for button in [game.restart_button, game.menu_button]:
			check(Rect2(Vector2.ZERO, Vector2(320, 180)).encloses(button.get_global_rect()), "Loss button fits viewport")
		click(game.restart_button.get_global_rect().get_center())
		check(not game.loss_overlay.visible and not game.traffic.lost, "Retry click resets and hides loss")
		check(game.traffic.elapsed == 0.0 and game.traffic.trains.is_empty() and game.traffic.warnings.is_empty(), "Retry clears round state")
		check(game.simulation == game.traffic.cart, "Simulation alias survives restart")
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
	await create_timer(0.1).timeout
	change_scene_to_file("res://scene/game.tscn")
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
