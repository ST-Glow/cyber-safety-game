class_name JigsawPuzzle
extends Control

const EVENT_BRIDGE := preload("res://scripts/experiment_event_bridge.gd")
const PIECE_SCRIPT := preload("res://scripts/digcomp/jigsaw_piece.gd")
const AI_PANEL_SCRIPT := preload("res://scripts/ui/ai_assistant_panel.gd")
const SCAFFOLD_SCRIPT := preload("res://scripts/scaffolding/scaffold_controller.gd")
const UI_FONT: FontFile = preload("res://assets/ui/fonts/noto_sans_sc_ui_600.ttf")
const SNAP_SOUND: AudioStream = preload("res://assets/audio/interface_sfx_pack_1/confirm_tones/style6/confirm_style_6_001.ogg")

@export var puzzle_texture: Texture2D
@export_enum("3 × 3:3", "4 × 4:4", "5 × 5:5") var grid_size: int = 3
@export_range(18.0, 60.0, 1.0) var snap_distance: float = 34.0

var task_container: Control
var assistant_panel: AiAssistantPanel
var scaffold_controller: ScaffoldController
var pieces_layer: Node2D
var preview: TextureRect
var timer_label: Label
var stats_label: Label
var feedback_label: Label
var completion_overlay: Control

var pieces: Array[JigsawPiece] = []
var board_rect := Rect2()
var cell_size := Vector2.ZERO
var moves: int = 0
var errors: int = 0
var placed_count: int = 0
var first_correct_count: int = 0
var start_msec: int = 0
var _completed: bool = false
var _dragged_piece: JigsawPiece
var _drag_offset := Vector2.ZERO
var _drag_target := Vector2.ZERO
var _z_counter: int = 20
var _horizontal_edges: Array = []
var _vertical_edges: Array = []
var _snap_player: AudioStreamPlayer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var puzzle_theme := Theme.new()
	puzzle_theme.default_font = UI_FONT
	puzzle_theme.default_font_size = 16
	theme = puzzle_theme
	_build_ui()
	_setup_ai()
	start_new_puzzle(grid_size)
	_record("digcomp_task_presented", {
		"task_type": "image_jigsaw",
		"digcomp_version": "3.0",
		"area_id": "area_5",
		"grid_size": grid_size,
	})


func _process(delta: float) -> void:
	if not _completed:
		timer_label.text = "用时  %s" % _format_time(_elapsed_seconds())
	if _dragged_piece and not _dragged_piece.locked:
		_dragged_piece.position = _dragged_piece.position.lerp(_drag_target, minf(1.0, delta * 24.0))


func _input(event: InputEvent) -> void:
	if _completed:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_drag(event.position)
		else:
			_end_drag()
	elif event is InputEventMouseMotion and _dragged_piece:
		_drag_target = event.position - _drag_offset
		get_viewport().set_input_as_handled()


