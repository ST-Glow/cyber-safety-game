class_name AiAssistantPanel
extends Control

signal open_changed(open: bool)
signal reminder_decided(choice: String)
signal manual_opened

const UI_FONT: FontFile = preload("res://assets/ui/fonts/noto_sans_sc_ui_600.ttf")
const AUTO_MESSAGE := "我连续遇到了几次困难，请根据当前进度给我一个简短提示，不要直接给出选择题答案。"

var level_id: String = ""
var state_provider: Callable
var assistant_button: Button
var overlay: ColorRect
var content_panel: PanelContainer
var title_label: Label
var response_label: Label
var input: LineEdit
var send_button: Button
var accept_button: Button
var decline_button: Button
var later_button: Button
var invitation_panel: PanelContainer
var invitation_label: Label
var _open: bool = false
var _offer_mode: bool = false
var _offer_context: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	var service := _service()
	service.configuration_changed.connect(_on_configuration_changed)
	service.request_started.connect(_on_request_started)
	service.reply_received.connect(_on_reply_received)
	service.request_failed.connect(_on_request_failed)
	_on_configuration_changed(service.is_configured(), service.configuration_diagnostic())


func configure(value: String, provider: Callable) -> void:
	level_id = value
	state_provider = provider


func is_available() -> bool:
	return _service().is_configured()


func set_gameplay_available(value: bool) -> void:
	assistant_button.visible = value and _service().is_configured()
	if not value:
		close()


func show_help_offer(context: Dictionary = {}) -> bool:
	if not is_available() or _open or is_invitation_visible():
		return false
	_offer_mode = true
	_offer_context = context.duplicate(true)
	var reason := String(context.get("trigger_reason", ""))
	invitation_label.text = "需要一点提示吗？\n%s" % _offer_reason_text(reason)
	invitation_panel.visible = true
	return true


func hide_help_offer() -> void:
	if invitation_panel:
		invitation_panel.visible = false
	_offer_mode = false
	_offer_context.clear()


func is_invitation_visible() -> bool:
	return invitation_panel != null and invitation_panel.visible


func open_manual() -> void:
	if not is_available():
		return
	hide_help_offer()
	_show_chat()
	manual_opened.emit()
	_set_open(true)


func close() -> void:
	_set_open(false)


func reset_run() -> void:
	close()
	hide_help_offer()
	response_label.text = "说说你卡在哪里，我会先给一个观察方向。"
	input.clear()


func _build_ui() -> void:
	var theme := Theme.new()
	theme.default_font = UI_FONT
	theme.default_font_size = 17
	self.theme = theme
	assistant_button = Button.new()
	assistant_button.name = "AssistantButton"
	assistant_button.text = "AI 助手"
	assistant_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	assistant_button.position = Vector2(-174.0, -94.0)
	assistant_button.size = Vector2(150.0, 56.0)
	assistant_button.add_theme_stylebox_override("normal", _style(Color("776af5"), 16))
	assistant_button.add_theme_stylebox_override("hover", _style(Color("8c82ff"), 16))
	assistant_button.pressed.connect(open_manual)
	add_child(assistant_button)

	invitation_panel = PanelContainer.new()
	invitation_panel.name = "ScaffoldInvitation"
	invitation_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	invitation_panel.position = Vector2(-430.0, -260.0)
	invitation_panel.size = Vector2(405.0, 150.0)
	invitation_panel.add_theme_stylebox_override("panel", _style(Color("172447"), 18))
	invitation_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var invitation_margin := MarginContainer.new()
	invitation_margin.add_theme_constant_override("margin_left", 18)
	invitation_margin.add_theme_constant_override("margin_right", 18)
	invitation_margin.add_theme_constant_override("margin_top", 14)
	invitation_margin.add_theme_constant_override("margin_bottom", 14)
	invitation_panel.add_child(invitation_margin)
	var invitation_box := VBoxContainer.new()
	invitation_box.add_theme_constant_override("separation", 10)
	invitation_margin.add_child(invitation_box)
	invitation_label = Label.new()
	invitation_label.text = "需要一点提示吗？"
	invitation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	invitation_label.add_theme_font_size_override("font_size", 17)
	invitation_box.add_child(invitation_label)
	var invitation_actions := HBoxContainer.new()
	invitation_actions.add_theme_constant_override("separation", 8)
	invitation_box.add_child(invitation_actions)
	accept_button = Button.new()
	accept_button.text = "需要提示"
	accept_button.pressed.connect(_accept_offer)
	invitation_actions.add_child(accept_button)
	decline_button = Button.new()
	decline_button.text = "我想自己试试"
	decline_button.pressed.connect(_decline_offer)
	invitation_actions.add_child(decline_button)
	later_button = Button.new()
	later_button.text = "稍后提醒"
	later_button.pressed.connect(_dismiss_offer)
	invitation_actions.add_child(later_button)
	invitation_panel.visible = false
	add_child(invitation_panel)

	overlay = ColorRect.new()
	overlay.name = "AssistantOverlay"
	overlay.color = Color(0.015, 0.025, 0.07, 0.72)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	add_child(overlay)
	content_panel = PanelContainer.new()
	content_panel.anchor_left = 0.5
	content_panel.anchor_top = 0.5
	content_panel.anchor_right = 0.5
	content_panel.anchor_bottom = 0.5
	content_panel.offset_left = -320.0
	content_panel.offset_top = -235.0
	content_panel.offset_right = 320.0
	content_panel.offset_bottom = 235.0
	content_panel.add_theme_stylebox_override("panel", _style(Color("101936"), 26))
	overlay.add_child(content_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_%s" % side, 32)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 26)
	content_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	margin.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	title_label = Label.new()
	title_label.text = "AI 学习助手"
	title_label.add_theme_font_size_override("font_size", 25)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	var close_button := Button.new()
	close_button.text = "关闭"
	close_button.pressed.connect(close)
	header.add_child(close_button)
	response_label = Label.new()
	response_label.text = "说说你卡在哪里，我会先给一个观察方向。"
	response_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	response_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	response_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(response_label)
	input = LineEdit.new()
	input.placeholder_text = "追问当前关卡（不要输入姓名等个人信息）"
	input.max_length = 300
	input.text_submitted.connect(func(_value: String) -> void: _send_message())
	box.add_child(input)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 12)
	box.add_child(actions)
	send_button = Button.new()
	send_button.text = "发送追问"
	send_button.pressed.connect(_send_message)
	actions.add_child(send_button)


