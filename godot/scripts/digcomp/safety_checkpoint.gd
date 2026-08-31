class_name SafetyCheckpoint
extends Control

const EVENT_BRIDGE := preload("res://scripts/experiment_event_bridge.gd")
const AI_PANEL_SCRIPT := preload("res://scripts/ui/ai_assistant_panel.gd")
const SCAFFOLD_SCRIPT := preload("res://scripts/scaffolding/scaffold_controller.gd")
const BACKDROP_SCRIPT := preload("res://scripts/digcomp/safety_checkpoint_backdrop.gd")
const STAGE_SCRIPT := preload("res://scripts/digcomp/safety_scan_stage.gd")
const GATE_SCRIPT := preload("res://scripts/digcomp/safety_checkpoint_gate.gd")
const CASE_SCRIPT := preload("res://scripts/digcomp/safety_case_file.gd")
const RISK_METER_SCRIPT := preload("res://scripts/digcomp/safety_risk_meter.gd")
const STAR_ROW_SCRIPT := preload("res://scripts/digcomp/safety_star_row.gd")
const ICON_SCRIPT := preload("res://scripts/digcomp/data_repair_icon.gd")
const UI_FONT: FontFile = preload("res://assets/ui/fonts/noto_sans_sc_ui_600.ttf")
const SUCCESS_SOUND: AudioStream = preload("res://assets/audio/interface_sfx_pack_1/confirm_tones/style6/confirm_style_6_001.ogg")
const ERROR_SOUND: AudioStream = preload("res://assets/audio/interface_sfx_pack_1/error_tones/style2/error_style_2_002.ogg")

const JUDGMENT_ITEMS: Array[Dictionary] = [
	{"id":"j01","area_id":"area_2","prompt":"小组把目标、限制和分工写清楚后，再请AI提出方案。","answer":true,"explanation":"明确共同目标和责任，AI只提供建议，协作流程可安全放行。","scene_kind":"team_plan","scene_title":"TEAM PLAN + AI ASSIST","evidence":[{"label":"目标与限制已填写","safe":true},{"label":"成员分工明确","safe":true},{"label":"AI仅提供建议","safe":true}]},
	{"id":"j02","area_id":"area_2","prompt":"同伴质疑AI答案时，组员用来源和证据一起复核。","answer":true,"explanation":"团队围绕可检查的来源复核，而不是盲从AI答案。","scene_kind":"evidence_review","scene_title":"EVIDENCE CROSS-CHECK","evidence":[{"label":"两份来源可追溯","safe":true},{"label":"组员共同复核","safe":true},{"label":"异议被完整记录","safe":true}]},
	{"id":"j03","area_id":"area_2","prompt":"把最终决定完全交给AI，组内没有人负责审核。","answer":false,"explanation":"缺少人工审核，重要决定不能完全交由AI。","scene_kind":"ai_final","scene_title":"AI FINAL DECISION","evidence":[{"label":"AI准备直接提交","safe":false},{"label":"人工审核席为空","safe":false},{"label":"责任人未指定","safe":false}]},
	{"id":"j04","area_id":"area_2","prompt":"提示语只写“帮我做完”，不说明受众、目标和限制。","answer":false,"explanation":"缺少受众、目标和限制，无法形成有效协作要求。","scene_kind":"vague_prompt","scene_title":"INCOMPLETE PROMPT","evidence":[{"label":"目标未填写","safe":false},{"label":"受众未知","safe":false},{"label":"约束条件缺失","safe":false}]},
	{"id":"j05","area_id":"area_2","prompt":"团队记录采用或拒绝AI建议的理由。","answer":true,"explanation":"决策理由有记录，有助于共享理解、追责和反思。","scene_kind":"decision_log","scene_title":"DECISION AUDIT LOG","evidence":[{"label":"采纳理由已记录","safe":true},{"label":"拒绝理由已记录","safe":true},{"label":"修改历史可追踪","safe":true}]},
	{"id":"j06","area_id":"area_4","prompt":"把含真实姓名和身份证号的表格直接上传到公开AI工具。","answer":false,"explanation":"个人信息未做最小化处理，不能上传到公开AI工具。","scene_kind":"privacy_upload","scene_title":"PUBLIC AI UPLOAD","evidence":[{"label":"真实姓名可见","safe":false},{"label":"身份证号未脱敏","safe":false},{"label":"工具未经批准","safe":false}]},
	{"id":"j07","area_id":"area_4","prompt":"收到陌生邮件附件时，先核验发件人并用安全工具扫描。","answer":true,"explanation":"先核验发件人并扫描附件，可以降低恶意文件风险。","scene_kind":"attachment_scan","scene_title":"ATTACHMENT QUARANTINE","evidence":[{"label":"发件人已核验","safe":true},{"label":"附件进入隔离区","safe":true},{"label":"恶意代码扫描完成","safe":true}]},
	{"id":"j08","area_id":"area_4","prompt":"发现AI输出可能歧视某群体，暂停使用并检查数据与影响。","answer":true,"explanation":"暂停使用并检查偏差及影响，是负责任的处理方式。","scene_kind":"bias_review","scene_title":"BIAS IMPACT REVIEW","evidence":[{"label":"异常输出已暂停","safe":true},{"label":"受影响群体已识别","safe":true},{"label":"训练数据待复核","safe":true}]},
	{"id":"j09","area_id":"area_4","prompt":"为了赶进度，长时间连续使用数字工具且忽略疲劳。","answer":false,"explanation":"持续忽略疲劳会损害数字福祉，应安排合理休息。","scene_kind":"wellbeing","scene_title":"FATIGUE OVERRIDE","evidence":[{"label":"连续工作时间过长","safe":false},{"label":"疲劳警告被忽略","safe":false},{"label":"休息计划为空","safe":false}]},
	{"id":"j10","area_id":"area_4","prompt":"为账号开启多因素认证并使用独立强密码。","answer":true,"explanation":"独立强密码配合多因素认证，能显著降低账号被盗风险。","scene_kind":"account_security","scene_title":"FINAL: ACCOUNT DEFENSE","evidence":[{"label":"独立强密码已启用","safe":true},{"label":"多因素认证在线","safe":true},{"label":"异常登录提醒开启","safe":true}]},
]

