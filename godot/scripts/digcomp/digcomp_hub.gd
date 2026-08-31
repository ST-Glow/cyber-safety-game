class_name DigCompHub
extends "res://scripts/party/party_level_base.gd"

const AI_PANEL_SCRIPT := preload("res://scripts/ui/ai_assistant_panel.gd")
const SCAFFOLD_SCRIPT := preload("res://scripts/scaffolding/scaffold_controller.gd")
const PORTAL_SCRIPT := preload("res://scripts/digcomp/hub_portal_node.gd")
const CORE_SCRIPT := preload("res://scripts/digcomp/hub_core.gd")
const UI_FONT: FontFile = preload("res://assets/ui/fonts/noto_sans_sc_ui_600.ttf")

const LEVEL_GUIDES := {
	"level_1_party_campaign": {
		"number":"01", "title":"AI派对闯关", "tag":"知识检查 + 游戏表现", "color":Color("4ec9ff"),
		"objective":"连续完成四个派对子阶段，并在检查点提交10个首次计分回答。",
		"steps":["WASD移动，SPACE跳跃，SHIFT冲刺", "抵达检查点后根据证据作答", "首次回答计入能力测量，重试仅用于学习"],
		"measure":"五个 DigComp 领域的知识证据", "duration":"约 12–18 分钟"
	},
	"level_2_puzzle": {
		"number":"02", "title":"数字策略拼图", "tag":"空间操作 + 问题解决", "color":Color("ffca5f"),
		"objective":"拖动真实拼图块，利用图像线索把完整的数字问题解决流程拼回原位。",
		"steps":["按住拼图块拖动，松开即可放置", "接近正确位置时会磁吸并锁定", "完成全部拼块；时间、首次放置和错误都会记录"],
		"measure":"问题解决领域的行为证据", "duration":"约 3–6 分钟"
	},
	"level_3_matching": {
		"number":"03", "title":"数据修复工厂", "tag":"实时判断 + 拖拽修复", "color":Color("69e38c"),
		"objective":"从工具槽抓取修复芯片，在故障模块进入熔炉前完成正确匹配。",
		"steps":["观察故障模块的图标与简短描述", "拖动对应修复芯片到移动中的模块", "错误会扣分并中断连击，漏修会损失能量"],
		"measure":"信息管理与内容创作证据", "duration":"最多 90 秒"
	},
	"level_4_image_judgment": {
		"number":"04", "title":"AI安全审查站", "tag":"证据扫描 + 风险决策", "color":Color("ff7e9d"),
		"objective":"检查10个AI协作案例，将档案拖入安全放行门或风险隔离门。",
		"steps":["先观察案例场景；可扫描3条证据", "拖动整份档案到左侧 SAFE 或右侧 RISK", "扫描消耗2秒；误判会提高系统风险并清空连击"],
		"measure":"协作与安全领域的行为证据", "duration":"每案 15–24 秒"
	}
}

var assistant_panel: AiAssistantPanel
var scaffold_controller: ScaffoldController
var status_label: Label
var profile_label: Label
var progress_bar: ProgressBar
var _portal_locked: bool = false
var hub_hud_root: Control
var instruction_overlay: Control
var pending_level_id: String = ""
var portal_nodes: Dictionary = {}
var active_portal_id: String = ""
var portal_card: PanelContainer
var portal_number_label: Label
var portal_title_label: Label
var portal_description_label: Label
var portal_meta_label: Label
var portal_action_label: Label
var tutorial_panel: PanelContainer
var _portal_card_tween: Tween


func _ready() -> void:
	_ensure_party_inputs()
	_build_party_world(Color("08182f"), Color("132d4f"), [Color("244a70"), Color("173d5e")])
	_build_floor()
	_spawn_party_player(Vector3(0.0, 1.2, 8.6))
	_connect_party_player_events("digcomp_hub")
	_build_party_camera(9.1, -15.5)
	# Party levels normally enable controls after an intro countdown. The hub has
	# no countdown, so it must hand control to the player immediately.
	player.set_controls_enabled(true)
	_build_hall_objects()
	_build_hud()
	_setup_ai()
	_record_hub_entry()
	DigCompSession.finalize_if_complete()
	call_deferred("_release_hub_focus")
	if DisplayServer.get_name() != "headless":
		call_deferred("_show_control_tutorial")


