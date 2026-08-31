class_name DataRepairConveyorBelt
extends Control

var belt_phase: float = 0.0
var running: bool = false
var visual_speed: float = 58.0
var stage: int = 1
var alert_strength: float = 0.0
var frozen: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func set_running(value: bool) -> void:
	running = value
	queue_redraw()


func _process(delta: float) -> void:
	if running:
		belt_phase = fmod(belt_phase + visual_speed * minf(delta, 0.05), 64.0)
	queue_redraw()


func _draw() -> void:
	# Factory floor shadow and heavy chassis.
	draw_colored_polygon(PackedVector2Array([Vector2(26, 30), Vector2(size.x - 40, 30), Vector2(size.x - 10, size.y - 28), Vector2(0, size.y - 28)]), Color("071323"))
	draw_rect(Rect2(18.0, 52.0, size.x - 118.0, size.y - 118.0), Color("122a43"), true)
	draw_rect(Rect2(18.0, 52.0, size.x - 118.0, size.y - 118.0), Color("3e6c86"), false, 5.0)
	# Moving belt slats and three channels.
	var slat_x := -72.0 + belt_phase
	while slat_x < size.x - 90.0:
		draw_colored_polygon(PackedVector2Array([
			Vector2(slat_x, 58.0), Vector2(slat_x + 50.0, 58.0),
			Vector2(slat_x + 34.0, size.y - 72.0), Vector2(slat_x - 16.0, size.y - 72.0),
		]), Color(0.12, 0.31, 0.45, 0.50))
		slat_x += 72.0
	for row in range(3):
		var y := 66.0 + float(row) * 104.0
		draw_line(Vector2(24.0, y + 90.0), Vector2(size.x - 110.0, y + 90.0), Color(0.20, 0.48, 0.62, 0.38), 3.0)
	# Rollers make the surface read as machinery rather than a web panel.
	for index in range(13):
		var roller_x := 48.0 + index * (size.x - 170.0) / 12.0
		var roller_center := Vector2(roller_x, size.y - 47.0)
		draw_circle(roller_center, 18.0, Color("07111e"))
		draw_arc(roller_center, 18.0, 0.0, TAU, 24, Color("47768e"), 5.0)
		var angle := belt_phase * 0.08 + index
		draw_line(roller_center + Vector2.from_angle(angle) * 4.0, roller_center + Vector2.from_angle(angle) * 15.0, Color("72b5c8"), 3.0)
	# Spawn turbine on the left.
	var gear_center := Vector2(30.0, size.y * 0.50)
	draw_circle(gear_center, 42.0, Color("081728"))
	draw_arc(gear_center, 42.0, 0.0, TAU, 32, Color("4c7891"), 6.0)
	for tooth in range(8):
		var angle := belt_phase * 0.025 + TAU * tooth / 8.0
		draw_line(gear_center + Vector2.from_angle(angle) * 30.0, gear_center + Vector2.from_angle(angle) * 48.0, Color("58a8bd"), 8.0)
	draw_circle(gear_center, 11.0, Color("65e8d1"))
	# Mechanical arm rail above the belt.
	draw_line(Vector2(size.x * 0.20, 30.0), Vector2(size.x * 0.68, 30.0), Color("345c72"), 9.0)
	var arm_x := size.x * 0.20 + fmod(belt_phase * 2.2, size.x * 0.48)
	draw_rect(Rect2(arm_x - 18.0, 18.0, 36.0, 24.0), Color("426f83"), true)
	draw_line(Vector2(arm_x, 40.0), Vector2(arm_x, 68.0), Color("6d9bad"), 7.0)
	draw_line(Vector2(arm_x - 13.0, 68.0), Vector2(arm_x + 13.0, 68.0), Color("70e7d1"), 5.0)
	# Scanner arch before the furnace.
	var scanner_x := size.x * 0.72
	draw_line(Vector2(scanner_x, 42.0), Vector2(scanner_x, size.y - 84.0), Color("436f86"), 12.0)
	draw_line(Vector2(scanner_x + 56.0, 42.0), Vector2(scanner_x + 56.0, size.y - 84.0), Color("436f86"), 12.0)
	draw_line(Vector2(scanner_x, 42.0), Vector2(scanner_x + 56.0, 42.0), Color("5f94aa"), 12.0)
	var scan_y := 58.0 + fmod(belt_phase * 1.8, maxf(80.0, size.y - 158.0))
	draw_line(Vector2(scanner_x + 5.0, scan_y), Vector2(scanner_x + 51.0, scan_y), Color(0.35, 0.96, 0.86, 0.70), 5.0)
	# Repaired channel rises above the furnace.
	draw_colored_polygon(PackedVector2Array([Vector2(scanner_x + 64.0, 74.0), Vector2(size.x - 88.0, 28.0), Vector2(size.x - 88.0, 68.0), Vector2(scanner_x + 64.0, 114.0)]), Color("164f59"))
	draw_line(Vector2(scanner_x + 70.0, 93.0), Vector2(size.x - 90.0, 47.0), Color("65e8d1"), 4.0)
	# Hazard furnace with animated shutters and warning lamps.
	var furnace := Rect2(size.x - 104.0, 30.0, 96.0, size.y - 58.0)
	draw_rect(furnace, Color("2b1023"), true)
	draw_rect(furnace, Color("9d3349"), false, 6.0)
	for stripe in range(5):
		var stripe_y := furnace.position.y + 30.0 + stripe * (furnace.size.y - 60.0) / 4.0
		draw_line(Vector2(furnace.position.x + 8.0, stripe_y), Vector2(furnace.end.x - 8.0, stripe_y + 24.0), Color(0.95, 0.19, 0.28, 0.38), 8.0)
	var alarm := Color("ff415c") if sin(belt_phase * 0.12) > 0.0 else Color("6e1c36")
	draw_circle(Vector2(furnace.position.x + 20.0, furnace.position.y + 18.0), 9.0 + alert_strength * 4.0, alarm)
	draw_circle(Vector2(furnace.end.x - 20.0, furnace.position.y + 18.0), 9.0 + alert_strength * 4.0, alarm)
	if frozen:
		draw_rect(Rect2(18.0, 52.0, size.x - 118.0, size.y - 118.0), Color(0.32, 0.88, 1.0, 0.10), true)
