class_name DigCompMinigame
extends Control

const EVENT_BRIDGE := preload("res://scripts/experiment_event_bridge.gd")
const AI_PANEL_SCRIPT := preload("res://scripts/ui/ai_assistant_panel.gd")
const SCAFFOLD_SCRIPT := preload("res://scripts/scaffolding/scaffold_controller.gd")
const UI_FONT: FontFile = preload("res://assets/ui/fonts/noto_sans_sc_ui_600.ttf")

@export_enum("matching", "image_judgment") var game_mode: String = "matching"

const MATCHING_ITEMS: Array[Dictionary] = [
	{"id":"m01","area_id":"area_1","left":"搜索结果有醒目标题","right":"检查作者、日期与原始来源后再采用","decoy":"立刻转发标题最醒目的结果"},
	{"id":"m02","area_id":"area_1","left":"两篇文章结论冲突","right":"比较证据质量并交叉核验","decoy":"只保留符合自己观点的一篇"},
	{"id":"m03","area_id":"area_1","left":"资料太多难以查找","right":"按来源、主题与日期建立标签","decoy":"全部堆在同一个无标题文件夹"},
	{"id":"m04","area_id":"area_1","left":"AI给出一个统计数字","right":"追溯数据集与计算口径","decoy":"因为语气肯定就直接使用"},
	{"id":"m05","area_id":"area_1","left":"网页可能已经过期","right":"检查更新时间和当前权威信息","decoy":"忽略日期，只看页面排版"},
	{"id":"m06","area_id":"area_3","left":"修改AI生成的海报","right":"保留修改记录并核对素材许可","decoy":"删除所有来源说明"},
	{"id":"m07","area_id":"area_3","left":"公开发布AI辅助文章","right":"按要求标注AI参与和素材来源","decoy":"宣称全部内容均为原创人工完成"},
	{"id":"m08","area_id":"area_3","left":"合并图片、文字和数据","right":"选择兼容格式并保持可访问性","decoy":"只考虑视觉效果，忽略可读性"},
	{"id":"m09","area_id":"area_3","left":"复用网络图片","right":"核对版权许可并正确署名","decoy":"能下载就代表可以任意使用"},
	{"id":"m10","area_id":"area_3","left":"迭代数字作品","right":"根据反馈修改并保存版本","decoy":"覆盖原文件且不记录变更"},
]
const JUDGMENT_ITEMS: Array[Dictionary] = [
	{"id":"j01","area_id":"area_2","prompt":"小组把目标、限制和分工写清楚后，再请AI提出方案。","answer":true,"explanation":"合适。明确共同目标和责任能提高人机协作质量。"},
	{"id":"j02","area_id":"area_2","prompt":"同伴质疑AI答案时，组员用来源和证据一起复核。","answer":true,"explanation":"合适。协作判断应围绕可检查的证据。"},
	{"id":"j03","area_id":"area_2","prompt":"把最终决定完全交给AI，组内没有人负责审核。","answer":false,"explanation":"不合适。人类仍需承担审核和最终责任。"},
	{"id":"j04","area_id":"area_2","prompt":"提示语只写“帮我做完”，不说明受众、目标和限制。","answer":false,"explanation":"不合适。有效沟通需要清晰情境、目标和约束。"},
	{"id":"j05","area_id":"area_2","prompt":"团队记录采用或拒绝AI建议的理由。","answer":true,"explanation":"合适。这有助于共享理解、追责和反思。"},
	{"id":"j06","area_id":"area_4","prompt":"把含真实姓名和身份证号的表格直接上传到公开AI工具。","answer":false,"explanation":"不安全。应最小化数据并使用获准的安全工具。"},
	{"id":"j07","area_id":"area_4","prompt":"收到陌生邮件附件时，先核验发件人并用安全工具扫描。","answer":true,"explanation":"安全。先核验再打开可降低恶意附件风险。"},
	{"id":"j08","area_id":"area_4","prompt":"发现AI输出可能歧视某群体，暂停使用并检查数据与影响。","answer":true,"explanation":"负责任。应识别偏差并避免造成伤害。"},
	{"id":"j09","area_id":"area_4","prompt":"为了赶进度，长时间连续使用数字工具且忽略疲劳。","answer":false,"explanation":"不安全。数字福祉包括合理休息与注意力管理。"},
	{"id":"j10","area_id":"area_4","prompt":"为账号开启多因素认证并使用独立强密码。","answer":true,"explanation":"安全。这能显著降低账号被盗风险。"},
]

