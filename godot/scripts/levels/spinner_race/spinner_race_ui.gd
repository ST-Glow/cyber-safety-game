class_name SpinnerRaceUI
extends CanvasLayer

signal restart_requested
signal next_level_requested
signal quiz_choice_selected(selected_index)

const UI_FONT: FontFile = preload("res://assets/ui/fonts/noto_sans_sc_ui_600.ttf")
const CLICK_SOUND := preload("res://assets/audio/kenney_ui_pack/click-a.ogg")
const COUNTDOWN_SOUND := preload("res://assets/audio/kenney_ui_pack/tap-a.ogg")
const CONFIRM_SOUND := preload("res://assets/audio/interface_sfx_pack_1/confirm_tones/style6/confirm_style_6_001.ogg")
const ERROR_SOUND := preload("res://assets/audio/interface_sfx_pack_1/error_tones/style1/error_style_1_001.ogg")
const OPTION_CIRCLE: Texture2D = preload("res://assets/ui/kenney_ui_pack/svg/blue/icon_circle.svg")
const OPTION_SELECTED: Texture2D = preload("res://assets/ui/kenney_ui_pack/svg/yellow/icon_circle.svg")
const OPTION_WRONG: Texture2D = preload("res://assets/ui/kenney_ui_pack/svg/red/icon_cross.svg")
const RESULT_STAR: Texture2D = preload("res://assets/ui/kenney_ui_pack/svg/yellow/star.svg")

var root: Control
var time_label: Label
var state_label: Label
var fall_label: Label
var checkpoint_label: Label
var progress_bar: ProgressBar
var countdown_panel: PanelContainer
var countdown_label: Label
var countdown_hint: Label
var quiz_overlay: ColorRect
var quiz_title: Label
var quiz_prompt: Label
var quiz_feedback: Label
var option_buttons: Array[Button] = []
var result_overlay: ColorRect
var result_title: Label
var result_metrics: Label
var next_button: Button
var click_audio: AudioStreamPlayer
var countdown_audio: AudioStreamPlayer
var confirm_audio: AudioStreamPlayer
var error_audio: AudioStreamPlayer
var _quiz_accepts_input: bool = false
var _last_countdown_sound: int = -1
var _last_hud_seconds: int = -1
var _last_hud_falls: int = -1
var _last_hud_checkpoint: int = -1
var _last_hud_progress: int = -1
var _last_hud_state: int = -1
var _last_hud_countdown_second: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_build_root()
	_build_hud()
	_build_countdown()
	_build_quiz()
	_build_result()
	_build_audio()


func _unhandled_input(event: InputEvent) -> void:
	if not _quiz_accepts_input or not quiz_overlay.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var selected_index := -1
		match event.physical_keycode:
			KEY_1, KEY_KP_1:
				selected_index = 0
			KEY_2, KEY_KP_2:
				selected_index = 1
			KEY_3, KEY_KP_3:
				selected_index = 2
		if selected_index >= 0:
			_on_option_pressed(selected_index)
			get_viewport().set_input_as_handled()


func reset_view() -> void:
	_last_hud_seconds = -1
	_last_hud_falls = -1
	_last_hud_checkpoint = -1
	_last_hud_progress = -1
	_last_hud_state = -1
	_last_hud_countdown_second = -1
	result_overlay.visible = false
	quiz_overlay.visible = false
	_quiz_accepts_input = false
	countdown_panel.visible = true
	countdown_label.text = "3"
	countdown_hint.text = "准备冲刺"
	_last_countdown_sound = -1
	update_race(3.0, 90.0, 0, 0, SpinnerRaceManager.RaceState.COUNTDOWN, 0.0)


func show_countdown(seconds_left: int) -> void:
	if seconds_left == _last_countdown_sound:
		return
	_last_countdown_sound = seconds_left
	if seconds_left > 0:
		countdown_panel.visible = true
		countdown_label.text = str(seconds_left)
		countdown_audio.pitch_scale = 1.0 + float(3 - clampi(seconds_left, 1, 3)) * 0.08
		_play_audio(countdown_audio)
	else:
		countdown_panel.visible = false
		_play_audio(confirm_audio)


