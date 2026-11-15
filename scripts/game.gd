extends Node2D

const Traffic = preload("res://scripts/traffic_simulation.gd")
const CART_TEXTURE = preload("res://wagon.png")
const TRAIN_TEXTURE = preload("res://pociag.png")
const MENU_PATH = "res://scene/main_menu.tscn"

var traffic = Traffic.new()
var simulation = traffic.cart
var ui_config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/game_ui.json"))
var loss_config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/loss_presentation.json"))
var _loss_started := false
var _loss_tween: Tween
var _result_menu_state: Dictionary = {}
var _buffer_bounces: Dictionary = {}
var _new_buffer_bounces: Array[int] = []
@onready var board_camera: Camera2D = $BoardCamera
@onready var status: Label = $CanvasLayer/GameUI/Status
@onready var restart_button: BaseButton = $CanvasLayer/GameUI/LossOverlay/Panel/Retry
@onready var menu_button: BaseButton = $CanvasLayer/GameUI/LossOverlay/Panel/Menu
@onready var loss_overlay: Control = $CanvasLayer/GameUI/LossOverlay
@onready var loss_reason: Label = $CanvasLayer/GameUI/LossOverlay/Panel/Reason
@onready var win_overlay: Control = $CanvasLayer/GameUI/WinOverlay
@onready var win_restart_button: BaseButton = $CanvasLayer/GameUI/WinOverlay/Panel/Retry
@onready var win_menu_button: BaseButton = $CanvasLayer/GameUI/WinOverlay/Panel/Menu
@onready var win_message: Label = $CanvasLayer/GameUI/WinOverlay/Panel/Reason
@onready var win_message_format: String = win_message.text
@onready var status_format: String = status.text
@onready var clearing_status_format: String = status.get_meta("clearing")
@onready var tutorial = $CanvasLayer/Tutorial
@onready var loss_messages: Dictionary = {
	"cart_exit": loss_reason.text,
	"cart_train": loss_reason.get_meta("cart_train"),
	"train_train": loss_reason.get_meta("train_train")
}


func _ready() -> void:
	_reset_loss_presentation()
	traffic.switch_changed.connect($Sfx/Switch.play)
	traffic.warning_created.connect($Sfx/Warning.play)
	traffic.train_spawned.connect(_on_train_spawned)
	simulation.buffer_hit.connect($Sfx/Buffer.play)
	simulation.buffer_hit.connect(_on_buffer_hit.bind(simulation.get_instance_id()))
	MusicManager.stop_music()
	tutorial.begin(self)
	_update_ui()
	$CiuchCiuchTheme.play(0)


func _on_train_spawned(train) -> void:
	train.buffer_hit.connect($Sfx/Buffer.play)
	train.buffer_hit.connect(_on_buffer_hit.bind(train.get_instance_id()))


func _on_buffer_hit(vehicle_id: int) -> void:
	_buffer_bounces[vehicle_id] = 0.0
	_new_buffer_bounces.append(vehicle_id)


func _advance_buffer_bounces(delta: float) -> void:
	if _buffer_bounces.is_empty():
		return
	var step: float = delta if is_finite(delta) and delta > 0.0 else 0.0
	var bounce: Dictionary = ui_config.buffer_bounce
	var duration: float = bounce.compress_duration + bounce.rebound_duration + bounce.settle_duration
	var active_ids: Array[int] = [simulation.get_instance_id()]
	for train in traffic.trains:
		active_ids.append(train.get_instance_id())
	for vehicle_id in _buffer_bounces.keys():
		var age: float = _buffer_bounces[vehicle_id]
		# Impacts from this model update must show their first phase before aging.
		if vehicle_id not in _new_buffer_bounces:
			age += step
		if vehicle_id not in active_ids or age >= duration:
			_buffer_bounces.erase(vehicle_id)
		else:
			_buffer_bounces[vehicle_id] = age


func _stop_sfx() -> void:
	for player in $Sfx.get_children():
		player.stop()


func restart() -> void:
	MusicManager.stop_music()
	$CiuchCiuchTheme.play(0)
	_reset_loss_presentation()
	tutorial.finish()
	_stop_sfx()
	_buffer_bounces.clear()
	_new_buffer_bounces.clear()
	traffic.restart()
	simulation = traffic.cart
	for button in [restart_button, menu_button, win_restart_button, win_menu_button]:
		button.release_focus()
	loss_overlay.hide()
	win_overlay.hide()
	_update_ui()
	queue_redraw()


