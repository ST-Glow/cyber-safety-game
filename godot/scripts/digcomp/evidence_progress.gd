class_name EvidenceProgress
extends Control

const NODE_COUNT := 10

var completed_count: int = 0
var pulse: float = 0.0
var _pulse_active: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(420.0, 62.0)


func reset() -> void:
	completed_count = 0
	pulse = 0.0
	_pulse_active = false
	queue_redraw()


func complete_next() -> void:
	completed_count = mini(NODE_COUNT, completed_count + 1)
	pulse = 1.0
	_pulse_active = true
	queue_redraw()


func _process(delta: float) -> void:
	if _pulse_active:
		pulse = maxf(0.0, pulse - delta * 2.7)
		if pulse <= 0.0:
			_pulse_active = false
		queue_redraw()


func _draw() -> void:
	if size.x <= 1.0:
		return
	var margin := 24.0
	var step := (size.x - margin * 2.0) / float(NODE_COUNT - 1)
	var y := size.y * 0.50
	for index in range(NODE_COUNT - 1):
		var active := index < completed_count - 1
		var start := Vector2(margin + step * index + 12.0, y)
		var finish := Vector2(margin + step * (index + 1) - 12.0, y)
		draw_line(start, finish, Color(0.38, 0.94, 0.82, 0.74) if active else Color(0.16, 0.34, 0.45, 0.46), 3.0)
		if active:
			var flow_x := lerpf(start.x, finish.x, fmod(Time.get_ticks_msec() / 450.0 + index * 0.17, 1.0))
			draw_circle(Vector2(flow_x, y), 3.0, Color("c1fff2"))
	for index in range(NODE_COUNT):
		var active := index < completed_count
		var radius := 11.0
		if _pulse_active and index == completed_count - 1:
			radius += pulse * 9.0
		var center := Vector2(margin + step * index, y)
		var diamond := PackedVector2Array([
			center + Vector2(0.0, -radius), center + Vector2(radius, 0.0),
			center + Vector2(0.0, radius), center + Vector2(-radius, 0.0),
		])
		draw_colored_polygon(diamond, Color("69efd0") if active else Color("102a42"))
		var outline := PackedVector2Array(diamond)
		outline.append(diamond[0])
		draw_polyline(outline, Color("d1fff6") if active else Color("3d6a82"), 2.0, true)
		if active:
			draw_circle(center, 3.5, Color("f0fffb"))