func start_new_puzzle(value_grid_size: int) -> void:
	grid_size = clampi(value_grid_size, 3, 5)
	_completed = false
	moves = 0
	errors = 0
	placed_count = 0
	first_correct_count = 0
	_dragged_piece = null
	start_msec = Time.get_ticks_msec()
	if completion_overlay:
		completion_overlay.queue_free()
		completion_overlay = null
	for piece in pieces:
		if is_instance_valid(piece):
			piece.free()
	pieces.clear()
	_update_board_geometry()
	_generate_edge_map()
	_generate_pieces()
	_scatter_pieces()
	_update_stats()
	feedback_label.text = "拖动任意拼图块开始。靠近正确位置时会自动吸附。"
	preview.texture = puzzle_texture
	preview.position = board_rect.position
	preview.size = board_rect.size
	preview.modulate = Color(1.0, 1.0, 1.0, 0.15)
	preview.visible = true
	if scaffold_controller:
		scaffold_controller.begin_run()
		scaffold_controller.notify_basic_operation({"kind": "jigsaw_started", "grid_size": grid_size})
		scaffold_controller.mark_safe_window()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color("071428")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var glow := ColorRect.new()
	glow.position = Vector2(360, 108)
	glow.size = Vector2(560, 480)
	glow.color = Color(0.08, 0.55, 0.68, 0.08)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)

	var header := PanelContainer.new()
	header.position = Vector2(24, 18)
	header.size = Vector2(1232, 112)
	header.add_theme_stylebox_override("panel", _style(Color("102745"), 18))
	add_child(header)
	var header_box := VBoxContainer.new()
	header_box.add_theme_constant_override("separation", 8)
	header.add_child(header_box)
	var top_line := HBoxContainer.new()
	header_box.add_child(top_line)
	var title := Label.new()
	title.text = "数字策略 · 图片拼图"
	title.add_theme_font_size_override("font_size", 27)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_line.add_child(title)
	for size_value in [3, 4, 5]:
		var button := Button.new()
		button.name = "Difficulty%d" % size_value
		button.text = "%d × %d" % [size_value, size_value]
		button.custom_minimum_size = Vector2(86, 40)
		button.pressed.connect(start_new_puzzle.bind(size_value))
		top_line.add_child(button)
	timer_label = Label.new()
	timer_label.custom_minimum_size.x = 132
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	timer_label.add_theme_font_size_override("font_size", 20)
	top_line.add_child(timer_label)
	var bottom_line := HBoxContainer.new()
	header_box.add_child(bottom_line)
	feedback_label = Label.new()
	feedback_label.text = "拖动拼图块，靠近正确位置后自动吸附。"
	feedback_label.add_theme_color_override("font_color", Color("b7d9ea"))
	feedback_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_line.add_child(feedback_label)
	stats_label = Label.new()
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stats_label.add_theme_font_size_override("font_size", 18)
	bottom_line.add_child(stats_label)

	task_container = Control.new()
	task_container.name = "JigsawWorkspace"
	task_container.position = Vector2.ZERO
	task_container.size = Vector2(1280, 720)
	task_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(task_container)

	var board_panel := Panel.new()
	board_panel.name = "PuzzleBoard"
	board_panel.position = Vector2(383, 153)
	board_panel.size = Vector2(514, 356)
	board_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_panel.add_theme_stylebox_override("panel", _style(Color("0d2039"), 16, Color("4c8ca9")))
	task_container.add_child(board_panel)

	preview = TextureRect.new()
	preview.name = "ImagePreview"
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_SCALE
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	task_container.add_child(preview)

	pieces_layer = Node2D.new()
	pieces_layer.name = "PiecesLayer"
	task_container.add_child(pieces_layer)

	_snap_player = AudioStreamPlayer.new()
	_snap_player.stream = SNAP_SOUND
	_snap_player.volume_db = -7.0
	add_child(_snap_player)


func _setup_ai() -> void:
	assistant_panel = AI_PANEL_SCRIPT.new() as AiAssistantPanel
	add_child(assistant_panel)
	assistant_panel.configure("level_2_puzzle", _ai_state)
	scaffold_controller = SCAFFOLD_SCRIPT.new() as ScaffoldController
	add_child(scaffold_controller)
	scaffold_controller.configure(
		"level_2_puzzle",
		"image_jigsaw_task",
		"观察图像线索，尝试不同组合并完成整张图片",
		_ai_state,
		func() -> bool: return true,
		assistant_panel
	)


func _update_board_geometry() -> void:
	var texture_size := Vector2(3.0, 2.0)
	if puzzle_texture:
		texture_size = puzzle_texture.get_size()
	var max_size := Vector2(500.0, 340.0)
	var aspect := texture_size.x / maxf(1.0, texture_size.y)
	var board_size := Vector2(max_size.x, max_size.x / aspect)
	if board_size.y > max_size.y:
		board_size = Vector2(max_size.y * aspect, max_size.y)
	board_rect = Rect2(Vector2(640.0, 340.0) - board_size * 0.5, board_size)
	cell_size = board_size / float(grid_size)


func _generate_edge_map() -> void:
	_horizontal_edges.clear()
	_vertical_edges.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 73013 + grid_size * 997
	for row in range(grid_size - 1):
		var row_edges: Array[int] = []
		for column in range(grid_size):
			row_edges.append(1 if rng.randi_range(0, 1) == 1 else -1)
		_horizontal_edges.append(row_edges)
	for row in range(grid_size):
		var column_edges: Array[int] = []
		for column in range(grid_size - 1):
			column_edges.append(1 if rng.randi_range(0, 1) == 1 else -1)
		_vertical_edges.append(column_edges)


