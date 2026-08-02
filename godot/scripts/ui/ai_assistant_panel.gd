class_name AiAssistantPanel
extends Control

signal open_changed(open: bool)
signal reminder_decided(accepted: bool)

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
var _open: bool = false
var _offer_mode: bool = false


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


func show_help_offer() -> bool:
	if not is_available() or _open:
		return false
	_offer_mode = true
	title_label.text = "需要一点提示吗？"
	response_label.text = "你已经连续遇到几次困难。AI 助手可以根据当前进度给一个分层提示，不会直接公布答案。"
	accept_button.visible = true
	decline_button.visible = true
	input.visible = false
	send_button.visible = false
	_set_open(true)
	return true


func open_manual() -> void:
	if not is_available():
		return
	_show_chat()
	_set_open(true)


func close() -> void:
	_set_open(false)


func reset_run() -> void:
	close()
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
	decline_button = Button.new()
	decline_button.text = "继续挑战"
	decline_button.pressed.connect(_decline_offer)
	actions.add_child(decline_button)
	accept_button = Button.new()
	accept_button.text = "获取提示"
	accept_button.pressed.connect(_accept_offer)
	actions.add_child(accept_button)
	send_button = Button.new()
	send_button.text = "发送追问"
	send_button.pressed.connect(_send_message)
	actions.add_child(send_button)


func _show_chat() -> void:
	_offer_mode = false
	title_label.text = "AI 学习助手"
	accept_button.visible = false
	decline_button.visible = false
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
	reminder_decided.emit(true)
	_show_chat()
	_send(AUTO_MESSAGE, "hurt_threshold")


func _decline_offer() -> void:
	reminder_decided.emit(false)
	close()


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
