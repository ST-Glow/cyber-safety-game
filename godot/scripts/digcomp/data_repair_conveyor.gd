class_name DataRepairConveyor
extends Control

const EVENT_BRIDGE := preload("res://scripts/experiment_event_bridge.gd")
const AI_PANEL_SCRIPT := preload("res://scripts/ui/ai_assistant_panel.gd")
const SCAFFOLD_SCRIPT := preload("res://scripts/scaffolding/scaffold_controller.gd")
const PAIR_DATA := preload("res://scripts/digcomp/data_repair_pairs.gd")
const PROBLEM_CARD_SCENE := preload("res://scenes/digcomp/data_repair_problem_card.tscn")
const SOLUTION_CARD_SCENE := preload("res://scenes/digcomp/data_repair_solution_card.tscn")
const BELT_SCRIPT := preload("res://scripts/digcomp/data_repair_conveyor_belt.gd")
const EVIDENCE_SCRIPT := preload("res://scripts/digcomp/evidence_progress.gd")
const FACTORY_BACKDROP_SCRIPT := preload("res://scripts/digcomp/data_repair_factory_backdrop.gd")
const TOOL_DOCK_SCRIPT := preload("res://scripts/digcomp/data_repair_tool_dock.gd")
const ICON_SCRIPT := preload("res://scripts/digcomp/data_repair_icon.gd")
const UI_FONT: FontFile = preload("res://assets/ui/fonts/noto_sans_sc_ui_600.ttf")
const SUCCESS_SOUND: AudioStream = preload("res://assets/audio/interface_sfx_pack_1/confirm_tones/style6/confirm_style_6_001.ogg")
const ERROR_SOUND: AudioStream = preload("res://assets/audio/interface_sfx_pack_1/error_tones/style2/error_style_2_002.ogg")

@export_range(20.0, 180.0, 1.0) var total_time_seconds: float = 90.0
@export_range(1, 9, 1) var starting_energy: int = 3
@export_range(20.0, 140.0, 1.0) var base_conveyor_speed: float = 30.0
@export_range(0.5, 8.0, 0.1) var spawn_interval_seconds: float = 2.6
@export_range(1, 3, 1) var max_active_problems: int = 3
@export_range(2, 4, 1) var solution_slots: int = 4
@export_range(0.0, 5.0, 0.1) var guide_duration_seconds: float = 2.6

var belt: DataRepairConveyorBelt
var factory_backdrop: Control
var tool_dock: Control
var problem_layer: Control
var solution_layer: Control
var task_container: Control
var evidence_progress: EvidenceProgress
var score_label: Label
var timer_label: Label
var energy_label: Label
var combo_label: Label
var round_label: Label
var feedback_label: Label
var stage_banner: Label
var countdown_label: Label
var freeze_button: Button
var assistant_panel: AiAssistantPanel
var scaffold_controller: ScaffoldController
var success_audio: AudioStreamPlayer
var error_audio: AudioStreamPlayer
var guide_overlay: Control
var result_overlay: Control
var guide_tween: Tween

var pair_items: Array[Dictionary] = []
var pending_queue: Array[String] = []
var active_problems: Array[DataRepairProblemCard] = []
var solution_cards: Array[DataRepairSolutionCard] = []
var completed_ids: Array[String] = []
var attempts: Dictionary = {}
var first_responses: Dictionary = {}
var domain_points := {"area_1": 0, "area_3": 0}
var gameplay_score: int = 0
var error_count: int = 0
var energy: int = 3
var combo: int = 0
var highest_combo: int = 0
var time_left: float = 90.0
var start_msec: int = 0
var spawn_clock: float = 0.0
var guide_active: bool = true
var running: bool = false
var run_finished: bool = false
var run_success: bool = false
var _dragged_solution: DataRepairSolutionCard
var _solution_refresh_pending: bool = false
var _repair_animations: int = 0
var _drag_line: Line2D
var _event_clock: float = 13.0
var _speed_boost_time: float = 0.0
var _freeze_time: float = 0.0
var _freeze_ready: bool = false
var _congestion_remaining: int = 0
var _congestion_clock: float = 0.0
var _last_countdown_second: int = -1
var _last_trail_msec: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var task_theme := Theme.new()
	task_theme.default_font = UI_FONT
	task_theme.default_font_size = 16
	theme = task_theme
	pair_items = PAIR_DATA.all_items()
	time_left = total_time_seconds
	energy = starting_energy
	_build_shell()
	_setup_ai()
	_prepare_queue()
	_show_quick_guide()
	_update_hud()
	_record("digcomp_task_presented", {"task_type": "data_repair_conveyor", "digcomp_version": "3.0", "pair_count": pair_items.size()})


func _process(delta: float) -> void:
	if not running or run_finished:
		return
	# Browser tabs can occasionally resume with a large frame delta. Cap gameplay
	# advancement so a brief Web stall cannot consume seconds or several lives.
	var safe_delta := minf(delta, 0.05)
	time_left = maxf(0.0, time_left - safe_delta)
	_speed_boost_time = maxf(0.0, _speed_boost_time - safe_delta)
	if _freeze_time > 0.0:
		_freeze_time = maxf(0.0, _freeze_time - safe_delta)
		belt.frozen = true
		belt.set_running(false)
		for frozen_problem in active_problems:
			if is_instance_valid(frozen_problem):
				frozen_problem.stop_motion()
		if _freeze_time <= 0.0:
			belt.frozen = false
			belt.set_running(true)
			for thawed_problem in active_problems:
				if is_instance_valid(thawed_problem):
					thawed_problem.start_motion()
	else:
		belt.frozen = false
	spawn_clock += safe_delta
	if spawn_clock >= spawn_interval_seconds and active_problems.size() < _phase_active_limit():
		spawn_clock = 0.0
		_spawn_problem()
	_event_clock -= safe_delta
	if _event_clock <= 0.0 and _current_round() >= 2:
		_trigger_factory_event()
	if _congestion_remaining > 0:
		_congestion_clock -= safe_delta
		if _congestion_clock <= 0.0 and active_problems.size() < _phase_active_limit():
			_congestion_remaining -= 1
			_congestion_clock = 0.42
			_spawn_problem()
	_update_final_countdown()
	_update_hud()
	if time_left <= 0.0:
		_finish_run(false, "修复时限已到")


