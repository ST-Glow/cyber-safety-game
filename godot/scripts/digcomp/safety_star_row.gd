class_name SafetyStarRow
extends Control

var earned: int = 1
var elapsed: float = 0.0


func configure(value: int) -> void:
	earned = clampi(value, 1, 3)
	elapsed = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	elapsed = minf(elapsed + delta, 1.4)
	queue_redraw()
	if elapsed >= 1.4:
		set_process(false)


func _draw() -> void:
	var center_y := size.y * 0.5
	for index in range(3):
		var center := Vector2(size.x * 0.5 + (index - 1) * 58.0, center_y)
		var reveal := clampf((elapsed - 0.18 * index) / 0.28, 0.0, 1.0)
		var filled := index < earned
		var radius := 22.0 * (0.72 + 0.28 * reveal)
		var points := PackedVector2Array()
		for point_index in range(10):
			var angle := -PI * 0.5 + float(point_index) * PI / 5.0
			var point_radius := radius if point_index % 2 == 0 else radius * 0.45
			points.append(center + Vector2(cos(angle), sin(angle)) * point_radius)
		var fill := Color("ffd46a") if filled else Color(0.13, 0.25, 0.30, 0.92)
		fill.a *= reveal
		draw_colored_polygon(points, fill)
		draw_polyline(points + PackedVector2Array([points[0]]), Color(1.0, 0.85, 0.43, reveal), 2.0, true)
		if filled and reveal > 0.05:
			draw_circle(center, radius * 1.35, Color(1.0, 0.78, 0.25, 0.08 * reveal))