func update_race(
	countdown_left: float,
	time_left: float,
	fall_count: int,
	checkpoint_index: int,
	race_state: int,
	progress: float
) -> void:
	var seconds := maxi(0, ceili(time_left))
	if seconds != _last_hud_seconds:
		_last_hud_seconds = seconds
		time_label.text = "剩余时间  %02d:%02d" % [seconds / 60, seconds % 60]
	if fall_count != _last_hud_falls:
		_last_hud_falls = fall_count
		fall_label.text = "掉落  %d" % fall_count
	if checkpoint_index != _last_hud_checkpoint:
		_last_hud_checkpoint = checkpoint_index
		checkpoint_label.text = "检查点  %d / 4" % checkpoint_index
	var progress_percent := clampi(int(round(progress * 100.0)), 0, 100)
	if progress_percent != _last_hud_progress:
		_last_hud_progress = progress_percent
		progress_bar.value = progress_percent

	if race_state != _last_hud_state:
		_last_hud_state = race_state
		match race_state:
			SpinnerRaceManager.RaceState.COUNTDOWN:
				state_label.text = "等待出发"
				countdown_panel.visible = true
				countdown_hint.text = "倒计时结束后才能移动"
			SpinnerRaceManager.RaceState.RUNNING:
				state_label.text = "竞速中"
				countdown_panel.visible = false
			SpinnerRaceManager.RaceState.QUIZ:
				state_label.text = "答题暂停"
				countdown_panel.visible = false
			SpinnerRaceManager.RaceState.FINISHED:
				state_label.text = "已完成"
				countdown_panel.visible = false
			SpinnerRaceManager.RaceState.FAILED:
				state_label.text = "挑战结束"
				countdown_panel.visible = false
	if race_state == SpinnerRaceManager.RaceState.COUNTDOWN:
		var countdown_second := maxi(1, ceili(countdown_left))
		if countdown_second != _last_hud_countdown_second:
			_last_hud_countdown_second = countdown_second
			countdown_label.text = str(countdown_second)


func show_result(result: Dictionary) -> void:
	var success := bool(result.get("success", false))
	var star_count := int(result.get("stars", 1))
	var stars_text := "★".repeat(star_count) + "☆".repeat(3 - star_count)
	result_title.text = "冲刺成功！" if success else "时间到"
	result_title.modulate = Color("73f2bd") if success else Color("ff9c91")
	result_metrics.text = "通关时间  %.2f 秒\n掉落次数  %d 次\n答题次数  %d 次\n到达检查点  %d / 4\n综合评分  %d / 100    %s" % [
		float(result.get("elapsed_seconds", 0.0)),
		int(result.get("falls", 0)),
		int(result.get("quiz_attempts", 0)),
		int(result.get("checkpoint_index", 0)),
		int(result.get("score", 0)),
		stars_text,
	]
	quiz_overlay.visible = false
	_quiz_accepts_input = false
	result_overlay.visible = true
	next_button.visible = success
	_play_audio(confirm_audio if success else error_audio)


func show_quiz(question: QuizQuestion, checkpoint_index: int) -> void:
	countdown_panel.visible = false
	result_overlay.visible = false
	quiz_title.text = "AI知识检查点  %d / 4" % checkpoint_index
	quiz_prompt.text = question.prompt
	quiz_feedback.text = "答对后才会保存这个检查点（鼠标点击或按数字键 1 / 2 / 3）"
	quiz_feedback.modulate = Color("b9cbed")
	for index in range(option_buttons.size()):
		var button := option_buttons[index]
		button.text = "%d    %s" % [index + 1, question.options[index]]
		button.disabled = false
		_apply_option_style(button, "normal")
	quiz_overlay.visible = true
	_quiz_accepts_input = true


func show_wrong_answer(selected_index: int, explanation: String) -> void:
	if selected_index >= 0 and selected_index < option_buttons.size():
		_apply_option_style(option_buttons[selected_index], "wrong")
	quiz_feedback.text = "还不准确：%s\n请重新选择。" % explanation
	quiz_feedback.modulate = Color("ffb2a9")
	for button in option_buttons:
		button.disabled = false
	_quiz_accepts_input = true