func _generate_pieces() -> void:
	if puzzle_texture == null:
		push_error("Jigsaw puzzle requires a source image texture.")
		return
	var source_scale := puzzle_texture.get_size() / board_rect.size
	for row in range(grid_size):
		for column in range(grid_size):
			var top_sign := 0 if row == 0 else -int(_horizontal_edges[row - 1][column])
			var right_sign := 0 if column == grid_size - 1 else int(_vertical_edges[row][column])
			var bottom_sign := 0 if row == grid_size - 1 else int(_horizontal_edges[row][column])
			var left_sign := 0 if column == 0 else -int(_vertical_edges[row][column - 1])
			var polygon := _piece_polygon(top_sign, right_sign, bottom_sign, left_sign)
			var uv_points := PackedVector2Array()
			var source_origin := Vector2(column * cell_size.x, row * cell_size.y) * source_scale
			for point in polygon:
				uv_points.append(source_origin + point * source_scale)
			var target := board_rect.position + Vector2(column * cell_size.x, row * cell_size.y)
			var piece := PIECE_SCRIPT.new() as JigsawPiece
			piece.name = "Piece_%02d_%02d" % [row, column]
			piece.setup(row * grid_size + column, row, column, target, polygon, uv_points, puzzle_texture)
			pieces_layer.add_child(piece)
			pieces.append(piece)


