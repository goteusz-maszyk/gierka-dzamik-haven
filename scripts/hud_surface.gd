extends Control
## HUD drawing surface (full-rect Control under the HUD CanvasLayer).
## Clock, deadline, rewind meter, current train, departure board (E),
## pause and end screens. Reads state from Main each frame.

var _main: Node2D
var _cfg: Dictionary
var _font: Font


func set_main(main: Node2D) -> void:
	_main = main
	_cfg = main.cfg()
	_font = main.font()
	queue_redraw()


func _draw() -> void:
	if _main == null:
		return
	var run: Run = _main.run()
	var rect := get_viewport_rect().size
	_draw_top_bar(run, rect)
	_draw_rewind_bar(run, rect)
	_draw_train_info(run, rect)
	_draw_message(rect)
	if _main.is_board_open():
		_draw_board(run, rect)
	if _main.is_paused():
		_draw_center_panel(rect, "PAUSED", "Esc to resume")
	if run.finished:
		_draw_end_screen(run, rect)
	_draw_controls_hint(rect)


func _draw_top_bar(run: Run, rect: Vector2) -> void:
	var pad := 16.0
	_draw_text(_format_time(run.clock), Vector2(pad, pad + 24), _cfg.hud_font_size, _cfg.hud_color)
	_draw_text("Deadline %s" % _format_time(run.deadline), Vector2(pad, pad + 50), _cfg.hud_small_font_size, _cfg.hud_muted_color)
	_draw_text("Time left %s" % _format_duration(run.time_remaining()), Vector2(pad, pad + 72), _cfg.hud_small_font_size, _cfg.hud_muted_color)
	_draw_text("View: %s (Tab)" % _main.view_name(), Vector2(rect.x - 200.0, pad + 24), _cfg.hud_small_font_size, _cfg.hud_muted_color)
	_draw_text("Seed %d" % run.seed_value, Vector2(rect.x - 200.0, pad + 46), _cfg.hud_small_font_size, _cfg.hud_muted_color)


func _draw_rewind_bar(run: Run, rect: Vector2) -> void:
	var total: float = ConfigData.load_file("time").rewind_meter_minutes
	var frac := clampf(run.rewind_meter / total, 0.0, 1.0)
	var w: float = _cfg.rewind_bar_width
	var h: float = _cfg.rewind_bar_height
	var pos := Vector2(rect.x - w - 16.0, rect.y - h - 40.0)
	draw_rect(Rect2(pos, Vector2(w, h)), _color(_cfg.rewind_bar_bg_color))
	draw_rect(Rect2(pos, Vector2(w * frac, h)), _color(_cfg.rewind_bar_color))
	_draw_text("Rewind (hold Space)", pos + Vector2(0, -8), _cfg.hud_small_font_size, _cfg.hud_muted_color)


func _draw_train_info(run: Run, rect: Vector2) -> void:
	if run.player_train == "":
		_draw_text("At %s — B to board a standing train" % _main.station_name(run.player_station),
			Vector2(16.0, rect.y - 40.0), _cfg.hud_small_font_size, _cfg.hud_color)
		return
	var info := run.world.train_info(run.player_train)
	var state := run.world.train_state(run.player_train, run.clock)
	var where := "moving"
	if state.phase == "dwelling":
		where = "at " + _main.station_name(state.station_id)
	elif state.phase == "finished":
		where = "terminated"
	_draw_text("%s (%s) → %s — %s — N to disembark" % [info.train_number, info.line_name, info.destination, where],
		Vector2(16.0, rect.y - 40.0), _cfg.hud_small_font_size, _cfg.hud_color)


func _draw_message(rect: Vector2) -> void:
	var msg: String = _main.message()
	if msg == "":
		return
	var fs: int = _cfg.hud_small_font_size
	var w := _font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_draw_text(msg, Vector2((rect.x - w) * 0.5, rect.y - 80.0), fs, _cfg.destination_color)


