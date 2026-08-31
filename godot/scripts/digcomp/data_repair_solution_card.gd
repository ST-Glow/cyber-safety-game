class_name DataRepairSolutionCard
extends PanelContainer

signal drag_started(card: DataRepairSolutionCard)
signal drag_moved(card: DataRepairSolutionCard, pointer_global: Vector2)
signal drag_released(card: DataRepairSolutionCard, pointer_global: Vector2)

const UI_FONT: FontFile = preload("res://assets/ui/fonts/noto_sans_sc_ui_600.ttf")
const ICON_SCRIPT := preload("res://scripts/digcomp/data_repair_icon.gd")

var solution_id: String = ""
var is_decoy: bool = false
var item: Dictionary = {}
var accent: Color = Color("65e8d1")
var _label: Label
var _icon: Control
var _dragging: bool = false
var _hovered: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _home_position: Vector2 = Vector2.ZERO
var _phase: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(166.0, 112.0)
	size = custom_minimum_size
	pivot_offset = size * 0.5
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var transparent := StyleBoxFlat.new()
	transparent.bg_color = Color.TRANSPARENT
	add_theme_stylebox_override("panel", transparent)
	_icon = ICON_SCRIPT.new() as Control
	_icon.position = Vector2(42.0, 5.0)
	_icon.size = Vector2(82.0, 72.0)
	add_child(_icon)
	_label = Label.new()
	_label.position = Vector2(12.0, 74.0)
	_label.size = Vector2(142.0, 27.0)
	_label.add_theme_font_override("font", UI_FONT)
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color("e8fbff"))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_label)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func configure(card_id: String, data: Dictionary, decoy: bool = false) -> void:
	solution_id = card_id
	is_decoy = decoy
	item = data.duplicate(true)
	accent = Color("9aa9bd") if decoy else Color(String(item.get("accent", "65e8d1")))
	var full_text := String(item.get("decoy" if decoy else "solution", ""))
	tooltip_text = full_text
	if _label:
		_label.text = "干扰信号" if decoy else String(item.get("solution_short", full_text))
		_label.add_theme_color_override("font_color", Color("c1cad5") if decoy else Color("e8fbff"))
	if _icon:
		_icon.call("configure", "data_stack" if decoy else String(item.get("solution_icon", "data_stack")), accent)
	queue_redraw()


func set_home_position(value: Vector2, animate: bool = false) -> void:
	_home_position = value
	if animate:
		return_home()
	else:
		position = value


func return_home() -> void:
	_dragging = false
	z_index = 0
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position", _home_position, 0.28)
	tween.parallel().tween_property(self, "scale", Vector2(1.04, 1.04) if _hovered else Vector2.ONE, 0.18)
	tween.parallel().tween_property(self, "rotation", 0.0, 0.18)
	queue_redraw()


func play_wrong_bounce() -> void:
	var tween := create_tween()
	tween.tween_property(self, "rotation", deg_to_rad(12.0), 0.06)
	tween.tween_property(self, "rotation", deg_to_rad(-10.0), 0.06)
	tween.tween_property(self, "rotation", deg_to_rad(6.0), 0.06)
	tween.tween_callback(return_home)


func stop_dragging() -> void:
	_dragging = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_phase = fmod(_phase + delta * 4.0, TAU)
	queue_redraw()


func _draw() -> void:
	var glow := Color("ff7186") if is_decoy else accent
	var cut := 18.0
	var shape := PackedVector2Array([
		Vector2(cut, 3.0), Vector2(size.x - cut, 3.0), Vector2(size.x - 3.0, cut),
		Vector2(size.x - 3.0, size.y - 22.0), Vector2(size.x - 22.0, size.y - 3.0),
		Vector2(22.0, size.y - 3.0), Vector2(3.0, size.y - 22.0), Vector2(3.0, cut),
	])
	var lift := 0.22 if _dragging else (0.12 if _hovered else 0.06)
	draw_colored_polygon(shape, Color(glow, lift))
	var outline := PackedVector2Array(shape)
	outline.append(shape[0])
	draw_polyline(outline, Color(glow, 0.98), 3.0 if _dragging else 2.0, true)
	draw_line(Vector2(23.0, 101.0), Vector2(size.x - 23.0, 101.0), Color(glow, 0.35), 2.0)
	for x in range(26, 151, 25):
		draw_rect(Rect2(float(x), -1.0, 9.0, 7.0), Color("85abc0"), true)
		draw_rect(Rect2(float(x), size.y - 6.0, 9.0, 7.0), Color("85abc0"), true)
	draw_circle(Vector2(17.0, 17.0), 4.0 + sin(_phase * 2.0) * 0.8, glow)
	if _dragging:
		draw_arc(size * 0.5, 65.0 + sin(_phase * 2.0) * 3.0, 0.0, TAU, 36, Color(glow, 0.56), 3.0)


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


func _begin_drag(pointer_global: Vector2) -> void:
	if _dragging:
		return
	_dragging = true
	_home_position = position
	_drag_offset = pointer_global - global_position
	z_index = 100
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2(1.12, 1.12), 0.12)
	tween.parallel().tween_property(self, "rotation", deg_to_rad(-3.5), 0.12)
	drag_started.emit(self)


func _update_drag(pointer_global: Vector2) -> void:
	global_position = pointer_global - _drag_offset
	drag_moved.emit(self, pointer_global)


func _end_drag(pointer_global: Vector2) -> void:
	if not _dragging:
		return
	_dragging = false
	drag_released.emit(self, pointer_global)


func _on_mouse_entered() -> void:
	_hovered = true
	if not _dragging:
		create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(self, "scale", Vector2(1.05, 1.05), 0.12)


func _on_mouse_exited() -> void:
	_hovered = false
	if not _dragging:
		create_tween().tween_property(self, "scale", Vector2.ONE, 0.12)
