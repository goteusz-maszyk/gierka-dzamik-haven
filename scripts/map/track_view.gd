class_name TrackView
extends Node2D
## One line's track: dark casing + colored core, both Line2D. The artist may
## restyle widths/colors here; points come from the network config.

@onready var _casing: Line2D = $Casing
@onready var _core: Line2D = $Core


func setup(cfg: Dictionary, points: PackedVector2Array, line_color: Color) -> void:
	_casing.points = points
	_casing.width = cfg.track_width
	_casing.default_color = Color.from_string(cfg.track_color, Color.WHITE)
	_core.points = points
	_core.width = maxf(cfg.track_min_width, cfg.track_width * cfg.track_core_width_factor)
	_core.default_color = line_color