func _build_shell() -> void:
	factory_backdrop = FACTORY_BACKDROP_SCRIPT.new() as Control
	factory_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(factory_backdrop)

	var title := Label.new()
	_anchor(title, 0.025, 0.018, 0.265, 0.085, 0, 0, 0, 0)
	title.text = "DATA REPAIR STATION"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("e5fbff"))
	title.add_theme_color_override("font_shadow_color", Color(0.1, 0.8, 0.9, 0.4))
	title.add_theme_constant_override("shadow_offset_x", 2)
	add_child(title)
	round_label = Label.new()
	_anchor(round_label, 0.027, 0.074, 0.25, 0.118, 0, 0, 0, 0)
	round_label.text = "PHASE 1 // 基础修复"
	round_label.add_theme_font_size_override("font_size", 14)
	round_label.add_theme_color_override("font_color", Color("68e5d1"))
	add_child(round_label)

	evidence_progress = EVIDENCE_SCRIPT.new() as EvidenceProgress
	_anchor(evidence_progress, 0.30, 0.020, 0.67, 0.103, 0, 0, 0, 0)
	add_child(evidence_progress)
	var evidence_tag := Label.new()
	_anchor(evidence_tag, 0.235, 0.040, 0.305, 0.080, 0, 0, 0, 0)
	evidence_tag.text = "证据节点"
	evidence_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	evidence_tag.add_theme_font_size_override("font_size", 13)
	evidence_tag.add_theme_color_override("font_color", Color("6eead3"))
	add_child(evidence_tag)

	score_label = _hud_label("SCORE 000")
	timer_label = _hud_label("TIME 01:30")
	energy_label = _hud_label("LIFE 3")
	combo_label = _hud_label("COMBO x1")
	var hud_labels: Array[Label] = [score_label, timer_label, energy_label, combo_label]
	for index in range(hud_labels.size()):
		_anchor(hud_labels[index], 0.675 + index * 0.079, 0.026, 0.748 + index * 0.079, 0.087, 0, 0, 0, 0)
		add_child(hud_labels[index])

	belt = BELT_SCRIPT.new() as DataRepairConveyorBelt
	_anchor(belt, 0.018, 0.115, 0.985, 0.755, 0, 0, 0, 0)
	add_child(belt)
	problem_layer = Control.new()
	problem_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	problem_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	problem_layer.clip_contents = false
	problem_layer.z_index = 3
	belt.add_child(problem_layer)
	var furnace_label := Label.new()
	_anchor(furnace_label, 0.905, 0.34, 0.995, 0.66, 0, 0, 0, 0)
	furnace_label.text = "DANGER\n故障熔炉"
	furnace_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	furnace_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	furnace_label.add_theme_font_size_override("font_size", 16)
	furnace_label.add_theme_color_override("font_color", Color("ff6f82"))
	furnace_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	furnace_label.z_index = 8
	belt.add_child(furnace_label)
	var scanner_label := Label.new()
	_anchor(scanner_label, 0.695, 0.015, 0.79, 0.09, 0, 0, 0, 0)
	scanner_label.text = "REPAIR SCANNER"
	scanner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scanner_label.add_theme_font_size_override("font_size", 11)
	scanner_label.add_theme_color_override("font_color", Color("6fe8d4"))
	scanner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scanner_label.z_index = 8
	belt.add_child(scanner_label)

	tool_dock = TOOL_DOCK_SCRIPT.new() as Control
	_anchor(tool_dock, 0.17, 0.742, 0.985, 1.0, 0, 0, 0, 0)
	tool_dock.z_index = 7
	add_child(tool_dock)
	solution_layer = Control.new()
	_anchor(solution_layer, 0.015, 0.12, 0.985, 0.98, 0, 0, 0, 0)
	solution_layer.mouse_filter = Control.MOUSE_FILTER_PASS
	solution_layer.clip_contents = false
	tool_dock.add_child(solution_layer)
	task_container = solution_layer

	feedback_label = Label.new()
	_anchor(feedback_label, 0.30, 0.735, 0.86, 0.778, 0, 0, 0, 0)
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback_label.add_theme_font_size_override("font_size", 14)
	feedback_label.add_theme_color_override("font_color", Color("8ddcf0"))
	feedback_label.text = "从工具槽抓起修复芯片，拖入对应的数据核心"
	feedback_label.z_index = 12
	add_child(feedback_label)

	freeze_button = Button.new()
	_anchor(freeze_button, 0.025, 0.715, 0.155, 0.790, 0, 0, 0, 0)
	freeze_button.text = "FREEZE 3s"
	freeze_button.visible = false
	freeze_button.add_theme_font_size_override("font_size", 16)
	freeze_button.add_theme_stylebox_override("normal", _style(Color("123955"), Color("6de7ff"), 2, 9))
	freeze_button.add_theme_stylebox_override("hover", _style(Color("185b73"), Color("b9f8ff"), 3, 9))
	freeze_button.pressed.connect(_activate_freeze)
	freeze_button.z_index = 15
	add_child(freeze_button)

	stage_banner = Label.new()
	_anchor(stage_banner, 0.30, 0.19, 0.70, 0.30, 0, 0, 0, 0)
	stage_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stage_banner.add_theme_font_size_override("font_size", 31)
	stage_banner.add_theme_color_override("font_color", Color("77f3d7"))
	stage_banner.modulate.a = 0.0
	stage_banner.z_index = 22
	add_child(stage_banner)
	countdown_label = Label.new()
	_anchor(countdown_label, 0.39, 0.29, 0.61, 0.62, 0, 0, 0, 0)
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	countdown_label.add_theme_font_size_override("font_size", 112)
	countdown_label.add_theme_color_override("font_color", Color("ff536c"))
	countdown_label.add_theme_color_override("font_shadow_color", Color(1.0, 0.05, 0.12, 0.55))
	countdown_label.modulate.a = 0.0
	countdown_label.z_index = 30
	add_child(countdown_label)

	success_audio = AudioStreamPlayer.new()
	success_audio.stream = SUCCESS_SOUND
	success_audio.volume_db = -6.0
	add_child(success_audio)
	error_audio = AudioStreamPlayer.new()
	error_audio.stream = ERROR_SOUND
	error_audio.volume_db = -8.0
	add_child(error_audio)