@export_enum("image_judgment") var game_mode: String = "image_judgment"

var case_items: Array[Dictionary] = []
var backdrop: Control
var scan_stage: Control
var safe_gate: Control
var risk_gate: Control
var risk_meter: Control
var case_layer: Control
var task_container: Control
var evidence_layer: Control
var active_case: Control
var score_label: Label
var timer_label: Label
var combo_label: Label
var case_label: Label
var risk_label: Label
var phase_label: Label
var feedback_label: Label
var banner_label: Label
var scan_button: Button
var assistant_panel: AiAssistantPanel
var scaffold_controller: ScaffoldController
var success_audio: AudioStreamPlayer
var error_audio: AudioStreamPlayer
var result_overlay: Control

var judgment_index: int = 0
var judgment_scores := {"area_2": 0, "area_4": 0}
var attempts: Dictionary = {}
var first_responses: Dictionary = {}
var error_case_ids: Array[String] = []
var timeout_case_ids: Array[String] = []
var gameplay_score: int = 0
var risk_value: float = 0.0
var combo: int = 0
var highest_combo: int = 0
var case_time_left: float = 24.0
var scan_used: bool = false
var judgment_waiting: bool = true
var running: bool = false
var completed: bool = false
var run_success: bool = false
var start_msec: int = 0
var case_start_msec: int = 0
var case_deadline_msec: int = 0
var _case_home: Vector2 = Vector2.ZERO
var _drag_line: Line2D
var _last_trail_msec: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var task_theme := Theme.new()
	task_theme.default_font = UI_FONT
	task_theme.default_font_size = 16
	theme = task_theme
	case_items = JUDGMENT_ITEMS.duplicate(true)
	_build_shell()
	_setup_ai()
	start_msec = Time.get_ticks_msec()
	running = true
	_show_case()
	_record("digcomp_task_presented", {"task_type":"safety_checkpoint_drag_review","digcomp_version":"3.0","case_count":case_items.size()})


func _process(delta: float) -> void:
	if not running or completed:
		return
	var safe_delta := minf(delta, 0.05)
	if not judgment_waiting:
		case_time_left = maxf(0.0, float(case_deadline_msec - Time.get_ticks_msec()) / 1000.0)
		if case_time_left <= 0.0:
			_handle_timeout()
	if backdrop:
		var alert := float(backdrop.get("alert_strength"))
		backdrop.set("alert_strength", move_toward(alert, 0.0 if risk_value < 70.0 else 0.28, safe_delta * 0.55))
	_update_hud()


