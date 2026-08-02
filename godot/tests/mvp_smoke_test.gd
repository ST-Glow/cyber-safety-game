extends SceneTree

const TEST_CLEANUP := preload("res://tests/test_cleanup.gd")
const INPUT_DEFAULTS := preload("res://scripts/input_defaults.gd")
const RUN_SCORING := preload("res://scripts/run_scoring.gd")

var failures: Array[String] = []
var jump_event_count: int = 0
var dash_event_count: int = 0
var respawn_event_count: int = 0
var completed_result: Dictionary = {}
var game_instance: Node


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var expected_input_keys := {
		&"move_forward": [KEY_W, KEY_UP],
		&"move_back": [KEY_S, KEY_DOWN],
		&"move_left": [KEY_A, KEY_LEFT],
		&"move_right": [KEY_D, KEY_RIGHT],
		&"jump": [KEY_SPACE],
		&"dash": [KEY_SHIFT],
		&"camera_left": [KEY_Q],
		&"camera_right": [KEY_E],
		&"camera_reset": [KEY_R],
	}
	for action_name: StringName in expected_input_keys:
		_expect(InputMap.has_action(action_name), "%s is defined by project input settings" % action_name)
		for keycode: Key in expected_input_keys[action_name]:
			_expect(_action_has_physical_key(action_name, keycode), "%s includes physical key %d" % [action_name, keycode])
	InputMap.erase_action(&"camera_reset")
	INPUT_DEFAULTS.ensure_actions()
	_expect(_action_has_physical_key(&"camera_reset", KEY_R), "central runtime input fallback restores a missing action")
	var golden_score := RUN_SCORING.build_score([2], 0, 0, 0.0, 135.0, true)
	_expect(int(golden_score.get("total", -1)) == 80 and int(golden_score.get("stars", -1)) == 2, "two-attempt clean scoring golden case is 80 points and two stars")
	_expect(int(golden_score.get("maximum", -1)) == 100, "shared score breakdown declares a 100-point maximum")

	var main_scene := load("res://scenes/main.tscn") as PackedScene
	_expect(main_scene != null, "main scene loads")
	if main_scene == null:
		call_deferred("_finish")
		return

	var game := main_scene.instantiate()
	game_instance = game
	root.add_child(game)
	await process_frame
	await physics_frame

	var manager := game.get_node_or_null("GameManager") as GameManager
	var player := game.get_node_or_null("RangerPlayer") as PlayerController
	var sweeper := game.get_node_or_null("Obstacles/CognitionSweeper") as RotatingSweeper
	var camera_rig := game.get_node_or_null("CameraRig") as Node3D
	var spring_arm := game.get_node_or_null("CameraRig/SpringArm3D") as SpringArm3D
	var game_ui := game.get_node_or_null("GameUI") as GameUI
	_expect(manager != null, "game manager exists")
	_expect(player != null, "Ranger player exists")
	_expect(game_ui != null, "first-level UI exists")
	var animation_player := player.get("_animation_player") as AnimationPlayer if player else null
	_expect(animation_player != null, "Ranger animation player exists")
	if animation_player:
		var expected_animations := {
			"Idle": "General/Idle_A",
			"Cheering": "Simulation/Cheering",
			"Hit_A": "General/Hit_A",
			"Dodge_Forward": "MovementAdvanced/Dodge_Forward",
			"Jump_Start": "MovementBasic/Jump_Start",
			"Jump_Full_Short": "MovementBasic/Jump_Full_Short",
			"Jump_Land": "MovementBasic/Jump_Land",
			"Running_A": "MovementBasic/Running_A",
		}
		var missing_animation_targets := 0
		var animation_root := animation_player.get_node(animation_player.root_node)
		for token in expected_animations:
			var resolved: StringName = player.call("_resolve_animation", token)
			_expect(String(resolved) == String(expected_animations[token]), "%s resolves to the intended KayKit animation" % token)
			var animation := animation_player.get_animation(resolved)
			if animation == null:
				continue
			for track_index in range(animation.get_track_count()):
				var target_path := NodePath(animation.track_get_path(track_index).get_concatenated_names())
				if not target_path.is_empty() and animation_root.get_node_or_null(target_path) == null:
					missing_animation_targets += 1
		_expect(missing_animation_targets == 0, "KayKit animation tracks target the Ranger rig")
		_expect(animation_player.get_animation(&"General/Idle_A").loop_mode == Animation.LOOP_NONE, "idle loop mode remains unchanged during performance work")
		_expect(animation_player.get_animation(&"MovementBasic/Running_A").loop_mode == Animation.LOOP_NONE, "running loop mode remains unchanged during performance work")
		var cache_size := int((player.get("_animation_token_cache") as Dictionary).size())
		player.call("_resolve_animation", &"Idle")
		_expect(int((player.get("_animation_token_cache") as Dictionary).size()) == cache_size, "resolved animation tokens are served from cache")
	_expect(sweeper != null, "rotating sweeper exists")
	_expect(spring_arm != null and spring_arm.collision_mask == 1, "camera collides with static course geometry only")
	_expect(InputMap.has_action("camera_left") and InputMap.has_action("camera_right") and InputMap.has_action("camera_reset"), "main level exposes rotate and recenter camera controls")
	if manager == null or player == null or sweeper == null or game_ui == null:
		call_deferred("_finish")
		return

	manager.jump_used.connect(_on_jump_used)
	manager.dash_used.connect(_on_dash_used)
	manager.player_respawned.connect(_on_player_respawned)
	manager.run_completed.connect(_on_run_completed)

	game.call("_on_start_requested")
	await _wait_physics_frames(3)
	_expect(manager.state == GameManager.GameState.RUNNING, "start enters RUNNING state")
	_expect(game_ui.score_label.text.contains("过程表现") and game_ui.score_label.text.contains("/ 40"), "running HUD labels the 40-point process score")
	var camera_yaw_before := camera_rig.rotation.y
	Input.action_press("camera_right")
	for _frame in range(8):
		await process_frame
	Input.action_release("camera_right")
	_expect(not is_equal_approx(camera_rig.rotation.y, camera_yaw_before), "Q/E rotates the main-level camera")
	Input.action_press("camera_reset")
	await process_frame
	Input.action_release("camera_reset")
	_expect(absf(angle_difference(float(game.get("camera_target_yaw")), player.get_facing_yaw())) < 0.01, "R recenters the main camera behind the player facing")

	var start_z := player.global_position.z
	Input.action_press("move_forward")
	await _wait_physics_frames(24)
	Input.action_release("move_forward")
	_expect(player.global_position.z < start_z - 1.2, "forward input moves toward negative Z")

	var grounded_y := player.global_position.y
	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	await _wait_physics_frames(8)
	_expect(player.global_position.y > grounded_y + 0.45, "jump rises above the track")
	_expect(player.velocity.y > 0.0, "jump has positive vertical velocity")
	_expect(jump_event_count == 1, "jump_used emits once")
	var visual_root := player.get_node_or_null("VisualRoot") as Node3D
	_expect(visual_root != null and visual_root.scale.distance_to(Vector3.ONE) > 0.004, "jump applies subtle squash-and-stretch feedback")

	Input.action_press("move_forward")
	Input.action_press("dash")
	await physics_frame
	Input.action_release("dash")
	Input.action_release("camera_left")
	Input.action_release("camera_right")
	Input.action_release("camera_reset")
	await _wait_physics_frames(3)
	Input.action_release("move_forward")
	_expect(player.dash_cooldown_left > 2.0, "dash starts a 2.5 second cooldown")
	_expect(dash_event_count == 1, "dash_used emits once")

	var phase_before_pause := sweeper.rotation.y
	manager.set_assistant_open(true)
	await _wait_physics_frames(20)
	var phase_during_pause := sweeper.rotation.y
	_expect(is_equal_approx(phase_before_pause, phase_during_pause), "assistant pauses obstacle phase")
	manager.set_assistant_open(false)
	await _wait_physics_frames(8)
	_expect(not is_equal_approx(phase_during_pause, sweeper.rotation.y), "obstacle resumes from paused phase")

	player.global_position.y = -8.5
	await _wait_physics_frames(2)
	_expect(manager.falls == 1, "fall is recorded")
	_expect(manager.state == GameManager.GameState.KNOCKBACK, "fall enters KNOCKBACK state")
	await _wait_physics_frames(38)
	_expect(respawn_event_count == 1, "fall triggers one respawn event")
	_expect(manager.state == GameManager.GameState.RUNNING, "respawn returns to RUNNING state")
	_expect(player.global_position.distance_to(Vector3(0.0, 0.08, 5.0)) < 0.35, "respawn returns to the course start")

	game.call("_on_restart_requested")
	await _wait_physics_frames(2)
	_expect(manager.obstacle_hits == 0 and manager.falls == 0, "restart clears hit and fall counters")
	_expect(manager.quiz_attempts == 0, "restart clears quiz attempts")

	game.call("_on_finish_body_entered", player)
	await process_frame
	_expect(manager.state == GameManager.GameState.QUIZ, "finish opens quiz and pauses the run")
	var quiz_phase := sweeper.rotation.y
	await _wait_physics_frames(12)
	_expect(is_equal_approx(quiz_phase, sweeper.rotation.y), "quiz pauses obstacle phase")

	game.call("_on_quiz_choice_selected", 1)
	_expect(manager.quiz_attempts == 1, "wrong answer counts one attempt")
	_expect(manager.state == GameManager.GameState.QUIZ, "wrong answer keeps quiz open")
	game.call("_on_quiz_choice_selected", 0)
	await process_frame
	_expect(manager.state == GameManager.GameState.FINISHED, "correct answer finishes the run")
	_expect(manager.quiz_attempts == 2, "correct retry records two attempts")
	_expect(completed_result.get("score", -1) == 80, "two-attempt clean run scores 80")
	_expect(completed_result.get("stars", -1) == 2, "score 80 awards two stars")
	_expect(completed_result.get("normalized_score", -1) == 80, "first-level normalized score matches its 100-point score")
	_expect(completed_result.get("score_schema_version", -1) == 2, "first-level result uses score schema v2")
	_expect(int(completed_result.get("score_breakdown", {}).get("maximum", -1)) == 100, "first-level score breakdown has a 100-point maximum")
	_expect(game_ui.result_score.text.contains("综合评分") and game_ui.result_score.text.contains("/ 100"), "result UI labels the 100-point composite score")
	for key in ["elapsed_seconds", "obstacle_hits", "falls", "quiz_attempts", "score", "normalized_score", "score_breakdown", "stars"]:
		_expect(completed_result.has(key), "run_completed result contains %s" % key)

	call_deferred("_finish")


func _wait_physics_frames(frame_count: int) -> void:
	for _frame in range(frame_count):
		await physics_frame


func _action_has_physical_key(action_name: StringName, keycode: Key) -> bool:
	for event in InputMap.action_get_events(action_name):
		if event is InputEventKey and event.physical_keycode == keycode:
			return true
	return false


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		failures.append(label)
		push_error("[FAIL] %s" % label)


func _on_jump_used() -> void:
	jump_event_count += 1


func _on_dash_used() -> void:
	dash_event_count += 1


func _on_player_respawned() -> void:
	respawn_event_count += 1


func _on_run_completed(result: Dictionary) -> void:
	completed_result = result.duplicate(true)


func _finish() -> void:
	paused = false
	Input.action_release("move_forward")
	Input.action_release("move_back")
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("jump")
	Input.action_release("dash")
	TEST_CLEANUP.stop_all_audio(root)
	if is_instance_valid(game_instance):
		game_instance.queue_free()
		await process_frame
		await process_frame
	await create_timer(0.25, true, false, true).timeout
	if failures.is_empty():
		print("MVP_SMOKE_TEST_OK")
		quit(0)
	else:
		print("MVP_SMOKE_TEST_FAILED: %s" % ", ".join(failures))
		quit(1)