func _setup_ai() -> void:
	assistant_panel = AI_PANEL_SCRIPT.new() as AiAssistantPanel
	add_child(assistant_panel)
	assistant_panel.configure("level_3_matching", _ai_state)
	scaffold_controller = SCAFFOLD_SCRIPT.new() as ScaffoldController
	add_child(scaffold_controller)
	scaffold_controller.configure("level_3_matching", "data_repair_conveyor", "比较信息管理和内容创作策略，及时修复移动中的数据问题", _ai_state, func() -> bool: return running, assistant_panel)
	scaffold_controller.begin_run()
	scaffold_controller.notify_basic_operation({"kind": "task_opened"})
	scaffold_controller.mark_safe_window()


func _prepare_queue() -> void:
	pending_queue.clear()
	for item in pair_items:
		pending_queue.append(String(item.get("id", "")))
	pending_queue.shuffle()


func _show_quick_guide() -> void:
	guide_active = true
	guide_overlay = Control.new()
	guide_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	guide_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	guide_overlay.z_index = 70
	add_child(guide_overlay)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.01, 0.04, 0.09, 0.72)
	guide_overlay.add_child(shade)
	var title := Label.new()
	_anchor(title, 0.20, 0.25, 0.80, 0.36, 0, 0, 0, 0)
	title.text = "抓起修复芯片  →  接入故障数据核心"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("dffff9"))
	guide_overlay.add_child(title)
	var subtitle := Label.new()
	_anchor(subtitle, 0.28, 0.63, 0.72, 0.70, 0, 0, 0, 0)
	subtitle.text = "绿色磁吸 = 可以修复    ·    完整说明可悬停查看"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color("82c8dc"))
	guide_overlay.add_child(subtitle)
	var tool_icon: Control = ICON_SCRIPT.new() as Control
	tool_icon.call("configure", "cross_check", Color("65ead0"))
	tool_icon.position = Vector2(size.x * 0.32, size.y * 0.40)
	tool_icon.size = Vector2(112.0, 112.0)
	guide_overlay.add_child(tool_icon)
	var fault_icon: Control = ICON_SCRIPT.new() as Control
	fault_icon.call("configure", "conflict_docs", Color("ff667d"))
	fault_icon.position = Vector2(size.x * 0.60, size.y * 0.40)
	fault_icon.size = Vector2(112.0, 112.0)
	guide_overlay.add_child(fault_icon)
	var link := Line2D.new()
	link.points = PackedVector2Array([tool_icon.position + tool_icon.size * 0.5, fault_icon.position + fault_icon.size * 0.5])
	link.width = 5.0
	link.default_color = Color(0.38, 0.94, 0.82, 0.65)
	guide_overlay.add_child(link)
	guide_tween = create_tween().set_loops()
	var start_x: float = tool_icon.position.x
	guide_tween.tween_property(tool_icon, "position:x", start_x + 52.0, 0.65).set_trans(Tween.TRANS_SINE)
	guide_tween.tween_property(tool_icon, "position:x", start_x, 0.65).set_trans(Tween.TRANS_SINE)
	get_tree().create_timer(guide_duration_seconds).timeout.connect(_finish_guide)


func _finish_guide() -> void:
	if not guide_active:
		return
	guide_active = false
	if guide_tween:
		guide_tween.kill()
	if guide_overlay:
		guide_overlay.queue_free()
	_begin_game()


func _begin_game() -> void:
	start_msec = Time.get_ticks_msec()
	running = true
	belt.set_running(true)
	_show_stage_banner("PHASE 1\n基础修复")
	spawn_clock = 0.0
	_spawn_problem()


func _spawn_problem() -> void:
	if not running or run_finished or active_problems.size() >= _phase_active_limit() or pending_queue.is_empty():
		return
	var item_id: String = pending_queue.pop_front()
	if completed_ids.has(item_id):
		_spawn_problem()
		return
	var item: Dictionary = PAIR_DATA.item_by_id(item_id)
	if item.is_empty():
		return
	var lane := _next_free_lane()
	var card := PROBLEM_CARD_SCENE.instantiate() as DataRepairProblemCard
	problem_layer.add_child(card)
	var deadline := maxf(640.0, belt.size.x - 112.0 - card.size.x * 0.70)
	card.configure(item, lane, _current_conveyor_speed(), deadline)
	card.position = Vector2(56.0, 78.0 + float(lane) * 116.0)
	card.reached_fault_zone.connect(_on_problem_expired)
	card.start_motion()
	active_problems.append(card)
	_record("data_repair_problem_spawned", {"task_id": item_id, "round": _current_round(), "queue_remaining": pending_queue.size()})
	_request_solution_refresh()


func _next_free_lane() -> int:
	for lane in range(max_active_problems):
		var occupied := false
		for card in active_problems:
			if is_instance_valid(card) and card.lane_index == lane:
				occupied = true
				break
		if not occupied:
			return lane
	return active_problems.size() % max_active_problems


func _phase_active_limit() -> int:
	return mini(max_active_problems, 2 if _current_round() == 1 else 3)


func _request_solution_refresh() -> void:
	if _dragged_solution != null or _repair_animations > 0:
		_solution_refresh_pending = true
		return
	_refresh_solution_cards()