func _build_shell() -> void:
	backdrop = BACKDROP_SCRIPT.new() as Control
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var title := Label.new()
	_anchor(title, 0.022, 0.018, 0.30, 0.072)
	title.text = "DIGITAL SAFETY CHECKPOINT"
	title.add_theme_font_size_override("font_size", 23)
	title.add_theme_color_override("font_color", Color("e4fbff"))
	add_child(title)
	phase_label = Label.new()
	_anchor(phase_label, 0.024, 0.070, 0.30, 0.112)
	phase_label.text = "PHASE 1 // 训练审查"
	phase_label.add_theme_font_size_override("font_size", 13)
	phase_label.add_theme_color_override("font_color", Color("6ce7d1"))
	add_child(phase_label)

	risk_meter = RISK_METER_SCRIPT.new() as Control
	_anchor(risk_meter, 0.43, 0.002, 0.57, 0.122)
	add_child(risk_meter)
	risk_label = Label.new()
	_anchor(risk_label, 0.455, 0.068, 0.545, 0.112)
	risk_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	risk_label.add_theme_font_size_override("font_size", 12)
	risk_label.add_theme_color_override("font_color", Color("d9eff5"))
	add_child(risk_label)

	score_label = _hud_label("SCORE 0000")
	timer_label = _hud_label("TIME 24")
	combo_label = _hud_label("COMBO x1")
	case_label = _hud_label("CASE 01/10")
	var hud: Array[Label] = [score_label, timer_label, combo_label, case_label]
	for index in range(hud.size()):
		_anchor(hud[index], 0.64 + index * 0.087, 0.030, 0.72 + index * 0.087, 0.090)
		add_child(hud[index])

	safe_gate = GATE_SCRIPT.new() as Control
	_anchor(safe_gate, 0.015, 0.16, 0.235, 0.83)
	safe_gate.call("configure", true)
	add_child(safe_gate)
	_add_gate_label(safe_gate, "SAFE\nPASS", Color("66efbd"))
	risk_gate = GATE_SCRIPT.new() as Control
	_anchor(risk_gate, 0.765, 0.16, 0.985, 0.83)
	risk_gate.call("configure", false)
	add_child(risk_gate)
	_add_gate_label(risk_gate, "RISK\nBLOCK", Color("ff6077"))

	scan_stage = STAGE_SCRIPT.new() as Control
	_anchor(scan_stage, 0.215, 0.125, 0.785, 0.87)
	add_child(scan_stage)
	case_layer = Control.new()
	case_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	case_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	case_layer.z_index = 15
	add_child(case_layer)
	task_container = case_layer
	evidence_layer = Control.new()
	evidence_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	evidence_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	evidence_layer.z_index = 32
	add_child(evidence_layer)

	scan_button = Button.new()
	_anchor(scan_button, 0.40, 0.855, 0.60, 0.928)
	scan_button.text = "SCAN EVIDENCE  (-2s)"
	scan_button.add_theme_font_size_override("font_size", 15)
	scan_button.add_theme_stylebox_override("normal", _button_style(Color("12384d"), Color("54c8d6"), 2))
	scan_button.add_theme_stylebox_override("hover", _button_style(Color("185768"), Color("78efda"), 3))
	scan_button.pressed.connect(_scan_evidence)
	scan_button.z_index = 40
	add_child(scan_button)
	feedback_label = Label.new()
	_anchor(feedback_label, 0.23, 0.934, 0.77, 0.985)
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	feedback_label.add_theme_font_size_override("font_size", 14)
	feedback_label.add_theme_color_override("font_color", Color("9dd9e8"))
	feedback_label.text = "拖动案例档案：左侧放行，右侧拦截；需要时先扫描证据"
	feedback_label.z_index = 38
	add_child(feedback_label)
	banner_label = Label.new()
	_anchor(banner_label, 0.27, 0.22, 0.73, 0.40)
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner_label.add_theme_font_size_override("font_size", 34)
	banner_label.add_theme_color_override("font_color", Color("dffff8"))
	banner_label.modulate.a = 0.0
	banner_label.z_index = 60
	add_child(banner_label)

	success_audio = AudioStreamPlayer.new()
	success_audio.stream = SUCCESS_SOUND
	success_audio.volume_db = -6.0
	add_child(success_audio)
	error_audio = AudioStreamPlayer.new()
	error_audio.stream = ERROR_SOUND
	error_audio.volume_db = -7.0
	add_child(error_audio)


func _setup_ai() -> void:
	assistant_panel = AI_PANEL_SCRIPT.new() as AiAssistantPanel
	add_child(assistant_panel)
	assistant_panel.configure("level_4_image_judgment", _ai_state)
	scaffold_controller = SCAFFOLD_SCRIPT.new() as ScaffoldController
	add_child(scaffold_controller)
	scaffold_controller.configure("level_4_image_judgment", "digital_safety_checkpoint", "观察数字协作场景中的证据，决定放行或拦截", _ai_state, func() -> bool: return running and not completed, assistant_panel)
	scaffold_controller.begin_run()
	scaffold_controller.notify_basic_operation({"kind":"task_opened"})
	scaffold_controller.mark_safe_window()


