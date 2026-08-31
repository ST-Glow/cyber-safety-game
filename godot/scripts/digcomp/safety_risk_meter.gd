class_name SafetyRiskMeter
extends Control

var risk_value: float = 0.0
var phase: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_risk(value: float) -> void:
	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "risk_value", clampf(value, 0.0, 100.0), 0.34)


func _process(delta: float) -> void:
	phase = fmod(phase + delta * 4.0, TAU)
	queue_redraw()


func _draw() -> void:
	var c := Vector2(size.x * 0.5, size.y * 0.72)
	var radius := minf(size.x * 0.40, size.y * 0.65)
	var start := PI * 1.12
	var sweep := PI * 0.76
	for segment in range(20):
		var t0 := float(segment) / 20.0
		var t1 := float(segment + 1) / 20.0
		var color := Color("58e1bd") if t0 < 0.45 else (Color("ffd05e") if t0 < 0.72 else Color("ff4f69"))
		draw_arc(c, radius, start + sweep * t0, start + sweep * t1 - 0.015, 5, Color(color, 0.28 if risk_value / 100.0 < t0 else 0.95), 7.0)
	var angle := start + sweep * risk_value / 100.0
	draw_line(c, c + Vector2.from_angle(angle) * (radius - 10.0), Color("edfaff"), 4.0)
	draw_circle(c, 7.0, Color("dffbff"))
	if risk_value >= 70.0:
		draw_arc(c, radius + 9.0 + sin(phase * 2.0) * 3.0, start, start + sweep, 32, Color(1.0, 0.18, 0.28, 0.48), 4.0)
