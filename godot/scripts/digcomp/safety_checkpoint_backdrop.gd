class_name SafetyCheckpointBackdrop
extends Control

var phase: float = 0.0
var alert_strength: float = 0.0
var security_level: float = 0.0
var motes: Array[Vector2] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260829
	for index in range(32):
		motes.append(Vector2(rng.randf(), rng.randf()))


func _process(delta: float) -> void:
	phase = fmod(phase + delta, TAU * 100.0)
	queue_redraw()


func _draw() -> void:
	# Layer 1: deep control-center atmosphere.
	for band in range(18):
		var t := float(band) / 17.0
		var color := Color("050d1f").lerp(Color("102b45"), t * 0.76)
		draw_rect(Rect2(0.0, size.y * t, size.x, size.y / 17.0 + 2.0), color, true)
	# Server towers on both sides leave the scan arena visually open.
	for side in [-1, 1]:
		for index in range(3):
			var x := size.x * (0.07 + index * 0.075) if side < 0 else size.x * (0.93 - index * 0.075)
			var rack := Rect2(x - 34.0, size.y * 0.18, 68.0, size.y * 0.57)
			draw_rect(rack, Color(0.02, 0.06, 0.13, 0.80), true)
			draw_rect(rack, Color(0.16, 0.39, 0.54, 0.44), false, 3.0)
			for light in range(9):
				var lit := (light + index + int(phase * 3.0)) % 7 == 0
				draw_circle(Vector2(rack.position.x + 13.0, rack.position.y + 18.0 + light * 27.0), 3.0, Color("55e6d0") if lit else Color("22445d"))
	# Overhead security conduits.
	draw_line(Vector2(0.0, size.y * 0.14), Vector2(size.x, size.y * 0.14), Color("1e3b55"), 14.0)
	for x_ratio in [0.08, 0.25, 0.50, 0.75, 0.92]:
		var node := Vector2(size.x * x_ratio, size.y * 0.14)
		draw_circle(node, 13.0, Color("071427"))
		draw_arc(node, 13.0, 0.0, TAU, 24, Color("3a6b84"), 4.0)
	# Central holographic shield, deliberately subtle behind gameplay.
	var shield_center := Vector2(size.x * 0.50, size.y * 0.48)
	var shield := PackedVector2Array([
		shield_center + Vector2(0.0, -190.0), shield_center + Vector2(145.0, -130.0),
		shield_center + Vector2(126.0, 62.0), shield_center + Vector2(0.0, 178.0),
		shield_center + Vector2(-126.0, 62.0), shield_center + Vector2(-145.0, -130.0),
	])
	draw_colored_polygon(shield, Color(0.12, 0.56, 0.70, 0.045 + security_level * 0.05))
	var shield_outline := PackedVector2Array(shield)
	shield_outline.append(shield[0])
	draw_polyline(shield_outline, Color(0.35, 0.87, 0.86, 0.12 + security_level * 0.16), 3.0, true)
	# Perspective floor and flowing packets.
	var horizon := size.y * 0.69
	draw_line(Vector2(0.0, horizon), Vector2(size.x, horizon), Color("315a73"), 4.0)
	for index in range(11):
		var bottom_x := size.x * float(index) / 10.0
		draw_line(Vector2(size.x * 0.5, horizon), Vector2(bottom_x, size.y), Color(0.16, 0.39, 0.52, 0.24), 2.0)
	for row in range(4):
		var y := horizon + (size.y - horizon) * pow(float(row + 1) / 4.0, 1.6)
		draw_line(Vector2(0.0, y), Vector2(size.x, y), Color(0.15, 0.39, 0.51, 0.25), 2.0)
	for lane in range(3):
		var y := size.y * (0.79 + lane * 0.055)
		var packet_x := fmod(phase * (80.0 + lane * 16.0) + lane * 290.0, size.x + 80.0) - 40.0
		draw_line(Vector2(0.0, y), Vector2(size.x, y), Color(0.10, 0.48, 0.56, 0.20), 2.0)
		draw_circle(Vector2(packet_x, y), 5.0, Color("62ead2"))
	for index in range(motes.size()):
		var seed := motes[index]
		var px := fmod(seed.x * size.x + phase * (7.0 + index % 4), size.x)
		var py := seed.y * size.y
		draw_circle(Vector2(px, py), 1.5 + float(index % 3), Color(0.40, 0.90, 0.92, 0.12))
	if alert_strength > 0.01:
		var pulse := (0.045 + 0.07 * (0.5 + 0.5 * sin(phase * 10.0))) * alert_strength
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.95, 0.02, 0.10, pulse), true)
		for y in range(0, int(size.y), 38):
			draw_line(Vector2(0.0, float(y)), Vector2(size.x, float(y)), Color(1.0, 0.12, 0.22, 0.06 * alert_strength), 2.0)
