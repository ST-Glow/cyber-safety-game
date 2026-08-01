class_name PartyModeUI
extends CanvasLayer

signal restart_requested
signal next_level_requested
signal restart_campaign_requested
signal quiz_choice_selected(selected_index: int)

const UI_FONT: FontFile = preload("res://assets/ui/fonts/noto_sans_sc_ui_600.ttf")
const CLICK_SOUND := preload("res://assets/audio/kenney_ui_pack/click-a.ogg")
const COUNTDOWN_SOUND := preload("res://assets/audio/kenney_ui_pack/tap-a.ogg")
const CONFIRM_SOUND := preload("res://assets/audio/interface_sfx_pack_1/confirm_tones/style6/confirm_style_6_002.ogg")
const ERROR_SOUND := preload("res://assets/audio/interface_sfx_pack_1/error_tones/style2/error_style_2_002.ogg")
const OPTION_NORMAL: Texture2D = preload("res://assets/ui/kenney_ui_pack/svg/blue/icon_circle.svg")
const OPTION_SELECTED: Texture2D = preload("res://assets/ui/kenney_ui_pack/svg/yellow/icon_circle.svg")
const OPTION_WRONG: Texture2D = preload("res://assets/ui/kenney_ui_pack/svg/red/icon_cross.svg")
const RESULT_STAR: Texture2D = preload("res://assets/ui/kenney_ui_pack/svg/yellow/star.svg")

var mode_kicker: String = "PARTY MODE"
var mode_title: String = "派对挑战"
var objective_text: String = "完成挑战目标"
var final_level: bool = false

var root: Control
var time_label: Label
var state_label: Label
var primary_label: Label
var secondary_label: Label
var progress_bar: ProgressBar
var countdown_panel: PanelContainer
var countdown_label: Label
var quiz_overlay: ColorRect
var quiz_title: Label
var quiz_prompt: Label
var quiz_feedback: Label
var option_buttons: Array[Button] = []
var result_overlay: ColorRect
var result_title: Label
var result_metrics: Label
var next_button: Button
var restart_campaign_button: Button
var click_audio: AudioStreamPlayer
var countdown_audio: AudioStreamPlayer
var confirm_audio: AudioStreamPlayer
var error_audio: AudioStreamPlayer
var _quiz_accepts_input: bool = false
var _last_countdown_sound: int = -1
var _last_hud_seconds: int = -1
var _last_hud_state: String = ""
var _last_hud_primary: String = ""
var _last_hud_secondary: String = ""
var _last_hud_progress: int = -1


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


func reset_view(time_limit: float) -> void:
	_last_hud_seconds = -1
	_last_hud_state = ""
	_last_hud_primary = ""
	_last_hud_secondary = ""
	_last_hud_progress = -1
	result_overlay.visible = false
	quiz_overlay.visible = false
	_quiz_accepts_input = false
	countdown_panel.visible = true
	countdown_label.text = "3"
	_last_countdown_sound = -1
	update_hud(time_limit, "等待出发", "0", "0", 0.0)


func update_hud(time_left: float, state_text: String, primary_text: String, secondary_text: String, progress: float) -> void:
	var seconds := maxi(0, ceili(time_left))
	if seconds != _last_hud_seconds:
		_last_hud_seconds = seconds
		time_label.text = "剩余时间  %02d:%02d" % [seconds / 60, seconds % 60]
	if state_text != _last_hud_state:
		_last_hud_state = state_text
		state_label.text = state_text
	if primary_text != _last_hud_primary:
		_last_hud_primary = primary_text
		primary_label.text = primary_text
	if secondary_text != _last_hud_secondary:
		_last_hud_secondary = secondary_text
		secondary_label.text = secondary_text
	var progress_percent := clampi(int(round(progress * 100.0)), 0, 100)
	if progress_percent != _last_hud_progress:
		_last_hud_progress = progress_percent
		progress_bar.value = progress_percent


func show_countdown(seconds_left: int) -> void:
	countdown_panel.visible = seconds_left > 0
	if seconds_left == _last_countdown_sound:
		return
	_last_countdown_sound = seconds_left
	if seconds_left > 0:
		countdown_label.text = str(seconds_left)
		countdown_audio.pitch_scale = 1.0 + float(3 - clampi(seconds_left, 1, 3)) * 0.08
		_play_audio(countdown_audio)
	else:
		_play_audio(confirm_audio)