func _process(delta: float) -> void:
	_update_party_camera(delta)
	if player and player.global_position.y < -8.0:
		player.global_position = Vector3(0.0, 1.2, 8.6)
		player.velocity = Vector3.ZERO


func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if active_portal_id.is_empty() or _portal_locked or is_instance_valid(instruction_overlay):
		return
	if player == null or not player.controls_enabled:
		return
	if event.is_action_pressed("interact") or event.physical_keycode == KEY_E:
		get_viewport().set_input_as_handled()
		_start_level(active_portal_id)
	elif event.is_action_pressed("task_help") or event.physical_keycode == KEY_F:
		get_viewport().set_input_as_handled()
		_show_level_guide(active_portal_id)


func _build_floor() -> void:
	var floor := _create_party_collision_box(self, Vector3(30.0, 0.5, 25.0), Vector3(0.0, -0.25, 0.0), "HallFloor")
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(30.0, 0.5, 25.0)
	box.material = _make_party_material(Color("173554"), 0.08, 0.7)
	mesh.mesh = box
	floor.add_child(mesh)


func _build_hall_objects() -> void:
	_add_npc(Vector3(3.3, 0.0, 4.3))
	var levels: Array[Dictionary] = DigCompSession.get_top_levels()
	var positions := [Vector3(-8.5, 0.0, -2.3), Vector3(-3.1, 0.0, -7.2), Vector3(3.1, 0.0, -7.2), Vector3(8.5, 0.0, -2.3)]
	var colors := [Color("4ec9ff"), Color("ffca5f"), Color("69e38c"), Color("ff7e9d")]
	for index in range(levels.size()):
		_add_portal(levels[index], positions[index], colors[index], index)
	var core: Node3D = CORE_SCRIPT.new() as Node3D
	core.name = "DigCompCore"
	core.position = Vector3(0.0, 0.0, 0.8)
	add_child(core)
	var local_positions: Array = []
	for portal_position in positions:
		local_positions.append(Vector3(portal_position) - core.position)
	core.call("configure", local_positions, DigCompSession.top_level_results.size())


func _add_npc(position_value: Vector3) -> void:
	var npc := Node3D.new()
	npc.name = "GuideNPC"
	npc.position = position_value
	add_child(npc)
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.62
	capsule.height = 2.25
	capsule.material = _make_party_material(Color("67eee0"), 0.35, 0.4)
	body.mesh = capsule
	body.position.y = 1.15
	npc.add_child(body)
	_add_world_label(npc, "数字能力向导\n自由选择四个任务", Vector3(0.0, 2.8, 0.0), Color("d7fffb"))


func _add_portal(level: Dictionary, position_value: Vector3, color: Color, icon_index: int) -> void:
	var level_id := String(level.get("id", ""))
	var portal: Area3D = PORTAL_SCRIPT.new() as Area3D
	portal.name = "Portal_%s" % level_id
	portal.position = position_value
	add_child(portal)
	var guide: Dictionary = LEVEL_GUIDES.get(level_id, {})
	portal.call("configure", level_id, String(guide.get("title", level.get("title", ""))), String(guide.get("tag", "")), color, icon_index, bool(level.get("completed", false)))
	portal.body_entered.connect(_on_portal_near.bind(level_id))
	portal.body_exited.connect(_on_portal_left.bind(level_id))
	portal_nodes[level_id] = portal


