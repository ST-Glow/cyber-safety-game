class_name DataRepairProblemCard
extends PanelContainer

signal reached_fault_zone(card: DataRepairProblemCard)

const UI_FONT: FontFile = preload("res://assets/ui/fonts/noto_sans_sc_ui_600.ttf")
const ICON_SCRIPT := preload("res://scripts/digcomp/data_repair_icon.gd")

var item: Dictionary = {}
var item_id: String = ""
var lane_index: int = 0
var movement_speed: float = 54.0
var fault_x: float = 900.0
var moving: bool = false
var accent: Color = Color("58c8ff")
var _label: Label
var _icon: Control
var _phase: float = 0.0
var _snap_hint: bool = false
var _repaired: bool = false
var _fault_flash: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(184.0, 108.0)
	size = custom_minimum_size
	pivot_offset = size * 0.5
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var transparent := StyleBoxFlat.new()
	transparent.bg_color = Color.TRANSPARENT
	add_theme_stylebox_override("panel", transparent)
	_icon = ICON_SCRIPT.new() as Control
	_icon.position = Vector2(12.0, 12.0)
	_icon.size = Vector2(70.0, 70.0)
	add_child(_icon)
	_label = Label.new()
	_label.position = Vector2(80.0, 21.0)
	_label.size = Vector2(96.0, 64.0)
	_label.add_theme_font_override("font", UI_FONT)
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color("eafaff"))
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)


func configure(data: Dictionary, lane: int, speed: float, deadline_x: float) -> void:
	item = data.duplicate(true)
	item_id = String(item.get("id", ""))
	lane_index = lane
	movement_speed = speed
	fault_x = deadline_x
	accent = Color(String(item.get("accent", "58c8ff")))
	tooltip_text = String(item.get("problem", ""))
	if _icon:
		_icon.call("configure", String(item.get("problem_icon", "data_stack")), Color("ff6d83"))
	if _label:
		_label.text = String(item.get("problem_short", item.get("problem", "")))
	queue_redraw()


func start_motion() -> void:
	moving = true


func stop_motion() -> void:
	moving = false


func set_snap_hint(value: bool) -> void:
	if _snap_hint == value:
		return
	_snap_hint = value
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2(1.08, 1.08) if value else Vector2.ONE, 0.12)
	queue_redraw()


func play_fault_feedback() -> void:
	set_snap_hint(false)
	_fault_flash = 1.0
	var origin := position
	var tween := create_tween()
	for offset in [12.0, -10.0, 7.0, -4.0, 0.0]:
		tween.tween_property(self, "position:x", origin.x + offset, 0.045)
	tween.parallel().tween_property(self, "_fault_flash", 0.0, 0.32)
	queue_redraw()


func play_repair_feedback() -> void:
	moving = false
	_repaired = true
	_snap_hint = false
	if _icon:
		_icon.set("accent", Color("69f1ce"))
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2(1.12, 1.12), 0.16)
	queue_redraw()


func _process(delta: float) -> void:
	_phase = fmod(_phase + delta * 4.0, TAU)
	_fault_flash = maxf(0.0, _fault_flash - delta * 3.5)
	if moving:
		position.x += movement_speed * minf(delta, 0.05)
		if position.x >= fault_x:
			moving = false
			reached_fault_zone.emit(self)
	queue_redraw()


func _draw() -> void:
	var glow_color := Color("69f1ce") if _repaired else (Color("65f1d3") if _snap_hint else Color("ff5a72"))
	var body_color := Color("153c48") if _repaired else Color("321b35")
	var cut := 15.0
	var shape := PackedVector2Array([
		Vector2(cut, 2.0), Vector2(size.x - 22.0, 2.0), Vector2(size.x - 4.0, 20.0),
		Vector2(size.x - 4.0, size.y - cut), Vector2(size.x - cut, size.y - 2.0),
		Vector2(22.0, size.y - 2.0), Vector2(3.0, size.y - 21.0), Vector2(3.0, cut),
	])
	draw_colored_polygon(shape, body_color.lerp(glow_color, 0.08 + _fault_flash * 0.22))
	var outline := PackedVector2Array(shape)
	outline.append(shape[0])
	draw_polyline(outline, glow_color, 3.0, true)
	for y in [28.0, 78.0]:
		draw_rect(Rect2(-1.0, y, 12.0, 18.0), Color("0a1527"), true)
		draw_rect(Rect2(size.x - 11.0, y, 12.0, 18.0), Color("0a1527"), true)
	var status := glow_color if _repaired or _snap_hint else Color("ff435f")
	draw_circle(Vector2(size.x - 17.0, 16.0), 5.0 + sin(_phase) * 1.2, status)
	if not _repaired:
		var electric_y := 93.0 + sin(_phase * 2.0) * 2.0
		draw_polyline(PackedVector2Array([
			Vector2(22.0, electric_y), Vector2(47.0, electric_y - 5.0), Vector2(69.0, electric_y + 3.0),
			Vector2(96.0, electric_y - 3.0), Vector2(123.0, electric_y + 4.0), Vector2(159.0, electric_y),
		]), Color(1.0, 0.25, 0.38, 0.55 + _fault_flash * 0.4), 2.0)
	if _snap_hint:
		draw_arc(size * 0.5, 64.0 + sin(_phase * 2.0) * 4.0, 0.0, TAU, 40, Color(0.4, 1.0, 0.86, 0.68), 4.0)
