class_name MainMenu
extends Control

const UI_FONT: FontFile = preload("res://assets/ui/fonts/noto_sans_sc_ui_600.ttf")
const BACKDROP_SCRIPT := preload("res://scripts/ui/main_menu_backdrop.gd")

var level_buttons: Dictionary = {}
var campaign_button: Button
var hub_button: Button
var _buttons_locked: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var web_bridge := get_node_or_null("/root/ExperimentWebBridge")
	if web_bridge and bool(web_bridge.call("is_production")):
		_build_production_waiting()
		set_process(true)
	else:
		_build_menu()
		set_process(false)


func _process(_delta: float) -> void:
	var web_bridge := get_node_or_null("/root/ExperimentWebBridge")
	if web_bridge and String(web_bridge.call("consent_status")) == "accepted":
		set_process(false)
		_start_hub()


func _unhandled_input(event: InputEvent) -> void:
	if _buttons_locked or not event is InputEventKey or not event.pressed or event.echo:
		return
	var levels := CampaignSession.get_levels_in_menu_order()
	var selected_index := -1
	match event.physical_keycode:
		KEY_1, KEY_KP_1:
			selected_index = 0
		KEY_2, KEY_KP_2:
			selected_index = 1
		KEY_3, KEY_KP_3:
			selected_index = 2
		KEY_4, KEY_KP_4:
			selected_index = 3
		KEY_5, KEY_KP_5, KEY_C:
			_start_campaign()
		KEY_6, KEY_KP_6, KEY_H:
			_start_hub()
	if selected_index >= 0 and selected_index < levels.size():
		_start_single_level(String(levels[selected_index].get("id", "")))


