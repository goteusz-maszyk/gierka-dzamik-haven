class_name TrainView
extends Node2D
## One train on the map. Placeholder shapes are config-driven nodes; the
## artist replaces them inside this scene. EventIcon is the asset slot for
## per-event-type icons (batch 4).

var _cfg: Dictionary

@onready var _marker: Polygon2D = $Marker
@onready var _ring: Line2D = $PlayerRing
@onready var _icon: Polygon2D = $EventIcon


func setup(cfg: Dictionary, line_color: Color) -> void:
	_cfg = cfg
	var radius: float = cfg.train_radius
	_marker.polygon = MapShapes.circle_points(radius, cfg.circle_segments)
	_marker.color = line_color
	_ring.points = MapShapes.circle_points(radius + cfg.player_train_ring_gap, cfg.circle_segments)
	_ring.width = cfg.player_train_ring_width
	_ring.default_color = Color.from_string(cfg.player_train_ring_color, Color.WHITE)
	_icon.polygon = MapShapes.circle_points(cfg.event_icon_radius, cfg.circle_segments)
	_icon.position = Vector2(cfg.event_icon_offset, -cfg.event_icon_offset)


func set_player_highlight(on: bool) -> void:
	_ring.visible = on


func set_event_icon(color: Color, show_icon: bool) -> void:
	_icon.color = color
	_icon.visible = show_icon
