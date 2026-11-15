extends Node2D

const Traffic = preload("res://scripts/traffic_simulation.gd")
const CART_TEXTURE = preload("res://wagon.png")
const TRAIN_TEXTURE = preload("res://pociag.png")
const MENU_PATH = "res://scene/main_menu.tscn"

var traffic = Traffic.new()
var simulation = traffic.cart
var ui_config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/game_ui.json"))
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
	traffic.switch_changed.connect($Sfx/Switch.play)
	traffic.warning_created.connect($Sfx/Warning.play)
	traffic.train_spawned.connect(_on_train_spawned)
	simulation.buffer_hit.connect($Sfx/Buffer.play)
	MusicManager.stop_music()
	tutorial.begin(self)
	_update_ui()


func _on_train_spawned(train) -> void:
	train.buffer_hit.connect($Sfx/Buffer.play)


func _stop_sfx() -> void:
	for player in $Sfx.get_children():
		player.stop()


func restart() -> void:
	tutorial.finish()
	_stop_sfx()
	traffic.restart()
	simulation = traffic.cart
	for button in [restart_button, menu_button, win_restart_button, win_menu_button]:
		button.release_focus()
	loss_overlay.hide()
	win_overlay.hide()
	_update_ui()
	queue_redraw()


func give_up() -> void:
	tutorial.finish()
	_stop_sfx()
	get_tree().change_scene_to_file(MENU_PATH)


func _process(delta: float) -> void:
	if tutorial.active:
		tutorial.advance(delta)
		queue_redraw()
		return
	var was_clearing: bool = traffic.is_clearing()
	traffic.advance(delta)
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
		if not loss_overlay.visible:
			tutorial.finish()
			_stop_sfx()
			if traffic.loss_reason == "cart_train" or traffic.loss_reason == "train_train":
				$Sfx/Collision.play()
			loss_reason.text = loss_messages[traffic.loss_reason]
			loss_overlay.show()
			restart_button.grab_focus()
	elif traffic.won:
		loss_overlay.hide()
		if not win_overlay.visible:
			tutorial.finish()
			_stop_sfx()
			win_message.text = win_message_format.format({"duration": str(traffic.config.round_duration)})
			win_overlay.show()
			win_restart_button.grab_focus()


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