func _refresh_solution_cards() -> void:
	_solution_refresh_pending = false
	for card in solution_cards:
		if is_instance_valid(card):
			card.queue_free()
	solution_cards.clear()
	var desired: Array[String] = []
	for problem in active_problems:
		if is_instance_valid(problem) and not desired.has(problem.item_id):
			desired.append(problem.item_id)
	var fillers: Array[String] = []
	for item in pair_items:
		var item_id := String(item.get("id", ""))
		if not completed_ids.has(item_id) and not desired.has(item_id):
			fillers.append(item_id)
	fillers.shuffle()
	var reserve_for_decoy := 1 if _current_round() >= 3 else 0
	while desired.size() < solution_slots - reserve_for_decoy and not fillers.is_empty():
		desired.append(fillers.pop_front())
	if _current_round() >= 3 and desired.size() < solution_slots:
		var decoy_source: Dictionary = pair_items.pick_random()
		desired.append("decoy:%s" % String(decoy_source.get("id", "")))
	while desired.size() < solution_slots and not fillers.is_empty():
		desired.append(fillers.pop_front())
	desired.shuffle()
	for card_id in desired:
		var decoy := card_id.begins_with("decoy:")
		var source_id := card_id.trim_prefix("decoy:") if decoy else card_id
		var item: Dictionary = PAIR_DATA.item_by_id(source_id)
		var card := SOLUTION_CARD_SCENE.instantiate() as DataRepairSolutionCard
		solution_layer.add_child(card)
		card.configure(card_id, item, decoy)
		card.drag_started.connect(_on_solution_drag_started)
		card.drag_moved.connect(_on_solution_drag_moved)
		card.drag_released.connect(_on_solution_drag_released)
		solution_cards.append(card)
	call_deferred("_layout_solution_cards")


func _layout_solution_cards() -> void:
	if solution_cards.is_empty() or not is_instance_valid(solution_layer):
		return
	var width := solution_layer.size.x
	var card_width := 166.0
	var gap := 28.0
	var total_width := card_width * solution_cards.size() + gap * (solution_cards.size() - 1)
	var start_x := maxf(0.0, (width - total_width) * 0.5)
	for index in range(solution_cards.size()):
		var card: DataRepairSolutionCard = solution_cards[index]
		if is_instance_valid(card):
			card.set_home_position(Vector2(start_x + float(index) * (card_width + gap), 4.0), false)


func _on_solution_drag_started(card: DataRepairSolutionCard) -> void:
	_dragged_solution = card
	feedback_label.text = "扫描中：把芯片接入相符的数据核心"
	_drag_line = Line2D.new()
	_drag_line.width = 3.0
	_drag_line.default_color = Color(0.38, 0.94, 0.82, 0.52)
	_drag_line.z_index = 85
	_drag_line.points = PackedVector2Array([card.global_position + card.size * 0.5, get_global_mouse_position()])
	add_child(_drag_line)


func _on_solution_drag_moved(card: DataRepairSolutionCard, pointer_global: Vector2) -> void:
	if is_instance_valid(_drag_line):
		_drag_line.points = PackedVector2Array([card._home_position + tool_dock.global_position + solution_layer.position + card.size * 0.5, pointer_global])
	if Time.get_ticks_msec() - _last_trail_msec > 45:
		_last_trail_msec = Time.get_ticks_msec()
		_spawn_trail_dot(pointer_global, card.accent)
	for problem in active_problems:
		if not is_instance_valid(problem):
			continue
		var near := card.solution_id == problem.item_id and problem.get_global_rect().grow(34.0).has_point(pointer_global)
		problem.set_snap_hint(near)


func _on_solution_drag_released(card: DataRepairSolutionCard, pointer_global: Vector2) -> void:
	_dragged_solution = null
	if is_instance_valid(_drag_line):
		var line_tween := create_tween()
		line_tween.tween_property(_drag_line, "modulate:a", 0.0, 0.12)
		line_tween.tween_callback(_drag_line.queue_free)
	_drag_line = null
	var target: DataRepairProblemCard = _problem_at_pointer(pointer_global, card.solution_id)
	for problem in active_problems:
		if is_instance_valid(problem):
			problem.set_snap_hint(false)
	if target == null:
		card.return_home()
		feedback_label.text = "继续观察移动中的故障模块"
		_flush_solution_refresh()
		return
	_attempt_match(target, card)


func _problem_at_pointer(pointer_global: Vector2, solution_id: String) -> DataRepairProblemCard:
	for problem in active_problems:
		if is_instance_valid(problem) and problem.item_id == solution_id and problem.get_global_rect().grow(34.0).has_point(pointer_global):
			return problem
	for problem in active_problems:
		if is_instance_valid(problem) and problem.get_global_rect().grow(10.0).has_point(pointer_global):
			return problem
	return null