func _build_menu() -> void:
	var theme := Theme.new()
	theme.default_font = UI_FONT
	theme.default_font_size = 18
	self.theme = theme

	var background: Control = BACKDROP_SCRIPT.new() as Control
	background.name = "Background"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var top_bar := HBoxContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_left = 36
	top_bar.offset_top = 24
	top_bar.offset_right = -36
	top_bar.offset_bottom = 72
	add_child(top_bar)
	var brand := _label("DIGCOMP 3.0  //  DIGITAL COMPETENCE MISSION", 15, Color("62e8dc"))
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(brand)
	var build_label := _label("GODOT WEB  ·  FOUR TASK STUDY", 12, Color("789ab2"))
	build_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top_bar.add_child(build_label)

	var stage := HBoxContainer.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.offset_left = 64
	stage.offset_top = 92
	stage.offset_right = -64
	stage.offset_bottom = -54
	stage.add_theme_constant_override("separation", 28)
	add_child(stage)

	var hero := PanelContainer.new()
	hero.name = "MenuCard"
	hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero.add_theme_stylebox_override("panel", _stylebox(Color(0.025, 0.09, 0.16, 0.91), 26, Color("2daea9"), 1))
	stage.add_child(hero)
	var hero_margin := MarginContainer.new()
	hero_margin.add_theme_constant_override("margin_left", 40)
	hero_margin.add_theme_constant_override("margin_right", 40)
	hero_margin.add_theme_constant_override("margin_top", 42)
	hero_margin.add_theme_constant_override("margin_bottom", 38)
	hero.add_child(hero_margin)
	var hero_content := VBoxContainer.new()
	hero_content.add_theme_constant_override("separation", 15)
	hero_margin.add_child(hero_content)
	var kicker := _label("能力探索计划  /  正式实验入口", 15, Color("62e8dc"))
	hero_content.add_child(kicker)
	var title := _label("进入数字能力\n探索总部", 49, Color("f2fbff"))
	title.add_theme_constant_override("line_spacing", 2)
	hero_content.add_child(title)
	var subtitle := _label("在四个可自由选择的任务中收集证据，\n完成后生成五领域 DigComp 3.0 能力画像。", 18, Color("a9c7d8"))
	subtitle.add_theme_constant_override("line_spacing", 5)
	hero_content.add_child(subtitle)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 7)
	hero_content.add_child(chips)
	for chip_text in ["四类小游戏", "AI全程陪伴", "自动保存记录"]:
		var chip := _label("  %s  " % chip_text, 13, Color("c9f4ef"))
		chip.add_theme_stylebox_override("normal", _stylebox(Color(0.06, 0.21, 0.25, 0.86), 10, Color(0.20, 0.72, 0.67, 0.55), 1))
		chips.add_child(chip)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero_content.add_child(spacer)
	hub_button = _menu_button("进入正式能力大厅     START", Color("52dbc9"), Color("082126"))
	hub_button.name = "HubButton"
	hub_button.custom_minimum_size.y = 74
	hub_button.add_theme_font_size_override("font_size", 23)
	hub_button.pressed.connect(_start_hub)
	hero_content.add_child(hub_button)
	var formal_hint := _label("正式链接将自动进入此流程；支持电脑 Chrome / Edge。", 13, Color("789ab2"))
	hero_content.add_child(formal_hint)

	var dev_panel := PanelContainer.new()
	dev_panel.custom_minimum_size.x = 440
	dev_panel.add_theme_stylebox_override("panel", _stylebox(Color(0.025, 0.075, 0.14, 0.94), 24, Color("315878"), 1))
	stage.add_child(dev_panel)
	var dev_margin := MarginContainer.new()
	dev_margin.add_theme_constant_override("margin_left", 26)
	dev_margin.add_theme_constant_override("margin_right", 26)
	dev_margin.add_theme_constant_override("margin_top", 27)
	dev_margin.add_theme_constant_override("margin_bottom", 24)
	dev_panel.add_child(dev_margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	dev_margin.add_child(content)
	content.add_child(_label("开发测试入口", 25, Color("effaff")))
	content.add_child(_label("用于单关调试，不进入正式四任务测量。", 13, Color("7fa5bc")))

	for level in CampaignSession.get_levels_in_menu_order():
		var level_id := String(level.get("id", ""))
		var button := _menu_button(
			"%d    %s" % [int(level.get("menu_order", 0)), String(level.get("title", "AI训练"))],
			Color("3176c7")
		)
		button.name = "Level_%s" % level_id
		button.tooltip_text = String(level.get("detail", ""))
		button.custom_minimum_size = Vector2(380.0, 47.0)
		button.add_theme_font_size_override("font_size", 15)
		button.pressed.connect(_start_single_level.bind(level_id))
		content.add_child(button)
		level_buttons[level_id] = button

	campaign_button = _menu_button("5    派对流程 · 连续挑战四关", Color("ecb947"), Color("2e2440"))
	campaign_button.name = "CampaignButton"
	campaign_button.custom_minimum_size = Vector2(380.0, 47.0)
	campaign_button.add_theme_font_size_override("font_size", 15)
	campaign_button.pressed.connect(_start_campaign)
	content.add_child(campaign_button)

	var hint := _label("快捷键 1–5：开发测试   ·   6 / H：正式大厅", 12, Color("789ab2"))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(hint)


func _build_production_waiting() -> void:
	var theme := Theme.new()
	theme.default_font = UI_FONT
	theme.default_font_size = 18
	self.theme = theme
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color("0b1832")
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var label := _label("正在准备四关实验流程…\n请先阅读并选择页面上的参与说明", 24, Color("d9f7f4"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(label)


func _start_single_level(level_id: String) -> void:
	if _buttons_locked:
		return
	_set_buttons_locked(true)
	var change_error := CampaignSession.start_single_level(level_id)
	if change_error != OK:
		push_error("Unable to start single level %s: %s" % [level_id, error_string(change_error)])
		_set_buttons_locked(false)


func _start_campaign() -> void:
	if _buttons_locked:
		return
	_set_buttons_locked(true)
	var change_error := CampaignSession.start_campaign()
	if change_error != OK:
		push_error("Unable to start campaign: %s" % error_string(change_error))
		_set_buttons_locked(false)


func _start_hub() -> void:
	if _buttons_locked:
		return
	_set_buttons_locked(true)
	var change_error := DigCompSession.start_hub(true)
	if change_error != OK:
		push_error("Unable to start DigComp hub: %s" % error_string(change_error))
		_set_buttons_locked(false)


func _set_buttons_locked(locked: bool) -> void:
	_buttons_locked = locked
	for button in level_buttons.values():
		(button as Button).disabled = locked
	if campaign_button:
		campaign_button.disabled = locked
	if hub_button:
		hub_button.disabled = locked


func _menu_button(text_value: String, color: Color, font_color: Color = Color("ffffff")) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(560.0, 58.0)
	button.add_theme_font_size_override("font_size", 19)
	button.add_theme_color_override("font_color", font_color)
	button.add_theme_color_override("font_hover_color", font_color)
	button.add_theme_stylebox_override("normal", _stylebox(color.darkened(0.18), 15, color, 2))
	button.add_theme_stylebox_override("hover", _stylebox(color, 15, color.lightened(0.16), 2))
	button.add_theme_stylebox_override("pressed", _stylebox(color.darkened(0.3), 15, color, 2))
	button.add_theme_stylebox_override("disabled", _stylebox(Color("33435d"), 15, Color("53647c"), 1))
	return button


func _label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _stylebox(color: Color, radius: int, border_color: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.border_color = border_color
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	return style
