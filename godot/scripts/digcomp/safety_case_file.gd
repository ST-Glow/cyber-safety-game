class_name SafetyCaseFile
extends Control

signal drag_started(card: SafetyCaseFile)
signal drag_moved(card: SafetyCaseFile, pointer_global: Vector2)
signal drag_released(card: SafetyCaseFile, pointer_global: Vector2)

const UI_FONT: FontFile = preload("res://assets/ui/fonts/noto_sans_sc_ui_600.ttf")

var item: Dictionary = {}
var item_id: String = ""
var scene_kind: String = "team_plan"
var _header: Label
var _scene_title: Label
var _prompt: Label
var _dragging: bool = false
var _magnetized: bool = false
var _home_position: Vector2 = Vector2.ZERO
var _drag_offset: Vector2 = Vector2.ZERO
var _last_pointer: Vector2 = Vector2.ZERO
var _phase: float = 0.0
var _scan_pulse: float = 0.0
var _fault_flash: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(450.0, 304.0)
	size = custom_minimum_size
	pivot_offset = size * 0.5
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	_header = Label.new()
	_header.position = Vector2(24.0, 12.0)
	_header.size = Vector2(180.0, 28.0)
	_header.add_theme_font_override("font", UI_FONT)
	_header.add_theme_font_size_override("font_size", 13)
	_header.add_theme_color_override("font_color", Color("73ead5"))
	add_child(_header)
	_scene_title = Label.new()
	_scene_title.position = Vector2(120.0, 52.0)
	_scene_title.size = Vector2(210.0, 30.0)
	_scene_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scene_title.add_theme_font_override("font", UI_FONT)
	_scene_title.add_theme_font_size_override("font_size", 17)
	_scene_title.add_theme_color_override("font_color", Color("dffaff"))
	add_child(_scene_title)
	_prompt = Label.new()
	_prompt.position = Vector2(28.0, 229.0)
	_prompt.size = Vector2(394.0, 58.0)
	_prompt.add_theme_font_override("font", UI_FONT)
	_prompt.add_theme_font_size_override("font_size", 16)
	_prompt.add_theme_color_override("font_color", Color("d9edf6"))
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_prompt)


func configure(data: Dictionary, case_number: int) -> void:
	item = data.duplicate(true)
	item_id = String(item.get("id", ""))
	scene_kind = String(item.get("scene_kind", "team_plan"))
	tooltip_text = String(item.get("prompt", ""))
	if _header:
		_header.text = "CASE FILE %02d  //  %s" % [case_number, "COLLAB" if String(item.get("area_id", "")) == "area_2" else "SAFETY"]
	if _scene_title:
		_scene_title.text = String(item.get("scene_title", "DIGITAL CASE"))
	if _prompt:
		_prompt.text = String(item.get("prompt", ""))
	queue_redraw()


func set_home_position(value: Vector2, immediate: bool = false) -> void:
	_home_position = value
	if immediate:
		position = value


func return_home() -> void:
	_dragging = false
	_magnetized = false
	z_index = 20
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_parallel(true)
	tween.tween_property(self, "position", _home_position, 0.30)
	tween.tween_property(self, "rotation", 0.0, 0.22)
	tween.tween_property(self, "scale", Vector2.ONE, 0.22)


func set_magnetized(value: bool) -> void:
	if _magnetized == value:
		return
	_magnetized = value
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2(1.07, 1.07) if value else (Vector2(1.06, 1.06) if _dragging else Vector2.ONE), 0.12)
	queue_redraw()


func stop_dragging() -> void:
	_dragging = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func play_scan() -> void:
	_scan_pulse = 1.0
	queue_redraw()


func play_wrong() -> void:
	_fault_flash = 1.0
	var origin := position
	var tween := create_tween()
	for offset in [Vector2(12, -3), Vector2(-10, 2), Vector2(7, -1), Vector2(-4, 1), Vector2.ZERO]:
		tween.tween_property(self, "position", origin + offset, 0.045)


func _process(delta: float) -> void:
	_phase = fmod(_phase + delta * 3.5, TAU)
	_scan_pulse = maxf(0.0, _scan_pulse - delta * 1.8)
	_fault_flash = maxf(0.0, _fault_flash - delta * 2.3)
	queue_redraw()