func _attempt_match(problem: DataRepairProblemCard, solution: DataRepairSolutionCard) -> void:
	if run_finished or not active_problems.has(problem):
		solution.return_home()
		return
	var item: Dictionary = problem.item
	var task_id := problem.item_id
	var area_id := String(item.get("area_id", ""))
	attempts[task_id] = int(attempts.get(task_id, 0)) + 1
	var correct := solution.solution_id == task_id
	if not first_responses.has(task_id):
		first_responses[task_id] = correct
	if correct:
		var previous_round := _current_round()
		combo += 1
		highest_combo = maxi(highest_combo, combo)
		var points := 10 * _combo_multiplier(combo)
		gameplay_score += points
		domain_points[area_id] = mini(50, int(domain_points.get(area_id, 0)) + 10)
		completed_ids.append(task_id)
		if _current_round() != previous_round:
			_apply_round_speed()
		if combo >= 3 and not _freeze_ready:
			_freeze_ready = true
			freeze_button.visible = true
			_show_stage_banner("FREEZE READY\n紧急冻结已充能")
		active_problems.erase(problem)
		problem.stop_motion()
		problem.play_repair_feedback()
		solution.stop_dragging()
		feedback_label.text = "修复成功 +%d · 证据链已连接" % points
		feedback_label.add_theme_color_override("font_color", Color("75efd1"))
		success_audio.play()
		scaffold_controller.notify_progress({"pair_id": task_id, "combo": combo})
		_record_match(item, solution.solution_id, true, points)
		_spawn_floating_text("+%d" % points, problem.global_position + problem.size * 0.5, Color("72f1d1"), 34)
		if _combo_multiplier(combo) > 1:
			_show_combo_burst(_combo_multiplier(combo))
		_animate_correct_match(problem, solution)
	else:
		gameplay_score = maxi(0, gameplay_score - 5)
		domain_points[area_id] = maxi(0, int(domain_points.get(area_id, 0)) - 5)
		error_count += 1
		combo = 0
		problem.play_fault_feedback()
		solution.play_wrong_bounce()
		feedback_label.text = String(item.get("hint", "不匹配，请比较两张卡的依据。"))
		feedback_label.add_theme_color_override("font_color", Color("ff8798"))
		error_audio.play()
		scaffold_controller.notify_failure("repeated_failure", {"pair_id": task_id, "solution_id": solution.solution_id})
		_record_match(item, solution.solution_id, false, -5)
		_spawn_floating_text("-5", problem.global_position + problem.size * 0.5, Color("ff526d"), 34)
		_shake_factory()
		_flush_solution_refresh()
	_update_hud()


func _animate_correct_match(problem: DataRepairProblemCard, solution: DataRepairSolutionCard) -> void:
	_repair_animations += 1
	var from := solution.global_position + solution.size * 0.5
	var to := problem.global_position + problem.size * 0.5
	var line := Line2D.new()
	line.width = 5.0
	line.default_color = Color("65f2d1")
	line.points = PackedVector2Array([from, to])
	line.z_index = 90
	add_child(line)
	var scan_beam := ColorRect.new()
	scan_beam.color = Color(0.45, 1.0, 0.87, 0.68)
	scan_beam.position = problem.global_position + Vector2(-14.0, -9.0)
	scan_beam.size = Vector2(7.0, problem.size.y + 18.0)
	scan_beam.z_index = 91
	scan_beam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scan_beam)
	var scan_tween := create_tween()
	scan_tween.tween_property(scan_beam, "position:x", problem.global_position.x + problem.size.x + 8.0, 0.30)
	scan_tween.parallel().tween_property(scan_beam, "modulate:a", 0.0, 0.30)
	scan_tween.tween_callback(scan_beam.queue_free)
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(solution, "global_position", problem.global_position + problem.size * 0.5 - solution.size * 0.5, 0.28)
	tween.tween_property(solution, "scale", Vector2(0.72, 0.72), 0.28)
	tween.tween_property(line, "modulate:a", 0.0, 0.28)
	tween.finished.connect(_mechanical_arm_lift.bind(problem, solution, line))


func _mechanical_arm_lift(problem: DataRepairProblemCard, solution: DataRepairSolutionCard, line: Line2D) -> void:
	if not is_instance_valid(problem) or not is_instance_valid(solution):
		_finalize_correct_match(problem, solution, line)
		return
	var claw := Line2D.new()
	var center := problem.global_position + problem.size * 0.5
	claw.points = PackedVector2Array([Vector2(center.x, belt.global_position.y + 32.0), Vector2(center.x, center.y - 22.0)])
	claw.width = 9.0
	claw.default_color = Color("6d98a9")
	claw.z_index = 89
	add_child(claw)
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(problem, "global_position:y", problem.global_position.y - 42.0, 0.22)
	tween.tween_property(solution, "global_position:y", solution.global_position.y - 42.0, 0.22)
	tween.tween_property(claw, "modulate:a", 0.0, 0.22)
	tween.finished.connect(func() -> void:
		claw.queue_free()
		_fly_repaired_card_to_evidence(problem, solution, line)
	)


func _fly_repaired_card_to_evidence(problem: DataRepairProblemCard, solution: DataRepairSolutionCard, line: Line2D) -> void:
	if not is_instance_valid(problem) or not is_instance_valid(solution):
		_finalize_correct_match(problem, solution, line)
		return
	var evidence_target := evidence_progress.global_position + Vector2(evidence_progress.size.x * 0.5, evidence_progress.size.y * 0.5)
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(problem, "global_position", evidence_target - problem.size * 0.5, 0.28)
	tween.tween_property(problem, "scale", Vector2(0.16, 0.16), 0.28)
	tween.tween_property(solution, "global_position", evidence_target - solution.size * 0.5, 0.28)
	tween.tween_property(solution, "scale", Vector2(0.10, 0.10), 0.28)
	tween.finished.connect(_finalize_correct_match.bind(problem, solution, line))


func _finalize_correct_match(problem: DataRepairProblemCard, solution: DataRepairSolutionCard, line: Line2D) -> void:
	if is_instance_valid(problem):
		_play_repair_particles(problem.global_position + problem.size * 0.5)
		problem.queue_free()
	if is_instance_valid(solution):
		solution.queue_free()
	if is_instance_valid(line):
		line.queue_free()
	evidence_progress.complete_next()
	_repair_animations = maxi(0, _repair_animations - 1)
	if completed_ids.size() >= pair_items.size():
		_finish_run(true, "十个数据模块全部修复")
	else:
		_spawn_problem()
		_request_solution_refresh()
	_flush_solution_refresh()


func _play_repair_particles(center: Vector2) -> void:
	for index in range(8):
		var dot := ColorRect.new()
		dot.color = Color("6ef2d3")
		dot.size = Vector2(7.0, 7.0)
		dot.position = center - dot.size * 0.5
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.z_index = 92
		add_child(dot)
		var angle := TAU * float(index) / 8.0
		var target := dot.position + Vector2.from_angle(angle) * 48.0
		var tween := create_tween().set_parallel(true)
		tween.tween_property(dot, "position", target, 0.38).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(dot, "modulate:a", 0.0, 0.38)
		tween.chain().tween_callback(dot.queue_free)


