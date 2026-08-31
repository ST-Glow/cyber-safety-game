class_name DataRepairFactoryBackdrop
extends Control

var phase: float = 0.0
var alert_strength: float = 0.0
var stage: int = 1
var particles: Array[Vector2] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260828
	for index in range(34):
		particles.append(Vector2(rng.randf(), rng.randf()))


func _process(delta: float) -> void:
	phase = fmod(phase + delta, TAU * 100.0)
	queue_redraw()


func _draw() -> void:
	# Deep factory gradient, drawn in bands to stay inexpensive on Web.
	for index in range(18):
		var t := float(index) / 17.0
		var color := Color("061126").lerp(Color("10284a"), t * 0.78)
		draw_rect(Rect2(0.0, size.y * t, size.x, size.y / 17.0 + 2.0), color, true)
	# Distant server cabinets.
	for index in range(9):
		var rack_x := 36.0 + index * (size.x - 72.0) / 8.0
		var rack_y := size.y * (0.18 + 0.018 * sin(phase * 0.2 + index))
		var rack := Rect2(rack_x - 38.0, rack_y, 76.0, size.y * 0.52)
		draw_rect(rack, Color(0.03, 0.08, 0.16, 0.72), true)
		draw_rect(rack, Color(0.18, 0.38, 0.56, 0.38), false, 2.0)
		for light_index in range(6):
			var light_color := Color("58e5d0") if (light_index + index + int(phase * 2.0)) % 5 == 0 else Color("244965")
			draw_circle(Vector2(rack.position.x + 14.0, rack.position.y + 18.0 + light_index * 21.0), 3.0, light_color)
	# Overhead pipes and junctions.
	draw_line(Vector2(0.0, size.y * 0.13), Vector2(size.x, size.y * 0.13), Color("243e57"), 15.0)
	draw_line(Vector2(size.x * 0.08, 0.0), Vector2(size.x * 0.08, size.y * 0.78), Color("1a344d"), 12.0)
	draw_line(Vector2(size.x * 0.92, 0.0), Vector2(size.x * 0.92, size.y * 0.75), Color("1a344d"), 12.0)
	for x_ratio in [0.08, 0.33, 0.67, 0.92]:
		draw_circle(Vector2(size.x * x_ratio, size.y * 0.13), 16.0, Color("0b1c32"))
		draw_arc(Vector2(size.x * x_ratio, size.y * 0.13), 16.0, 0.0, TAU, 24, Color("355b74"), 4.0)
	# Rotating cooling fans.
	for x_ratio in [0.18, 0.82]:
		var center := Vector2(size.x * x_ratio, size.y * 0.36)
		draw_circle(center, 48.0, Color(0.02, 0.07, 0.14, 0.72))
		draw_arc(center, 48.0, 0.0, TAU, 32, Color("294c67"), 4.0)
		for blade in range(5):
			var angle := phase * (0.45 + stage * 0.08) + TAU * blade / 5.0
			var p1 := center + Vector2.from_angle(angle) * 8.0
			var p2 := center + Vector2.from_angle(angle + 0.35) * 39.0
			var p3 := center + Vector2.from_angle(angle + 0.82) * 23.0
			draw_colored_polygon(PackedVector2Array([p1, p2, p3]), Color(0.22, 0.56, 0.72, 0.30))
	# Flowing data conduits.
	for lane in range(3):
		var y := size.y * (0.70 + lane * 0.055)
		draw_line(Vector2(0.0, y), Vector2(size.x, y), Color(0.08, 0.30, 0.45, 0.50), 2.0)
		var light_x := fmod(phase * (46.0 + stage * 16.0) + lane * 260.0, size.x + 60.0) - 30.0
		draw_circle(Vector2(light_x, y), 5.0, Color("68ecd2"))
	# Small floating data motes.
	for index in range(particles.size()):
		var seed := particles[index]
		var px := fmod(seed.x * size.x + phase * (5.0 + float(index % 4)), size.x)
		var py := seed.y * size.y
		draw_circle(Vector2(px, py), 1.5 + float(index % 3), Color(0.35, 0.78, 0.90, 0.12 + 0.05 * sin(phase + index)))
	if alert_strength > 0.01:
		var pulse := (0.06 + 0.08 * (0.5 + 0.5 * sin(phase * 8.0))) * alert_strength
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.75, 0.03, 0.10, pulse), true)