func hide_quiz() -> void:
	quiz_overlay.visible = false
	_quiz_accepts_input = false
	_play_audio(confirm_audio)


func _build_root() -> void:
	root = Control.new()
	root.name = "SpinnerRaceUIRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = UI_FONT
	theme.default_font_size = 19
	root.theme = theme
	add_child(root)


func _build_hud() -> void:
	var level_card := _make_panel("LevelCard", Color(0.045, 0.075, 0.16, 0.9), 20)
	level_card.offset_left = 22.0
	level_card.offset_top = 20.0
	level_card.offset_right = 326.0
	level_card.offset_bottom = 118.0
	root.add_child(level_card)
	var level_margin := _wrap_margin(level_card, 20, 13)
	var level_box := VBoxContainer.new()
	level_box.add_theme_constant_override("separation", 3)
	level_margin.add_child(level_box)
	level_box.add_child(_new_label("第 2 关 · SPINNER RACE", 15, Color("75e8df")))
	level_box.add_child(_new_label("旋转障碍冲刺", 27, Color("f7fbff")))
	state_label = _new_label("等待出发", 15, Color("ffe477"))
	level_box.add_child(state_label)

	var timer_card := _make_panel("TimerCard", Color(0.045, 0.075, 0.16, 0.9), 20)
	timer_card.anchor_left = 0.5
	timer_card.anchor_right = 0.5
	timer_card.offset_left = -235.0
	timer_card.offset_top = 20.0
	timer_card.offset_right = 235.0
	timer_card.offset_bottom = 112.0
	root.add_child(timer_card)
	var timer_margin := _wrap_margin(timer_card, 22, 13)
	var timer_box := VBoxContainer.new()
	timer_box.add_theme_constant_override("separation", 7)
	timer_margin.add_child(timer_box)
	time_label = _new_label("剩余时间  01:30", 24, Color("fff5d6"))
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_box.add_child(time_label)
	progress_bar = ProgressBar.new()
	progress_bar.min_value = 0.0
	progress_bar.max_value = 100.0
	progress_bar.value = 0.0
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size = Vector2(0.0, 16.0)
	progress_bar.add_theme_stylebox_override("background", _stylebox(Color("263552"), 8, Color.TRANSPARENT, 0))
	progress_bar.add_theme_stylebox_override("fill", _stylebox(Color("42d6d1"), 8, Color.TRANSPARENT, 0))
	timer_box.add_child(progress_bar)

	var stats_card := _make_panel("StatsCard", Color(0.045, 0.075, 0.16, 0.9), 20)
	stats_card.anchor_left = 1.0
	stats_card.anchor_right = 1.0
	stats_card.offset_left = -318.0
	stats_card.offset_top = 20.0
	stats_card.offset_right = -22.0
	stats_card.offset_bottom = 112.0
	root.add_child(stats_card)
	var stats_margin := _wrap_margin(stats_card, 20, 13)
	var stats_box := VBoxContainer.new()
	stats_box.add_theme_constant_override("separation", 7)
	stats_margin.add_child(stats_box)
	fall_label = _new_label("掉落  0", 19, Color("ffb09f"))
	checkpoint_label = _new_label("检查点  0 / 4", 19, Color("8ee9ff"))
	stats_box.add_child(fall_label)
	stats_box.add_child(checkpoint_label)

	var route_hint := _new_label("WASD / 方向键移动   SPACE 跳跃   SHIFT 冲刺   Q/E或右键转视角   R回正", 16, Color("eef7ff"))
	route_hint.anchor_left = 0.5
	route_hint.anchor_right = 0.5
	route_hint.anchor_top = 1.0
	route_hint.anchor_bottom = 1.0
	route_hint.offset_left = -310.0
	route_hint.offset_top = -48.0
	route_hint.offset_right = 310.0
	route_hint.offset_bottom = -16.0
	route_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	route_hint.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.72))
	route_hint.add_theme_constant_override("shadow_offset_x", 2)
	route_hint.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(route_hint)