func _on_problem_expired(problem: DataRepairProblemCard) -> void:
	if run_finished or not active_problems.has(problem):
		return
	active_problems.erase(problem)
	pending_queue.append(problem.item_id)
	energy = maxi(0, energy - 1)
	combo = 0
	feedback_label.text = "模块进入故障区，损失 1 点能量；它会稍后重新出现"
	feedback_label.add_theme_color_override("font_color", Color("ff8798"))
	error_audio.play()
	_record("data_repair_problem_missed", {"task_id": problem.item_id, "energy_remaining": energy, "requeued": true})
	problem.play_fault_feedback()
	_spawn_floating_text("LIFE -1", problem.global_position + problem.size * 0.5, Color("ff4e68"), 29)
	_shake_factory()
	if factory_backdrop:
		factory_backdrop.set("alert_strength", 1.0)
	if belt:
		belt.alert_strength = 1.0
	var tween := create_tween()
	tween.tween_property(problem, "modulate:a", 0.0, 0.25)
	tween.tween_callback(problem.queue_free)
	_request_solution_refresh()
	_update_hud()
	if energy <= 0:
		_finish_run(false, "修复能量耗尽")
	else:
		_spawn_problem()


func _finish_run(success: bool, reason: String) -> void:
	if run_finished:
		return
	run_finished = true
	run_success = success
	running = false
	belt.set_running(false)
	for problem in active_problems:
		if is_instance_valid(problem):
			problem.stop_motion()
	for solution in solution_cards:
		if is_instance_valid(solution):
			solution.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scaffold_controller.end_run()
	var elapsed := minf(total_time_seconds, total_time_seconds - time_left)
	var stars := _calculate_stars() if success else 1
	if success:
		var area_scores := {
			"area_1": float(domain_points.area_1) * 2.0,
			"area_3": float(domain_points.area_3) * 2.0,
		}
		var session := get_node_or_null("/root/DigCompSession")
		if session:
			session.call("record_specialist_score", "level_3_matching", area_scores, _result_payload(stars).merged({"attempts": attempts.duplicate(true), "first_responses": first_responses.duplicate(true)}))
	_record("data_repair_run_finished", _result_payload(stars).merged({"success": success, "reason": reason}))
	_show_results(success, reason, elapsed, stars)


func _show_results(success: bool, reason: String, elapsed: float, stars: int) -> void:
	if factory_backdrop:
		factory_backdrop.set("alert_strength", 0.0)
	if belt:
		belt.alert_strength = 0.0
	_screen_pulse(Color(0.45, 1.0, 0.82, 0.55) if success else Color(1.0, 0.16, 0.28, 0.35))
	result_overlay = Control.new()
	result_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	result_overlay.z_index = 75
	add_child(result_overlay)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.015, 0.09, 0.11, 0.80) if success else Color(0.10, 0.02, 0.06, 0.82)
	result_overlay.add_child(shade)
	var box := VBoxContainer.new()
	_anchor(box, 0.24, 0.13, 0.76, 0.90, 0, 0, 0, 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	result_overlay.add_child(box)
	var core: Control = ICON_SCRIPT.new() as Control
	core.custom_minimum_size = Vector2(126.0, 126.0)
	core.call("configure", "verify_source" if success else "search_alert", Color("70f0d0") if success else Color("ff6177"))
	box.add_child(core)
	var title := Label.new()
	title.text = "DATA REPAIR COMPLETE" if success else "SYSTEM REPAIR FAILED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color("dffff7") if success else Color("ff8092"))
	box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "维修中心已恢复稳定运行" if success else reason
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color("83dbc9") if success else Color("e59aaa"))
	box.add_child(subtitle)
	var star_label := Label.new()
	star_label.text = ("★".repeat(stars) + "☆".repeat(3 - stars)) if success else "本轮未评级"
	star_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	star_label.add_theme_font_size_override("font_size", 46)
	star_label.add_theme_color_override("font_color", Color("ffd46a"))
	box.add_child(star_label)
	var detail := Label.new()
	detail.text = "SCORE  %03d     TIME  %s     ACCURACY  %d/10\nMAX COMBO  %d     LIFE  %d     ERRORS  %d" % [gameplay_score, _format_time(elapsed), completed_ids.size(), highest_combo, energy, error_count]
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_theme_font_size_override("font_size", 19)
	detail.add_theme_color_override("font_color", Color("d9edf7"))
	box.add_child(detail)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 14)
	box.add_child(actions)
	var retry := Button.new()
	retry.text = "再来一次"
	retry.custom_minimum_size = Vector2(190.0, 54.0)
	retry.add_theme_stylebox_override("normal", _style(Color("183b53"), Color("4b8da6"), 2, 10))
	retry.add_theme_stylebox_override("hover", _style(Color("206077"), Color("71e8d1"), 3, 10))
	retry.pressed.connect(_retry_from_results.bind(success, stars))
	actions.add_child(retry)
	var back := Button.new()
	back.text = "返回能力大厅"
	back.custom_minimum_size = Vector2(210.0, 54.0)
	back.add_theme_stylebox_override("normal", _style(Color("125043") if success else Color("4a2638"), Color("71e8d1") if success else Color("ff7b90"), 2, 10))
	back.pressed.connect(_return_to_hub.bind(success, stars))
	actions.add_child(back)
	box.modulate.a = 0.0
	box.scale = Vector2(0.86, 0.86)
	box.pivot_offset = box.size * 0.5
	var entrance := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	entrance.tween_property(box, "modulate:a", 1.0, 0.34)
	entrance.tween_property(box, "scale", Vector2.ONE, 0.48)


func _restart_level() -> void:
	get_tree().reload_current_scene()


func _retry_from_results(success: bool, stars: int) -> void:
	if success:
		_commit_success(stars)
	_restart_level()