func _draw_board(run: Run, rect: Vector2) -> void:
	var station := run.player_station if run.player_station != "" else run.start_station
	var rows := run.world.departures(station, run.clock, _cfg.board_rows)
	var w: float = _cfg.board_width
	var row_h: float = _cfg.board_row_height
	var header_h := 40.0
	var h: float = header_h + row_h * (_cfg.board_rows + 1)
	var pos := Vector2((rect.x - w) * 0.5, (rect.y - h) * 0.5)
	draw_rect(Rect2(pos, Vector2(w, h)), _color(_cfg.hud_panel_color))
	_draw_text("Departures — %s" % _main.station_name(station), pos + Vector2(16, 26), _cfg.board_font_size, _cfg.hud_color)
	var cols := [16.0, 120.0, 380.0, 480.0, 560.0]
	var headers := ["Time", "Train", "Destination", "Plat", "Status"]
	for i in headers.size():
		_draw_text(headers[i], pos + Vector2(cols[i], header_h + 18), _cfg.board_font_size, _cfg.hud_muted_color)
	var y := header_h + row_h
	for i in _cfg.board_rows:
		if i >= rows.size():
			break
		var row: Dictionary = rows[i]
		var status := "on time"
		var status_color: String = _cfg.hud_color
		if row.cancelled:
			status = "Cancelled"
			status_color = _cfg.board_cancel_color
		elif row.delay > 0.5:
			status = "+%d min" % int(round(row.delay))
			status_color = _cfg.board_delay_color
		var cells := [_format_time(row.departure), row.train_number, row.destination, str(row.platform), status]
		for c in cells.size():
			var col: String = status_color if c == 4 else _cfg.hud_color
			_draw_text(cells[c], pos + Vector2(cols[c], y + 18), _cfg.board_font_size, col)
		y += row_h


func _draw_end_screen(run: Run, rect: Vector2) -> void:
	var late := run.minutes_late()
	var verdict := "%d min early" % int(round(-late)) if late < 0 else "%d min late" % int(round(late))
	var body := "Arrival %s   Deadline %s\n%s\nSeed %d\nR for a new run" % [
		_format_time(run.arrival_time), _format_time(run.deadline), verdict, run.seed_value]
	_draw_center_panel(rect, "ARRIVED IN KRAKÓW", body)


func _draw_center_panel(rect: Vector2, title: String, body: String) -> void:
	var w := 460.0
	var h := 220.0
	var pos := Vector2((rect.x - w) * 0.5, (rect.y - h) * 0.5)
	draw_rect(Rect2(pos, Vector2(w, h)), _color(_cfg.hud_panel_color))
	var tw := _font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, _cfg.hud_font_size).x
	_draw_text(title, pos + Vector2((w - tw) * 0.5, 40), _cfg.hud_font_size, _cfg.destination_color)
	var y := 80.0
	for line in body.split("\n"):
		var lw := _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, _cfg.hud_small_font_size).x
		_draw_text(line, pos + Vector2((w - lw) * 0.5, y), _cfg.hud_small_font_size, _cfg.hud_color)
		y += 26.0


func _draw_controls_hint(rect: Vector2) -> void:
	_draw_text("Tab view · Space rewind · E board · B board train · N disembark · Esc pause · R restart",
		Vector2(16.0, rect.y - 16.0), 12, _cfg.hud_muted_color)


func _draw_text(text: String, pos: Vector2, fs: int, hex: String) -> void:
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _color(hex))


func _format_time(minutes: float) -> String:
	var m := int(round(minutes))
	@warning_ignore("integer_division")
	var h := (m / 60) % 24
	return "%02d:%02d" % [h, m % 60]


func _format_duration(minutes: float) -> String:
	var m := int(round(minutes))
	@warning_ignore("integer_division")
	var h := m / 60
	return "%dh %02dm" % [h, m % 60] if h > 0 else "%dm" % (m % 60)


func _color(hex: String) -> Color:
	return Color.from_string(hex, Color.WHITE)