func give_up() -> void:
	_reset_loss_presentation()
	tutorial.finish()
	_stop_sfx()
	_buffer_bounces.clear()
	_new_buffer_bounces.clear()
	get_tree().change_scene_to_file(MENU_PATH)


func _process(delta: float) -> void:
	_new_buffer_bounces.clear()
	if tutorial.active:
		tutorial.advance(delta)
		_advance_buffer_bounces(delta)
		queue_redraw()
		return
	var was_clearing: bool = traffic.is_clearing()
	var previous_time: float = traffic.elapsed
	traffic.advance(delta)
	_advance_buffer_bounces(traffic.elapsed - previous_time)
	if not was_clearing and traffic.is_clearing():
		$Sfx/Warning.stop()
		tutorial.finish()
	_update_ui()
	queue_redraw()


func _update_ui() -> void:
	var text_format: String = clearing_status_format if traffic.is_clearing() else status_format
	status.text = text_format.format({"remaining": ceili(maxf(0.0, traffic.remaining_time())), "trains": traffic.trains.size()})
	if traffic.lost:
		win_overlay.hide()
		if not _loss_started:
			_begin_loss_presentation()
	elif traffic.won:
		loss_overlay.hide()
		if not win_overlay.visible:
			tutorial.finish()
			_stop_sfx()
			win_message.text = win_message_format.format({"duration": str(traffic.config.round_duration)})
			win_overlay.show()
			_prepare_result_controls()


func _begin_loss_presentation() -> void:
	_loss_started = true
	tutorial.finish()
	_stop_sfx()
	if traffic.loss_reason == "cart_train" or traffic.loss_reason == "train_train":
		$Sfx/Collision.play()
	loss_reason.text = loss_messages[traffic.loss_reason]
	var target_zoom := Vector2.ONE * maxf(1.0, float(loss_config.zoom))
	var bounds := get_viewport_rect()
	var half_view := bounds.size / target_zoom / 2.0
	var target := Vector2(
		clampf(traffic.loss_position.x, bounds.position.x + half_view.x, bounds.end.x - half_view.x),
		clampf(traffic.loss_position.y, bounds.position.y + half_view.y, bounds.end.y - half_view.y))
	_loss_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_loss_tween.tween_interval(loss_config.freeze_duration)
	_loss_tween.tween_property(board_camera, "position", target, loss_config.zoom_duration)
	_loss_tween.parallel().tween_property(board_camera, "zoom", target_zoom, loss_config.zoom_duration)
	_loss_tween.tween_interval(loss_config.hold_duration)
	_loss_tween.tween_callback(_show_loss_panel)


func _show_loss_panel() -> void:
	if not _loss_started or not traffic.lost:
		return
	loss_overlay.show()
	_prepare_result_controls()
	$CiuchCiuchTheme.stop()
	MusicManager.play_music(preload("res://assets/tomek_i_przyjaciele.mp3"))


func _prepare_result_controls() -> void:
	for button in [restart_button, menu_button, win_restart_button, win_menu_button]:
		button.release_focus()
	var gameplay_menu: BaseButton = $CanvasLayer/GiveUpBtn
	if _result_menu_state.is_empty():
		_result_menu_state = {"disabled": gameplay_menu.disabled, "focus_mode": gameplay_menu.focus_mode}
	gameplay_menu.release_focus()
	gameplay_menu.disabled = true
	gameplay_menu.focus_mode = Control.FOCUS_NONE


func _cancel_loss_tween() -> void:
	if _loss_tween != null:
		_loss_tween.kill()
		_loss_tween = null


func _reset_loss_presentation() -> void:
	_cancel_loss_tween()
	_loss_started = false
	if not _result_menu_state.is_empty():
		var gameplay_menu: BaseButton = $CanvasLayer/GiveUpBtn
		gameplay_menu.disabled = _result_menu_state.disabled
		gameplay_menu.focus_mode = _result_menu_state.focus_mode
		_result_menu_state.clear()
	board_camera.position = get_viewport_rect().get_center()
	board_camera.zoom = Vector2.ONE
	board_camera.force_update_scroll()