func _add_world_label(parent: Node3D, text_value: String, position_value: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.text = text_value
	label.font = UI_FONT
	label.position = position_value
	label.font_size = 42
	label.modulate = color
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(label)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HubHUDLayer"
	add_child(layer)
	var root := Control.new()
	root.name = "HubHUD"
	var hub_theme := Theme.new()
	hub_theme.default_font = UI_FONT
	hub_theme.default_font_size = 16
	root.theme = hub_theme
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	hub_hud_root = root

	var status_panel := PanelContainer.new()
	status_panel.name = "ProgressCard"
	status_panel.position = Vector2(18, 16)
	status_panel.size = Vector2(248, 118)
	status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.01, 0.055, 0.10, 0.72), 16, Color(0.20, 0.69, 0.70, 0.38), 5))
	root.add_child(status_panel)
	var status_box := VBoxContainer.new()
	status_box.add_theme_constant_override("separation", 4)
	status_panel.add_child(status_box)
	var top_row := HBoxContainer.new()
	status_box.add_child(top_row)
	var eyebrow := Label.new()
	eyebrow.text = "DIGCOMP 3.0"
	eyebrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eyebrow.add_theme_font_size_override("font_size", 12)
	eyebrow.add_theme_color_override("font_color", Color("6fe5da"))
	top_row.add_child(eyebrow)
	var help_button := Button.new()
	help_button.name = "HubHelpButton"
	help_button.text = "?"
	help_button.tooltip_text = "查看大厅玩法说明"
	help_button.focus_mode = Control.FOCUS_NONE
	help_button.custom_minimum_size = Vector2(28, 24)
	help_button.add_theme_font_size_override("font_size", 13)
	help_button.add_theme_stylebox_override("normal", _panel_style(Color(0.03, 0.13, 0.18, 0.88), 9, Color("397b82"), 0))
	help_button.add_theme_stylebox_override("hover", _panel_style(Color(0.06, 0.24, 0.27, 1.0), 9, Color("6fe5da"), 0))
	help_button.pressed.connect(_show_hub_help)
	top_row.add_child(help_button)
	var title := Label.new()
	title.text = "数字能力探索总部"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("effaff"))
	status_box.add_child(title)
	status_label = Label.new()
	status_label.text = "任务  %d / 4" % DigCompSession.top_level_results.size()
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color("abc9d7"))
	status_box.add_child(status_label)
	var node_row := HBoxContainer.new()
	node_row.add_theme_constant_override("separation", 8)
	status_box.add_child(node_row)
	var node_colors := [Color("4ec9ff"), Color("ffca5f"), Color("69e38c"), Color("ff7e9d")]
	for index in range(4):
		var progress_node := Label.new()
		progress_node.custom_minimum_size = Vector2(25, 8)
		var complete := index < DigCompSession.top_level_results.size()
		var node_color: Color = node_colors[index] if complete else Color("29465a")
		progress_node.add_theme_stylebox_override("normal", _bar_style(node_color))
		node_row.add_child(progress_node)
	progress_bar = ProgressBar.new()
	progress_bar.name = "HubProgressBar"
	progress_bar.visible = false
	progress_bar.max_value = 4
	progress_bar.value = DigCompSession.top_level_results.size()
	status_box.add_child(progress_bar)
	profile_label = Label.new()
	profile_label.visible = false
	profile_label.text = _profile_progress_text()
	status_box.add_child(profile_label)

	portal_card = PanelContainer.new()
	portal_card.name = "NearbyTaskCard"
	portal_card.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	portal_card.position = Vector2(18, -118)
	portal_card.size = Vector2(276, 236)
	portal_card.visible = false
	portal_card.modulate.a = 0.0
	portal_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portal_card.add_theme_stylebox_override("panel", _panel_style(Color(0.012, 0.055, 0.10, 0.94), 18, Color("3b7898"), 12))
	root.add_child(portal_card)
	var card_box := VBoxContainer.new()
	card_box.add_theme_constant_override("separation", 7)
	portal_card.add_child(card_box)
	portal_number_label = Label.new()
	portal_number_label.text = "01"
	portal_number_label.add_theme_font_size_override("font_size", 14)
	portal_number_label.add_theme_color_override("font_color", Color("6fe5da"))
	card_box.add_child(portal_number_label)
	portal_title_label = Label.new()
	portal_title_label.text = "任务"
	portal_title_label.add_theme_font_size_override("font_size", 23)
	card_box.add_child(portal_title_label)
	portal_description_label = Label.new()
	portal_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	portal_description_label.custom_minimum_size.y = 62
	portal_description_label.add_theme_font_size_override("font_size", 13)
	portal_description_label.add_theme_color_override("font_color", Color("abc8d7"))
	card_box.add_child(portal_description_label)
	portal_meta_label = Label.new()
	portal_meta_label.add_theme_font_size_override("font_size", 12)
	portal_meta_label.add_theme_color_override("font_color", Color("86aabd"))
	card_box.add_child(portal_meta_label)
	portal_action_label = Label.new()
	portal_action_label.text = "E 进入任务     F 查看说明"
	portal_action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portal_action_label.add_theme_font_size_override("font_size", 15)
	portal_action_label.add_theme_color_override("font_color", Color("eafffb"))
	portal_action_label.add_theme_stylebox_override("normal", _panel_style(Color(0.05, 0.22, 0.22, 0.96), 11, Color("65dacc"), 0))
	card_box.add_child(portal_action_label)

	tutorial_panel = PanelContainer.new()
	tutorial_panel.name = "PersistentControlsGuide"
	tutorial_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	tutorial_panel.position = Vector2(-330, -84)
	tutorial_panel.size = Vector2(660, 62)
	tutorial_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.01, 0.05, 0.09, 0.88), 16, Color(0.31, 0.75, 0.73, 0.45), 8))
	root.add_child(tutorial_panel)
	var tutorial_row := HBoxContainer.new()
	tutorial_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tutorial_row.add_theme_constant_override("separation", 22)
	tutorial_panel.add_child(tutorial_row)
	for hint_text in ["WASD\n移动", "空格键\n跳跃", "SHIFT\n冲刺", "E\n进入任务", "F\n任务说明"]:
		var hint := Label.new()
		hint.text = hint_text
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.add_theme_font_size_override("font_size", 13)
		hint.add_theme_color_override("font_color", Color("cde9ec"))
		tutorial_row.add_child(hint)