func _build_countdown() -> void:
	countdown_panel = _make_panel("CountdownPanel", Color(0.05, 0.075, 0.17, 0.92), 28)
	countdown_panel.anchor_left = 0.5
	countdown_panel.anchor_top = 0.5
	countdown_panel.anchor_right = 0.5
	countdown_panel.anchor_bottom = 0.5
	countdown_panel.offset_left = -180.0
	countdown_panel.offset_top = -130.0
	countdown_panel.offset_right = 180.0
	countdown_panel.offset_bottom = 130.0
	root.add_child(countdown_panel)
	var margin := _wrap_margin(countdown_panel, 26, 24)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	var title := _new_label("旋转障碍冲刺", 24, Color("7deee0"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	countdown_label = _new_label("3", 86, Color("ffe067"))
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(countdown_label)
	countdown_hint = _new_label("倒计时结束后才能移动", 17, Color("c8d8f1"))
	countdown_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(countdown_hint)


func _build_quiz() -> void:
	quiz_overlay = ColorRect.new()
	quiz_overlay.name = "QuizOverlay"
	quiz_overlay.color = Color(0.012, 0.024, 0.065, 0.82)
	quiz_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	quiz_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(quiz_overlay)

	var panel := _make_panel("QuizPanel", Color("121c3c"), 30)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -455.0
	panel.offset_top = -305.0
	panel.offset_right = 455.0
	panel.offset_bottom = 305.0
	quiz_overlay.add_child(panel)
	var margin := _wrap_margin(panel, 42, 30)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 13)
	margin.add_child(box)

	quiz_title = _new_label("AI知识检查点  1 / 4", 22, Color("77eee0"))
	quiz_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(quiz_title)
	var rule_label := _new_label("机关与计时已暂停 · 答对后保存重生点", 16, Color("ffe275"))
	rule_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(rule_label)
	quiz_prompt = _new_label("", 25, Color("f7fbff"))
	quiz_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quiz_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	quiz_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quiz_prompt.custom_minimum_size = Vector2(0.0, 80.0)
	box.add_child(quiz_prompt)

	for index in range(3):
		var option_button := Button.new()
		option_button.name = "Option%d" % (index + 1)
		option_button.custom_minimum_size = Vector2(0.0, 72.0)
		option_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		option_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		option_button.add_theme_font_size_override("font_size", 18)
		option_button.pressed.connect(_on_option_pressed.bind(index))
		_apply_option_style(option_button, "normal")
		option_buttons.append(option_button)
		box.add_child(option_button)

	quiz_feedback = _new_label("", 16, Color("b9cbed"))
	quiz_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quiz_feedback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	quiz_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quiz_feedback.custom_minimum_size = Vector2(0.0, 66.0)
	box.add_child(quiz_feedback)
	quiz_overlay.visible = false


func _build_result() -> void:
	result_overlay = ColorRect.new()
	result_overlay.name = "ResultOverlay"
	result_overlay.color = Color(0.015, 0.025, 0.07, 0.68)
	result_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(result_overlay)

	var panel := _make_panel("ResultPanel", Color("111936"), 30)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -340.0
	panel.offset_top = -295.0
	panel.offset_right = 340.0
	panel.offset_bottom = 295.0
	result_overlay.add_child(panel)
	var margin := _wrap_margin(panel, 42, 34)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	margin.add_child(box)
	var eyebrow := _new_label("SPINNER RACE · 结算", 17, Color("7deee0"))
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(eyebrow)
	result_title = _new_label("冲刺成功！", 46, Color("73f2bd"))
	result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(result_title)
	var result_star := TextureRect.new()
	result_star.name = "KenneyResultStar"
	result_star.texture = RESULT_STAR
	result_star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result_star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result_star.custom_minimum_size = Vector2(54.0, 54.0)
	result_star.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(result_star)
	result_metrics = _new_label("通关时间  0.00 秒\n掉落次数  0 次", 22, Color("e8f2ff"))
	result_metrics.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(result_metrics)
	next_button = _make_button("进入下一关", Color("73f2bd"), Color("172b38"), 23)
	next_button.custom_minimum_size = Vector2(300.0, 66.0)
	next_button.pressed.connect(_on_next_level_pressed)
	box.add_child(next_button)
	var restart_button := _make_button("重新开始", Color("ffc247"), Color("22213e"), 20)
	restart_button.custom_minimum_size = Vector2(300.0, 70.0)
	restart_button.pressed.connect(_on_restart_pressed)
	box.add_child(restart_button)
	result_overlay.visible = false


func _build_audio() -> void:
	click_audio = AudioStreamPlayer.new()
	click_audio.stream = CLICK_SOUND
	click_audio.volume_db = -7.0
	add_child(click_audio)
	countdown_audio = AudioStreamPlayer.new()
	countdown_audio.name = "CountdownAudio"
	countdown_audio.stream = COUNTDOWN_SOUND
	countdown_audio.volume_db = -4.0
	add_child(countdown_audio)
	confirm_audio = AudioStreamPlayer.new()
	confirm_audio.stream = CONFIRM_SOUND
	confirm_audio.volume_db = -5.0
	add_child(confirm_audio)
	error_audio = AudioStreamPlayer.new()
	error_audio.stream = ERROR_SOUND
	error_audio.volume_db = -5.0
	add_child(error_audio)


func _on_restart_pressed() -> void:
	_play_audio(click_audio)
	restart_requested.emit()


func _on_next_level_pressed() -> void:
	_play_audio(confirm_audio)
	next_level_requested.emit()


func _on_option_pressed(selected_index: int) -> void:
	if not _quiz_accepts_input:
		return
	_play_audio(click_audio)
	_quiz_accepts_input = false
	for button in option_buttons:
		button.disabled = true
	_apply_option_style(option_buttons[selected_index], "selected")
	quiz_choice_selected.emit(selected_index)


func _play_audio(player: AudioStreamPlayer) -> void:
	if player and player.stream:
		player.play()


func _make_panel(panel_name: String, color: Color, radius: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = panel_name
	panel.add_theme_stylebox_override("panel", _stylebox(color, radius, Color(1.0, 1.0, 1.0, 0.1), 1))
	return panel


func _wrap_margin(parent: Control, horizontal: int, vertical: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	button.add_theme_stylebox_override("normal", _stylebox(background, 18, Color(1.0, 1.0, 1.0, 0.15), 1))
	button.add_theme_stylebox_override("hover", _stylebox(background.lightened(0.08), 18, Color(1.0, 1.0, 1.0, 0.3), 1))
	button.add_theme_stylebox_override("pressed", _stylebox(background.darkened(0.07), 18, Color(1.0, 1.0, 1.0, 0.2), 1))
	button.add_theme_stylebox_override("focus", _stylebox(background, 18, Color("75f3e5"), 2))
	return button


func _apply_option_style(button: Button, state: String) -> void:
	var background := Color("202d53")
	var border := Color("40527f")
	var foreground := Color("eef6ff")
	button.icon = OPTION_CIRCLE
	button.add_theme_constant_override("icon_max_width", 28)
	match state:
		"selected":
			background = Color("294875")
			border = Color("70eadd")
			button.icon = OPTION_SELECTED
		"wrong":
			background = Color("632f45")
			border = Color("ff8277")
			foreground = Color("fff2ef")
			button.icon = OPTION_WRONG
	button.add_theme_color_override("font_color", foreground)
	button.add_theme_color_override("font_hover_color", foreground)
	button.add_theme_color_override("font_pressed_color", foreground)
	button.add_theme_color_override("font_disabled_color", foreground)
	button.add_theme_stylebox_override("normal", _stylebox(background, 18, border, 2))
	button.add_theme_stylebox_override("hover", _stylebox(background.lightened(0.06), 18, border.lightened(0.08), 2))
	button.add_theme_stylebox_override("pressed", _stylebox(background.darkened(0.05), 18, border, 2))
	button.add_theme_stylebox_override("disabled", _stylebox(background, 18, border, 2))
	button.add_theme_stylebox_override("focus", _stylebox(background, 18, Color("fff07b"), 3))


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