func _draw() -> void:
	var cyan := Color("62e4d0")
	var danger := Color("ff586f")
	var cut := 22.0
	var shell := PackedVector2Array([
		Vector2(cut, 3), Vector2(size.x - 68, 3), Vector2(size.x - 45, 25), Vector2(size.x - 3, 25),
		Vector2(size.x - 3, size.y - cut), Vector2(size.x - cut, size.y - 3),
		Vector2(cut, size.y - 3), Vector2(3, size.y - cut), Vector2(3, cut),
	])
	draw_colored_polygon(shell, Color("0e2840").lerp(danger, _fault_flash * 0.24))
	var outline := PackedVector2Array(shell)
	outline.append(shell[0])
	draw_polyline(outline, Color("83f2e0") if _magnetized else Color("3c7890"), 4.0 if _magnetized else 3.0, true)
	draw_rect(Rect2(21.0, 42.0, size.x - 42.0, 178.0), Color("071426"), true)
	draw_rect(Rect2(21.0, 42.0, size.x - 42.0, 178.0), Color(0.30, 0.68, 0.76, 0.46), false, 3.0)
	# Scene viewport scanlines.
	for y in range(50, 216, 18):
		draw_line(Vector2(25.0, float(y)), Vector2(size.x - 25.0, float(y)), Color(0.30, 0.75, 0.82, 0.045), 1.0)
	match scene_kind:
		"team_plan": _draw_team_plan()
		"evidence_review": _draw_evidence_review()
		"ai_final": _draw_ai_final()
		"vague_prompt": _draw_vague_prompt()
		"decision_log": _draw_decision_log()
		"privacy_upload": _draw_privacy_upload()
		"attachment_scan": _draw_attachment_scan()
		"bias_review": _draw_bias_review()
		"wellbeing": _draw_wellbeing()
		"account_security": _draw_account_security()
		_: _draw_team_plan()
	# Status LEDs and scan/magnet rings.
	for index in range(4):
		draw_circle(Vector2(size.x - 24.0 - index * 16.0, 15.0), 4.0, cyan if (index + int(_phase * 2.0)) % 3 == 0 else Color("24485f"))
	if _scan_pulse > 0.0:
		var scan_x := 28.0 + (size.x - 56.0) * (1.0 - _scan_pulse)
		draw_line(Vector2(scan_x, 45.0), Vector2(scan_x, 217.0), Color(0.45, 1.0, 0.86, _scan_pulse), 8.0)
	if _magnetized:
		draw_arc(size * 0.5, 181.0 + sin(_phase * 2.0) * 6.0, 0.0, TAU, 50, Color(0.42, 1.0, 0.87, 0.68), 4.0)
	if _fault_flash > 0.0:
		for y in range(46, 216, 28):
			draw_line(Vector2(24, float(y)), Vector2(size.x - 24, float(y + 8)), Color(1.0, 0.1, 0.22, _fault_flash * 0.38), 4.0)


func _draw_team_plan() -> void:
	_draw_monitor(Rect2(144, 82, 162, 91), Color("55dbc7"))
	for index in range(3):
		_draw_avatar(Vector2(88 + index * 138, 187), Color.from_hsv(0.48 + index * 0.12, 0.55, 0.92))
		draw_line(Vector2(170, 112 + index * 18), Vector2(279, 112 + index * 18), Color("65e4d0"), 5.0)
	_draw_robot(Vector2(360, 119), Color("69d8f1"))


func _draw_evidence_review() -> void:
	_draw_document(Rect2(62, 78, 104, 114), Color("72b9ed"), true)
	_draw_document(Rect2(282, 78, 104, 114), Color("e9bb62"), true)
	draw_arc(Vector2(224, 132), 38, 0, TAU, 30, Color("66ead4"), 7.0)
	draw_line(Vector2(250, 159), Vector2(276, 187), Color("66ead4"), 8.0)
	draw_line(Vector2(168, 131), Vector2(186, 131), Color("62e8d2"), 4.0)
	draw_line(Vector2(262, 131), Vector2(281, 131), Color("62e8d2"), 4.0)


func _draw_ai_final() -> void:
	_draw_monitor(Rect2(133, 76, 184, 104), Color("ff5d72"))
	_draw_robot(Vector2(77, 126), Color("ff7b8d"))
	# Empty human review chair.
	draw_rect(Rect2(354, 118, 42, 52), Color(0.8, 0.9, 1.0, 0.04), true)
	draw_rect(Rect2(354, 118, 42, 52), Color("657b8f"), false, 4.0)
	draw_line(Vector2(363, 170), Vector2(354, 194), Color("657b8f"), 5.0)
	draw_line(Vector2(387, 170), Vector2(396, 194), Color("657b8f"), 5.0)
	_draw_warning(Vector2(375, 91))