func _setup_ai() -> void:
	assistant_panel = AI_PANEL_SCRIPT.new() as AiAssistantPanel
	add_child(assistant_panel)
	assistant_panel.configure("digcomp_hub", _ai_state)
	assistant_panel.open_changed.connect(_on_ai_open_changed)
	scaffold_controller = SCAFFOLD_SCRIPT.new() as ScaffoldController
	add_child(scaffold_controller)
	scaffold_controller.configure("digcomp_hub", "digcomp_hub_orientation", "选择下一项任务，并根据当前证据反思自己的策略", _ai_state, func() -> bool: return true, assistant_panel)
	scaffold_controller.begin_run()
	scaffold_controller.notify_basic_operation({"kind": "hub_entered"})
	scaffold_controller.mark_safe_window()


func _ai_state() -> Dictionary:
	return {
		"current_area": "DigComp 3.0 能力大厅",
		"current_checkpoint": "选择四类任务",
		"completed_tasks": DigCompSession.top_level_results.size(),
		"selected_tasks": DigCompSession.selection_order.size(),
	}


func _record_hub_entry() -> void:
	var event_name := "hub_returned" if not DigCompSession.selection_order.is_empty() else "hub_entered"
	var experiment := get_node_or_null("/root/ExperimentSession")
	if experiment:
		experiment.call("record_event", event_name, "digcomp_hub", {"completed_levels": DigCompSession.top_level_results.size(), "selection_order": DigCompSession.selection_order.duplicate()})


func _on_portal_near(body: Node3D, level_id: String) -> void:
	if body != player or _portal_locked:
		return
	active_portal_id = level_id
	var portal: Node = portal_nodes.get(level_id)
	if portal:
		portal.call("set_player_near", true)
	_show_nearby_task_card(level_id)


func _on_portal_left(body: Node3D, level_id: String) -> void:
	if body != player:
		return
	var portal: Node = portal_nodes.get(level_id)
	if portal:
		portal.call("set_player_near", false)
	if active_portal_id == level_id:
		active_portal_id = ""
		_hide_nearby_task_card()