var title_label: Label
var instruction_label: Label
var score_label: Label
var feedback_label: Label
var task_container: Control
var assistant_panel: AiAssistantPanel
var scaffold_controller: ScaffoldController
var start_msec: int = 0
var attempts: Dictionary = {}
var first_responses: Dictionary = {}
var _completed: bool = false

var matching_left_selected: int = -1
var matching_right_selected: int = -1
var matching_scores := {"area_1": 0, "area_3": 0}
var matching_locked: Dictionary = {}
var matching_right_ids: Array[int] = []

var judgment_index: int = 0
var judgment_scores := {"area_2": 0, "area_4": 0}
var judgment_waiting: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var task_theme := Theme.new()
	task_theme.default_font = UI_FONT
	task_theme.default_font_size = 16
	theme = task_theme
	_build_shell()
	_setup_ai()
	start_msec = Time.get_ticks_msec()
	match game_mode:
		"image_judgment": _build_judgment()
		_: _build_matching()
	_record("digcomp_task_presented", {"task_type": game_mode, "digcomp_version": "3.0"})


func _build_shell() -> void:
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color("08172e")
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 26)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)
	title_label = Label.new()
	title_label.text = _title()
	title_label.add_theme_font_size_override("font_size", 30)
	layout.add_child(title_label)
	instruction_label = Label.new()
	instruction_label.text = _instruction()
	instruction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instruction_label.add_theme_color_override("font_color", Color("b9d6eb"))
	instruction_label.add_theme_font_size_override("font_size", 17)
	layout.add_child(instruction_label)
	var info := HBoxContainer.new()
	layout.add_child(info)
	score_label = Label.new()
	score_label.text = "当前得分：0"
	score_label.add_theme_font_size_override("font_size", 19)
	info.add_child(score_label)
	feedback_label = Label.new()
	feedback_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	feedback_label.add_theme_font_size_override("font_size", 17)
	info.add_child(feedback_label)
	task_container = VBoxContainer.new()
	task_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(task_container)


func _setup_ai() -> void:
	assistant_panel = AI_PANEL_SCRIPT.new() as AiAssistantPanel
	add_child(assistant_panel)
	assistant_panel.configure(_level_id(), _ai_state)
	scaffold_controller = SCAFFOLD_SCRIPT.new() as ScaffoldController
	add_child(scaffold_controller)
	scaffold_controller.configure(_level_id(), "%s_task" % game_mode, _objective(), _ai_state, func() -> bool: return true, assistant_panel)
	scaffold_controller.begin_run()
	scaffold_controller.notify_basic_operation({"kind": "task_opened"})
	scaffold_controller.mark_safe_window()


func _build_matching() -> void:
	matching_right_ids = []
	for index in range(MATCHING_ITEMS.size()):
		matching_right_ids.append(index)
	matching_right_ids.shuffle()
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	task_container.add_child(columns)
	var left_box := VBoxContainer.new()
	left_box.name = "LeftChoices"
	left_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left_box)
	var right_box := VBoxContainer.new()
	right_box.name = "RightChoices"
	right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right_box)
	for index in range(MATCHING_ITEMS.size()):
		var left_button := Button.new()
		left_button.text = String(MATCHING_ITEMS[index].get("left", ""))
		left_button.custom_minimum_size.y = 46
		left_button.pressed.connect(_select_matching_left.bind(index, left_button))
		left_box.add_child(left_button)
	for item_index in matching_right_ids:
		var right_button := Button.new()
		right_button.text = String(MATCHING_ITEMS[item_index].get("right", ""))
		right_button.custom_minimum_size.y = 46
		right_button.pressed.connect(_select_matching_right.bind(item_index, right_button))
		right_box.add_child(right_button)


func _select_matching_left(index: int, _button: Button) -> void:
	if _completed or matching_locked.has(index):
		return
	matching_left_selected = index
	feedback_label.text = "已选择左侧情境，请选择右侧对应策略。"
	_try_matching_pair()


func _select_matching_right(index: int, _button: Button) -> void:
	if _completed or matching_locked.has(index):
		return
	matching_right_selected = index
	feedback_label.text = "已选择右侧策略，请选择左侧对应情境。"
	_try_matching_pair()