func hide_countdown() -> void:
	countdown_panel.visible = false


func show_quiz(question: QuizQuestion, slot: int, total_slots: int) -> void:
	countdown_panel.visible = false
	result_overlay.visible = false
	quiz_title.text = "AI知识检查点  %d / %d" % [slot, total_slots]
	quiz_prompt.text = question.prompt
	quiz_feedback.text = "答对后继续游戏（鼠标点击或按数字键 1 / 2 / 3）"
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
	_play_audio(error_audio)


func hide_quiz() -> void:
	quiz_overlay.visible = false
	_quiz_accepts_input = false
	_play_audio(confirm_audio)


func show_result(result: Dictionary, metrics_text: String, campaign_summary: Dictionary = {}) -> void:
	var success := bool(result.get("success", false))
	var star_count := int(result.get("stars", 1))
	var score_text := "综合评分  %d / 100    %s" % [
		int(result.get("score", 0)),
		"★".repeat(star_count) + "☆".repeat(3 - star_count),
	]
	var scored_metrics := metrics_text + "\n" + score_text
	quiz_overlay.visible = false
	countdown_panel.visible = false
	_quiz_accepts_input = false
	if final_level and success:
		result_title.text = "全部训练完成！"
		result_title.modulate = Color("73f2bd")
		result_metrics.text = scored_metrics + "\n\n" + _format_campaign_summary(campaign_summary)
	else:
		result_title.text = "挑战完成！" if success else String(result.get("failure_title", "时间到"))
		result_title.modulate = Color("73f2bd") if success else Color("ff9c91")
		result_metrics.text = scored_metrics
	next_button.visible = success and not final_level
	restart_campaign_button.visible = final_level and success
	result_overlay.visible = true
	_play_audio(confirm_audio if success else error_audio)


func _format_campaign_summary(summary: Dictionary) -> String:
	if summary.is_empty():
		return ""
	var lines: Array[String] = [
		"综合成绩  %d / %d 关" % [
			int(summary.get("completed_levels", 0)),
			int(summary.get("total_levels", 4)),
		],
		"平均评分  %d / 100\n总用时  %.2f 秒    总掉落  %d 次    总答题  %d 次" % [
			int(summary.get("average_score", 0)),
			float(summary.get("total_elapsed_seconds", 0.0)),
			int(summary.get("total_falls", 0)),
			int(summary.get("total_quiz_attempts", 0)),
		],
	]
	for level_result in summary.get("level_results", []):
		lines.append("%s  %.2f 秒" % [
			String(level_result.get("level_name", level_result.get("level_id", "关卡"))),
			float(level_result.get("elapsed_seconds", 0.0)),
		])
	return "\n".join(lines)


func _build_root() -> void:
	root = Control.new()
	root.name = "PartyModeUIRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = UI_FONT
	root.theme = theme
	add_child(root)