func _show_case() -> void:
	if completed:
		return
	if judgment_index >= case_items.size():
		_finish_checkpoint(true, "十个案例审查完成")
		return
	judgment_waiting = true
	scan_used = false
	_clear_children(evidence_layer)
	if is_instance_valid(active_case):
		active_case.queue_free()
	var stage := _current_stage()
	scan_stage.set("stage", stage)
	case_time_left = _case_time_limit(judgment_index)
	case_start_msec = Time.get_ticks_msec()
	case_deadline_msec = case_start_msec + int(case_time_left * 1000.0)
	scan_button.disabled = false
	scan_button.text = "SCAN EVIDENCE  (-2s)"
	active_case = CASE_SCRIPT.new() as Control
	case_layer.add_child(active_case)
	active_case.call("configure", case_items[judgment_index], judgment_index + 1)
	_case_home = Vector2((size.x - active_case.size.x) * 0.5, (size.y - active_case.size.y) * 0.49)
	active_case.call("set_home_position", _case_home, false)
	active_case.position = Vector2(_case_home.x, -active_case.size.y - 20.0)
	active_case.connect("drag_started", Callable(self, "_on_case_drag_started"))
	active_case.connect("drag_moved", Callable(self, "_on_case_drag_moved"))
	active_case.connect("drag_released", Callable(self, "_on_case_drag_released"))
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(active_case, "position", _case_home, 0.48)
	tween.finished.connect(func() -> void:
		if not completed:
			judgment_waiting = false
			scaffold_controller.notify_quiz_started()
	)
	if judgment_index == 0:
		_show_banner("DRAG TO REVIEW\n左侧放行  /  右侧拦截", Color("dffff7"))
	elif judgment_index == 3:
		_show_banner("PHASE 2\n正式安全审查", Color("6fead3"))
	elif judgment_index == 7:
		_show_banner("PHASE 3\nEMERGENCY EVENTS", Color("ffbc68"))
	elif judgment_index == 9:
		_show_banner("FINAL SECURITY CASE", Color("ffe06b"))
	_update_hud()
	_record("safety_case_presented", {"task_id":String(case_items[judgment_index].get("id", "")),"case_index":judgment_index + 1,"stage":stage,"time_limit_seconds":case_time_left})


func _on_case_drag_started(card: Control) -> void:
	if judgment_waiting or card != active_case:
		return
	feedback_label.text = "审查通道已锁定：接近闸门时会产生磁吸"
	_drag_line = Line2D.new()
	_drag_line.points = PackedVector2Array([_case_home + card.size * 0.5, get_global_mouse_position()])
	_drag_line.width = 3.0
	_drag_line.default_color = Color(0.48, 0.94, 0.88, 0.48)
	_drag_line.z_index = 45
	add_child(_drag_line)


func _on_case_drag_moved(card: Control, pointer: Vector2) -> void:
	if card != active_case or judgment_waiting:
		return
	var over_safe := safe_gate.get_global_rect().has_point(pointer)
	var over_risk := risk_gate.get_global_rect().has_point(pointer)
	safe_gate.call("set_hot", over_safe)
	risk_gate.call("set_hot", over_risk)
	active_case.call("set_magnetized", over_safe or over_risk)
	if is_instance_valid(_drag_line):
		_drag_line.points = PackedVector2Array([_case_home + card.size * 0.5, pointer])
	if Time.get_ticks_msec() - _last_trail_msec > 42:
		_last_trail_msec = Time.get_ticks_msec()
		_spawn_trail(pointer, Color("64edce") if over_safe else (Color("ff5e76") if over_risk else Color("75bcd4")))


func _on_case_drag_released(card: Control, pointer: Vector2) -> void:
	if card != active_case or judgment_waiting:
		return
	_fade_drag_line()
	var answer_set := false
	var answer := false
	if safe_gate.get_global_rect().has_point(pointer):
		answer_set = true
		answer = true
	elif risk_gate.get_global_rect().has_point(pointer):
		answer_set = true
		answer = false
	safe_gate.call("set_hot", false)
	risk_gate.call("set_hot", false)
	active_case.call("set_magnetized", false)
	if not answer_set:
		active_case.call("return_home")
		feedback_label.text = "档案未进入通道，继续观察场景或扫描证据"
		return
	_resolve_judgment(answer)


func _resolve_judgment(answer: bool) -> void:
	if completed or judgment_waiting or judgment_index >= case_items.size():
		return
	judgment_waiting = true
	scan_button.disabled = true
	active_case.call("stop_dragging")
	var item: Dictionary = case_items[judgment_index]
	var task_id := String(item.get("id", ""))
	var area_id := String(item.get("area_id", ""))
	attempts[task_id] = int(attempts.get(task_id, 0)) + 1
	var correct := answer == bool(item.get("answer", false))
	if not first_responses.has(task_id):
		first_responses[task_id] = correct
	var points := 0
	if correct:
		judgment_scores[area_id] = int(judgment_scores.get(area_id, 0)) + 1
		combo += 1
		highest_combo = maxi(highest_combo, combo)
		points = 100 * _score_multiplier()
		gameplay_score += points
		_set_risk(maxf(0.0, risk_value - 3.0))
		var message := "APPROVED" if answer else "RISK BLOCKED"
		_show_banner("%s\n+%d" % [message, points], Color("69efc8") if answer else Color("ff9a70"))
		feedback_label.text = "证据链一致，案例已%s。" % ("安全放行" if answer else "隔离拦截")
		success_audio.play()
		scaffold_controller.notify_progress({"case_id":task_id,"combo":combo,"risk":risk_value})
		if combo == 2:
			_show_combo_message("GOOD")
		elif combo == 3:
			_show_combo_message("COMBO x2")
		elif combo == 5:
			_show_combo_message("SECURITY EXPERT")
	else:
		combo = 0
		if not error_case_ids.has(task_id):
			error_case_ids.append(task_id)
		var risk_gain := 30.0 if answer and not bool(item.get("answer", false)) else 20.0
		_set_risk(risk_value + risk_gain)
		active_case.call("play_wrong")
		backdrop.set("alert_strength", 1.0)
		_show_banner("SECURITY BREACH\nRISK +%d" % int(risk_gain), Color("ff5c73"))
		feedback_label.text = String(item.get("explanation", "判断与证据不一致。"))
		error_audio.play()
		_glitch_pulse()
		scaffold_controller.notify_failure("wrong_safety_gate", {"case_id":task_id,"answer":answer,"risk":risk_value})
	var selected_gate := safe_gate if answer else risk_gate
	selected_gate.call("play_result", correct)
	_record("image_judgment_submitted", _measurement(item, correct, answer, points))
	scaffold_controller.notify_quiz_result(correct, {"slot":task_id})
	scaffold_controller.notify_quiz_ended()
	_animate_case_departure(selected_gate, correct)
	judgment_index += 1
	_update_hud()
	var timer := get_tree().create_timer(1.28)
	timer.timeout.connect(func() -> void:
		if risk_value >= 100.0:
			_finish_checkpoint(false, "系统风险值达到100")
		else:
			_show_case()
	)


