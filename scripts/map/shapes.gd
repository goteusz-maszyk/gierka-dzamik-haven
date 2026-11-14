class_name MapShapes
extends RefCounted
## Shared placeholder geometry for map nodes. Circles are Polygon2D/Line2D
## point lists so the artist can swap any marker for a Sprite2D later.


static func circle_points(radius: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in segments:
		var angle := TAU * float(i) / float(segments)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points
