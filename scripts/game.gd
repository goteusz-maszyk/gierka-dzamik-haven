extends Node2D

const Simulation = preload("res://scripts/cart_simulation.gd")
const MENU_PATH = "res://scene/main_menu.tscn"

var simulation = Simulation.new()
var status: Label
var restart_button: Button
var menu_button: Button


func _ready() -> void:
	var visual: Dictionary = simulation.config.visual
	var text: Dictionary = simulation.config.text
	for key in ["title", "status", "help"]:
		var label := Label.new()
		var rect: Array = visual[key + "_rect"]
		label.position = Vector2(rect[0], rect[1])
		label.size = Vector2(rect[2], rect[3])
		label.add_theme_font_size_override("font_size", int(visual.font_size))
		label.add_theme_color_override("font_color", Color(visual.text))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.text = text.running if key == "status" else text[key]
		$CanvasLayer.add_child(label)
		if key == "status":
			status = label


func restart() -> void:
	simulation.restart()
	status.text = simulation.config.text.running
	queue_redraw()

func give_up() -> void:
	get_tree().change_scene_to_file("res://scene/main_menu.tscn")


func _process(delta: float) -> void:
	simulation.advance(delta)
	status.text = simulation.config.text.lost if simulation.lost else simulation.config.text.running
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local_click: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		for id in simulation.switches:
			if local_click.distance_to(simulation.point(id)) <= simulation.config.visual.click_radius:
				simulation.toggle(id)
				get_viewport().set_input_as_handled()
				queue_redraw()
				return


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
		var color := Color(v.locked if simulation.is_locked(id) else v.switch)
		draw_circle(center, v.switch_radius, color)
		var ports: Array = config.switches[id].ports
		for neighbor in [ports[0], ports[1 + simulation.switches[id]]]:
			var tip: Vector2 = center + (simulation.point(neighbor) - center).normalized() * v.route_arm
			draw_line(center, tip, Color(v.route), v.route_width)
	var half_cart: Vector2 = simulation.heading() * config.cart_length / 2.0
	var position_on_track: Vector2 = simulation.cart_position()
	draw_line(position_on_track - half_cart, position_on_track + half_cart, Color(v.cart), config.cart_width)
	draw_circle(position_on_track + half_cart, v.cart_front_radius, Color(v.cart_front))