func _show_nearby_task_card(level_id: String) -> void:
	if not is_instance_valid(portal_card):
		return
	var guide: Dictionary = LEVEL_GUIDES.get(level_id, {})
	if guide.is_empty():
		return
	var accent: Color = guide.get("color", Color("61e3d7"))
	portal_number_label.text = String(guide.get("number", "")) + "  ·  当前任务"
	portal_number_label.add_theme_color_override("font_color", accent)
	portal_title_label.text = String(guide.get("title", "任务"))
	portal_description_label.text = String(guide.get("objective", ""))
	var difficulty: String = String({"level_1_party_campaign":"2 / 3", "level_2_puzzle":"1 / 3", "level_3_matching":"2 / 3", "level_4_image_judgment":"2 / 3"}.get(level_id, "2 / 3"))
	portal_meta_label.text = "难度  %s     预计  %s" % [difficulty, String(guide.get("duration", ""))]
	portal_action_label.add_theme_stylebox_override("normal", _panel_style(Color(accent.r * 0.18, accent.g * 0.18, accent.b * 0.18, 0.96), 11, accent, 0))
	portal_card.add_theme_stylebox_override("panel", _panel_style(Color(0.012, 0.055, 0.10, 0.94), 18, accent, 12))
	if _portal_card_tween and _portal_card_tween.is_valid():
		_portal_card_tween.kill()
	portal_card.visible = true
	portal_card.position = Vector2(18, -118)
	portal_card.modulate.a = 0.0
	_portal_card_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_portal_card_tween.tween_property(portal_card, "position", Vector2(-294, -118), 0.24)
	_portal_card_tween.tween_property(portal_card, "modulate:a", 1.0, 0.18)


func _hide_nearby_task_card() -> void:
	if not is_instance_valid(portal_card) or not portal_card.visible:
		return
	if _portal_card_tween and _portal_card_tween.is_valid():
		_portal_card_tween.kill()
	_portal_card_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_portal_card_tween.tween_property(portal_card, "position", Vector2(18, -118), 0.20)
	_portal_card_tween.tween_property(portal_card, "modulate:a", 0.0, 0.15)
	_portal_card_tween.chain().tween_callback(func() -> void: portal_card.visible = false)


func _show_control_tutorial() -> void:
	if not is_instance_valid(tutorial_panel):
		return
	tutorial_panel.visible = true
	tutorial_panel.modulate.a = 1.0


func _release_hub_focus() -> void:
	get_viewport().gui_release_focus()
	if player and not _portal_locked and not is_instance_valid(instruction_overlay):
		player.set_controls_enabled(true)


func _show_hub_help() -> void:
	var guide := {
		"number":"开始", "title":"欢迎来到能力探索总部", "tag":"自由选择 · 四项任务 · AI全程可用", "color":Color("61e3d7"),
		"objective":"在大厅选择四项任务，完成后系统会综合知识题与游戏行为生成五领域画像。",
		"steps":["使用 WASD 移动，SPACE 跳跃，SHIFT 冲刺", "靠近发光任务台后按 E 进入，按 F 查看详细说明", "遇到困难可打开AI助手；主动组还可能收到策略邀请"],
		"measure":"正式分数会在四项任务全部完成后显示", "duration":"完整流程约 25–35 分钟"
	}
	_show_guide_overlay(guide, "")


func _show_level_guide(level_id: String) -> void:
	if _portal_locked or is_instance_valid(instruction_overlay):
		return
	var guide: Dictionary = LEVEL_GUIDES.get(level_id, {})
	if guide.is_empty():
		_start_level(level_id)
		return
	_show_guide_overlay(guide, level_id)