func _return_to_hub(success: bool, stars: int) -> void:
	if success:
		_commit_success(stars)
	else:
		var session := get_node_or_null("/root/DigCompSession")
		if session:
			session.call("start_hub", false)


func _commit_success(stars: int) -> void:
	var session := get_node_or_null("/root/DigCompSession")
	if session:
		session.call("complete_top_level", "level_3_matching", _result_payload(stars).merged({"success": true, "task_type": "data_repair_conveyor", "first_responses": first_responses.duplicate(true), "attempts": attempts.duplicate(true)}))


func _record_match(item: Dictionary, solution_id: String, correct: bool, points: int) -> void:
	var task_id := String(item.get("id", ""))
	var attempt_count := int(attempts.get(task_id, 1))
	var payload := {
		"task_id": task_id,
		"task_type": "data_repair_drag_match",
		"digcomp_version": "3.0",
		"area_id": String(item.get("area_id", "")),
		"competence_id": _competence_id(String(item.get("area_id", ""))),
		"learning_outcome_id": "%s_%s" % [String(item.get("area_id", "")), task_id],
		"first_response": attempt_count == 1,
		"correct": correct,
		"points_awarded": points if attempt_count == 1 else 0,
		"response_time_msec": Time.get_ticks_msec() - start_msec,
		"attempt_count": attempt_count,
		"ai_used_before_response": _hint_count() > 0,
		"support_trigger": "",
		"hint_level": 0,
		"scaffold_id": "",
		"solution_id": solution_id,
		"round": _current_round(),
		"combo": combo,
		"multiplier": _combo_multiplier(combo),
	}
	_record("matching_pair_attempted", payload)
	_record("digcomp_response_submitted", payload)


func _result_payload(stars: int) -> Dictionary:
	return {
		"score": gameplay_score,
		"elapsed_seconds": snappedf(total_time_seconds - time_left, 0.01),
		"remaining_seconds": snappedf(time_left, 0.01),
		"correct_count": completed_ids.size(),
		"error_count": error_count,
		"energy_remaining": energy,
		"highest_combo": highest_combo,
		"stars": stars,
		"area_points": domain_points.duplicate(true),
	}


func _calculate_stars() -> int:
	var rating_points := float(gameplay_score) + time_left + float(maxi(0, 30 - error_count * 5))
	if rating_points >= 210.0 and error_count <= 2:
		return 3
	if rating_points >= 145.0:
		return 2
	return 1


func _combo_multiplier(value: int) -> int:
	if value >= 4:
		return 3
	if value >= 2:
		return 2
	return 1


func _current_round() -> int:
	return mini(3, completed_ids.size() / 3 + 1)


func _current_conveyor_speed() -> float:
	var stage_multiplier: float = float({1: 1.0, 2: 1.34, 3: 1.72}.get(_current_round(), 1.0))
	var event_multiplier := 1.55 if _speed_boost_time > 0.0 else 1.0
	var final_multiplier := 1.24 if time_left <= 10.0 else 1.0
	return base_conveyor_speed * stage_multiplier * event_multiplier * final_multiplier


func _apply_round_speed() -> void:
	_sync_problem_speeds()
	var banners := {2: "PHASE 2\n高速处理", 3: "PHASE 3\nDATA STORM"}
	_show_stage_banner(String(banners.get(_current_round(), "SPEED UP")))
	feedback_label.text = "生产线升档：移动速度与并发故障已提升"
	_event_clock = 7.5


func _update_hud() -> void:
	if score_label == null:
		return
	score_label.text = "SCORE %03d" % gameplay_score
	timer_label.text = "TIME %s" % _format_time(time_left)
	energy_label.text = "LIFE %d" % energy
	combo_label.text = "COMBO x%d" % _combo_multiplier(combo)
	var descriptions := {1: "基础修复", 2: "高速处理", 3: "数据风暴"}
	round_label.text = "PHASE %d // %s" % [_current_round(), descriptions[_current_round()]]
	if belt:
		belt.visual_speed = _current_conveyor_speed()
		belt.stage = _current_round()
	if factory_backdrop:
		factory_backdrop.set("stage", _current_round())
	_sync_problem_speeds()


func _sync_problem_speeds() -> void:
	for problem in active_problems:
		if is_instance_valid(problem):
			problem.movement_speed = _current_conveyor_speed()


func _trigger_factory_event() -> void:
	_event_clock = randf_range(10.0, 16.0)
	if randi() % 2 == 0:
		_speed_boost_time = 5.0
		_show_stage_banner("SYSTEM BOOST\n生产线加速 5 秒")
		feedback_label.text = "系统加速：优先处理最靠近熔炉的数据核心"
		_record("data_repair_factory_event", {"event": "system_boost", "duration_seconds": 5})
	else:
		_congestion_remaining = 3
		_congestion_clock = 0.0
		_show_stage_banner("DATA JAM\n连续故障涌入")
		feedback_label.text = "数据拥堵：三个故障核心即将连续进入生产线"
		_record("data_repair_factory_event", {"event": "data_congestion", "spawn_count": 3})


func _activate_freeze() -> void:
	if not _freeze_ready or run_finished:
		return
	_freeze_ready = false
	_freeze_time = 3.0
	freeze_button.visible = false
	_show_stage_banner("EMERGENCY FREEZE\n生产线冻结 3 秒")
	feedback_label.text = "紧急冻结启动：趁现在修复最危险的数据核心"
	_record("data_repair_factory_event", {"event": "emergency_freeze", "duration_seconds": 3})


