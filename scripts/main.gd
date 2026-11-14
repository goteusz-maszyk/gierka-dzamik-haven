extends Node2D
## Batch-1 runnable preview: launches straight into a run and renders the live
## simulation (map, moving trains, HUD, departure board, rewind). The world is
## the tested sim core (Run/World); this node only draws and feeds input.
##
## Controls: Tab switch map/station clock rate, Space hold to rewind (map),
## E departure board, Esc pause, mouse wheel zoom, B board next train,
## N disembark, R restart. Station-view walking is a later batch; here B/N
## stand in for walking to a platform so the loop is previewable.

const VIEW := preload("res://config/view.json")

var _cfg: Dictionary
var _net: Dictionary
var _run: Run
var _view: String = "map"
var _paused: bool = false
var _board_open: bool = false
var _rewinding: bool = false
var _zoom: float = 1.0
var _cam: Vector2 = Vector2.ZERO
var _hover_station: String = ""
var _station_pos: Dictionary = {}
var _font: Font
var _message: String = ""
var _message_timer: float = 0.0

@onready var _hud: CanvasLayer = $HUD


func _ready() -> void:
	_cfg = ConfigData.load_file("view")
	_net = ConfigData.load_file("network")
	_font = ThemeDB.fallback_font
	_build_station_positions()
	_start_run(randi())
	_cam = _station_pos[_run.start_station]
	set_process(true)
	set_process_input(true)


func _start_run(seed_value: int) -> void:
	_run = Run.create(seed_value)
	_view = "map"
	_board_open = false
	_rewinding = false
	_zoom = 1.0
	_cam = _station_pos[_run.start_station]
	_flash("Run seed %d — start: %s" % [seed_value, _station_name(_run.start_station)])


func _build_station_positions() -> void:
	for station in _net.stations:
		_station_pos[station.id] = Vector2(station.map_pos[0], station.map_pos[1])


func _process(delta: float) -> void:
	if _message_timer > 0.0:
		_message_timer -= delta
		if _message_timer <= 0.0:
			_message = ""
	if _paused or _run.finished:
		queue_redraw()
		_hud.refresh(self)
		return
	_rewinding = Input.is_key_pressed(KEY_SPACE) and _view == "map"
	if _rewinding:
		_run.rewind(delta)
	else:
		_run.advance(delta, _view)
	_update_camera(delta)
	queue_redraw()
	_hud.refresh(self)


func _update_camera(delta: float) -> void:
	var target: Vector2
	if _run.player_train != "":
		target = _train_pos(_run.player_train)
	else:
		target = _station_pos[_run.player_station]
	var t: float = clampf(_cfg.camera_lerp_speed * delta, 0.0, 1.0)
	_cam = _cam.lerp(target, t)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				_paused = not _paused
			KEY_TAB:
				_view = "station" if _view == "map" else "map"
			KEY_E:
				_board_open = not _board_open
			KEY_B:
				_try_board()
			KEY_N:
				_try_disembark()
			KEY_R:
				_start_run(randi())
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = clampf(_zoom * _cfg.zoom_step, _cfg.zoom_min, _cfg.zoom_max)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = clampf(_zoom / _cfg.zoom_step, _cfg.zoom_min, _cfg.zoom_max)
	if event is InputEventMouseMotion:
		_hover_station = _station_at_screen(event.position)


func _try_board() -> void:
	if _run.finished or _run.player_train != "":
		return
	var station: String = _run.player_station
	for row in _run.world.departures(station, _run.clock, 20):
		if row.cancelled:
			continue
		var state := _run.world.train_state(row.train_id, _run.clock)
		if state.phase == "dwelling" and state.station_id == station:
			_run.board(row.train_id)
			_view = "map"
			_flash("Boarded %s to %s" % [row.train_number, row.destination])
			return
	_flash("No train standing at " + _station_name(station))


func _try_disembark() -> void:
	if _run.finished or _run.player_train == "":
		return
	var state := _run.world.train_state(_run.player_train, _run.clock)
	if state.phase != "dwelling":
		_flash("Train is moving — wait for a stop")
		return
	var station: String = state.station_id
	_run.disembark()
	if _run.finished:
		_flash("Arrived in Kraków!")
	else:
		_view = "station"
		_flash("Disembarked at " + _station_name(station))


func _flash(text: String) -> void:
	_message = text
	_message_timer = 3.0


# --- geometry helpers -------------------------------------------------------

func _world_to_screen(p: Vector2) -> Vector2:
	var center := get_viewport_rect().size * 0.5
	return center + (p - _cam) * _zoom


