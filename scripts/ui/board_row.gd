extends HBoxContainer
## One departure board row. Cell widths come from view config columns.

const CELL_NAMES := ["Time", "Train", "Destination", "Platform", "Status"]

var _cells: Array[Label] = []


func _ready() -> void:
	for cell_name in CELL_NAMES:
		var label: Label = get_node(cell_name)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_cells.append(label)


func setup(cfg: Dictionary) -> void:
	var columns: Array = cfg.board_columns
	for i in _cells.size():
		var width: float = columns[i + 1] - columns[i] if i + 1 < columns.size() else cfg.board_width - cfg.hud_pad - columns[i]
		_cells[i].custom_minimum_size.x = width
		_cells[i].add_theme_font_size_override("font_size", cfg.board_font_size)
	custom_minimum_size.y = cfg.board_row_height


func set_row(row: Dictionary, cfg: Dictionary) -> void:
	var status := "on time"
	var status_color: String = cfg.hud_color
	if row.cancelled:
		status = "Cancelled"
		status_color = cfg.board_cancel_color
	elif row.delay > 0.5:
		status = "+%d min" % int(round(row.delay))
		status_color = cfg.board_delay_color
	var texts := [TimeFormat.format_time(row.departure), row.train_number, row.destination, str(row.platform), status]
	for i in _cells.size():
		_cells[i].text = texts[i]
		var hex: String = status_color if i == 4 else cfg.hud_color
		_cells[i].add_theme_color_override("font_color", Color.from_string(hex, Color.WHITE))
