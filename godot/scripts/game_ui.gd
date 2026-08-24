class_name GameUI
extends CanvasLayer

signal start_requested
signal restart_requested
signal next_level_requested
signal quiz_choice_selected(selected_index)
signal assistant_toggled(open)

const CLICK_SOUND := preload("res://assets/audio/kenney_ui_pack/click-a.ogg")
const CONFIRM_SOUND := preload("res://assets/audio/interface_sfx_pack_1/confirm_tones/style6/confirm_style_6_001.ogg")
const ERROR_SOUND := preload("res://assets/audio/interface_sfx_pack_1/error_tones/style1/error_style_1_001.ogg")
const UI_FONT: FontFile = preload("res://assets/ui/fonts/noto_sans_sc_ui_600.ttf")
const AI_ASSISTANT_PANEL_SCRIPT := preload("res://scripts/ui/ai_assistant_panel.gd")

var root: Control
var ready_overlay: ColorRect
var quiz_overlay: ColorRect
var result_overlay: ColorRect
var assistant_widget
var progress_bar: ProgressBar
var progress_label: Label
var time_label: Label
var score_label: Label
var dash_label: Label
var quiz_title: Label
var quiz_prompt: Label
var quiz_feedback: Label
var option_buttons: Array[Button] = []
var result_stars: Label
var result_score: Label
var result_metrics: Label
var next_button: Button
var click_audio: AudioStreamPlayer
var confirm_audio: AudioStreamPlayer
var error_audio: AudioStreamPlayer
var _quiz_accepts_input: bool = false
var _last_hud_percent: int = -1
var _last_hud_elapsed_second: int = -1
var _last_hud_score: int = -1
var _last_hud_dash_key: int = -2


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_build_root()
	_build_hud()
	_build_ready_overlay()
	_build_quiz_overlay()
	_build_result_overlay()
	_build_assistant()
	_build_audio()


func _unhandled_input(event: InputEvent) -> void:
	if not _quiz_accepts_input or not quiz_overlay.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var selected := -1
		match event.physical_keycode:
			KEY_1, KEY_KP_1:
				selected = 0
			KEY_2, KEY_KP_2:
				selected = 1
			KEY_3, KEY_KP_3:
				selected = 2
		if selected >= 0:
			_on_option_pressed(selected)
			get_viewport().set_input_as_handled()


func show_ready() -> void:
	ready_overlay.visible = true
	quiz_overlay.visible = false
	result_overlay.visible = false
	assistant_widget.reset_run()
	assistant_widget.set_gameplay_available(true)
	_quiz_accepts_input = false
	update_hud(0.0, 0.0, 40, 0.0, 2.5)


func show_running() -> void:
	ready_overlay.visible = false
	quiz_overlay.visible = false
	result_overlay.visible = false
	assistant_widget.reset_run()
	assistant_widget.set_gameplay_available(true)
	_quiz_accepts_input = false


func configure_result_action(campaign_mode: bool) -> void:
	if next_button:
		next_button.text = "进入下一关" if campaign_mode else "返回主菜单"


func update_hud(progress: float, elapsed: float, score: int, dash_cooldown_left: float, dash_cooldown: float) -> void:
	var percent := clampi(int(round(progress * 100.0)), 0, 100)
	if percent != _last_hud_percent:
		_last_hud_percent = percent
		progress_bar.value = percent
		progress_label.text = "赛道进度  %d%%" % percent
	var elapsed_second := maxi(0, int(elapsed))
	if elapsed_second != _last_hud_elapsed_second:
		_last_hud_elapsed_second = elapsed_second
		time_label.text = "时间  %02d:%02d" % [elapsed_second / 60, elapsed_second % 60]
	if score != _last_hud_score:
		_last_hud_score = score
		score_label.text = "过程表现  %d / 40" % score
	var dash_key := -1 if dash_cooldown_left <= 0.01 else int(round(dash_cooldown_left * 10.0))
	if dash_key != _last_hud_dash_key:
		_last_hud_dash_key = dash_key
		if dash_key < 0:
			dash_label.text = "冲刺  就绪"
			dash_label.modulate = Color("7bffd2")
		else:
			dash_label.text = "冲刺  %.1fs" % (float(dash_key) / 10.0)
			dash_label.modulate = Color("ffe77d")


