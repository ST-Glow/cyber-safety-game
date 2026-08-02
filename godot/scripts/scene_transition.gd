extends CanvasLayer

signal transition_started(scene_path: String)
signal transition_finished(scene_path: String)

const UI_FONT: FontFile = preload("res://assets/ui/fonts/noto_sans_sc_ui_600.ttf")
const TRANSITION_SOUND: AudioStream = preload("res://assets/audio/kenney_ui_pack/switch-a.ogg")
const ARRIVAL_SOUND: AudioStream = preload("res://assets/audio/interface_sfx_pack_1/confirm_tones/style6/confirm_style_6_002.ogg")
const MILESTONE_SOUND: AudioStream = preload("res://assets/audio/interface_sfx_pack_1/confirm_tones/style6/confirm_style_6_001.ogg")

var transition_overlay: ColorRect
var transition_kicker: Label
var transition_title: Label
var transition_detail: Label
var milestone_panel: PanelContainer
var milestone_title: Label
var milestone_detail: Label
var transition_audio: AudioStreamPlayer
var arrival_audio: AudioStreamPlayer
var milestone_audio: AudioStreamPlayer
var _transition_tween: Tween
var _milestone_tween: Tween
var _transitioning: bool = false
var _headless: bool = false
var _transition_pause_token: int = 0
var _initial_reveal_pause_token: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_headless = DisplayServer.get_name() == "headless"
	_build_overlay()
	_build_milestone()
	_build_audio()
	if _headless:
		transition_overlay.visible = false
		milestone_panel.visible = false
	else:
		transition_overlay.visible = true
		transition_overlay.modulate.a = 1.0
		call_deferred("_play_initial_reveal")


func request_scene_change(scene_path: String, level_title: String = "") -> Error:
	if _transitioning:
		return ERR_BUSY
	if not ResourceLoader.exists(scene_path, "PackedScene"):
		return ERR_FILE_NOT_FOUND
	_transitioning = true
	_transition_pause_token = get_node("/root/PauseCoordinator").acquire(self, &"scene_transition")
	if _headless:
		var change_error := get_tree().change_scene_to_file(scene_path)
		if change_error != OK:
			_finish_transition_request()
			return change_error
		call_deferred("_finish_headless_transition", scene_path)
		return OK
	transition_started.emit(scene_path)
	_set_transition_copy(scene_path, level_title, "下一站")
	transition_overlay.visible = true
	transition_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	transition_overlay.modulate.a = 0.0
	_play_audio(transition_audio)
	if _transition_tween and _transition_tween.is_valid():
		_transition_tween.kill()
	_transition_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_transition_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_transition_tween.tween_property(transition_overlay, "modulate:a", 1.0, 0.28)
	_transition_tween.tween_callback(_swap_scene.bind(scene_path))
	return OK


func show_milestone(title_text: String, detail_text: String = "") -> void:
	if _headless or _transitioning:
		return
	milestone_title.text = title_text
	milestone_detail.text = detail_text
	milestone_detail.visible = not detail_text.is_empty()
	milestone_panel.visible = true
	milestone_panel.modulate.a = 0.0
	_play_audio(milestone_audio)
	if _milestone_tween and _milestone_tween.is_valid():
		_milestone_tween.kill()
	_milestone_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_milestone_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_milestone_tween.tween_property(milestone_panel, "modulate:a", 1.0, 0.16)
	_milestone_tween.tween_interval(1.15)
	_milestone_tween.tween_property(milestone_panel, "modulate:a", 0.0, 0.24)
	_milestone_tween.tween_callback(func() -> void: milestone_panel.visible = false)


func is_transitioning() -> bool:
	return _transitioning


func _play_initial_reveal() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var scene_path := "res://scenes/main.tscn"
	if get_tree().current_scene and not get_tree().current_scene.scene_file_path.is_empty():
		scene_path = get_tree().current_scene.scene_file_path
	_set_transition_copy(scene_path, "", "AI训练场大挑战")
	_initial_reveal_pause_token = get_node("/root/PauseCoordinator").acquire(self, &"initial_reveal")
	_play_audio(arrival_audio)
	_transition_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_transition_tween.tween_interval(0.24)
	_transition_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_transition_tween.tween_property(transition_overlay, "modulate:a", 0.0, 0.42)
	await _transition_tween.finished
	transition_overlay.visible = false
	transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_node("/root/PauseCoordinator").release(_initial_reveal_pause_token)
	_initial_reveal_pause_token = 0


