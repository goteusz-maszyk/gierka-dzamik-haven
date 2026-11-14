class_name RewindOverlay
extends Control
## Rewind tape effect: tint + scanlines while scrubbing backwards. This is the
## one allowed _draw() — an isolated dynamic overlay, not game rendering.
## Batch 4 replaces it with a VHS shader.

var _cfg: Dictionary


func setup(cfg: Dictionary) -> void:
	_cfg = cfg


func set_active(active: bool) -> void:
	if visible != active:
		visible = active
		queue_redraw()


func _draw() -> void:
	var screen_size := get_viewport_rect().size
	var tint := Color.from_string(_cfg.rewind_tint_color, Color.WHITE)
	tint.a = _cfg.rewind_tint_alpha
	draw_rect(Rect2(Vector2.ZERO, screen_size), tint)
	var line := Color.from_string(_cfg.rewind_scanline_color, Color.WHITE)
	line.a = _cfg.rewind_scanline_alpha
	var y := 0.0
	while y < screen_size.y:
		draw_line(Vector2(0, y), Vector2(screen_size.x, y), line, 1.0)
		y += _cfg.rewind_scanline_spacing