func _draw_vague_prompt() -> void:
	_draw_robot(Vector2(340, 137), Color("78c8e8"))
	draw_colored_polygon(PackedVector2Array([Vector2(58, 86), Vector2(278, 86), Vector2(278, 162), Vector2(123, 162), Vector2(103, 182), Vector2(105, 162), Vector2(58, 162)]), Color(0.12, 0.32, 0.46, 0.85))
	for index in range(3):
		draw_circle(Vector2(135 + index * 36, 124), 8.0, Color("b7d8e6"))
	_draw_warning(Vector2(301, 92))


func _draw_decision_log() -> void:
	_draw_document(Rect2(138, 69, 174, 137), Color("58e2c4"), true)
	for index in range(3):
		_draw_avatar(Vector2(72 + index * 150, 176), Color.from_hsv(0.42 + index * 0.10, 0.46, 0.92))
		_draw_check(Vector2(171, 100 + index * 28), Color("70edca"))


func _draw_privacy_upload() -> void:
	_draw_monitor(Rect2(210, 76, 170, 112), Color("ff657c"))
	_draw_avatar(Vector2(78, 118), Color("68b8e6"))
	# Exposed identity rows and upload arrow.
	for index in range(3):
		draw_rect(Rect2(236, 105 + index * 22, 111, 12), Color(0.96, 0.22, 0.34, 0.58), true)
	draw_line(Vector2(119, 124), Vector2(192, 124), Color("ff6178"), 8.0)
	draw_colored_polygon(PackedVector2Array([Vector2(192, 110), Vector2(212, 124), Vector2(192, 138)]), Color("ff6178"))
	_draw_warning(Vector2(114, 82))


func _draw_attachment_scan() -> void:
	# Envelope entering a shield scanner.
	draw_rect(Rect2(65, 99, 118, 78), Color(0.20, 0.42, 0.58, 0.72), true)
	draw_rect(Rect2(65, 99, 118, 78), Color("7fcbe8"), false, 4.0)
	draw_line(Vector2(65, 101), Vector2(124, 145), Color("7fcbe8"), 4.0)
	draw_line(Vector2(183, 101), Vector2(124, 145), Color("7fcbe8"), 4.0)
	_draw_shield(Vector2(310, 134), Color("62e6c7"))
	draw_line(Vector2(190, 137), Vector2(253, 137), Color("68ead0"), 6.0)


func _draw_bias_review() -> void:
	_draw_monitor(Rect2(144, 75, 166, 101), Color("ff6577"))
	for index in range(4):
		_draw_avatar(Vector2(70 + index * 94, 190), Color.from_hsv(0.05 + index * 0.13, 0.45, 0.94))
	draw_arc(Vector2(354, 118), 34, 0, TAU, 26, Color("65e7d1"), 6.0)
	draw_line(Vector2(378, 142), Vector2(401, 168), Color("65e7d1"), 7.0)
	_draw_warning(Vector2(224, 125))


func _draw_wellbeing() -> void:
	_draw_monitor(Rect2(204, 75, 154, 99), Color("ffb95a"))
	_draw_avatar(Vector2(112, 142), Color("7dbbe5"))
	# Clock and depleted attention battery.
	draw_arc(Vector2(372, 184), 27, 0, TAU, 24, Color("ffbe61"), 5.0)
	draw_line(Vector2(372, 184), Vector2(372, 167), Color("ffbe61"), 4.0)
	draw_line(Vector2(372, 184), Vector2(387, 191), Color("ffbe61"), 4.0)
	draw_rect(Rect2(61, 78, 105, 22), Color(0.9, 0.25, 0.32, 0.18), true)
	draw_rect(Rect2(61, 78, 105, 22), Color("ff6578"), false, 3.0)
	draw_rect(Rect2(64, 81, 17, 16), Color("ff6578"), true)


func _draw_account_security() -> void:
	_draw_monitor(Rect2(140, 70, 173, 111), Color("5ee4c8"))
	_draw_shield(Vector2(82, 132), Color("61ebc8"))
	# Phone confirmation and password nodes make the final case denser.
	draw_rect(Rect2(342, 82, 62, 112), Color("0e3148"), true)
	draw_rect(Rect2(342, 82, 62, 112), Color("72cde6"), false, 4.0)
	_draw_check(Vector2(373, 139), Color("62ebc9"))
	for index in range(6):
		draw_circle(Vector2(165 + index * 22, 151), 5.0, Color("d9faff"))