func _scan_evidence() -> void:
	if completed or judgment_waiting or scan_used or not is_instance_valid(active_case):
		return
	scan_used = true
	case_deadline_msec -= 2000
	case_time_left = maxf(0.0, float(case_deadline_msec - Time.get_ticks_msec()) / 1000.0)
	scan_button.disabled = true
	scan_button.text = "EVIDENCE ACQUIRED"
	active_case.call("play_scan")
	scan_stage.call("trigger_scan")
	_show_evidence_tags(case_items[judgment_index])
	feedback_label.text = "证据扫描完成：检查发光标签后再决定通道"
	_record("safety_evidence_scanned", {"task_id":String(case_items[judgment_index].get("id", "")),"time_cost_seconds":2,"remaining_seconds":snappedf(case_time_left, 0.01)})


func _show_evidence_tags(item: Dictionary) -> void:
	_clear_children(evidence_layer)
	var evidence: Array = Array(item.get("evidence", []))
	var tag_width := 212.0
	var gap := 14.0
	var total := tag_width * evidence.size() + gap * maxf(0, evidence.size() - 1)
	var start_x := (size.x - total) * 0.5
	for index in range(evidence.size()):
		var point: Dictionary = evidence[index]
		var safe := bool(point.get("safe", false))
		var tag := Label.new()
		tag.text = ("OK  " if safe else "!  ") + String(point.get("label", ""))
		tag.position = Vector2(start_x + index * (tag_width + gap), _case_home.y - 42.0)
		tag.size = Vector2(tag_width, 38.0)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tag.add_theme_font_size_override("font_size", 13)
		tag.add_theme_color_override("font_color", Color("aef9e3") if safe else Color("ff9aaa"))
		tag.add_theme_stylebox_override("normal", _pill_style(Color(0.04, 0.22, 0.22, 0.92) if safe else Color(0.28, 0.07, 0.12, 0.92), Color("63e6ca") if safe else Color("ff6078")))
		tag.modulate.a = 0.0
		tag.scale = Vector2(0.72, 0.72)
		tag.pivot_offset = tag.size * 0.5
		evidence_layer.add_child(tag)
		var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(tag, "modulate:a", 1.0, 0.18).set_delay(index * 0.10)
		tween.tween_property(tag, "scale", Vector2.ONE, 0.25).set_delay(index * 0.10)


func _handle_timeout() -> void:
	if judgment_waiting or completed or judgment_index >= case_items.size():
		return
	judgment_waiting = true
	scan_button.disabled = true
	var item: Dictionary = case_items[judgment_index]
	var task_id := String(item.get("id", ""))
	attempts[task_id] = int(attempts.get(task_id, 0)) + 1
	if not first_responses.has(task_id):
		first_responses[task_id] = false
	if not timeout_case_ids.has(task_id):
		timeout_case_ids.append(task_id)
	combo = 0
	_set_risk(risk_value + 25.0)
	backdrop.set("alert_strength", 1.0)
	active_case.call("play_wrong")
	active_case.call("stop_dragging")
	_show_banner("REVIEW TIMEOUT\nRISK +25", Color("ff6378"))
	feedback_label.text = "案例未及时审查，系统风险上升。"
	error_audio.play()
	_record("image_judgment_submitted", _measurement(item, false, false, 0).merged({"timeout":true}))
	judgment_index += 1
	_update_hud()
	var timer := get_tree().create_timer(1.15)
	timer.timeout.connect(func() -> void:
		if risk_value >= 100.0:
			_finish_checkpoint(false, "系统风险值达到100")
		else:
			_show_case()
	)