func _try_matching_pair() -> void:
	if matching_left_selected < 0 or matching_right_selected < 0:
		return
	var left_id := matching_left_selected
	var right_id := matching_right_selected
	var item: Dictionary = MATCHING_ITEMS[left_id]
	var task_id := String(item.get("id", ""))
	var area_id := String(item.get("area_id", ""))
	attempts[task_id] = int(attempts.get(task_id, 0)) + 1
	var correct := left_id == right_id
	if not first_responses.has(task_id):
		first_responses[task_id] = correct
	if correct:
		matching_scores[area_id] = int(matching_scores[area_id]) + 10
		matching_locked[left_id] = true
		feedback_label.text = "匹配正确，组合已锁定。"
		scaffold_controller.notify_progress({"pair_id": task_id})
	else:
		matching_scores[area_id] = maxi(0, int(matching_scores[area_id]) - 5)
		feedback_label.text = "匹配错误（-5），请重新比较两侧含义。"
		scaffold_controller.notify_failure("repeated_failure", {"pair_id": task_id, "right_id": right_id})
	_record("matching_pair_attempted", _measurement(task_id, "matching", area_id, correct, int(attempts[task_id]), 10 if correct else -5).merged({"left_id": left_id, "right_id": right_id}))
	matching_left_selected = -1
	matching_right_selected = -1
	score_label.text = "信息管理：%d / 50　内容创作：%d / 50" % [matching_scores.area_1, matching_scores.area_3]
	_refresh_matching_buttons()
	if matching_locked.size() == MATCHING_ITEMS.size():
		DigCompSession.record_specialist_score(_level_id(), {"area_1": float(matching_scores.area_1) * 2.0, "area_3": float(matching_scores.area_3) * 2.0}, {"attempts": attempts.duplicate(true), "elapsed_seconds": _elapsed_seconds()})
		_show_completion((float(matching_scores.area_1) + float(matching_scores.area_3)))


func _refresh_matching_buttons() -> void:
	var left_box := task_container.find_child("LeftChoices", true, false)
	var right_box := task_container.find_child("RightChoices", true, false)
	if left_box:
		for index in range(left_box.get_child_count()):
			var button := left_box.get_child(index) as Button
			button.disabled = matching_locked.has(index)
			if button.disabled:
				button.modulate = Color("74e6a3")
	if right_box:
		for child in right_box.get_children():
			var button := child as Button
			var item_id := matching_right_ids[button.get_index()]
			button.disabled = matching_locked.has(item_id)
			if button.disabled:
				button.modulate = Color("74e6a3")


func _build_judgment() -> void:
	_show_judgment_item()


func _show_judgment_item() -> void:
	judgment_waiting = false
	_clear_children(task_container)
	if judgment_index >= JUDGMENT_ITEMS.size():
		DigCompSession.record_specialist_score(_level_id(), {"area_2": float(judgment_scores.area_2) * 20.0, "area_4": float(judgment_scores.area_4) * 20.0}, {"first_responses": first_responses.duplicate(true), "elapsed_seconds": _elapsed_seconds()})
		_show_completion((float(judgment_scores.area_2) + float(judgment_scores.area_4)) * 10.0)
		return
	var item: Dictionary = JUDGMENT_ITEMS[judgment_index]
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(760.0, 280.0)
	card.add_theme_stylebox_override("panel", _style(Color("17365b")))
	task_container.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	card.add_child(box)
	var counter := Label.new()
	counter.text = "场景 %d / 10 · %s" % [judgment_index + 1, "沟通与协作" if item.area_id == "area_2" else "安全与负责任使用"]
	counter.add_theme_color_override("font_color", Color("72e6da"))
	box.add_child(counter)
	var prompt := Label.new()
	prompt.text = String(item.get("prompt", ""))
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt.add_theme_font_size_override("font_size", 26)
	prompt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(prompt)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 22)
	box.add_child(actions)
	for option in [true, false]:
		var button := Button.new()
		button.text = "安全 / 合适" if option else "不安全 / 不合适"
		button.custom_minimum_size = Vector2(240.0, 64.0)
		button.pressed.connect(_submit_judgment.bind(option))
		actions.add_child(button)
	scaffold_controller.notify_quiz_started()


func _submit_judgment(answer: bool) -> void:
	if _completed or judgment_waiting or judgment_index >= JUDGMENT_ITEMS.size():
		return
	judgment_waiting = true
	var item: Dictionary = JUDGMENT_ITEMS[judgment_index]
	var task_id := String(item.get("id", ""))
	var correct := answer == bool(item.get("answer", false))
	attempts[task_id] = int(attempts.get(task_id, 0)) + 1
	if not first_responses.has(task_id):
		first_responses[task_id] = correct
		if correct:
			judgment_scores[String(item.get("area_id", ""))] = int(judgment_scores[String(item.get("area_id", ""))]) + 1
	_record("image_judgment_submitted", _measurement(task_id, "image_judgment", String(item.get("area_id", "")), correct, int(attempts[task_id]), 1 if correct else 0).merged({"answer": answer}))
	feedback_label.text = ("正确：" if correct else "不正确：") + String(item.get("explanation", ""))
	feedback_label.add_theme_color_override("font_color", Color("79eca8") if correct else Color("ff8b9d"))
	var answer_buttons := task_container.find_children("", "Button", true, false)
	for child in answer_buttons:
		var button := child as Button
		button.disabled = true
		var button_answer := button.text.begins_with("安全")
		if button_answer == bool(item.get("answer", false)):
			button.modulate = Color("79eca8")
		elif button_answer == answer:
			button.modulate = Color("ff8b9d")
	scaffold_controller.notify_quiz_result(correct, {"slot": task_id})
	scaffold_controller.notify_quiz_ended()
	judgment_index += 1
	score_label.text = "首次正确：%d / 10" % (int(judgment_scores.area_2) + int(judgment_scores.area_4))
	var timer := get_tree().create_timer(1.35)
	timer.timeout.connect(_show_judgment_item)