func _show_guide_overlay(guide: Dictionary, level_id: String) -> void:
	if is_instance_valid(instruction_overlay) or not is_instance_valid(hub_hud_root):
		return
	pending_level_id = level_id
	if player:
		player.controls_enabled = false
	instruction_overlay = Control.new()
	instruction_overlay.name = "MissionGuideOverlay"
	instruction_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	instruction_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	instruction_overlay.z_index = 60
	hub_hud_root.add_child(instruction_overlay)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.005, 0.025, 0.055, 0.82)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	instruction_overlay.add_child(shade)
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.position = Vector2(-385, -260)
	card.size = Vector2(770, 520)
	var accent: Color = guide.get("color", Color("61e3d7"))
	card.add_theme_stylebox_override("panel", _panel_style(Color(0.018, 0.065, 0.115, 0.98), 25, accent, 22))
	instruction_overlay.add_child(card)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 25)
	card.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)
	var eyebrow := Label.new()
	eyebrow.text = "任务说明  ·  %s" % String(guide.get("number", ""))
	eyebrow.add_theme_font_size_override("font_size", 14)
	eyebrow.add_theme_color_override("font_color", accent)
	content.add_child(eyebrow)
	var title := Label.new()
	title.text = String(guide.get("title", "任务说明"))
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("f1fbff"))
	content.add_child(title)
	var tag := Label.new()
	tag.text = String(guide.get("tag", ""))
	tag.add_theme_font_size_override("font_size", 14)
	tag.add_theme_color_override("font_color", Color("9fc2d4"))
	content.add_child(tag)
	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(0, 2)
	divider.color = Color(accent.r, accent.g, accent.b, 0.55)
	content.add_child(divider)
	var objective_title := Label.new()
	objective_title.text = "本次任务"
	objective_title.add_theme_font_size_override("font_size", 15)
	objective_title.add_theme_color_override("font_color", accent.lightened(0.15))
	content.add_child(objective_title)
	var objective := Label.new()
	objective.text = String(guide.get("objective", ""))
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective.add_theme_font_size_override("font_size", 18)
	objective.add_theme_color_override("font_color", Color("dfedf5"))
	content.add_child(objective)
	var step_row := HBoxContainer.new()
	step_row.add_theme_constant_override("separation", 10)
	content.add_child(step_row)
	var steps: Array = guide.get("steps", [])
	for step_index in range(steps.size()):
		var step_panel := PanelContainer.new()
		step_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		step_panel.custom_minimum_size = Vector2(0, 104)
		step_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.035, 0.12, 0.18, 0.94), 14, Color(accent.r, accent.g, accent.b, 0.45), 0))
		step_row.add_child(step_panel)
		var step_box := VBoxContainer.new()
		step_box.add_theme_constant_override("separation", 5)
		step_panel.add_child(step_box)
		var step_number := Label.new()
		step_number.text = "%02d" % (step_index + 1)
		step_number.add_theme_font_size_override("font_size", 20)
		step_number.add_theme_color_override("font_color", accent)
		step_box.add_child(step_number)
		var step_label := Label.new()
		step_label.text = String(steps[step_index])
		step_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		step_label.add_theme_font_size_override("font_size", 13)
		step_label.add_theme_color_override("font_color", Color("c9dde8"))
		step_box.add_child(step_label)
	var info_row := HBoxContainer.new()
	info_row.add_theme_constant_override("separation", 18)
	content.add_child(info_row)
	var measure := Label.new()
	measure.text = "记录内容  %s" % String(guide.get("measure", ""))
	measure.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	measure.add_theme_font_size_override("font_size", 13)
	measure.add_theme_color_override("font_color", Color("8fb3c8"))
	info_row.add_child(measure)
	var duration := Label.new()
	duration.text = "预计时长  %s" % String(guide.get("duration", ""))
	duration.add_theme_font_size_override("font_size", 13)
	duration.add_theme_color_override("font_color", Color("8fb3c8"))
	info_row.add_child(duration)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 10)
	content.add_child(actions)
	if not level_id.is_empty():
		var cancel := Button.new()
		cancel.text = "暂不进入"
		cancel.custom_minimum_size = Vector2(140, 48)
		cancel.focus_mode = Control.FOCUS_NONE
		cancel.add_theme_color_override("font_color", Color("c8dbe6"))
		cancel.add_theme_color_override("font_hover_color", Color.WHITE)
		cancel.add_theme_stylebox_override("normal", _panel_style(Color(0.035, 0.105, 0.16, 0.96), 13, Color("355a70"), 0))
		cancel.add_theme_stylebox_override("hover", _panel_style(Color(0.06, 0.16, 0.22, 1.0), 13, Color("78a7bb"), 0))
		cancel.pressed.connect(_close_guide)
		actions.add_child(cancel)
	var confirm := Button.new()
	confirm.text = "开始探索" if level_id.is_empty() else "进入任务"
	confirm.custom_minimum_size = Vector2(180, 48)
	confirm.focus_mode = Control.FOCUS_NONE
	confirm.add_theme_color_override("font_color", Color("071d25"))
	confirm.add_theme_color_override("font_hover_color", Color("071d25"))
	confirm.add_theme_stylebox_override("normal", _panel_style(accent, 13, accent.lightened(0.18), 0))
	confirm.add_theme_stylebox_override("hover", _panel_style(accent.lightened(0.12), 13, Color.WHITE, 0))
	confirm.pressed.connect(_confirm_guide)
	actions.add_child(confirm)
	card.modulate.a = 0.0
	card.scale = Vector2(0.92, 0.92)
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "modulate:a", 1.0, 0.24)
	tween.tween_property(card, "scale", Vector2.ONE, 0.34)