func _animate_case_departure(gate: Control, correct: bool) -> void:
	if not is_instance_valid(active_case):
		return
	var target := gate.global_position + gate.size * 0.5 - active_case.size * 0.5
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(active_case, "global_position", target, 0.52)
	tween.tween_property(active_case, "scale", Vector2(0.16, 0.16), 0.52)
	tween.tween_property(active_case, "rotation", deg_to_rad(10.0 if gate == safe_gate else -10.0), 0.52)
	tween.tween_property(active_case, "modulate:a", 0.0, 0.25).set_delay(0.30)
	if correct:
		_spawn_burst(gate.global_position + gate.size * 0.5, Color("64eec8") if gate == safe_gate else Color("ff8a72"))


func _finish_checkpoint(success: bool, reason: String) -> void:
	if completed:
		return
	completed = true
	run_success = success
	running = false
	judgment_waiting = true
	scan_button.disabled = true
	if is_instance_valid(active_case):
		active_case.call("stop_dragging")
	scaffold_controller.end_run()
	var correct_count := int(judgment_scores.area_2) + int(judgment_scores.area_4)
	var stars := _calculate_stars(correct_count) if success else 1
	if success:
		get_node("/root/DigCompSession").call("record_specialist_score", "level_4_image_judgment", {"area_2":float(judgment_scores.area_2) * 20.0,"area_4":float(judgment_scores.area_4) * 20.0}, {"first_responses":first_responses.duplicate(true),"attempts":attempts.duplicate(true),"risk":risk_value,"score":gameplay_score,"highest_combo":highest_combo,"elapsed_seconds":_elapsed_seconds()})
	_record("safety_checkpoint_finished", {"success":success,"reason":reason,"correct_count":correct_count,"risk":risk_value,"score":gameplay_score,"highest_combo":highest_combo,"stars":stars})
	_show_results(success, reason, correct_count, stars)


func _show_results(success: bool, reason: String, correct_count: int, stars: int) -> void:
	result_overlay = Control.new()
	result_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	result_overlay.z_index = 80
	add_child(result_overlay)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.01, 0.09, 0.11, 0.86) if success else Color(0.12, 0.02, 0.06, 0.88)
	result_overlay.add_child(shade)
	var box := VBoxContainer.new()
	_anchor(box, 0.23, 0.09, 0.77, 0.92)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	result_overlay.add_child(box)
	var icon: Control = ICON_SCRIPT.new() as Control
	icon.custom_minimum_size = Vector2(116.0, 116.0)
	icon.call("configure", "verify_source" if success else "search_alert", Color("69edca") if success else Color("ff6077"))
	box.add_child(icon)
	var title := Label.new()
	title.text = "SECURITY CHECK COMPLETE" if success else "SECURITY SYSTEM BREACHED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 35)
	title.add_theme_color_override("font_color", Color("dffff7") if success else Color("ff8092"))
	box.add_child(title)
	var rank := _rank_text(stars)
	var stars_row: Control = STAR_ROW_SCRIPT.new() as Control
	stars_row.custom_minimum_size = Vector2(240, 58)
	stars_row.call("configure", stars)
	box.add_child(stars_row)
	var rank_label := Label.new()
	rank_label.text = rank
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_label.add_theme_font_size_override("font_size", 27)
	rank_label.add_theme_color_override("font_color", Color("ffd46a"))
	box.add_child(rank_label)
	var risk_control := "优秀" if risk_value <= 20.0 else ("稳定" if risk_value < 60.0 else "需改进")
	var detail := Label.new()
	detail.text = "%s\n\n安全判断  %d / 10     最高连击  %d\n风险控制  %s     最终得分  %d" % [reason, correct_count, highest_combo, risk_control, gameplay_score]
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_theme_font_size_override("font_size", 19)
	detail.add_theme_color_override("font_color", Color("d8eef5"))
	box.add_child(detail)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	box.add_child(actions)
	var review := Button.new()
	review.text = "查看错误案例"
	review.custom_minimum_size = Vector2(170, 52)
	review.disabled = error_case_ids.is_empty() and timeout_case_ids.is_empty()
	review.pressed.connect(_show_error_review)
	actions.add_child(review)
	var retry := Button.new()
	retry.text = "再次挑战"
	retry.custom_minimum_size = Vector2(160, 52)
	retry.pressed.connect(_retry)
	actions.add_child(retry)
	var hub := Button.new()
	hub.text = "返回能力大厅"
	hub.custom_minimum_size = Vector2(180, 52)
	hub.pressed.connect(_return_to_hub)
	actions.add_child(hub)
	box.modulate.a = 0.0
	box.scale = Vector2(0.82, 0.82)
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(box, "modulate:a", 1.0, 0.35)
	tween.tween_property(box, "scale", Vector2.ONE, 0.48)
	_screen_flash(Color(0.40, 1.0, 0.80, 0.52) if success else Color(1.0, 0.12, 0.24, 0.42))


