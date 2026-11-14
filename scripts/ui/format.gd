class_name TimeFormat
extends RefCounted
## Time formatting shared by HUD and departure board. Minutes since midnight.


static func format_time(minutes: float) -> String:
	var m := int(round(minutes))
	@warning_ignore("integer_division")
	var h := (m / 60) % 24
	return "%02d:%02d" % [h, m % 60]


static func format_duration(minutes: float) -> String:
	var m := int(round(minutes))
	@warning_ignore("integer_division")
	var h := m / 60
	return "%dh %02dm" % [h, m % 60] if h > 0 else "%dm" % (m % 60)
