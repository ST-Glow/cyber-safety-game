class_name MainMenu
extends Control

const UI_FONT: FontFile = preload("res://assets/ui/fonts/noto_sans_sc_ui_600.ttf")

var level_buttons: Dictionary = {}
var campaign_button: Button
var _buttons_locked: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_menu()


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
	if selected_index >= 0 and selected_index < levels.size():
		_start_single_level(String(levels[selected_index].get("id", "")))


func _build_menu() -> void:
	var theme := Theme.new()
	theme.default_font = UI_FONT
	theme.default_font_size = 18
	self.theme = theme

	var background := ColorRect.new()
	background.name = "Background"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color("0b1832")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var glow := ColorRect.new()
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.color = Color(0.15, 0.82, 0.82, 0.08)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.add_child(glow)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.name = "MenuCard"
	panel.custom_minimum_size = Vector2(660.0, 650.0)
	panel.add_theme_stylebox_override("panel", _stylebox(Color("132747"), 28, Color("50dfd4"), 2))
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 42)
	margin.add_theme_constant_override("margin_right", 42)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)

	var kicker := _label("GODOT · AI TRAINING ARENA", 16, Color("69eee2"))
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(kicker)
	var title := _label("AI训练场大挑战", 38, Color("ffffff"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	var subtitle := _label("选择单关自由练习，或进入四关连续派对流程", 17, Color("c6d9ef"))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(subtitle)

	var separator := HSeparator.new()
	separator.add_theme_constant_override("separation", 8)
	content.add_child(separator)

	for level in CampaignSession.get_levels_in_menu_order():
		var level_id := String(level.get("id", ""))
		var button := _menu_button(
			"%d    %s" % [int(level.get("menu_order", 0)), String(level.get("title", "AI训练"))],
			Color("3176c7")
		)
		button.name = "Level_%s" % level_id
		button.tooltip_text = String(level.get("detail", ""))
		button.pressed.connect(_start_single_level.bind(level_id))
		content.add_child(button)
		level_buttons[level_id] = button

	campaign_button = _menu_button("5    派对流程 · 连续挑战四关", Color("ecb947"), Color("2e2440"))
	campaign_button.name = "CampaignButton"
	campaign_button.pressed.connect(_start_campaign)
	content.add_child(campaign_button)

	var hint := _label("鼠标点击或按 1–5 选择 · F6 仍可在编辑器直接运行单关", 14, Color("91a9c7"))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(hint)


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


func _set_buttons_locked(locked: bool) -> void:
	_buttons_locked = locked
	for button in level_buttons.values():
		(button as Button).disabled = locked
	if campaign_button:
		campaign_button.disabled = locked


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