func show_quiz(question: QuizQuestion) -> void:
	assistant_widget.set_gameplay_available(false)
	quiz_title.text = question.title
	quiz_prompt.text = question.prompt
	quiz_feedback.text = "选择你认为最准确的答案（鼠标点击或按数字键 1 / 2 / 3）"
	quiz_feedback.modulate = Color("b8c9e8")
	for index in range(option_buttons.size()):
		var button := option_buttons[index]
		button.text = "%d    %s" % [index + 1, question.options[index]]
		button.disabled = false
		_apply_option_style(button, "normal")
	quiz_overlay.visible = true
	_quiz_accepts_input = true


func show_wrong_answer(selected_index: int, explanation: String) -> void:
	_play_audio(error_audio)
	quiz_feedback.text = "再想一想：%s" % explanation
	quiz_feedback.modulate = Color("ffaaa3")
	for index in range(option_buttons.size()):
		option_buttons[index].disabled = false
		_apply_option_style(option_buttons[index], "wrong" if index == selected_index else "normal")
	_quiz_accepts_input = true


func show_result(result: Dictionary) -> void:
	_play_audio(confirm_audio)
	quiz_overlay.visible = false
	assistant_widget.set_gameplay_available(false)
	_quiz_accepts_input = false
	var star_count := int(result.get("stars", 1))
	result_stars.text = "★".repeat(star_count) + "☆".repeat(3 - star_count)
	result_score.text = "综合评分  %d / 100" % int(result.get("score", 0))
	result_metrics.text = "完成用时  %.1f 秒\n机关碰撞  %d 次\n其中跌落  %d 次\n答题尝试  %d 次" % [
		float(result.get("elapsed_seconds", 0.0)),
		int(result.get("obstacle_hits", 0)),
		int(result.get("falls", 0)),
		int(result.get("quiz_attempts", 0)),
	]
	result_overlay.visible = true


func _build_root() -> void:
	root = Control.new()
	root.name = "UIRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ui_theme := Theme.new()
	ui_theme.default_font = UI_FONT
	ui_theme.default_font_size = 19
	root.theme = ui_theme
	add_child(root)