func _update_final_countdown() -> void:
	if time_left <= 10.0 and time_left > 0.0:
		var second := int(ceil(time_left))
		if factory_backdrop:
			factory_backdrop.set("alert_strength", 1.0)
		if belt:
			belt.alert_strength = 1.0
		if second != _last_countdown_second:
			_last_countdown_second = second
			countdown_label.text = str(second)
			countdown_label.modulate.a = 0.92
			countdown_label.scale = Vector2(1.32, 1.32)
			countdown_label.pivot_offset = countdown_label.size * 0.5
			var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property(countdown_label, "scale", Vector2.ONE, 0.36)
			tween.tween_property(countdown_label, "modulate:a", 0.0, 0.70).set_delay(0.20)
			_screen_pulse(Color(0.95, 0.04, 0.12, 0.10))
	else:
		if factory_backdrop:
			factory_backdrop.set("alert_strength", move_toward(float(factory_backdrop.get("alert_strength")), 0.0, 0.025))
		if belt:
			belt.alert_strength = move_toward(belt.alert_strength, 0.0, 0.025)


func _show_stage_banner(text_value: String) -> void:
	if not is_instance_valid(stage_banner):
		return
	stage_banner.text = text_value
	stage_banner.modulate.a = 0.0
	stage_banner.scale = Vector2(0.82, 0.82)
	stage_banner.pivot_offset = stage_banner.size * 0.5
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(stage_banner, "modulate:a", 1.0, 0.18)
	tween.tween_property(stage_banner, "scale", Vector2.ONE, 0.25)
	tween.chain().tween_interval(0.82)
	tween.chain().tween_property(stage_banner, "modulate:a", 0.0, 0.32)


func _show_combo_burst(multiplier: int) -> void:
	var label := Label.new()
	label.text = "COMBO x%d" % multiplier
	label.add_theme_font_override("font", UI_FONT)
	label.add_theme_font_size_override("font_size", 44)
	label.add_theme_color_override("font_color", Color("ffe26d") if multiplier == 3 else Color("72efd3"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(size.x * 0.38, size.y * 0.34)
	label.size = Vector2(size.x * 0.24, 70.0)
	label.z_index = 94
	label.scale = Vector2(0.55, 0.55)
	label.pivot_offset = label.size * 0.5
	add_child(label)
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector2.ONE, 0.20)
	tween.tween_property(label, "position:y", label.position.y - 42.0, 0.62)
	tween.tween_property(label, "modulate:a", 0.0, 0.32).set_delay(0.35)
	tween.chain().tween_callback(label.queue_free)


func _spawn_floating_text(text_value: String, center: Vector2, color: Color, font_size: int) -> void:
	var label := Label.new()
	label.text = text_value
	label.position = center - Vector2(80.0, 30.0)
	label.size = Vector2(160.0, 60.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", UI_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.z_index = 96
	add_child(label)
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "position:y", label.position.y - 70.0, 0.68)
	tween.tween_property(label, "modulate:a", 0.0, 0.34).set_delay(0.30)
	tween.chain().tween_callback(label.queue_free)


func _spawn_trail_dot(pointer: Vector2, color: Color) -> void:
	var dot := ColorRect.new()
	dot.color = Color(color, 0.72)
	dot.size = Vector2(8.0, 8.0)
	dot.position = pointer - dot.size * 0.5
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.z_index = 82
	add_child(dot)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(dot, "scale", Vector2(0.2, 0.2), 0.28)
	tween.tween_property(dot, "modulate:a", 0.0, 0.28)
	tween.chain().tween_callback(dot.queue_free)


func _shake_factory() -> void:
	if not is_instance_valid(belt):
		return
	var origin := belt.position
	var tween := create_tween()
	for offset in [Vector2(7.0, -2.0), Vector2(-6.0, 2.0), Vector2(4.0, 0.0), Vector2.ZERO]:
		tween.tween_property(belt, "position", origin + offset, 0.045)


func _screen_pulse(color: Color) -> void:
	var flash := ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = color
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 93
	add_child(flash)
	var tween := create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 0.28)
	tween.tween_callback(flash.queue_free)


func _format_time(seconds: float) -> String:
	var value := maxi(0, int(ceil(seconds)))
	return "%02d:%02d" % [value / 60, value % 60]


func _flush_solution_refresh() -> void:
	if _solution_refresh_pending and _dragged_solution == null and _repair_animations == 0:
		_refresh_solution_cards()


func _ai_state() -> Dictionary:
	return {
		"current_area": "数据修复传送带",
		"current_checkpoint": "%d/10 已修复 · 第%d轮" % [completed_ids.size(), _current_round()],
		"repaired_items": completed_ids.size(),
		"total_items": 10,
		"round": _current_round(),
		"combo": combo,
		"energy": energy,
	}


func _active_problem_ids() -> Array[String]:
	var ids: Array[String] = []
	for problem in active_problems:
		if is_instance_valid(problem):
			ids.append(problem.item_id)
	return ids


func _competence_id(area_id: String) -> String:
	return {"area_1":"information_data_literacy", "area_3":"digital_content_creation"}.get(area_id, "")


func _hint_count() -> int:
	var service := get_node_or_null("/root/AiAssistantService")
	return Array(service.call("get_previous_hints", "level_3_matching")).size() if service else 0


func _record(event_name: String, payload: Dictionary) -> void:
	EVENT_BRIDGE.record(self, event_name, "level_3_matching", payload)


func _hud_label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color("cfe9f7"))
	label.add_theme_stylebox_override("normal", _style(Color(0.03, 0.11, 0.19, 0.70), Color(0.24, 0.47, 0.58, 0.65), 1, 7))
	return label


func _style(background: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _anchor(control: Control, left: float, top: float, right: float, bottom: float, offset_left: float, offset_top: float, offset_right: float, offset_bottom: float) -> void:
	control.set_anchor(SIDE_LEFT, left)
	control.set_anchor(SIDE_TOP, top)
	control.set_anchor(SIDE_RIGHT, right)
	control.set_anchor(SIDE_BOTTOM, bottom)
	control.offset_left = offset_left
	control.offset_top = offset_top
	control.offset_right = offset_right
	control.offset_bottom = offset_bottom


func skip_guide_for_test() -> void:
	_finish_guide()


func force_problem_expired_for_test() -> void:
	if not active_problems.is_empty():
		_on_problem_expired(active_problems[0])