func _confirm_guide() -> void:
	var level_id := pending_level_id
	if level_id.is_empty():
		_close_guide(true)
	else:
		_close_guide(false)
		_start_level(level_id)


func _close_guide(restore_controls: bool = true) -> void:
	if is_instance_valid(instruction_overlay):
		instruction_overlay.queue_free()
	instruction_overlay = null
	pending_level_id = ""
	if restore_controls and player:
		var ai_open := is_instance_valid(assistant_panel) and bool(assistant_panel.get("_open"))
		player.controls_enabled = not ai_open and not _portal_locked
	call_deferred("_release_hub_focus")


func _start_level(level_id: String) -> void:
	if _portal_locked:
		return
	_portal_locked = true
	if player:
		player.controls_enabled = false
	if scaffold_controller:
		scaffold_controller.end_run()
	var change_error := DigCompSession.start_top_level(level_id)
	if change_error != OK:
		_portal_locked = false
		if player:
			player.controls_enabled = true
		push_error("Unable to enter DigComp task %s: %s" % [level_id, error_string(change_error)])


func _on_ai_open_changed(open: bool) -> void:
	if player:
		player.controls_enabled = not open and not _portal_locked and not is_instance_valid(instruction_overlay)
	if not open:
		call_deferred("_release_hub_focus")


func _profile_progress_text() -> String:
	if not DigCompSession.all_top_levels_complete():
		return "五领域证据正在积累；完成四项任务后显示正式分数。"
	var profile: Dictionary = DigCompSession.get_profile()
	return "综合数字能力：%.1f / 100" % float(profile.get("overall_score", 0.0))


func _final_profile_text() -> String:
	var profile: Dictionary = DigCompSession.get_profile()
	var lines: Array[String] = ["五领域画像（正式结果）"]
	for domain in Array(profile.get("domains", [])):
		lines.append("%s：%.1f　%s" % [String(domain.get("title", "")), float(domain.get("score", 0.0)), "★".repeat(int(domain.get("stars", 1)))])
	lines.append("综合：%.1f / 100" % float(profile.get("overall_score", 0.0)))
	lines.append("正在生成 manifest 并保存，收到成功确认后再关闭页面。")
	return "\n".join(lines)


func _panel_style(color: Color, radius: int = 18, border_color: Color = Color.TRANSPARENT, shadow_size: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	if border_color.a > 0.0:
		style.border_width_left = 1
		style.border_width_right = 1
		style.border_width_top = 1
		style.border_width_bottom = 1
		style.border_color = border_color
	if shadow_size > 0:
		style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
		style.shadow_size = shadow_size
	return style


func _task_style(color: Color, border_color: Color, border_width: int) -> StyleBoxFlat:
	var style := _panel_style(color, 13, border_color)
	style.border_width_left = 5
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.content_margin_left = 13
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style


func _chip_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.22, 0.34, 0.9)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


func _bar_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_left = 7
	style.corner_radius_bottom_right = 7
	return style