func _show_error_review() -> void:
	if not is_instance_valid(result_overlay):
		return
	var review_overlay := Control.new()
	review_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	review_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	review_overlay.z_index = 5
	result_overlay.add_child(review_overlay)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.01, 0.05, 0.10, 0.94)
	review_overlay.add_child(shade)
	var title := Label.new()
	_anchor(title, 0.24, 0.08, 0.76, 0.16)
	title.text = "INCIDENT REVIEW  //  错误案例复盘"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	review_overlay.add_child(title)
	var list := VBoxContainer.new()
	_anchor(list, 0.20, 0.18, 0.80, 0.82)
	list.add_theme_constant_override("separation", 7)
	review_overlay.add_child(list)
	for item in case_items:
		var id := String(item.get("id", ""))
		if not error_case_ids.has(id) and not timeout_case_ids.has(id):
			continue
		var row := Label.new()
		row.text = "%s  %s\n%s" % ["TIMEOUT" if timeout_case_ids.has(id) else "ERROR", String(item.get("prompt", "")), String(item.get("explanation", ""))]
		row.custom_minimum_size.y = 58
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_theme_font_size_override("font_size", 14)
		row.add_theme_color_override("font_color", Color("ffd6dc"))
		row.add_theme_stylebox_override("normal", _pill_style(Color(0.22, 0.06, 0.11, 0.82), Color("a84b60")))
		list.add_child(row)
	var close := Button.new()
	_anchor(close, 0.42, 0.86, 0.58, 0.94)
	close.text = "返回结算"
	close.pressed.connect(review_overlay.queue_free)
	review_overlay.add_child(close)


func _return_to_hub() -> void:
	if run_success:
		get_node("/root/DigCompSession").call("complete_top_level", "level_4_image_judgment", {"success":true,"task_type":"digital_safety_checkpoint","elapsed_seconds":_elapsed_seconds(),"first_responses":first_responses.duplicate(true),"attempts":attempts.duplicate(true),"risk":risk_value,"score":gameplay_score})
	else:
		get_node("/root/DigCompSession").call("start_hub", false)


func _retry() -> void:
	get_tree().reload_current_scene()


func _measurement(item: Dictionary, correct: bool, answer: bool, points: int) -> Dictionary:
	var task_id := String(item.get("id", ""))
	return {
		"task_id":task_id,"task_type":"safety_checkpoint_drag_review","digcomp_version":"3.0",
		"area_id":String(item.get("area_id", "")),"competence_id":_competence_id(String(item.get("area_id", ""))),
		"learning_outcome_id":"%s_%s" % [String(item.get("area_id", "")), task_id],
		"first_response":int(attempts.get(task_id, 1)) == 1,"correct":correct,"points_awarded":points,
		"response_time_msec":Time.get_ticks_msec() - case_start_msec,"attempt_count":int(attempts.get(task_id, 1)),
		"ai_used_before_response":_hint_count() > 0,"support_trigger":"","hint_level":0,"scaffold_id":"",
		"answer":answer,"evidence_scanned":scan_used,"risk_after":risk_value,"combo":combo,"multiplier":_score_multiplier(),
	}


func _set_risk(value: float) -> void:
	risk_value = clampf(value, 0.0, 100.0)
	if risk_meter:
		risk_meter.call("set_risk", risk_value)
	if risk_value >= 70.0:
		backdrop.set("alert_strength", maxf(0.55, float(backdrop.get("alert_strength"))))


func _score_multiplier() -> int:
	if combo >= 5:
		return 3
	if combo >= 3:
		return 2
	return 1


func _current_stage() -> int:
	if judgment_index >= 7:
		return 3
	if judgment_index >= 3:
		return 2
	return 1


func _case_time_limit(index: int) -> float:
	if index < 3:
		return 24.0
	if index < 7:
		return 18.0
	return 15.0


func _calculate_stars(correct_count: int) -> int:
	if correct_count >= 9 and risk_value <= 25.0:
		return 3
	if correct_count >= 7 and risk_value < 70.0:
		return 2
	return 1


func _rank_text(stars: int) -> String:
	return {3:"数字安全专家",2:"安全审查员",1:"安全新手"}.get(stars, "安全新手")


func _update_hud() -> void:
	if score_label == null:
		return
	score_label.text = "SCORE %04d" % gameplay_score
	timer_label.text = "TIME %02d" % maxi(0, int(ceil(case_time_left)))
	combo_label.text = "COMBO x%d" % _score_multiplier()
	case_label.text = "CASE %02d/10" % mini(judgment_index + 1, 10)
	risk_label.text = "RISK %02d / 100" % int(round(risk_value))
	var labels := {1:"训练审查",2:"正式审查",3:"紧急事件"}
	phase_label.text = "PHASE %d // %s" % [_current_stage(), labels[_current_stage()]]
	backdrop.set("security_level", clampf(float(combo) / 5.0, 0.0, 1.0))


func _show_banner(text_value: String, color: Color) -> void:
	banner_label.text = text_value
	banner_label.add_theme_color_override("font_color", color)
	banner_label.modulate.a = 0.0
	banner_label.scale = Vector2(0.74, 0.74)
	banner_label.pivot_offset = banner_label.size * 0.5
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(banner_label, "modulate:a", 1.0, 0.18)
	tween.tween_property(banner_label, "scale", Vector2.ONE, 0.25)
	tween.chain().tween_interval(0.62)
	tween.chain().tween_property(banner_label, "modulate:a", 0.0, 0.28)


