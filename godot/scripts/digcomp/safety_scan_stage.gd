class_name SafetyScanStage
extends Control

var phase: float = 0.0
var scan_intensity: float = 0.0
var stage: int = 1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	phase = fmod(phase + delta * (1.0 + stage * 0.18), TAU * 100.0)
	scan_intensity = maxf(0.0, scan_intensity - delta * 0.75)
	queue_redraw()


func trigger_scan() -> void:
	scan_intensity = 1.0
	queue_redraw()


func _draw() -> void:
	var center := Vector2(size.x * 0.5, size.y * 0.54)
	# Suspension rail and moving inspection head.
	draw_line(Vector2(60.0, 38.0), Vector2(size.x - 60.0, 38.0), Color("345f77"), 10.0)
	var head_x := center.x + sin(phase * 0.8) * size.x * 0.25
	draw_rect(Rect2(head_x - 24.0, 24.0, 48.0, 30.0), Color("3e7387"), true)
	draw_line(Vector2(head_x, 52.0), Vector2(head_x, 86.0), Color("6b9bae"), 7.0)
	draw_circle(Vector2(head_x, 91.0), 12.0, Color("65ead2"))
	# Hexagonal scan pad and rotating rings.
	var radius := minf(size.x, size.y) * 0.34
	for ring in range(3):
		var r := radius + ring * 22.0
		var alpha := 0.26 - ring * 0.055 + scan_intensity * 0.18
		draw_arc(center, r, phase * (0.18 + ring * 0.04), phase * (0.18 + ring * 0.04) + PI * 1.55, 48, Color(0.34, 0.90, 0.82, alpha), 3.0 + scan_intensity * 2.0)
	var pad := PackedVector2Array()
	for index in range(6):
		pad.append(center + Vector2.from_angle(-PI * 0.5 + TAU * index / 6.0) * radius)
	draw_colored_polygon(pad, Color(0.03, 0.18, 0.24, 0.52))
	var outline := PackedVector2Array(pad)
	outline.append(pad[0])
	draw_polyline(outline, Color(0.33, 0.82, 0.79, 0.42 + scan_intensity * 0.35), 4.0, true)
	# Scanner columns and a moving beam.
	for x in [center.x - radius * 0.85, center.x + radius * 0.85]:
		draw_line(Vector2(x, center.y - radius * 0.72), Vector2(x, center.y + radius * 0.65), Color("315d72"), 10.0)
		draw_circle(Vector2(x, center.y - radius * 0.74), 13.0, Color("58dccb"))
	var scan_y := center.y - radius * 0.60 + fmod(phase * 55.0, radius * 1.18)
	draw_line(Vector2(center.x - radius * 0.76, scan_y), Vector2(center.x + radius * 0.76, scan_y), Color(0.42, 1.0, 0.87, 0.18 + scan_intensity * 0.66), 5.0)
	# Incoming file rail from the ceiling.
	draw_line(Vector2(center.x, -8.0), Vector2(center.x, center.y - radius), Color(0.25, 0.60, 0.69, 0.44), 4.0)
