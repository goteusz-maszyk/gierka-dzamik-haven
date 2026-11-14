extends Panel
## Shared centered panel for pause and end screens. Geometry/colors come from
## view config; the artist styles this scene.

var _cfg: Dictionary

@onready var _title: Label = $Title
@onready var _body: Label = $Body


func setup(cfg: Dictionary) -> void:
	_cfg = cfg
	var style := StyleBoxFlat.new()
	style.bg_color = Color.from_string(cfg.hud_panel_color, Color.WHITE)
	add_theme_stylebox_override("panel", style)
	_title.add_theme_font_size_override("font_size", cfg.hud_font_size)
	_title.add_theme_color_override("font_color", Color.from_string(cfg.destination_color, Color.WHITE))
	_title.offset_top = cfg.center_panel_title_y
	_title.offset_bottom = cfg.center_panel_title_y + cfg.hud_font_size + 8.0
	_body.add_theme_font_size_override("font_size", cfg.hud_small_font_size)
	_body.add_theme_color_override("font_color", Color.from_string(cfg.hud_color, Color.WHITE))
	_body.offset_top = cfg.center_panel_body_y
	_body.offset_bottom = cfg.center_panel_height - cfg.hud_pad
	_body.add_theme_constant_override("line_spacing", int(cfg.hud_line_gap - cfg.hud_small_font_size))


func show_panel(title: String, body: String) -> void:
	_title.text = title
	_body.text = body
	var panel_size := Vector2(_cfg.center_panel_width, _cfg.center_panel_height)
	var pos := (get_viewport_rect().size - panel_size) * 0.5
	offset_left = pos.x
	offset_top = pos.y
	offset_right = pos.x + panel_size.x
	offset_bottom = pos.y + panel_size.y
	visible = true


func hide_panel() -> void:
	visible = false