func _build_hud() -> void:
	var stage_card := _make_panel("StageCard", Color(0.055, 0.09, 0.19, 0.88), 20)
	stage_card.anchor_left = 0.0
	stage_card.anchor_top = 0.0
	stage_card.anchor_right = 0.0
	stage_card.anchor_bottom = 0.0
	stage_card.offset_left = 22.0
	stage_card.offset_top = 20.0
	stage_card.offset_right = 292.0
	stage_card.offset_bottom = 104.0
	root.add_child(stage_card)
	var stage_margin := _wrap_margin(stage_card, 20, 13)
	var stage_box := VBoxContainer.new()
	stage_box.add_theme_constant_override("separation", 2)
	stage_margin.add_child(stage_box)
	var stage_kicker := _new_label("第 1 赛段", 15, Color("73ddff"))
	stage_box.add_child(stage_kicker)
	var stage_name := _new_label("AI 认知训练区", 24, Color("ffffff"))
	stage_box.add_child(stage_name)

	var progress_card := _make_panel("ProgressCard", Color(0.055, 0.09, 0.19, 0.88), 20)
	progress_card.anchor_left = 0.5
	progress_card.anchor_top = 0.0
	progress_card.anchor_right = 0.5
	progress_card.anchor_bottom = 0.0
	progress_card.offset_left = -235.0
	progress_card.offset_top = 20.0
	progress_card.offset_right = 235.0
	progress_card.offset_bottom = 104.0
	root.add_child(progress_card)
	var progress_margin := _wrap_margin(progress_card, 20, 12)
	var progress_box := VBoxContainer.new()
	progress_box.add_theme_constant_override("separation", 7)
	progress_margin.add_child(progress_box)
	progress_label = _new_label("赛道进度  0%", 17, Color("eaf6ff"))
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress_box.add_child(progress_label)
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(0.0, 16.0)
	progress_bar.show_percentage = false
	progress_bar.min_value = 0.0
	progress_bar.max_value = 100.0
	progress_bar.value = 0.0
	progress_bar.add_theme_stylebox_override("background", _stylebox(Color("263552"), 8, Color.TRANSPARENT, 0))
	progress_bar.add_theme_stylebox_override("fill", _stylebox(Color("42d6d1"), 8, Color.TRANSPARENT, 0))
	progress_box.add_child(progress_bar)

	var stats_card := _make_panel("StatsCard", Color(0.055, 0.09, 0.19, 0.88), 20)
	stats_card.anchor_left = 1.0
	stats_card.anchor_top = 0.0
	stats_card.anchor_right = 1.0
	stats_card.anchor_bottom = 0.0
	stats_card.offset_left = -322.0
	stats_card.offset_top = 20.0
	stats_card.offset_right = -22.0
	stats_card.offset_bottom = 113.0
	root.add_child(stats_card)
	var stats_margin := _wrap_margin(stats_card, 18, 12)
	var stats_box := VBoxContainer.new()
	stats_box.add_theme_constant_override("separation", 5)
	stats_margin.add_child(stats_box)
	var stats_top := HBoxContainer.new()
	stats_top.alignment = BoxContainer.ALIGNMENT_CENTER
	stats_top.add_theme_constant_override("separation", 24)
	stats_box.add_child(stats_top)
	time_label = _new_label("时间  00:00", 17, Color("ffffff"))
	score_label = _new_label("过程表现  40 / 40", 17, Color("ffffff"))
	stats_top.add_child(time_label)
	stats_top.add_child(score_label)
	dash_label = _new_label("冲刺  就绪", 16, Color("7bffd2"))
	dash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_box.add_child(dash_label)

	var controls_hint := _new_label("WASD / 方向键移动   SPACE 跳跃   SHIFT 冲刺   Q/E或右键转视角   R回正", 16, Color(1.0, 1.0, 1.0, 0.9))
	controls_hint.anchor_left = 0.5
	controls_hint.anchor_top = 1.0
	controls_hint.anchor_right = 0.5
	controls_hint.anchor_bottom = 1.0
	controls_hint.offset_left = -310.0
	controls_hint.offset_top = -50.0
	controls_hint.offset_right = 310.0
	controls_hint.offset_bottom = -18.0
	controls_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	controls_hint.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.72))
	controls_hint.add_theme_constant_override("shadow_offset_x", 2)
	controls_hint.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(controls_hint)


