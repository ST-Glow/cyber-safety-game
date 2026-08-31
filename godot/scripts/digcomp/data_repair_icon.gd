class_name DataRepairIcon
extends Control

var icon_kind: String = "data_stack"
var accent: Color = Color("66e8d0")
var pulse: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func configure(kind: String, color: Color) -> void:
	icon_kind = kind
	accent = color
	queue_redraw()


func _process(delta: float) -> void:
	pulse = fmod(pulse + delta, TAU)
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var radius := minf(size.x, size.y) * 0.36
	draw_circle(c, radius * (1.0 + sin(pulse * 2.0) * 0.025), Color(accent, 0.12))
	draw_arc(c, radius, 0.0, TAU, 32, Color(accent, 0.62), 3.0)
	match icon_kind:
		"search_alert", "verify_source": _draw_search(c, radius)
		"conflict_docs", "cross_check": _draw_documents(c, radius)
		"data_stack", "organize_tags": _draw_stack(c, radius)
		"ai_chart", "trace_data": _draw_ai_chart(c, radius)
		"web_clock", "current_info": _draw_web_clock(c, radius)
		"edit_image", "license_edit": _draw_editor(c, radius)
		"ai_upload", "disclosure": _draw_upload(c, radius)
		"multimedia", "accessible_format": _draw_media(c, radius)
		"network_image", "copyright": _draw_network(c, radius)
		"version_loop", "versioning": _draw_version(c, radius)
		_: _draw_chip(c, radius)


func _draw_search(c: Vector2, r: float) -> void:
	draw_arc(c - Vector2(r * 0.12, r * 0.08), r * 0.38, 0.0, TAU, 24, accent, 5.0)
	draw_line(c + Vector2(r * 0.16, r * 0.18), c + Vector2(r * 0.52, r * 0.54), accent, 6.0)
	if icon_kind == "search_alert":
		draw_line(c + Vector2(r * 0.48, -r * 0.48), c + Vector2(r * 0.48, -r * 0.12), Color("ff7588"), 5.0)
		draw_circle(c + Vector2(r * 0.48, r * 0.02), 3.5, Color("ff7588"))
	else:
		_draw_check(c + Vector2(r * 0.26, -r * 0.18), r * 0.42)


func _draw_documents(c: Vector2, r: float) -> void:
	for offset in [Vector2(-r * 0.38, -r * 0.30), Vector2(r * 0.02, -r * 0.16)]:
		draw_rect(Rect2(c + offset, Vector2(r * 0.48, r * 0.62)), Color(accent, 0.18), true)
		draw_rect(Rect2(c + offset, Vector2(r * 0.48, r * 0.62)), accent, false, 3.0)
	if icon_kind == "conflict_docs":
		draw_line(c - Vector2(r * 0.14, r * 0.08), c + Vector2(r * 0.20, r * 0.26), Color("ff7588"), 4.0)
		draw_line(c + Vector2(r * 0.20, -r * 0.08), c - Vector2(r * 0.14, -r * 0.42), Color("ff7588"), 4.0)
	else:
		_draw_check(c + Vector2(r * 0.18, r * 0.06), r * 0.44)


func _draw_stack(c: Vector2, r: float) -> void:
	for index in range(3):
		var rect := Rect2(c + Vector2(-r * 0.5 + index * r * 0.10, -r * 0.38 + index * r * 0.28), Vector2(r * 0.78, r * 0.34))
		draw_rect(rect, Color(accent, 0.18), true)
		draw_rect(rect, accent, false, 3.0)
	if icon_kind == "organize_tags":
		draw_circle(c + Vector2(r * 0.36, -r * 0.32), r * 0.18, accent)


func _draw_ai_chart(c: Vector2, r: float) -> void:
	draw_circle(c + Vector2(-r * 0.24, -r * 0.20), r * 0.24, Color(accent, 0.24))
	draw_circle(c + Vector2(-r * 0.32, -r * 0.22), 3.0, accent)
	draw_circle(c + Vector2(-r * 0.16, -r * 0.22), 3.0, accent)
	for index in range(3):
		var h := r * (0.30 + index * 0.18)
		draw_rect(Rect2(c + Vector2(-r * 0.05 + index * r * 0.22, r * 0.48 - h), Vector2(r * 0.13, h)), accent, true)
	if icon_kind == "trace_data":
		draw_line(c - Vector2(r * 0.52, -r * 0.48), c + Vector2(r * 0.50, -r * 0.48), Color("fff19a"), 3.0)