func _show_chat() -> void:
	_offer_mode = false
	title_label.text = "AI 学习助手"
	input.visible = true
	send_button.visible = true


func _set_open(value: bool) -> void:
	if _open == value:
		return
	_open = value
	overlay.visible = value
	assistant_button.text = "返回游戏" if value else "AI 助手"
	open_changed.emit(value)


func _accept_offer() -> void:
	var trigger := String(_offer_context.get("trigger_reason", "no_progress"))
	reminder_decided.emit("accepted")
	invitation_panel.visible = false
	_show_chat()
	_set_open(true)
	_send(AUTO_MESSAGE, trigger)


func _decline_offer() -> void:
	reminder_decided.emit("rejected")
	hide_help_offer()


func _dismiss_offer() -> void:
	reminder_decided.emit("dismissed")
	hide_help_offer()


func _send_message() -> void:
	var message := input.text.strip_edges()
	if message.is_empty():
		return
	input.clear()
	_send(message, "manual")


func _send(message: String, trigger: String) -> void:
	var state: Dictionary = state_provider.call() if state_provider.is_valid() else {}
	_service().send_hint(level_id, trigger, state, message)


func _on_configuration_changed(configured: bool, diagnostic: String) -> void:
	assistant_button.visible = configured
	assistant_button.disabled = not configured
	assistant_button.tooltip_text = "" if configured else diagnostic
	if not configured:
		close()


func _on_request_started(request_level_id: String) -> void:
	if request_level_id != level_id:
		return
	response_label.text = "正在根据当前进度生成提示……"
	input.editable = false
	send_button.disabled = true


func _on_reply_received(request_level_id: String, reply: String) -> void:
	if request_level_id != level_id:
		return
	response_label.text = reply
	input.editable = true
	send_button.disabled = false


func _on_request_failed(request_level_id: String, message: String) -> void:
	if request_level_id != level_id:
		return
	response_label.text = message
	input.editable = true
	send_button.disabled = false


func _style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.border_color = Color(1, 1, 1, 0.18)
	style.set_border_width_all(1)
	return style


func _service() -> Node:
	return get_node("/root/AiAssistantService")


func _offer_reason_text(reason: String) -> String:
	match reason:
		"idle":
			return "如果你正在思考，可以先继续尝试，也可以让我澄清当前规则。"
		"no_progress":
			return "看起来这一段暂时没有新的进展，我可以给一个简短方向。"
		"quiz_error":
			return "这道题已经尝试了几次，我可以帮你梳理判断思路。"
		"repeated_failure", "repeated_strategy":
			return "这一处连续遇到困难，我可以提供一个不泄露答案的小提示。"
	return "我可以根据当前目标提供一个简短提示。"