func _train_pos(train_id: String) -> Vector2:
	var state := _run.world.train_state(train_id, _run.clock)
	var info := _run.world.train_info(train_id)
	if state.phase == "dwelling" or state.phase == "before" or state.phase == "cancelled":
		var station_id: String = state.station_id if state.station_id != "" else info.stops[0].station_id
		return _station_pos[station_id]
	if state.phase == "finished":
		return _station_pos[info.stops[info.stops.size() - 1].station_id]
	# moving: interpolate along the section by progress
	var a: Vector2 = _station_pos[state.from_station]
	var b: Vector2 = _station_pos[state.to_station]
	return a.lerp(b, state.progress)


func _station_at_screen(screen_pos: Vector2) -> String:
	var best := ""
	var best_dist: float = _cfg.hover_pick_radius
	for station_id in _station_pos:
		var d := screen_pos.distance_to(_world_to_screen(_station_pos[station_id]))
		if d < best_dist:
			best_dist = d
			best = station_id
	return best


func _station_name(id: String) -> String:
	for station in _net.stations:
		if station.id == id:
			return station.name
	return id


# --- drawing ----------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), _color(_cfg.background_color))
	_draw_lines()
	_draw_stations()
	_draw_trains()
	if _rewinding:
		_draw_rewind_effect()


func _draw_lines() -> void:
	for line in _net.lines:
		var color := _color(line.color)
		var pts: PackedVector2Array = []
		for stop in line.stops:
			pts.append(_world_to_screen(_station_pos[stop.station]))
		for i in range(pts.size() - 1):
			draw_line(pts[i], pts[i + 1], _color(_cfg.track_color), _cfg.track_width * _zoom)
			draw_line(pts[i], pts[i + 1], color, maxf(1.0, _cfg.track_width * _zoom * 0.4))


func _draw_stations() -> void:
	var dest: String = _net.destination_station
	for station in _net.stations:
		var p := _world_to_screen(_station_pos[station.id])
		var r: float = _cfg.station_radius * _zoom
		draw_circle(p, r, _color(_cfg.station_color))
		if station.id == dest:
			draw_arc(p, r + 4.0 * _zoom, 0.0, TAU, 32, _color(_cfg.destination_color), _cfg.destination_ring_width * _zoom)
		if station.id == _hover_station:
			var label: String = station.name
			var size := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, _cfg.hover_label_font_size)
			draw_string(_font, p + Vector2(-size.x * 0.5, -r - 8.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, _cfg.hover_label_font_size, _color(_cfg.hud_color))


func _draw_trains() -> void:
	var active := _active_events()
	for train_id in _run.world.train_ids():
		var state := _run.world.train_state(train_id, _run.clock)
		if state.phase == "before" or state.phase == "cancelled":
			continue
		var info := _run.world.train_info(train_id)
		var p := _world_to_screen(_train_pos(train_id))
		var r: float = _cfg.train_radius * _zoom
		draw_circle(p, r, _color(info.color))
		if train_id == _run.player_train:
			draw_arc(p, r + 3.0 * _zoom, 0.0, TAU, 24, _color(_cfg.player_train_ring_color), _cfg.player_train_ring_width * _zoom)
		if active.has(train_id):
			var icon_color := _event_color(active[train_id])
			draw_circle(p + Vector2(_cfg.event_icon_offset * _zoom, -_cfg.event_icon_offset * _zoom), _cfg.event_icon_radius * _zoom, icon_color)


func _active_events() -> Dictionary:
	var result := {}
	for event in _run.events:
		var end := _event_end(event)
		if event.at_minute <= _run.clock and _run.clock < end:
			result[event.train_id] = event.type
	return result


func _event_end(event: Dictionary) -> float:
	match event.type:
		"drunk_driver":
			return event.at_minute + event.duration_minutes
		"slow_down":
			return INF
		"cancel":
			return INF
	return INF


func _event_color(type: String) -> Color:
	match type:
		"drunk_driver":
			return _color(_cfg.event_drunk_color)
		"slow_down":
			return _color(_cfg.event_slow_color)
		_:
			return _color(_cfg.event_cancel_color)


func _draw_rewind_effect() -> void:
	var size := get_viewport_rect().size
	var tint := _color(_cfg.rewind_tint_color)
	tint.a = _cfg.rewind_tint_alpha
	draw_rect(Rect2(Vector2.ZERO, size), tint)
	var line := _color(_cfg.rewind_scanline_color)
	line.a = _cfg.rewind_scanline_alpha
	var y := 0.0
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), line, 1.0)
		y += _cfg.rewind_scanline_spacing


func _color(hex: String) -> Color:
	return Color.from_string(hex, Color.WHITE)


# --- accessors for the HUD --------------------------------------------------

func run() -> Run:
	return _run


func view_name() -> String:
	return _view


func is_paused() -> bool:
	return _paused


func is_board_open() -> bool:
	return _board_open


func is_rewinding() -> bool:
	return _rewinding


func message() -> String:
	return _message


func station_name(id: String) -> String:
	return _station_name(id)


func cfg() -> Dictionary:
	return _cfg


func font() -> Font:
	return _font