func _draw_web_clock(c: Vector2, r: float) -> void:
	draw_rect(Rect2(c - Vector2(r * 0.55, r * 0.42), Vector2(r * 0.82, r * 0.62)), Color(accent, 0.16), true)
	draw_rect(Rect2(c - Vector2(r * 0.55, r * 0.42), Vector2(r * 0.82, r * 0.62)), accent, false, 3.0)
	draw_circle(c + Vector2(r * 0.30, r * 0.22), r * 0.30, Color("0b1830"))
	draw_arc(c + Vector2(r * 0.30, r * 0.22), r * 0.30, 0.0, TAU, 24, accent, 4.0)
	draw_line(c + Vector2(r * 0.30, r * 0.22), c + Vector2(r * 0.30, r * 0.02), accent, 3.0)
	draw_line(c + Vector2(r * 0.30, r * 0.22), c + Vector2(r * 0.46, r * 0.30), accent, 3.0)


func _draw_editor(c: Vector2, r: float) -> void:
	draw_rect(Rect2(c - Vector2(r * 0.48, r * 0.38), Vector2(r * 0.78, r * 0.62)), Color(accent, 0.18), true)
	draw_rect(Rect2(c - Vector2(r * 0.48, r * 0.38), Vector2(r * 0.78, r * 0.62)), accent, false, 3.0)
	draw_line(c - Vector2(r * 0.18, -r * 0.45), c + Vector2(r * 0.50, -r * 0.20), Color("fff19a"), 7.0)
	draw_circle(c - Vector2(r * 0.34, -r * 0.08), r * 0.09, accent)


func _draw_upload(c: Vector2, r: float) -> void:
	draw_circle(c - Vector2(r * 0.22, r * 0.18), r * 0.25, Color(accent, 0.25))
	draw_circle(c - Vector2(r * 0.30, r * 0.20), 3.0, accent)
	draw_circle(c - Vector2(r * 0.14, r * 0.20), 3.0, accent)
	draw_line(c + Vector2(r * 0.26, r * 0.42), c + Vector2(r * 0.26, -r * 0.38), accent, 5.0)
	draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.02, -r * 0.14), c + Vector2(r * 0.26, -r * 0.46), c + Vector2(r * 0.50, -r * 0.14)]), accent)


func _draw_media(c: Vector2, r: float) -> void:
	draw_rect(Rect2(c - Vector2(r * 0.52, r * 0.34), Vector2(r * 0.66, r * 0.56)), Color(accent, 0.15), true)
	draw_circle(c + Vector2(r * 0.31, -r * 0.12), r * 0.24, Color(accent, 0.28))
	draw_colored_polygon(PackedVector2Array([c - Vector2(r * 0.17, r * 0.18), c + Vector2(r * 0.05, 0.0), c - Vector2(r * 0.17, -r * 0.18)]), accent)


func _draw_network(c: Vector2, r: float) -> void:
	draw_rect(Rect2(c - Vector2(r * 0.50, r * 0.34), Vector2(r * 0.70, r * 0.58)), Color(accent, 0.16), true)
	draw_colored_polygon(PackedVector2Array([c - Vector2(r * 0.38, -r * 0.08), c - Vector2(r * 0.12, r * 0.18), c + Vector2(r * 0.06, -r * 0.02)]), accent)
	for offset in [Vector2(r * 0.40, -r * 0.30), Vector2(r * 0.50, r * 0.04), Vector2(r * 0.34, r * 0.38)]:
		draw_line(c + Vector2(r * 0.12, 0.0), c + offset, accent, 3.0)
		draw_circle(c + offset, r * 0.09, accent)


func _draw_version(c: Vector2, r: float) -> void:
	draw_arc(c, r * 0.48, -PI * 0.25, PI * 1.25, 28, accent, 5.0)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.54, -r * 0.10), c + Vector2(-r * 0.24, -r * 0.16), c + Vector2(-r * 0.40, r * 0.12)]), accent)
	draw_circle(c, r * 0.19, Color(accent, 0.30))


func _draw_chip(c: Vector2, r: float) -> void:
	draw_rect(Rect2(c - Vector2(r * 0.40, r * 0.32), Vector2(r * 0.80, r * 0.64)), Color(accent, 0.20), true)
	draw_rect(Rect2(c - Vector2(r * 0.40, r * 0.32), Vector2(r * 0.80, r * 0.64)), accent, false, 4.0)


func _draw_check(c: Vector2, r: float) -> void:
	draw_line(c - Vector2(r * 0.45, 0.0), c - Vector2(r * 0.10, -r * 0.35), Color("7df4c9"), 5.0)
	draw_line(c - Vector2(r * 0.10, -r * 0.35), c + Vector2(r * 0.48, r * 0.35), Color("7df4c9"), 5.0)
