extends Panel
## Departure board overlay (E). Rows are instanced board_row.tscn controls,
## pooled once and refreshed from World.departures each frame while open.

const ROW_SCENE := preload("res://scenes/ui/board_row.tscn")

var _cfg: Dictionary
var _rows: Array = []

@onready var _title: Label = $Title
@onready var _headers: HBoxContainer = $Headers
@onready var _row_box: VBoxContainer = $Rows


func setup(cfg: Dictionary) -> void:
	_cfg = cfg
	var style := StyleBoxFlat.new()
	style.bg_color = Color.from_string(cfg.hud_panel_color, Color.WHITE)
	add_theme_stylebox_override("panel", style)
	_title.add_theme_font_size_override("font_size", cfg.board_font_size)
	_title.add_theme_color_override("font_color", Color.from_string(cfg.hud_color, Color.WHITE))
	_title.position = Vector2(cfg.hud_pad, 26.0 - cfg.board_font_size)
	_headers.position = Vector2(cfg.hud_pad, cfg.board_header_height)
	var columns: Array = cfg.board_columns
	for i in _headers.get_child_count():
		var header: Label = _headers.get_child(i)
		var width: float = columns[i + 1] - columns[i] if i + 1 < columns.size() else cfg.board_width - cfg.hud_pad - columns[i]
		header.custom_minimum_size.x = width
		header.add_theme_font_size_override("font_size", cfg.board_font_size)
		header.add_theme_color_override("font_color", Color.from_string(cfg.hud_muted_color, Color.WHITE))
	_row_box.position = Vector2(cfg.hud_pad, cfg.board_header_height + cfg.board_row_height)
	for i in cfg.board_rows:
		var row: HBoxContainer = ROW_SCENE.instantiate()
		_row_box.add_child(row)
		row.setup(cfg)
		_rows.append(row)


func refresh(station_name: String, rows: Array) -> void:
	_title.text = "Departures — %s" % station_name
	var height: float = _cfg.board_header_height + _cfg.board_row_height * (_cfg.board_rows + 1)
	var board_size := Vector2(_cfg.board_width, height)
	var pos := (get_viewport_rect().size - board_size) * 0.5
	offset_left = pos.x
	offset_top = pos.y
	offset_right = pos.x + board_size.x
	offset_bottom = pos.y + board_size.y
	for i in _rows.size():
		var row: HBoxContainer = _rows[i]
		row.visible = i < rows.size()
		if row.visible:
			row.set_row(rows[i], _cfg)
	visible = true
