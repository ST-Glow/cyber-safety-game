class_name MainMenuBackdrop
extends Control

var elapsed: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	elapsed += minf(delta, 0.05)
	queue_redraw()


func _draw() -> void:
	var viewport_size := size
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color("061225"))
	for band in range(9):
		var y := viewport_size.y * float(band) / 8.0
		var color := Color(0.035 + band * 0.004, 0.10 + band * 0.008, 0.18 + band * 0.012, 1.0)
		draw_rect(Rect2(0.0, y, viewport_size.x, viewport_size.y / 8.0 + 1.0), color)
	var horizon := viewport_size.y * 0.62
	for line_index in range(15):
		var ratio := float(line_index) / 14.0
		var y := lerpf(horizon, viewport_size.y, ratio * ratio)
		draw_line(Vector2(0.0, y), Vector2(viewport_size.x, y), Color(0.18, 0.66, 0.78, 0.08 + ratio * 0.08), 1.0)
	for column in range(-10, 11):
		var top_x := viewport_size.x * 0.5 + column * 34.0
		var bottom_x := viewport_size.x * 0.5 + column * 105.0
		draw_line(Vector2(top_x, horizon), Vector2(bottom_x, viewport_size.y), Color(0.16, 0.62, 0.74, 0.10), 1.0)
	for rack_index in range(8):
		var rack_x := 28.0 + rack_index * (viewport_size.x - 56.0) / 7.0
		var rack_height := 90.0 + float((rack_index * 37) % 95)
		var rack_rect := Rect2(rack_x - 34.0, horizon - rack_height, 68.0, rack_height)
		draw_rect(rack_rect, Color(0.04, 0.13, 0.22, 0.72), true)
		draw_rect(rack_rect, Color(0.15, 0.47, 0.61, 0.22), false, 1.0)
		for light_index in range(5):
			var pulse := 0.35 + 0.35 * sin(elapsed * 1.6 + rack_index + light_index)
			draw_circle(Vector2(rack_rect.position.x + 10.0, rack_rect.position.y + 15.0 + light_index * 13.0), 2.2, Color(0.35, 0.95, 0.80, pulse))
	var scan_y := fmod(elapsed * 54.0, maxf(viewport_size.y, 1.0))
	draw_rect(Rect2(0.0, scan_y, viewport_size.x, 2.0), Color(0.30, 0.90, 0.92, 0.10))
	for mote_index in range(22):
		var x := fmod(float(mote_index * 173) + elapsed * (8.0 + mote_index % 5), viewport_size.x)
		var y := fmod(float(mote_index * 91) - elapsed * (5.0 + mote_index % 4), viewport_size.y)
		draw_circle(Vector2(x, y), 1.4 + float(mote_index % 3), Color(0.37, 0.91, 0.85, 0.12))