func _piece_polygon(top_sign: int, right_sign: int, bottom_sign: int, left_sign: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	_append_edge(result, Vector2.ZERO, Vector2(cell_size.x, 0), Vector2(0, -1), top_sign, false)
	_append_edge(result, Vector2(cell_size.x, 0), cell_size, Vector2(1, 0), right_sign, true)
	_append_edge(result, cell_size, Vector2(0, cell_size.y), Vector2(0, 1), bottom_sign, true)
	_append_edge(result, Vector2(0, cell_size.y), Vector2.ZERO, Vector2(-1, 0), left_sign, true)
	return result


func _append_edge(points: PackedVector2Array, start: Vector2, finish: Vector2, outward: Vector2, sign_value: int, skip_first: bool) -> void:
	var begin_index := 1 if skip_first else 0
	if sign_value == 0:
		for index in range(begin_index, 2):
			points.append(start.lerp(finish, float(index)))
		return
	var profile_t := [0.0, 0.29, 0.34, 0.37, 0.40, 0.45, 0.50, 0.55, 0.60, 0.63, 0.66, 0.71, 1.0]
	var profile_h := [0.0, 0.0, 0.08, 0.26, 0.39, 0.47, 0.50, 0.47, 0.39, 0.26, 0.08, 0.0, 0.0]
	var depth := minf(cell_size.x, cell_size.y) * 0.25
	for index in range(begin_index, profile_t.size()):
		var base := start.lerp(finish, float(profile_t[index]))
		points.append(base + outward * depth * float(profile_h[index]) * float(sign_value))


func _scatter_pieces() -> void:
	var candidates: Array[Vector2] = []
	var margin := minf(cell_size.x, cell_size.y) * 0.28
	var footprint := cell_size + Vector2.ONE * margin * 2.0
	var left_xs := [36.0 + margin, 36.0 + footprint.x + margin]
	var right_xs := [932.0 + margin, 932.0 + footprint.x + margin]
	var y_step := maxf(70.0, footprint.y * 0.9)
	var y := 160.0 + margin
	while y + cell_size.y < 690.0:
		for x in left_xs:
			if x + cell_size.x < 360.0:
				candidates.append(Vector2(x, y))
		for x in right_xs:
			if x + cell_size.x < 1260.0:
				candidates.append(Vector2(x, y))
		y += y_step
	var bottom_y := minf(675.0 - cell_size.y, board_rect.end.y + 34.0 + margin)
	var bottom_step := maxf(cell_size.x * 0.92, 86.0)
	var bottom_x := 44.0 + margin
	while bottom_x + cell_size.x < 1230.0:
		candidates.append(Vector2(bottom_x, bottom_y))
		bottom_x += bottom_step
	var rng := RandomNumberGenerator.new()
	rng.seed = 99173 + grid_size * 811
	_shuffle_positions(candidates, rng)
	for index in range(pieces.size()):
		var piece := pieces[index]
		var position_value := candidates[index % candidates.size()]
		position_value += Vector2(rng.randf_range(-5.0, 5.0), rng.randf_range(-5.0, 5.0))
		piece.position = position_value
		piece.rotation = deg_to_rad(rng.randf_range(-3.0, 3.0))
		piece.z_index = index + 2


func _shuffle_positions(values: Array[Vector2], rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var temp := values[index]
		values[index] = values[other]
		values[other] = temp


func _begin_drag(mouse_position: Vector2) -> void:
	for index in range(pieces.size() - 1, -1, -1):
		var piece := pieces[index]
		if piece.contains_global_point(mouse_position):
			_dragged_piece = piece
			_drag_offset = mouse_position - piece.position
			_drag_target = piece.position
			_z_counter += 1
			piece.z_index = _z_counter
			piece.rotation = 0.0
			piece.set_dragging(true)
			pieces.erase(piece)
			pieces.append(piece)
			scaffold_controller.notify_activity({"piece_id": piece.piece_id})
			get_viewport().set_input_as_handled()
			return


func _end_drag() -> void:
	if _dragged_piece == null:
		return
	var piece := _dragged_piece
	_dragged_piece = null
	# Smooth following may still be a few pixels behind on a fast release. The
	# player's actual release point is authoritative for snapping.
	piece.position = _drag_target
	piece.set_dragging(false)
	moves += 1
	piece.attempts += 1
	var correct := piece.position.distance_to(piece.target_position) <= snap_distance
	if not piece.first_drop_recorded:
		piece.first_drop_recorded = true
		piece.first_drop_correct = correct
		if correct:
			first_correct_count += 1
	var task_id := "jigsaw_piece_%02d" % (piece.piece_id + 1)
	_record("puzzle_piece_placed", _measurement(piece, task_id, correct))
	if correct:
		piece.snap_to_target()
		placed_count += 1
		_snap_player.pitch_scale = 0.96 + float(placed_count % 5) * 0.025
		_snap_player.play()
		feedback_label.text = "吸附成功！这块已经锁定。"
		feedback_label.add_theme_color_override("font_color", Color("75efaa"))
		scaffold_controller.notify_progress({"piece_id": piece.piece_id, "placed": placed_count, "total": pieces.size()})
	else:
		errors += 1
		feedback_label.text = "还没有对齐，继续观察图像边缘和凹凸轮廓。"
		feedback_label.add_theme_color_override("font_color", Color("ffb47d"))
		scaffold_controller.notify_failure("repeated_failure", {"piece_id": piece.piece_id, "distance": piece.position.distance_to(piece.target_position)})
	_update_stats()
	if placed_count == pieces.size():
		_finish_puzzle()


func _finish_puzzle() -> void:
	if _completed:
		return
	_completed = true
	var elapsed := _elapsed_seconds()
	var total := maxi(1, pieces.size())
	var accuracy_ratio := float(first_correct_count) / float(total)
	var target_seconds: float = float({3: 150.0, 4: 300.0, 5: 480.0}.get(grid_size, 300.0))
	var time_ratio := clampf(1.0 - maxf(0.0, elapsed - target_seconds * 0.55) / (target_seconds * 0.45), 0.0, 1.0)
	var raw_score := 14.0 + accuracy_ratio * 4.0 + time_ratio * 2.0
	var percent := raw_score / 20.0 * 100.0
	DigCompSession.record_specialist_score("level_2_puzzle", {"area_5": percent}, {
		"grid_size": grid_size,
		"piece_count": total,
		"moves": moves,
		"errors": errors,
		"first_placement_correct": first_correct_count,
		"elapsed_seconds": elapsed,
		"base_points": 14.0,
		"accuracy_points": accuracy_ratio * 4.0,
		"time_points": time_ratio * 2.0,
	})
	scaffold_controller.end_run()
	preview.modulate = Color.WHITE
	for piece in pieces:
		piece.visible = false
	_show_completion(percent, elapsed)
	_record("digcomp_response_submitted", {
		"task_id": "image_jigsaw_complete",
		"task_type": "image_jigsaw",
		"digcomp_version": "3.0",
		"area_id": "area_5",
		"correct": true,
		"points_awarded": percent,
		"response_time_msec": int(elapsed * 1000.0),
		"attempt_count": moves,
	})


func _show_completion(percent: float, elapsed: float) -> void:
	completion_overlay = Control.new()
	completion_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(completion_overlay)
	var veil := ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.02, 0.07, 0.14, 0.78)
	completion_overlay.add_child(veil)
	var card := PanelContainer.new()
	card.position = Vector2(365, 205)
	card.size = Vector2(550, 310)
	card.pivot_offset = card.size * 0.5
	card.scale = Vector2(0.82, 0.82)
	card.modulate.a = 0.0
	card.add_theme_stylebox_override("panel", _style(Color("133d47"), 22, Color("70efbe")))
	completion_overlay.add_child(card)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 15)
	card.add_child(box)
	var title := Label.new()
	title.text = "拼图完成！"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color("7af0bd"))
	box.add_child(title)
	var result := Label.new()
	result.text = "%d 块全部归位\n用时 %s　移动 %d 次　未对齐 %d 次\n专项能力得分 %.1f / 100" % [pieces.size(), _format_time(elapsed), moves, errors, percent]
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result.add_theme_font_size_override("font_size", 20)
	box.add_child(result)
	var button := Button.new()
	button.text = "返回能力大厅"
	button.custom_minimum_size = Vector2(250, 58)
	button.pressed.connect(_return_to_hub)
	box.add_child(button)
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "scale", Vector2.ONE, 0.42)
	tween.tween_property(card, "modulate:a", 1.0, 0.28)