func _show_combo_message(text_value: String) -> void:
	var label := Label.new()
	label.text = text_value
	label.position = Vector2(size.x * 0.36, size.y * 0.42)
	label.size = Vector2(size.x * 0.28, 70)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 38)
	label.add_theme_color_override("font_color", Color("ffe06c") if combo >= 5 else Color("71eed2"))
	label.z_index = 70
	add_child(label)
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "position:y", label.position.y - 48, 0.62)
	tween.tween_property(label, "modulate:a", 0.0, 0.32).set_delay(0.34)
	tween.chain().tween_callback(label.queue_free)


func _spawn_trail(pointer: Vector2, color: Color) -> void:
	var dot := ColorRect.new()
	dot.position = pointer - Vector2(4, 4)
	dot.size = Vector2(8, 8)
	dot.color = Color(color, 0.72)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.z_index = 43
	add_child(dot)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(dot, "scale", Vector2(0.15, 0.15), 0.26)
	tween.tween_property(dot, "modulate:a", 0.0, 0.26)
	tween.chain().tween_callback(dot.queue_free)


func _fade_drag_line() -> void:
	if is_instance_valid(_drag_line):
		var tween := create_tween()
		tween.tween_property(_drag_line, "modulate:a", 0.0, 0.12)
		tween.tween_callback(_drag_line.queue_free)
	_drag_line = null


func _spawn_burst(center: Vector2, color: Color) -> void:
	for index in range(12):
		var dot := ColorRect.new()
		dot.color = color
		dot.size = Vector2(7, 7)
		dot.position = center - dot.size * 0.5
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.z_index = 72
		add_child(dot)
		var target := dot.position + Vector2.from_angle(TAU * index / 12.0) * 75.0
		var tween := create_tween().set_parallel(true)
		tween.tween_property(dot, "position", target, 0.42)
		tween.tween_property(dot, "modulate:a", 0.0, 0.42)
		tween.chain().tween_callback(dot.queue_free)


func _glitch_pulse() -> void:
	for index in range(5):
		var bar := ColorRect.new()
		bar.color = Color(1.0, 0.08, 0.20, 0.14)
		bar.position = Vector2(0, size.y * (0.20 + index * 0.13))
		bar.size = Vector2(size.x, 12 + index * 2)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.z_index = 68
		add_child(bar)
		var tween := create_tween().set_parallel(true)
		tween.tween_property(bar, "position:x", 36.0 if index % 2 == 0 else -36.0, 0.16)
		tween.tween_property(bar, "modulate:a", 0.0, 0.28)
		tween.chain().tween_callback(bar.queue_free)


func _screen_flash(color: Color) -> void:
	var flash := ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = color
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 90
	add_child(flash)
	var tween := create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 0.32)
	tween.tween_callback(flash.queue_free)


func _add_gate_label(gate: Control, text_value: String, color: Color) -> void:
	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.text = text_value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.offset_bottom = -45
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 6
	gate.add_child(label)


func _hud_label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color("d5edf5"))
	label.add_theme_stylebox_override("normal", _pill_style(Color(0.025, 0.10, 0.16, 0.74), Color("315a70")))
	return label


func _button_style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	return style


func _pill_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 10
	style.content_margin_right = 10
	return style


func _anchor(control: Control, left: float, top: float, right: float, bottom: float) -> void:
	control.set_anchor(SIDE_LEFT, left)
	control.set_anchor(SIDE_TOP, top)
	control.set_anchor(SIDE_RIGHT, right)
	control.set_anchor(SIDE_BOTTOM, bottom)
	control.offset_left = 0
	control.offset_top = 0
	control.offset_right = 0
	control.offset_bottom = 0


func _competence_id(area_id: String) -> String:
	return {"area_2":"communication_collaboration","area_4":"safety_wellbeing_responsibility"}.get(area_id, "")


func _hint_count() -> int:
	var service := get_node_or_null("/root/AiAssistantService")
	return Array(service.call("get_previous_hints", "level_4_image_judgment")).size() if service else 0


func _elapsed_seconds() -> float:
	return snappedf(float(Time.get_ticks_msec() - start_msec) / 1000.0, 0.01)


func _ai_state() -> Dictionary:
	return {
		"current_area": "AI协作安全审查站",
		"current_checkpoint": "案例 %d/10 · 风险 %d" % [mini(judgment_index + 1, 10), int(risk_value)],
		"case_index": mini(judgment_index + 1, 10),
		"total_cases": 10,
		"risk": risk_value,
		"combo": combo,
		"evidence_scanned": scan_used,
	}


func _record(event_name: String, payload: Dictionary) -> void:
	EVENT_BRIDGE.record(self, event_name, "level_4_image_judgment", payload)


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


func resolve_current_case_for_test(answer: bool) -> void:
	_resolve_judgment(answer)


func scan_current_case_for_test() -> void:
	_scan_evidence()