func _build_hud() -> void:
	var mode_panel := _make_panel("ModePanel", Color("121d39"), 24)
	mode_panel.position = Vector2(22.0, 20.0)
	mode_panel.size = Vector2(310.0, 118.0)
	root.add_child(mode_panel)
	var mode_margin := _wrap_margin(mode_panel, 20, 13)
	var mode_box := VBoxContainer.new()
	mode_box.add_theme_constant_override("separation", 4)
	mode_margin.add_child(mode_box)
	var kicker := _new_label(mode_kicker, 15, Color("73eee0"))
	mode_box.add_child(kicker)
	var title := _new_label(mode_title, 25, Color("ffffff"))
	mode_box.add_child(title)
	state_label = _new_label("等待出发", 16, Color("ffd65b"))
	mode_box.add_child(state_label)

	var timer_panel := _make_panel("TimerPanel", Color("121d39"), 24)
	timer_panel.anchor_left = 0.5
	timer_panel.anchor_right = 0.5
	timer_panel.offset_left = -235.0
	timer_panel.offset_right = 235.0
	timer_panel.offset_top = 20.0
	timer_panel.offset_bottom = 112.0
	root.add_child(timer_panel)
	var timer_margin := _wrap_margin(timer_panel, 22, 12)
	var timer_box := VBoxContainer.new()
	timer_box.add_theme_constant_override("separation", 9)
	timer_margin.add_child(timer_box)
	time_label = _new_label("剩余时间  01:15", 27, Color("fff8df"))
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_box.add_child(time_label)
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(0.0, 14.0)
	progress_bar.show_percentage = false
	progress_bar.add_theme_stylebox_override("background", _stylebox(Color("25365d"), 8, Color.TRANSPARENT, 0))
	progress_bar.add_theme_stylebox_override("fill", _stylebox(Color("54dfd4"), 8, Color.TRANSPARENT, 0))
	timer_box.add_child(progress_bar)

	var stats_panel := _make_panel("StatsPanel", Color("121d39"), 24)
	stats_panel.anchor_left = 1.0
	stats_panel.anchor_right = 1.0
	stats_panel.offset_left = -316.0
	stats_panel.offset_right = -22.0
	stats_panel.offset_top = 20.0
	stats_panel.offset_bottom = 112.0
	root.add_child(stats_panel)
	var stats_margin := _wrap_margin(stats_panel, 20, 12)
	var stats_box := VBoxContainer.new()
	stats_box.add_theme_constant_override("separation", 8)
	stats_margin.add_child(stats_box)
	primary_label = _new_label("进度  0", 19, Color("ffbb72"))
	stats_box.add_child(primary_label)
	secondary_label = _new_label("掉落  0", 19, Color("8deeff"))
	stats_box.add_child(secondary_label)

	var hint := _new_label("WASD / 方向键移动   SPACE 跳跃   SHIFT 冲刺   Q/E或右键转视角   R回正", 16, Color("ffffff"))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position.y = -40.0
	hint.add_theme_color_override("font_shadow_color", Color("14213b"))
	hint.add_theme_constant_override("shadow_offset_x", 2)
	hint.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(hint)


