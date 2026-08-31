class_name InputDefaults
extends RefCounted

const ACTION_KEYS := {
	&"move_forward": [KEY_W, KEY_UP],
	&"move_back": [KEY_S, KEY_DOWN],
	&"move_backward": [KEY_S, KEY_DOWN],
	&"move_left": [KEY_A, KEY_LEFT],
	&"move_right": [KEY_D, KEY_RIGHT],
	&"jump": [KEY_SPACE],
	&"dash": [KEY_SHIFT],
	&"sprint": [KEY_SHIFT],
	&"interact": [KEY_E],
	&"task_help": [KEY_F],
	&"camera_left": [KEY_Q],
	&"camera_right": [KEY_E],
	&"camera_reset": [KEY_R],
}


static func ensure_actions() -> void:
	for action_name: StringName in ACTION_KEYS:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name, 0.2)
		for keycode: Key in ACTION_KEYS[action_name]:
			var input_event := InputEventKey.new()
			input_event.physical_keycode = keycode
			if not InputMap.action_has_event(action_name, input_event):
				InputMap.action_add_event(action_name, input_event)
