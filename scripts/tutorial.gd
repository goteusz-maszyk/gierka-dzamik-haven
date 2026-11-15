extends Control

const SESSION_KEY = "zadupiowice_tutorial_shown"

var active := false
var watch_warning := false
var game
var step := 0
var _demo_running := false
var _give_up_state: Dictionary = {}
var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/tutorial.json"))
@onready var pages: Array[Node] = $Panel/Pages.get_children()
@onready var next_button: Button = $Panel/Next
@onready var skip_button: Button = $Panel/Skip
@onready var progress: Label = $Panel/Progress
@onready var progress_format: String = progress.text
@onready var next_text: String = next_button.text
@onready var goal_format: String = $Panel/Pages/Goal.text


func begin(game_scene) -> void:
	game = game_scene
	if get_tree().get_meta(SESSION_KEY, false):
		return
	get_tree().set_meta(SESSION_KEY, true)
	game.simulation.restart(int(settings.start_index))
	game.simulation.switches[settings.switch_id] = 1 - int(settings.switch_setting)
	if not game.simulation.buffer_hit.is_connected(_on_buffer_hit):
		game.simulation.buffer_hit.connect(_on_buffer_hit)
	if not game.traffic.warning_created.is_connected(_on_warning_created):
		game.traffic.warning_created.connect(_on_warning_created)
	if not game.traffic.train_spawned.is_connected(_on_train_spawned):
		game.traffic.train_spawned.connect(_on_train_spawned)
	var give_up: BaseButton = game.get_node("CanvasLayer/GiveUpBtn")
	_give_up_state = {"disabled": give_up.disabled, "focus_mode": give_up.focus_mode}
	give_up.release_focus()
	give_up.disabled = true
	give_up.focus_mode = Control.FOCUS_NONE
	$Panel/Pages/Goal.text = goal_format.format({"duration": str(game.traffic.config.round_duration).trim_suffix(".0")})
	active = true
	step = 0
	$Panel.show()
	show()
	_show_page()
	game.queue_redraw()


func finish() -> void:
	active = false
	_demo_running = false
	watch_warning = false
	next_button.release_focus()
	skip_button.release_focus()
	$WarningTip/Dismiss.release_focus()
	$WarningTip.hide()
	$Panel.hide()
	hide()
	queue_redraw()
	if not _give_up_state.is_empty():
		var give_up: BaseButton = game.get_node("CanvasLayer/GiveUpBtn")
		give_up.disabled = _give_up_state.disabled
		give_up.focus_mode = _give_up_state.focus_mode
		_give_up_state.clear()


func advance(delta: float) -> void:
	if not active or not _demo_running or delta <= 0.0 or not is_finite(delta):
		return
	var cart = game.simulation
	var remaining: float = delta * cart.config.speed
	# Stop at each model event: buffer_hit can change the lesson synchronously.
	while active and _demo_running and not cart.lost:
		var distance: float = cart.distance_to_event()
		var travel: float = minf(remaining, distance)
		cart.advance_distance(travel)
		remaining -= travel
		if not _demo_running or remaining <= 0.0 or travel < distance:
			break
	queue_redraw()


func _on_buffer_hit() -> void:
	if not active or not _demo_running:
		return
	_demo_running = false
	step += 1
	_show_page()


func _show_page() -> void:
	for index in range(pages.size()):
		pages[index].visible = index == step
	var action: String = pages[step].get_meta("action")
	var can_advance := action != "switch" and not _demo_running
	next_button.visible = can_advance
	next_button.disabled = not can_advance
	next_button.text = str(next_button.get_meta(action, next_text))
	progress.text = progress_format.format({"step": step + 1, "total": pages.size()})
	if can_advance:
		next_button.grab_focus()
	else:
		next_button.release_focus()
		skip_button.grab_focus()
	queue_redraw()


func _next_page() -> void:
	if not active or _demo_running:
		return
	match pages[step].get_meta("action"):
		"switch":
			return
		"demo":
			_demo_running = true
			_show_page()
		"play":
			finish()
			watch_warning = true
		_:
			step += 1
			_show_page()


func _skip_tutorial() -> void:
	finish()


func handle_board_input(event: InputEvent) -> void:
	if not active or pages[step].get_meta("action") != "switch":
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	get_viewport().set_input_as_handled()
	var position_on_board: Vector2 = game.get_global_transform_with_canvas().affine_inverse() * event.position
	if position_on_board.distance_to(game.simulation.point(settings.switch_id)) > game.simulation.config.visual.click_radius:
		return
	if game.traffic.toggle(settings.switch_id):
		game.queue_redraw()
		if game.simulation.switches[settings.switch_id] == int(settings.switch_setting):
			step += 1
			_show_page()


func _on_warning_created() -> void:
	if not watch_warning or active or game.traffic.lost or game.traffic.won or game.traffic.is_clearing():
		return
	watch_warning = false
	$WarningTip.show()
	show()


func _on_train_spawned(_train) -> void:
	if $WarningTip.visible:
		_dismiss_tip()


func _dismiss_tip() -> void:
	$WarningTip/Dismiss.release_focus()
	$WarningTip.hide()
	if not active:
		hide()


func _draw() -> void:
	if not active:
		return
	var points: Array[Vector2] = []
	match pages[step].get_meta("highlight", "none"):
		"cart":
			points.append(game.simulation.cart_position())
		"buffers":
			for id in settings.highlight_buffers:
				points.append(game.simulation.point(id))
		"switch":
			points.append(game.simulation.point(settings.switch_id))
	var board_to_local: Transform2D = get_global_transform_with_canvas().affine_inverse() * game.get_global_transform_with_canvas()
	for point in points:
		draw_circle(board_to_local * point, settings.highlight_radius, Color(settings.highlight_color), false, settings.highlight_width)