func _build_countdown() -> void:
	countdown_panel = _make_panel("CountdownPanel", Color("111b38"), 28)
	countdown_panel.anchor_left = 0.5
	countdown_panel.anchor_top = 0.5
	countdown_panel.anchor_right = 0.5
	countdown_panel.anchor_bottom = 0.5
	countdown_panel.offset_left = -180.0
	countdown_panel.offset_top = -130.0
	countdown_panel.offset_right = 180.0
	countdown_panel.offset_bottom = 130.0
	root.add_child(countdown_panel)
	var margin := _wrap_margin(countdown_panel, 28, 20)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 13)
	margin.add_child(box)
	var title := _new_label(mode_title, 23, Color("70eee1"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	countdown_label = _new_label("3", 70, Color("ffd75b"))
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(countdown_label)
	var objective := _new_label(objective_text, 16, Color("c6d7ef"))
	objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(objective)


func _build_quiz() -> void:
	quiz_overlay = ColorRect.new()
	quiz_overlay.name = "QuizOverlay"
	quiz_overlay.color = Color(0.012, 0.024, 0.065, 0.84)
	quiz_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	quiz_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(quiz_overlay)
	var panel := _make_panel("QuizPanel", Color("111936"), 30)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -410.0
	panel.offset_top = -290.0
	panel.offset_right = 410.0
	panel.offset_bottom = 290.0
	quiz_overlay.add_child(panel)
	var margin := _wrap_margin(panel, 42, 30)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 13)
	margin.add_child(box)
	quiz_title = _new_label("AI知识检查点", 22, Color("73eee0"))
	quiz_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(quiz_title)
	quiz_prompt = _new_label("", 25, Color("ffffff"))
	quiz_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quiz_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quiz_prompt.custom_minimum_size = Vector2(0.0, 80.0)
	box.add_child(quiz_prompt)
	for index in range(3):
		var button := Button.new()
		button.custom_minimum_size = Vector2(0.0, 72.0)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size", 18)
		button.icon = OPTION_NORMAL
		button.pressed.connect(_on_option_pressed.bind(index))
		_apply_option_style(button, "normal")
		option_buttons.append(button)
		box.add_child(button)
	quiz_feedback = _new_label("", 16, Color("b9cbed"))
	quiz_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quiz_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quiz_feedback.custom_minimum_size = Vector2(0.0, 56.0)
	box.add_child(quiz_feedback)
	quiz_overlay.visible = false


func _build_result() -> void:
	result_overlay = ColorRect.new()
	result_overlay.name = "ResultOverlay"
	result_overlay.color = Color(0.012, 0.024, 0.065, 0.78)
	result_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(result_overlay)
	var panel := _make_panel("ResultPanel", Color("111936"), 30)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -390.0
	panel.offset_top = -320.0
	panel.offset_right = 390.0
	panel.offset_bottom = 320.0
	result_overlay.add_child(panel)
	var margin := _wrap_margin(panel, 42, 28)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var eyebrow := _new_label("%s · 结算" % mode_kicker, 16, Color("73eee0"))
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(eyebrow)
	result_title = _new_label("挑战完成！", 42, Color("73f2bd"))
	result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(result_title)
	var star := TextureRect.new()
	star.name = "KenneyResultStar"
	star.texture = RESULT_STAR
	star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	star.custom_minimum_size = Vector2(48.0, 48.0)
	star.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(star)
	result_metrics = _new_label("", 18, Color("e8f2ff"))
	result_metrics.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_metrics.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_metrics.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(result_metrics)
	next_button = _make_button("进入下一关", Color("73f2bd"), Color("172b38"), 21)
	next_button.custom_minimum_size = Vector2(280.0, 58.0)
	next_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	next_button.pressed.connect(_on_next_pressed)
	box.add_child(next_button)
	restart_campaign_button = _make_button("重新挑战全部", Color("ffd25d"), Color("2b2340"), 21)
	restart_campaign_button.custom_minimum_size = Vector2(280.0, 58.0)
	restart_campaign_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	restart_campaign_button.pressed.connect(_on_restart_campaign_pressed)
	box.add_child(restart_campaign_button)
	var restart_button := _make_button("重玩本关", Color("4fdad1"), Color("183044"), 18)
	restart_button.custom_minimum_size = Vector2(250.0, 52.0)
	restart_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	restart_button.pressed.connect(_on_restart_pressed)
	box.add_child(restart_button)
	result_overlay.visible = false


func _build_audio() -> void:
	click_audio = _make_audio_player(CLICK_SOUND, -8.0)
	countdown_audio = _make_audio_player(COUNTDOWN_SOUND, -4.0)
	countdown_audio.name = "CountdownAudio"
	confirm_audio = _make_audio_player(CONFIRM_SOUND, -5.0)
	error_audio = _make_audio_player(ERROR_SOUND, -5.0)


func _on_option_pressed(index: int) -> void:
	if not _quiz_accepts_input:
		return
	_play_audio(click_audio)
	_quiz_accepts_input = false
	for button in option_buttons:
		button.disabled = true
	_apply_option_style(option_buttons[index], "selected")
	quiz_choice_selected.emit(index)


func _on_restart_pressed() -> void:
	_play_audio(click_audio)
	restart_requested.emit()


func _on_next_pressed() -> void:
	_play_audio(confirm_audio)
	next_level_requested.emit()


func _on_restart_campaign_pressed() -> void:
	_play_audio(confirm_audio)
	restart_campaign_requested.emit()


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
	button.add_theme_stylebox_override("normal", _stylebox(background, 16, Color(1.0, 1.0, 1.0, 0.14), 1))
	button.add_theme_stylebox_override("hover", _stylebox(background.lightened(0.09), 16, Color(1.0, 1.0, 1.0, 0.3), 1))
	button.add_theme_stylebox_override("pressed", _stylebox(background.darkened(0.08), 16, Color(1.0, 1.0, 1.0, 0.2), 1))
	button.add_theme_stylebox_override("focus", _stylebox(background.lightened(0.04), 16, Color("75f3e5"), 2))
	return button


func _apply_option_style(button: Button, state: String) -> void:
	var background := Color("1b294b")
	var border := Color("344a78")
	var foreground := Color("eef7ff")
	button.icon = OPTION_NORMAL
	if state == "selected":
		background = Color("243b67")
		border = Color("62e4db")
		button.icon = OPTION_SELECTED
	elif state == "wrong":
		background = Color("51283d")
		border = Color("ff7b72")
		foreground = Color("fff1ee")
		button.icon = OPTION_WRONG
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
	style.content_margin_top = 9.0
	style.content_margin_bottom = 9.0
	return style


func _make_audio_player(stream: AudioStream, volume_db: float) -> AudioStreamPlayer:
	var audio := AudioStreamPlayer.new()
	audio.stream = stream
	audio.volume_db = volume_db
	audio.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(audio)
	return audio


func _play_audio(audio: AudioStreamPlayer) -> void:
	if audio and audio.stream:
		audio.play()
