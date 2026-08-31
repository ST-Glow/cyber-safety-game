extends CanvasLayer

const EVENT_BRIDGE := preload("res://scripts/experiment_event_bridge.gd")
const UI_FONT: FontFile = preload("res://assets/ui/fonts/noto_sans_sc_ui_600.ttf")

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const HUB_SCENE := "res://scenes/digcomp_hub.tscn"

var back_button: Button
var _last_scene_path: String = ""
var _navigation_locked: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 85
	_build_button()
	call_deferred("_refresh_for_current_scene")


func _process(_delta: float) -> void:
	var scene_path := _current_scene_path()
	if scene_path != _last_scene_path:
		_last_scene_path = scene_path
		_navigation_locked = false
		_refresh_for_current_scene()


func destination_for_scene(scene_path: String) -> String:
	if scene_path.is_empty() or scene_path == MAIN_MENU_SCENE:
		return ""
	if scene_path == HUB_SCENE:
		return MAIN_MENU_SCENE
	if _is_digcomp_study_active():
		return HUB_SCENE
	return MAIN_MENU_SCENE


func _build_button() -> void:
	back_button = Button.new()
	back_button.name = "GlobalBackButton"
	back_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	back_button.position = Vector2(18.0, -66.0)
	back_button.size = Vector2(166.0, 48.0)
	back_button.focus_mode = Control.FOCUS_NONE
	back_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	back_button.add_theme_font_override("font", UI_FONT)
	back_button.add_theme_font_size_override("font_size", 16)
	back_button.add_theme_color_override("font_color", Color("d9edf7"))
	back_button.add_theme_color_override("font_hover_color", Color.WHITE)
	back_button.add_theme_stylebox_override("normal", _button_style(Color(0.025, 0.075, 0.14, 0.92), Color("3b7898"), 1))
	back_button.add_theme_stylebox_override("hover", _button_style(Color(0.05, 0.18, 0.27, 0.98), Color("68ddcf"), 2))
	back_button.add_theme_stylebox_override("pressed", _button_style(Color(0.02, 0.10, 0.17, 1.0), Color("68ddcf"), 2))
	back_button.pressed.connect(_on_back_pressed)
	add_child(back_button)


func _refresh_for_current_scene() -> void:
	if back_button == null:
		return
	var scene_path := _current_scene_path()
	var destination := destination_for_scene(scene_path)
	back_button.visible = not destination.is_empty()
	back_button.disabled = _navigation_locked
	if destination == HUB_SCENE:
		back_button.position = Vector2(18.0, -66.0)
		back_button.size = Vector2(166.0, 48.0)
		back_button.add_theme_font_size_override("font_size", 16)
		back_button.text = "←  返回能力大厅"
	elif destination == MAIN_MENU_SCENE:
		if scene_path == HUB_SCENE:
			back_button.position = Vector2(18.0, -62.0)
			back_button.size = Vector2(48.0, 44.0)
			back_button.add_theme_font_size_override("font_size", 21)
			back_button.text = "←"
			back_button.tooltip_text = "返回主菜单"
		else:
			back_button.position = Vector2(18.0, -66.0)
			back_button.size = Vector2(166.0, 48.0)
			back_button.add_theme_font_size_override("font_size", 16)
			back_button.text = "←  返回主菜单"


func _on_back_pressed() -> void:
	if _navigation_locked:
		return
	var source_path := _current_scene_path()
	var destination := destination_for_scene(source_path)
	if destination.is_empty():
		return
	_navigation_locked = true
	back_button.disabled = true
	_record_return(source_path, destination)
	if destination == HUB_SCENE:
		var change_error := int(get_node("/root/DigCompSession").call("start_hub", false))
		if change_error != OK:
			_unlock_after_error(change_error)
		return
	var transition := get_node_or_null("/root/SceneTransition")
	var change_error := OK
	if transition and transition.has_method("request_scene_change"):
		change_error = int(transition.call("request_scene_change", MAIN_MENU_SCENE, "AI训练场大挑战"))
	else:
		change_error = get_tree().change_scene_to_file(MAIN_MENU_SCENE)
	if change_error != OK:
		_unlock_after_error(change_error)


func _record_return(source_path: String, destination: String) -> void:
	var level_id := source_path.get_file().get_basename()
	var campaign := get_node_or_null("/root/CampaignSession")
	if campaign and not String(campaign.get("active_level_id")).is_empty():
		level_id = String(campaign.get("active_level_id"))
	EVENT_BRIDGE.record(self, "scene_return_requested", level_id, {
		"source_scene": source_path,
		"destination_scene": destination,
		"task_completed": false,
	})


func _unlock_after_error(change_error: int) -> void:
	_navigation_locked = false
	back_button.disabled = false
	push_error("Unable to return from scene: %s" % error_string(change_error))


func _current_scene_path() -> String:
	if get_tree() == null or get_tree().current_scene == null:
		return ""
	return get_tree().current_scene.scene_file_path


func _is_digcomp_study_active() -> bool:
	var session := get_node_or_null("/root/DigCompSession")
	return session != null and bool(session.get("session_active"))


func _button_style(color: Color, border_color: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.border_width_left = border_width
	style.border_width_right = border_width
	style.border_width_top = border_width
	style.border_width_bottom = border_width
	style.border_color = border_color
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.32)
	style.shadow_size = 7
	style.content_margin_left = 13
	style.content_margin_right = 13
	return style
