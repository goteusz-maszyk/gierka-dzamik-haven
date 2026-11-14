extends CanvasLayer
## HUD container. The actual drawing lives on the full-rect Control child
## (CanvasLayer itself cannot draw). Main calls refresh() each frame.

@onready var _surface: Control = $Surface


func refresh(main: Node2D) -> void:
	_surface.set_main(main)