func _show_completion(percent: float) -> void:
	if _completed:
		return
	_completed = true
	scaffold_controller.end_run()
	_clear_children(task_container)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color("174c49")))
	task_container.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	var title := Label.new()
	title.text = "任务完成"
	title.add_theme_font_size_override("font_size", 32)
	box.add_child(title)
	var result := Label.new()
	result.text = "专项能力得分：%.1f / 100\n正式首次测量已锁定，重玩不会覆盖。" % percent
	result.add_theme_font_size_override("font_size", 21)
	box.add_child(result)
	var button := Button.new()
	button.text = "返回能力大厅"
	button.custom_minimum_size = Vector2(260.0, 64.0)
	button.pressed.connect(_return_to_hub)
	box.add_child(button)


func _return_to_hub() -> void:
	DigCompSession.complete_top_level(_level_id(), {"success": true, "task_type": game_mode, "elapsed_seconds": _elapsed_seconds(), "first_responses": first_responses.duplicate(true), "attempts": attempts.duplicate(true)})


func _measurement(task_id: String, task_type: String, area_id: String, correct: bool, attempt_count: int, points: int) -> Dictionary:
	return {
		"task_id": task_id,
		"task_type": task_type,
		"digcomp_version": "3.0",
		"area_id": area_id,
		"competence_id": _competence_id(area_id),
		"learning_outcome_id": "%s_%s" % [area_id, task_id],
		"first_response": attempt_count == 1,
		"correct": correct,
		"points_awarded": points if attempt_count == 1 else 0,
		"response_time_msec": Time.get_ticks_msec() - start_msec,
		"attempt_count": attempt_count,
		"ai_used_before_response": _hint_count() > 0,
		"support_trigger": "",
		"hint_level": 0,
		"scaffold_id": "",
	}


func _ai_state() -> Dictionary:
	return {
		"current_area": _title(),
		"current_checkpoint": _progress_text(),
		"current_choice": {"matching_left": matching_left_selected, "matching_right": matching_right_selected, "judgment_index": judgment_index},
		"instruction": "只帮助学生明确目标、检查依据、比较策略并反思；不得泄露正确选项、拼图位置或匹配答案。",
	}


func _record(event_name: String, payload: Dictionary) -> void:
	EVENT_BRIDGE.record(self, event_name, _level_id(), payload)


func _level_id() -> String:
	match game_mode:
		"image_judgment": return "level_4_image_judgment"
		_: return "level_3_matching"


func _title() -> String:
	match game_mode:
		"image_judgment": return "安全协作影像判断"
		_: return "数据与内容匹配"


func _instruction() -> String:
	match game_mode:
		"image_judgment": return "判断数字场景是否安全或合适。首次回答计入能力分，随后显示解释。"
		_: return "从左右两侧各选一项建立正确组合。正确 +10，错误 -5，已完成组合自动锁定。"


func _objective() -> String:
	match game_mode:
		"image_judgment": return "识别沟通协作与数字安全场景中的关键证据"
		_: return "比较信息管理和内容创作策略，建立有依据的对应关系"


func _progress_text() -> String:
	match game_mode:
		"image_judgment": return "场景 %d/10" % mini(judgment_index + 1, 10)
		_: return "%d/10 组已锁定" % matching_locked.size()


func _competence_id(area_id: String) -> String:
	return {"area_1":"information_data_literacy", "area_2":"communication_collaboration", "area_3":"digital_content_creation", "area_4":"safety_wellbeing_responsibility", "area_5":"problem_solving"}.get(area_id, "")


func _hint_count() -> int:
	var service := get_node_or_null("/root/AiAssistantService")
	return Array(service.call("get_previous_hints", _level_id())).size() if service else 0


func _elapsed_seconds() -> float:
	return snappedf(float(Time.get_ticks_msec() - start_msec) / 1000.0, 0.01)


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


func _style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style
