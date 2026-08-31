class_name SafetyCheckpointGate
extends Control

var safe_gate: bool = true
var hot: bool = false
var phase: float = 0.0
var flash: float = 0.0
var door_open: float = 0.18


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func configure(is_safe: bool) -> void:
	safe_gate = is_safe
	queue_redraw()


func set_hot(value: bool) -> void:
	if hot == value:
		return
	hot = value
	queue_redraw()


func play_result(correct: bool) -> void:
	flash = 1.0
	var target_open := 0.92 if safe_gate and correct else (0.02 if not safe_gate and correct else 0.46)
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "door_open", target_open, 0.26)
	tween.parallel().tween_property(self, "flash", 0.0, 0.58)
	tween.tween_property(self, "door_open", 0.18, 0.28)


func _process(delta: float) -> void:
	phase = fmod(phase + delta * 4.0, TAU)
	flash = maxf(0.0, flash - delta * 1.8)
	queue_redraw()


func _draw() -> void:
	var color := Color("60efbd") if safe_gate else Color("ff526d")
	var dark := Color("113d3d") if safe_gate else Color("481626")
	var glow := 0.18 + (0.35 if hot else 0.0) + flash * 0.30
	# Recessed lane leading into the gate.
	var lane := PackedVector2Array([
		Vector2(size.x * 0.22, size.y * 0.80), Vector2(size.x * 0.78, size.y * 0.80),
		Vector2(size.x, size.y), Vector2(0.0, size.y),
	])
	draw_colored_polygon(lane, Color(color, 0.08 + glow * 0.16))
	for line_index in range(4):
		var t := float(line_index) / 3.0
		draw_line(Vector2(lerpf(size.x * 0.25, 0.0, t), lerpf(size.y * 0.80, size.y, t)), Vector2(lerpf(size.x * 0.75, size.x, t), lerpf(size.y * 0.80, size.y, t)), Color(color, 0.13), 2.0)
	# Thick security arch.
	var outer := Rect2(size.x * 0.10, size.y * 0.08, size.x * 0.80, size.y * 0.74)
	draw_rect(outer, Color("071220"), true)
	draw_rect(outer, Color(color, 0.55 + glow), false, 8.0 if hot else 5.0)
	var inner := outer.grow(-24.0)
	draw_rect(inner, dark, true)
	# Split shutters visibly react rather than acting as a button.
	var shutter_width := inner.size.x * (1.0 - door_open) * 0.5
	draw_rect(Rect2(inner.position, Vector2(shutter_width, inner.size.y)), Color(dark.lightened(0.08), 0.96), true)
	draw_rect(Rect2(inner.end.x - shutter_width, inner.position.y, shutter_width, inner.size.y), Color(dark.lightened(0.08), 0.96), true)
	for stripe in range(5):
		var y := inner.position.y + 28.0 + stripe * (inner.size.y - 56.0) / 4.0
		draw_line(Vector2(inner.position.x + 8.0, y), Vector2(inner.position.x + shutter_width - 8.0, y + 15.0), Color(color, 0.24), 5.0)
		draw_line(Vector2(inner.end.x - shutter_width + 8.0, y + 15.0), Vector2(inner.end.x - 8.0, y), Color(color, 0.24), 5.0)
	# Shield or quarantine icon is the main visual cue.
	var c := Vector2(size.x * 0.5, size.y * 0.43)
	if safe_gate:
		var shield := PackedVector2Array([c + Vector2(0, -48), c + Vector2(40, -30), c + Vector2(34, 23), c + Vector2(0, 53), c + Vector2(-34, 23), c + Vector2(-40, -30)])
		draw_colored_polygon(shield, Color(color, 0.18 + glow * 0.25))
		var shield_outline := PackedVector2Array(shield)
		shield_outline.append(shield[0])
		draw_polyline(shield_outline, color, 5.0, true)
		draw_line(c + Vector2(-19, 1), c + Vector2(-3, 18), color, 7.0)
		draw_line(c + Vector2(-3, 18), c + Vector2(24, -18), color, 7.0)
	else:
		draw_arc(c, 48.0, 0.0, TAU, 32, color, 6.0)
		draw_line(c + Vector2(-29, -29), c + Vector2(29, 29), color, 8.0)
		draw_line(c + Vector2(29, -29), c + Vector2(-29, 29), color, 8.0)
	var lamp := color if sin(phase * 2.0) > -0.2 or hot else dark
	draw_circle(Vector2(outer.position.x + 18.0, outer.position.y - 14.0), 10.0 + flash * 5.0, lamp)
	draw_circle(Vector2(outer.end.x - 18.0, outer.position.y - 14.0), 10.0 + flash * 5.0, lamp)
	if hot:
		draw_arc(c, 78.0 + sin(phase * 2.0) * 6.0, 0.0, TAU, 36, Color(color, 0.72), 4.0)