func _return_to_hub() -> void:
	DigCompSession.complete_top_level("level_2_puzzle", {
		"success": true,
		"task_type": "image_jigsaw",
		"grid_size": grid_size,
		"piece_count": pieces.size(),
		"elapsed_seconds": _elapsed_seconds(),
		"moves": moves,
		"errors": errors,
		"first_placement_correct": first_correct_count,
	})


func _measurement(piece: JigsawPiece, task_id: String, correct: bool) -> Dictionary:
	return {
		"task_id": task_id,
		"task_type": "image_jigsaw",
		"digcomp_version": "3.0",
		"area_id": "area_5",
		"competence_id": "problem_solving",
		"learning_outcome_id": "area_5_spatial_strategy",
		"first_response": piece.attempts == 1,
		"correct": correct,
		"points_awarded": 1 if piece.attempts == 1 and correct else 0,
		"response_time_msec": Time.get_ticks_msec() - start_msec,
		"attempt_count": piece.attempts,
		"ai_used_before_response": _hint_count() > 0,
		"support_trigger": "",
		"hint_level": mini(_hint_count(), 3),
		"scaffold_id": "",
		"piece_id": piece.piece_id,
		"row": piece.row,
		"column": piece.column,
		"distance_to_target": snappedf(piece.position.distance_to(piece.target_position), 0.01),
	}


func _ai_state() -> Dictionary:
	return {
		"current_area": "数字策略图片拼图",
		"current_checkpoint": "%d/%d 块已归位" % [placed_count, pieces.size()],
		"placed_pieces": placed_count,
		"total_pieces": pieces.size(),
		"moves": moves,
		"errors": errors,
	}


func _update_stats() -> void:
	stats_label.text = "已完成 %d / %d　移动 %d　未对齐 %d" % [placed_count, pieces.size(), moves, errors]


func _elapsed_seconds() -> float:
	return maxf(0.0, float(Time.get_ticks_msec() - start_msec) / 1000.0)


func _format_time(seconds: float) -> String:
	var total := int(floor(seconds))
	return "%02d:%02d" % [total / 60, total % 60]


func _hint_count() -> int:
	var service := get_node_or_null("/root/AiAssistantService")
	if service and service.has_method("get_previous_hints"):
		return Array(service.call("get_previous_hints", "level_2_puzzle")).size()
	return 0


func _record(event_name: String, payload: Dictionary) -> void:
	EVENT_BRIDGE.record(self, event_name, "level_2_puzzle", payload)


func _style(color: Color, radius: int, border_color: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	if border_color.a > 0.0:
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.border_color = border_color
	return style