func _swap_scene(scene_path: String) -> void:
	var change_error := get_tree().change_scene_to_file(scene_path)
	if change_error != OK:
		push_error("Scene transition failed for %s: %s" % [scene_path, error_string(change_error)])
		_transitioning = false
		transition_overlay.visible = false
		transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		get_node("/root/PauseCoordinator").release(_transition_pause_token)
		_transition_pause_token = 0
		return
	await get_tree().process_frame
	await get_tree().process_frame
	_set_transition_copy(scene_path, "", "准备出发")
	_play_audio(arrival_audio)
	_transition_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_transition_tween.tween_interval(0.20)
	_transition_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_transition_tween.tween_property(transition_overlay, "modulate:a", 0.0, 0.38)
	await _transition_tween.finished
	transition_overlay.visible = false
	transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transitioning = false
	get_node("/root/PauseCoordinator").release(_transition_pause_token)
	_transition_pause_token = 0
	transition_finished.emit(scene_path)


func _finish_headless_transition(scene_path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_finish_transition_request()
	transition_finished.emit(scene_path)


func _finish_transition_request() -> void:
	_transitioning = false
	get_node("/root/PauseCoordinator").release(_transition_pause_token)
	_transition_pause_token = 0


func _set_transition_copy(scene_path: String, override_title: String, kicker_text: String) -> void:
	var level := CampaignSession.get_level_by_scene_path(scene_path)
	transition_kicker.text = kicker_text if not kicker_text.is_empty() else String(level.get("kicker", "新挑战"))
	transition_title.text = override_title if not override_title.is_empty() else String(level.get("title", "AI训练场"))
	transition_detail.text = String(level.get("detail", "准备进入下一项训练"))


func _build_overlay() -> void:
	transition_overlay = ColorRect.new()
	transition_overlay.name = "TransitionOverlay"
	transition_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	transition_overlay.color = Color("09162e")
	transition_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(transition_overlay)

	var glow := ColorRect.new()
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.color = Color(0.1, 0.78, 0.82, 0.08)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	transition_overlay.add_child(glow)

	var card := PanelContainer.new()
	card.anchor_left = 0.5
	card.anchor_top = 0.5
	card.anchor_right = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -270.0
	card.offset_top = -112.0
	card.offset_right = 270.0
	card.offset_bottom = 112.0
	card.add_theme_stylebox_override("panel", _stylebox(Color("122646"), 30, Color("49ddd3"), 2))
	transition_overlay.add_child(card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	card.add_child(margin)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	transition_kicker = _new_label("AI训练场大挑战", 17, Color("69eee2"))
	transition_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(transition_kicker)
	transition_title = _new_label("AI认知训练区", 37, Color("ffffff"))
	transition_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(transition_title)
	transition_detail = _new_label("跑、跳、冲刺，完成基础训练", 17, Color("c3d7ef"))
	transition_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(transition_detail)


func _build_milestone() -> void:
	milestone_panel = PanelContainer.new()
	milestone_panel.name = "MilestonePanel"
	milestone_panel.anchor_left = 0.5
	milestone_panel.anchor_top = 0.0
	milestone_panel.anchor_right = 0.5
	milestone_panel.anchor_bottom = 0.0
	milestone_panel.offset_left = -205.0
	milestone_panel.offset_top = 126.0
	milestone_panel.offset_right = 205.0
	milestone_panel.offset_bottom = 210.0
	milestone_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	milestone_panel.add_theme_stylebox_override("panel", _stylebox(Color(0.04, 0.10, 0.21, 0.94), 22, Color("62eadb"), 2))
	add_child(milestone_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	milestone_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	margin.add_child(box)
	milestone_title = _new_label("检查点已保存", 22, Color("71f2df"))
	milestone_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(milestone_title)
	milestone_detail = _new_label("失败后将从这里继续", 15, Color("d4e5f5"))
	milestone_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(milestone_detail)
	milestone_panel.visible = false


func _build_audio() -> void:
	transition_audio = _make_audio_player(TRANSITION_SOUND, -5.0)
	arrival_audio = _make_audio_player(ARRIVAL_SOUND, -6.0)
	milestone_audio = _make_audio_player(MILESTONE_SOUND, -8.0)


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


func _new_label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_override("font", UI_FONT)
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
