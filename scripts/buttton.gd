@tool
extends TextureButton

@export var text: String:
	set(value):
		text = value
		if is_node_ready():
			$BoxContainer/Label.text = text

func _ready() -> void:
	custom_minimum_size = Vector2(get_theme_constant("minimum_width"), get_theme_constant("minimum_height"))
	$BoxContainer/Label.text = text
