class_name JigsawPiece
extends Node2D

var piece_id: int = -1
var row: int = 0
var column: int = 0
var target_position: Vector2 = Vector2.ZERO
var locked: bool = false
var attempts: int = 0
var first_drop_correct: bool = false
var first_drop_recorded: bool = false
var polygon_points: PackedVector2Array = PackedVector2Array()

var _shadow: Polygon2D
var _image: Polygon2D
var _outline: Line2D
var _drag_tween: Tween


func setup(
	value_id: int,
	value_row: int,
	value_column: int,
	value_target: Vector2,
	points: PackedVector2Array,
	uv_points: PackedVector2Array,
	texture: Texture2D
) -> void:
	piece_id = value_id
	row = value_row
	column = value_column
	target_position = value_target
	polygon_points = points

	_shadow = Polygon2D.new()
	_shadow.polygon = points
	_shadow.color = Color(0.01, 0.03, 0.08, 0.5)
	_shadow.position = Vector2(7.0, 9.0)
	add_child(_shadow)

	_image = Polygon2D.new()
	_image.polygon = points
	_image.uv = uv_points
	_image.texture = texture
	add_child(_image)

	_outline = Line2D.new()
	_outline.width = 2.5
	_outline.default_color = Color(0.91, 0.97, 1.0, 0.9)
	_outline.antialiased = true
	_outline.joint_mode = Line2D.LINE_JOINT_ROUND
	var closed := PackedVector2Array(points)
	closed.append(points[0])
	_outline.points = closed
	add_child(_outline)


func contains_global_point(global_point: Vector2) -> bool:
	if locked or polygon_points.is_empty():
		return false
	return Geometry2D.is_point_in_polygon(to_local(global_point), polygon_points)


func set_dragging(value: bool) -> void:
	if locked:
		return
	if _drag_tween and _drag_tween.is_running():
		_drag_tween.kill()
	_drag_tween = create_tween().set_parallel(true)
	_drag_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_drag_tween.tween_property(self, "scale", Vector2.ONE * (1.055 if value else 1.0), 0.12)
	_drag_tween.tween_property(_shadow, "position", Vector2(12.0, 15.0) if value else Vector2(7.0, 9.0), 0.12)
	_outline.default_color = Color("74f4e3") if value else Color(0.91, 0.97, 1.0, 0.9)


func snap_to_target() -> Tween:
	locked = true
	z_index = 1
	if _drag_tween and _drag_tween.is_running():
		_drag_tween.kill()
	_drag_tween = create_tween().set_parallel(true)
	_drag_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_drag_tween.tween_property(self, "position", target_position, 0.2)
	_drag_tween.tween_property(self, "scale", Vector2.ONE, 0.2)
	_drag_tween.tween_property(_shadow, "modulate:a", 0.16, 0.2)
	_outline.default_color = Color("72f3a6")
	var highlight := create_tween()
	highlight.tween_interval(0.25)
	highlight.tween_property(_outline, "default_color", Color(0.8, 0.91, 1.0, 0.72), 0.35)
	return _drag_tween