func _build_ready_overlay() -> void:
	ready_overlay = _make_overlay("ReadyOverlay", Color(0.025, 0.05, 0.12, 0.68))
	root.add_child(ready_overlay)
	var panel := _make_center_panel(ready_overlay, Vector2(650.0, 470.0), Color("121a36"), 30)
	var margin := _wrap_margin(panel, 42, 34)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	margin.add_child(box)
	var kicker := _new_label("GODOT · 最小可玩版本", 16, Color("66e8ed"))
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(kicker)
	var title := _new_label("AI训练场大挑战", 42, Color("ffffff"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var subtitle := _new_label("跑过固定周期机关，在终点完成生成式AI认知挑战", 21, Color("c9d8ef"))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(subtitle)
	var mission_card := _make_panel("Mission", Color("1d2b51"), 18)
	mission_card.custom_minimum_size = Vector2(0.0, 112.0)
	box.add_child(mission_card)
	var mission_margin := _wrap_margin(mission_card, 24, 18)
	var mission := _new_label("目标：越过固定周期机关，抵达黄色终点门。\n观察节奏，善用跳跃和冲刺；受击或跌落会返回起点。", 18, Color("edf8ff"))
	mission.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mission.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mission_margin.add_child(mission)
	var start_button := _make_button("开始挑战", Color("ffbf3e"), Color("29203d"), 22)
	start_button.custom_minimum_size = Vector2(280.0, 62.0)
	start_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start_button.pressed.connect(_on_start_pressed)
	box.add_child(start_button)
	var research_note := _new_label("带课堂票据的网页版可使用分关 AI 提示；不会向助手发送姓名、题目选项或完整轨迹。", 14, Color("8ea1c2"))
	research_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(research_note)


func _build_quiz_overlay() -> void:
	quiz_overlay = _make_overlay("QuizOverlay", Color(0.018, 0.035, 0.09, 0.84))
	quiz_overlay.visible = false
	root.add_child(quiz_overlay)
	var panel := _make_center_panel(quiz_overlay, Vector2(820.0, 590.0), Color("111a37"), 30)
	var margin := _wrap_margin(panel, 42, 34)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)
	quiz_title = _new_label("终点挑战", 17, Color("63e7e5"))
	quiz_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(quiz_title)
	quiz_prompt = _new_label("", 29, Color("ffffff"))
	quiz_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quiz_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quiz_prompt.custom_minimum_size = Vector2(0.0, 78.0)
	box.add_child(quiz_prompt)
	for index in range(3):
		var button := Button.new()
		button.custom_minimum_size = Vector2(0.0, 76.0)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size", 19)
		button.add_theme_constant_override("outline_size", 0)
		button.pressed.connect(_on_option_pressed.bind(index))
		_apply_option_style(button, "normal")
		option_buttons.append(button)
		box.add_child(button)
	quiz_feedback = _new_label("", 16, Color("b8c9e8"))
	quiz_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quiz_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quiz_feedback.custom_minimum_size = Vector2(0.0, 58.0)
	box.add_child(quiz_feedback)


func _build_result_overlay() -> void:
	result_overlay = _make_overlay("ResultOverlay", Color(0.018, 0.035, 0.09, 0.86))
	result_overlay.visible = false
	root.add_child(result_overlay)
	var panel := _make_center_panel(result_overlay, Vector2(650.0, 620.0), Color("131b39"), 30)
	var margin := _wrap_margin(panel, 46, 34)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)
	var title := _new_label("训练完成！", 38, Color("ffffff"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var subtitle := _new_label("你已经完成跑酷与AI知识挑战", 18, Color("9eb6d9"))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)
	result_stars = _new_label("★★★", 48, Color("ffd84f"))
	result_stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(result_stars)
	result_score = _new_label("综合评分  100 / 100", 30, Color("78f1df"))
	result_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(result_score)
	var metrics_panel := _make_panel("Metrics", Color("202d53"), 18)
	metrics_panel.custom_minimum_size = Vector2(400.0, 138.0)
	metrics_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(metrics_panel)
	var metrics_margin := _wrap_margin(metrics_panel, 28, 16)
	result_metrics = _new_label("", 18, Color("edf6ff"))
	result_metrics.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_metrics.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	metrics_margin.add_child(result_metrics)
	next_button = _make_button("进入下一关", Color("ffd85a"), Color("30244f"), 22)
	next_button.custom_minimum_size = Vector2(260.0, 62.0)
	next_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	next_button.pressed.connect(_on_next_level_pressed)
	box.add_child(next_button)
	var restart_button := _make_button("重玩本关", Color("58ded7"), Color("14253c"), 19)
	restart_button.custom_minimum_size = Vector2(260.0, 60.0)
	restart_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	restart_button.pressed.connect(_on_restart_pressed)
	box.add_child(restart_button)


func _build_assistant() -> void:
	assistant_widget = AI_ASSISTANT_PANEL_SCRIPT.new()
	assistant_widget.name = "AiAssistantPanel"
	assistant_widget.open_changed.connect(func(open: bool) -> void: assistant_toggled.emit(open))
	root.add_child(assistant_widget)


func configure_assistant(level_id: String, state_provider: Callable) -> void:
	assistant_widget.configure(level_id, state_provider)


func show_assistant_reminder(context: Dictionary = {}) -> bool:
	return assistant_widget.show_help_offer(context)


func reset_assistant() -> void:
	assistant_widget.reset_run()


func _build_audio() -> void:
	click_audio = _make_audio_player(CLICK_SOUND, -9.0)
	confirm_audio = _make_audio_player(CONFIRM_SOUND, -6.0)
	error_audio = _make_audio_player(ERROR_SOUND, -6.0)


func _on_start_pressed() -> void:
	_play_audio(click_audio)
	start_requested.emit()


func _on_restart_pressed() -> void:
	_play_audio(click_audio)
	restart_requested.emit()


func _on_next_level_pressed() -> void:
	_play_audio(confirm_audio)
	next_level_requested.emit()


func _on_option_pressed(index: int) -> void:
	if not _quiz_accepts_input:
		return
	_play_audio(click_audio)
	_quiz_accepts_input = false
	for button in option_buttons:
		button.disabled = true
	_apply_option_style(option_buttons[index], "selected")
	quiz_choice_selected.emit(index)


func _toggle_assistant() -> void:
	_play_audio(click_audio)
	if assistant_widget.overlay.visible:
		assistant_widget.close()
	else:
		assistant_widget.open_manual()


func _make_overlay(overlay_name: String, color: Color) -> ColorRect:
	var overlay := ColorRect.new()
	overlay.name = overlay_name
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = color
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	return overlay


func _make_center_panel(parent: Control, size: Vector2, color: Color, radius: int) -> PanelContainer:
	var panel := _make_panel("CenterCard", color, radius)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -size.x * 0.5
	panel.offset_top = -size.y * 0.5
	panel.offset_right = size.x * 0.5
	panel.offset_bottom = size.y * 0.5
	parent.add_child(panel)
	return panel


func _make_panel(panel_name: String, color: Color, radius: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = panel_name
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := _stylebox(color, radius, Color(1.0, 1.0, 1.0, 0.09), 1)
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.25)
	panel_style.shadow_size = 8
	panel_style.shadow_offset = Vector2(0.0, 4.0)
	panel.add_theme_stylebox_override("panel", panel_style)
	return panel


func _wrap_margin(parent: Control, horizontal: int, vertical: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", horizontal)
	margin.add_theme_constant_override("margin_right", horizontal)
	margin.add_theme_constant_override("margin_top", vertical)
	margin.add_theme_constant_override("margin_bottom", vertical)
	parent.add_child(margin)
	return margin


func _new_label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_button(text_value: String, background: Color, foreground: Color, font_size: int) -> Button:
	var button := Button.new()
	button.text = text_value
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", foreground)
	button.add_theme_color_override("font_hover_color", foreground)
	button.add_theme_color_override("font_pressed_color", foreground)
	button.add_theme_stylebox_override("normal", _stylebox(background, 16, Color(1.0, 1.0, 1.0, 0.14), 1))
	button.add_theme_stylebox_override("hover", _stylebox(background.lightened(0.09), 16, Color(1.0, 1.0, 1.0, 0.3), 1))
	button.add_theme_stylebox_override("pressed", _stylebox(background.darkened(0.08), 16, Color(1.0, 1.0, 1.0, 0.2), 1))
	button.add_theme_stylebox_override("focus", _stylebox(background.lightened(0.04), 16, Color("75f3e5"), 2))
	return button


func _apply_option_style(button: Button, state: String) -> void:
	var background := Color("1b294b")
	var border := Color("344a78")
	var foreground := Color("eef7ff")
	if state == "selected":
		background = Color("243b67")
		border = Color("62e4db")
	elif state == "wrong":
		background = Color("51283d")
		border = Color("ff7b72")
		foreground = Color("fff1ee")
	button.add_theme_color_override("font_color", foreground)
	button.add_theme_color_override("font_disabled_color", foreground)
	button.add_theme_stylebox_override("normal", _stylebox(background, 16, border, 2))
	button.add_theme_stylebox_override("hover", _stylebox(background.lightened(0.07), 16, border.lightened(0.1), 2))
	button.add_theme_stylebox_override("pressed", _stylebox(background.darkened(0.06), 16, border, 2))
	button.add_theme_stylebox_override("disabled", _stylebox(background, 16, border, 2))
	button.add_theme_stylebox_override("focus", _stylebox(background, 16, Color("ffe16a"), 2))


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
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


func _make_audio_player(audio_stream: AudioStream, volume_db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = audio_stream
	player.volume_db = volume_db
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(player)
	return player


func _play_audio(player: AudioStreamPlayer) -> void:
	if player and player.stream:
		player.play()
