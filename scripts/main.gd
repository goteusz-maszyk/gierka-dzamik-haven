extends Node2D
## Runnable preview: launches straight into a run and shows the live sim as
## retained-mode nodes (map scenes + Control HUD). The sim core (Run/World)
## is untouched; this node only feeds input and updates node properties.
##
## Controls: Tab switch map/station clock rate, Space hold to rewind (map),
## E departure board, Esc pause, mouse wheel zoom, B board next train,
## N disembark, R restart. Station-view walking is a later batch; here B/N
## stand in for walking to a platform so the loop is previewable.

var _cfg: Dictionary
var _net: Dictionary
var _run: Run
var _view: String = "map"
var _paused: bool = false
var _board_open: bool = false
var _rewinding: bool = false
var _message: String = ""
var _message_timer: float = 0.0

@onready var _map: MapView = $Map
@onready var _hud: Hud = $HUD
@onready var _background: ColorRect = $BackgroundLayer/Background
@onready var _rewind_overlay: RewindOverlay = $RewindLayer/Overlay


func _ready() -> void:
	_cfg = ConfigData.load_file("view")
	_net = ConfigData.load_file("network")
	_background.color = Color.from_string(_cfg.background_color, Color.WHITE)
	_map.setup(_cfg, _net)
	_hud.setup(_cfg)
	_rewind_overlay.setup(_cfg)
	_start_run(randi())


func _start_run(seed_value: int) -> void:
	_run = Run.create(seed_value)
	_view = "map"
	_board_open = false
	_rewinding = false
	_map.bind_run(_run)
	_flash("Run seed %d — start: %s" % [seed_value, _station_name(_run.start_station)])


func _process(delta: float) -> void:
	if _message_timer > 0.0:
		_message_timer -= delta
		if _message_timer <= 0.0:
			_message = ""
	if _paused or _run.finished:
		_rewinding = false
		_rewind_overlay.set_active(false)
		_hud.refresh(self)
		return
	_rewinding = Input.is_key_pressed(KEY_SPACE) and _view == "map"
	if _rewinding:
		_run.rewind(delta)
	else:
		_run.advance(delta, _view)
	_map.update(delta)
	_rewind_overlay.set_active(_rewinding)
	_hud.refresh(self)


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
			_map.zoom_by(_cfg.zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_map.zoom_by(1.0 / _cfg.zoom_step)
	if event is InputEventMouseMotion:
		_map.set_hover(_map.station_at_screen(event.position))


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
	_message_timer = _cfg.message_duration_seconds


func _station_name(id: String) -> String:
	for station in _net.stations:
		if station.id == id:
			return station.name
	return id


# --- accessors for the HUD --------------------------------------------------

func run() -> Run:
	return _run


func view_name() -> String:
	return _view


func is_paused() -> bool:
	return _paused


func is_board_open() -> bool:
	return _board_open


func message() -> String:
	return _message


func station_name(id: String) -> String:
	return _station_name(id)
