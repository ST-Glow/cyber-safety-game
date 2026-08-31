class_name DataRepairToolDock
extends Control

var phase: float = 0.0
var slot_count: int = 4


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	phase = fmod(phase + delta * 2.5, TAU)
	queue_redraw()


func _draw() -> void:
	# Open mechanical deck: no enclosing webpage panel.
	draw_colored_polygon(PackedVector2Array([
		Vector2(34.0, 14.0), Vector2(size.x - 34.0, 14.0), Vector2(size.x, size.y), Vector2(0.0, size.y),
	]), Color(0.025, 0.09, 0.15, 0.82))
	draw_line(Vector2(34.0, 14.0), Vector2(size.x - 34.0, 14.0), Color("3e7188"), 4.0)
	var slot_width := size.x / float(slot_count)
	for index in range(slot_count):
		var center := Vector2(slot_width * (float(index) + 0.5), size.y * 0.58)
		draw_circle(center, 66.0, Color(0.02, 0.08, 0.14, 0.88))
		draw_arc(center, 66.0, PI * 1.05, PI * 1.95, 28, Color(0.28, 0.56, 0.68, 0.50), 5.0)
		draw_arc(center, 56.0, -PI * 0.05, PI * 1.05, 24, Color(0.25, 0.88, 0.78, 0.28), 3.0)
		for pin in range(5):
			var angle := PI * 1.1 + pin * PI * 0.2
			draw_circle(center + Vector2.from_angle(angle) * 68.0, 3.0, Color("6ab9c9"))
	# Power cables connect the tool pods to the factory.
	for index in range(slot_count - 1):
		var x1 := slot_width * (float(index) + 0.76)
		var x2 := slot_width * (float(index) + 1.24)
		var y := size.y - 10.0 + sin(phase + index) * 2.0
		draw_line(Vector2(x1, y), Vector2(x2, y), Color(0.22, 0.70, 0.72, 0.38), 4.0)
