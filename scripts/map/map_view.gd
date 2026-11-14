class_name MapView
extends Node2D
## Live map: Line2D tracks, instanced station/train scenes, Camera2D follow.
## Reads Run/World every frame and only sets node properties — no _draw().

const STATION_SCENE := preload("res://scenes/map/station.tscn")
const TRAIN_SCENE := preload("res://scenes/map/train.tscn")
const TRACK_SCENE := preload("res://scenes/map/track.tscn")

var _cfg: Dictionary
var _net: Dictionary
var _run: Run
var _station_pos: Dictionary = {}
var _station_views: Dictionary = {}
var _train_views: Dictionary = {}
var _hover_station: String = ""

@onready var _tracks: Node2D = $Tracks
@onready var _stations: Node2D = $Stations
@onready var _trains: Node2D = $Trains
@onready var _camera: Camera2D = $Camera2D


## Builds the static network visuals (tracks + stations). Call once.
func setup(cfg: Dictionary, network: Dictionary) -> void:
	_cfg = cfg
	_net = network
	for station in network.stations:
		_station_pos[station.id] = Vector2(station.map_pos[0], station.map_pos[1])
	for line in network.lines:
		var points := PackedVector2Array()
		for stop in line.stops:
			points.append(_station_pos[stop.station])
		var track: TrackView = TRACK_SCENE.instantiate()
		_tracks.add_child(track)
		track.setup(cfg, points, Color.from_string(line.color, Color.WHITE))
	for station in network.stations:
		var view: StationView = STATION_SCENE.instantiate()
		_stations.add_child(view)
		view.position = _station_pos[station.id]
		view.setup(cfg, station, station.id == network.destination_station)
		_station_views[station.id] = view


## (Re)builds train views for a run and resets camera/zoom. Call on start/restart.
func bind_run(run: Run) -> void:
	_run = run
	for child in _trains.get_children():
		child.queue_free()
	_train_views.clear()
	for train_id in run.world.train_ids():
		var view: TrainView = TRAIN_SCENE.instantiate()
		_trains.add_child(view)
		var info := run.world.train_info(train_id)
		view.setup(_cfg, Color.from_string(info.color, Color.WHITE))
		_train_views[train_id] = view
	_camera.position = _station_pos[run.start_station]
	_camera.zoom = Vector2.ONE
	set_hover("")


func update(delta: float) -> void:
	for train_id in _train_views:
		var view: TrainView = _train_views[train_id]
		var state := _run.world.train_state(train_id, _run.clock)
		view.visible = state.phase != "before" and state.phase != "cancelled"
		if not view.visible:
			continue
		view.position = train_position(train_id)
		view.set_player_highlight(train_id == _run.player_train)
		var event_type := _active_event_type(train_id)
		view.set_event_icon(_event_color(event_type), event_type != "")
	var t := clampf(_cfg.camera_lerp_speed * delta, 0.0, 1.0)
	_camera.position = _camera.position.lerp(_camera_target(), t)


func zoom_by(factor: float) -> void:
	var z := clampf(_camera.zoom.x * factor, _cfg.zoom_min, _cfg.zoom_max)
	_camera.zoom = Vector2(z, z)


func set_hover(station_id: String) -> void:
	if station_id == _hover_station:
		return
	if _hover_station != "":
		_station_views[_hover_station].set_hovered(false)
	_hover_station = station_id
	if station_id != "":
		_station_views[station_id].set_hovered(true)


func station_at_screen(screen_pos: Vector2) -> String:
	var best := ""
	var best_dist: float = _cfg.hover_pick_radius
	for station_id in _station_pos:
		var d := screen_pos.distance_to(_world_to_screen(_station_pos[station_id]))
		if d < best_dist:
			best_dist = d
			best = station_id
	return best


func train_position(train_id: String) -> Vector2:
	var state := _run.world.train_state(train_id, _run.clock)
	var info := _run.world.train_info(train_id)
	if state.phase == "dwelling" or state.phase == "before" or state.phase == "cancelled":
		var station_id: String = state.station_id if state.station_id != "" else info.stops[0].station_id
		return _station_pos[station_id]
	if state.phase == "finished":
		return _station_pos[info.stops[info.stops.size() - 1].station_id]
	# moving: interpolate along the section by progress
	return _station_pos[state.from_station].lerp(_station_pos[state.to_station], state.progress)


func _camera_target() -> Vector2:
	if _run.player_train != "":
		return train_position(_run.player_train)
	return _station_pos[_run.player_station]


func _world_to_screen(p: Vector2) -> Vector2:
	var center := get_viewport_rect().size * 0.5
	return center + (p - _camera.position) * _camera.zoom.x


func _active_event_type(train_id: String) -> String:
	for event in _run.events:
		if event.train_id != train_id:
			continue
		if event.at_minute <= _run.clock and _run.clock < _event_end(event):
			return event.type
	return ""


func _event_end(event: Dictionary) -> float:
	if event.type == "drunk_driver":
		return event.at_minute + event.duration_minutes
	return INF


func _event_color(type: String) -> Color:
	match type:
		"drunk_driver":
			return Color.from_string(_cfg.event_drunk_color, Color.WHITE)
		"slow_down":
			return Color.from_string(_cfg.event_slow_color, Color.WHITE)
		_:
			return Color.from_string(_cfg.event_cancel_color, Color.WHITE)
