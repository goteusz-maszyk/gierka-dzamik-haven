@tool
extends TextureButton

@export var hover_color := Color(1, 1.1, 1.1, 1.0)
@export var transition_duration := 0.15

@export var text: String:
	set(value):
		text = value
		if is_node_ready():
			$BoxContainer/Label.text = text

func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	custom_minimum_size = Vector2(get_theme_constant("minimum_width"), get_theme_constant("minimum_height"))
	$BoxContainer/Label.text = text

func _on_mouse_entered():
	animate_color(hover_color, Color.WEB_GRAY)

func _on_mouse_exited():
	animate_color(Color.WHITE, Color.WHITE)

func animate_color(target_bg: Color, target_lb: Color):
	var tween_bg = $Background.create_tween()
	tween_bg.tween_property(self, "modulate", target_bg, transition_duration)

	var tween_lb = $BoxContainer/Label.create_tween()
	tween_lb.tween_property($BoxContainer/Label, "modulate", target_lb, transition_duration)