func _exit_tree() -> void:
	_cancel_loss_tween()


func _unhandled_input(event: InputEvent) -> void:
	if tutorial.active:
		tutorial.handle_board_input(event)
		return
	if traffic.lost or traffic.won or loss_overlay.visible or win_overlay.visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local_click: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		for id in simulation.switches:
			if local_click.distance_to(simulation.point(id)) <= simulation.config.visual.click_radius:
				traffic.toggle(id)
				get_viewport().set_input_as_handled()
				queue_redraw()
				return


func _draw_vehicle(vehicle, texture: Texture2D, tint: Color) -> void:
	var vehicle_size := Vector2(vehicle.config.cart_length, vehicle.config.cart_width)
	var heading: Vector2 = vehicle.heading()
	var facing_left := heading.x < 0.0
	var angle := (-heading).angle() if facing_left else heading.angle()
	var sprite_scale := Vector2(-1, 1) if facing_left else Vector2.ONE
	if _buffer_bounces.has(vehicle.get_instance_id()):
		var age: float = _buffer_bounces[vehicle.get_instance_id()]
		var bounce: Dictionary = ui_config.buffer_bounce
		var compressed := Vector2(bounce.compressed_scale[0], bounce.compressed_scale[1])
		var rebound := Vector2(bounce.rebound_scale[0], bounce.rebound_scale[1])
		var deformation := Vector2.ONE
		if age < bounce.compress_duration:
			deformation = Vector2.ONE.lerp(compressed, smoothstep(0.0, 1.0, age / bounce.compress_duration))
		elif age < bounce.compress_duration + bounce.rebound_duration:
			deformation = compressed.lerp(rebound, smoothstep(0.0, 1.0, (age - bounce.compress_duration) / bounce.rebound_duration))
		elif age < bounce.compress_duration + bounce.rebound_duration + bounce.settle_duration:
			deformation = rebound.lerp(Vector2.ONE, smoothstep(0.0, 1.0, (age - bounce.compress_duration - bounce.rebound_duration) / bounce.settle_duration))
		sprite_scale *= deformation
	draw_set_transform(vehicle.cart_position(), angle, sprite_scale)
	draw_texture_rect(texture, Rect2(-vehicle_size / 2.0, vehicle_size), false, tint)


func _draw() -> void:
	var config: Dictionary = simulation.config
	var v: Dictionary = config.visual
	draw_rect(get_viewport_rect(), Color(v.background))
	for edge in config.edges:
		draw_line(simulation.point(edge[0]), simulation.point(edge[1]), Color(v.track), v.track_width)
	for id in config.buffers:
		var center: Vector2 = simulation.point(id)
		var neighbor: String
		for edge in config.edges:
			if id in edge:
				neighbor = edge[1] if edge[0] == id else edge[0]
				break
		var heading: Vector2 = (simulation.point(neighbor) - center).normalized()
		var arm := heading.orthogonal() * float(v.buffer_half_width)
		draw_line(center - arm, center + arm, Color(v.buffer), v.buffer_width)
	for id in config.exits:
		draw_circle(simulation.point(id), v.exit_radius, Color(v.exit))
	for id in simulation.switches:
		var center: Vector2 = simulation.point(id)
		var color := Color(v.locked if traffic.is_locked(id) else v.switch)
		draw_circle(center, v.switch_radius, color)
		var ports: Array = config.switches[id].ports
		for neighbor in [ports[0], ports[1 + simulation.switches[id]]]:
			var tip: Vector2 = center + (simulation.point(neighbor) - center).normalized() * v.route_arm
			draw_line(center, tip, Color(v.route), v.route_width)
	_draw_vehicle(simulation, CART_TEXTURE, Color(ui_config.cart_modulate))
	for train in traffic.trains:
		_draw_vehicle(train, TRAIN_TEXTURE, Color(ui_config.train_modulate))
	draw_set_transform(Vector2.ZERO)
	for warning in traffic.warnings:
		draw_circle(simulation.point(warning.entry), ui_config.warning_radius,
			Color(ui_config.warning_color), false, ui_config.warning_width)