func _draw_monitor(rect: Rect2, color: Color) -> void:
	draw_rect(rect, Color(color, 0.13), true)
	draw_rect(rect, color, false, 4.0)
	draw_line(Vector2(rect.position.x + rect.size.x * 0.5, rect.end.y), Vector2(rect.position.x + rect.size.x * 0.5, rect.end.y + 15), color, 5.0)
	draw_line(Vector2(rect.position.x + rect.size.x * 0.32, rect.end.y + 15), Vector2(rect.position.x + rect.size.x * 0.68, rect.end.y + 15), color, 5.0)


func _draw_avatar(c: Vector2, color: Color) -> void:
	draw_circle(c - Vector2(0, 18), 14, color)
	draw_arc(c + Vector2(0, 17), 25, PI, TAU, 20, color, 9.0)


func _draw_robot(c: Vector2, color: Color) -> void:
	draw_rect(Rect2(c - Vector2(29, 25), Vector2(58, 50)), Color(color, 0.20), true)
	draw_rect(Rect2(c - Vector2(29, 25), Vector2(58, 50)), color, false, 4.0)
	draw_circle(c + Vector2(-12, -4), 5, color)
	draw_circle(c + Vector2(12, -4), 5, color)
	draw_line(c + Vector2(0, -25), c + Vector2(0, -42), color, 4.0)
	draw_circle(c + Vector2(0, -45), 5, color)


func _draw_document(rect: Rect2, color: Color, checked: bool) -> void:
	draw_rect(rect, Color(color, 0.14), true)
	draw_rect(rect, color, false, 4.0)
	for index in range(4):
		draw_line(rect.position + Vector2(16, 25 + index * 20), rect.position + Vector2(rect.size.x - 16, 25 + index * 20), Color(color, 0.72), 3.0)
	if checked:
		_draw_check(rect.position + Vector2(rect.size.x - 22, rect.size.y - 19), Color("69e8c9"))


func _draw_check(c: Vector2, color: Color) -> void:
	draw_line(c + Vector2(-10, 0), c + Vector2(-2, 9), color, 5.0)
	draw_line(c + Vector2(-2, 9), c + Vector2(13, -10), color, 5.0)


func _draw_warning(c: Vector2) -> void:
	var color := Color("ff5b72") if sin(_phase * 3.0) > -0.1 else Color("8a273d")
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -20), c + Vector2(20, 18), c + Vector2(-20, 18)]), Color(color, 0.28))
	draw_polyline(PackedVector2Array([c + Vector2(0, -20), c + Vector2(20, 18), c + Vector2(-20, 18), c + Vector2(0, -20)]), color, 4.0)
	draw_line(c + Vector2(0, -7), c + Vector2(0, 7), color, 4.0)
	draw_circle(c + Vector2(0, 13), 3, color)


func _draw_shield(c: Vector2, color: Color) -> void:
	var points := PackedVector2Array([c + Vector2(0, -45), c + Vector2(37, -29), c + Vector2(31, 22), c + Vector2(0, 49), c + Vector2(-31, 22), c + Vector2(-37, -29)])
	draw_colored_polygon(points, Color(color, 0.16))
	var outline := PackedVector2Array(points)
	outline.append(points[0])
	draw_polyline(outline, color, 5.0, true)
	_draw_check(c, color)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_drag(get_global_mouse_position())
		else:
			_end_drag(get_global_mouse_position())
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_update_drag(get_global_mouse_position())
		accept_event()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_begin_drag(event.position)
		else:
			_end_drag(event.position)
		accept_event()
	elif event is InputEventScreenDrag and _dragging:
		_update_drag(event.position)
		accept_event()


func _begin_drag(pointer: Vector2) -> void:
	if _dragging:
		return
	_dragging = true
	_drag_offset = pointer - global_position
	_last_pointer = pointer
	z_index = 100
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2(1.06, 1.06), 0.13)
	tween.tween_property(self, "position:y", position.y - 10.0, 0.13)
	drag_started.emit(self)


func _update_drag(pointer: Vector2) -> void:
	global_position = pointer - _drag_offset
	var velocity_x := pointer.x - _last_pointer.x
	rotation = lerpf(rotation, deg_to_rad(clampf(velocity_x * 0.34, -6.0, 6.0)), 0.30)
	_last_pointer = pointer
	drag_moved.emit(self, pointer)


func _end_drag(pointer: Vector2) -> void:
	if not _dragging:
		return
	_dragging = false
	drag_released.emit(self, pointer)
