class_name StationView
extends Node2D
## One station marker on the map. Placeholder shapes are config-driven
## Polygon2D/Line2D nodes; the artist replaces them inside this scene.


@onready var _marker: Polygon2D = $Marker
@onready var _ring: Line2D = $DestinationRing
@onready var _label: Label = $NameLabel


func setup(cfg: Dictionary, station: Dictionary, is_destination: bool) -> void:
	var radius: float = cfg.station_radius
	_marker.polygon = MapShapes.circle_points(radius, cfg.circle_segments)
	_marker.color = Color.from_string(cfg.station_color, Color.WHITE)
	if is_destination:
		_ring.points = MapShapes.circle_points(radius + cfg.destination_ring_gap, cfg.circle_segments)
		_ring.width = cfg.destination_ring_width
		_ring.default_color = Color.from_string(cfg.destination_color, Color.WHITE)
		_ring.visible = true
	_label.text = station.name
	_label.add_theme_font_size_override("font_size", cfg.hover_label_font_size)
	_label.add_theme_color_override("font_color", Color.from_string(cfg.hud_color, Color.WHITE))
	_label.offset_top = -radius - cfg.hover_label_gap - cfg.hover_label_height
	_label.offset_bottom = -radius - cfg.hover_label_gap


func set_hovered(hovered: bool) -> void:
	_label.visible = hovered
