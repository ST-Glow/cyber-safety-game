extends SceneTree

const TEST_CLEANUP := preload("res://tests/test_cleanup.gd")

var failures: Array[String] = []
var finished_results: Array[Dictionary] = []
var game_instance: Node


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var level_scene := load("res://scenes/levels/data_chip_hunt/data_chip_hunt.tscn") as PackedScene
	_expect(level_scene != null, "data_chip_hunt scene loads")
	_expect(load("res://scenes/party/data_chip.tscn") != null, "reusable data chip scene loads")
	_expect(load("res://scenes/party/spring_pad.tscn") != null, "reusable spring pad scene loads")
	if level_scene == null:
		quit(1)
		return
	var game := level_scene.instantiate()
	game_instance = game
	root.add_child(game)
	await process_frame
	await physics_frame

	var manager := game.get_node_or_null("ModeManager") as PartyModeManager
	var player := game.get_node_or_null("RangerPlayer") as PlayerController
	var mode_ui := game.get_node_or_null("ModeUI") as PartyModeUI
	var chip_root := game.get_node_or_null("DataChips")
	var mover_a := game.get_node_or_null("MovingPlatforms/MovingPlatformA") as MovingPlatform
	var mover_b := game.get_node_or_null("MovingPlatforms/MovingPlatformB") as MovingPlatform
	var spring_root := game.get_node_or_null("SpringPads")
	var camera_rig := game.get_node_or_null("CameraRig") as Node3D
	var spring_arm := game.get_node_or_null("CameraRig/SpringArm3D") as SpringArm3D
	_expect(manager != null, "collection manager exists")
	_expect(player != null, "shared Ranger player exists in collection mode")
	_expect(mode_ui != null, "shared party UI exists")
	_expect(chip_root != null and chip_root.get_child_count() == 12, "exactly 12 data chips exist")
	_expect(mover_a != null and mover_b != null, "collection mode reuses two moving platforms")
	_expect(spring_root != null and spring_root.get_child_count() == 2, "two reusable spring pads exist")
	_expect(spring_arm != null and spring_arm.collision_mask == 1, "collection camera ignores moving hazards")
	_expect(InputMap.has_action("camera_left") and InputMap.has_action("camera_right") and InputMap.has_action("camera_reset"), "open modes expose camera rotate and recenter controls")
	_expect(game.find_children("KayKitCoin", "Node3D", true, false).size() == 12, "Prototype Bits coin art is used for all chips")
	_expect(game.find_children("*FlightHoop", "Node3D", true, false).size() == 2, "KayKit hoops mark the spring route")
	_expect(game.get_node_or_null("CollectionArena/PipeStraight") != null, "KayKit pipe art marks the moving route")
	_expect(game.find_children("*RouteBeacon*", "Node3D", true, false).size() == 9, "three collection routes have floor markers and paired beacons")
	_expect(mode_ui.option_buttons[0].icon != null, "new quiz cards use Kenney icons")
	for question_path in [
		"res://resources/quiz/data_chip_hunt/checkpoint_1_training_data.tres",
		"res://resources/quiz/data_chip_hunt/checkpoint_2_prediction.tres",
	]:
		var question := load(question_path) as QuizQuestion
		_expect(question != null and question.options.size() == 3, "%s is a three-option question" % question_path.get_file())
	if manager == null or player == null or mode_ui == null or chip_root == null or mover_a == null:
		call_deferred("_finish")
		return

	manager.run_finished.connect(_on_run_finished)
	_expect(manager.state == PartyModeManager.RunState.COUNTDOWN, "collection level starts in countdown")
	_expect(not player.controls_enabled, "collection controls are locked during countdown")
	_expect(is_equal_approx(manager.time_left, 75.0), "collection deadline is 75 seconds")
	manager.begin_run_now()
	await physics_frame
	_expect(manager.is_running() and player.controls_enabled, "countdown completion starts collection")
	_expect(not manager.finish(true), "collection cannot finish before both learning checkpoints")
	var spring_pad := spring_root.get_child(0) as PartySpringPad
	var spring_visual := spring_pad.get_node("SpringPadVisual") as Node3D
	var spring_scale_before := spring_visual.scale
	player.velocity.y = 0.0
	spring_pad.call("_on_body_entered", player)
	_expect(player.velocity.y >= spring_pad.bounce_velocity, "spring pad applies its configured bounce velocity")
	_expect(float(spring_pad.get("_cooldown_left")) > 0.0, "spring pad starts its retrigger cooldown")
	await create_timer(0.05, true, false, true).timeout
	_expect(spring_pad.is_processing() and not spring_visual.scale.is_equal_approx(spring_scale_before), "spring pad pulse remains active")
	var mover_start := mover_a.position
	var camera_yaw_before := camera_rig.rotation.y
	Input.action_press("camera_right")
	for _frame in range(8):
		await process_frame
	Input.action_release("camera_right")
	_expect(not is_equal_approx(camera_rig.rotation.y, camera_yaw_before), "Q/E rotates the open-mode camera")
	Input.action_press("camera_reset")
	await process_frame
	Input.action_release("camera_reset")
	_expect(absf(angle_difference(float(game.get("camera_target_yaw")), player.get_facing_yaw())) < 0.01, "R recenters an open-mode camera behind the player")
	await _wait_physics_frames(12)
	_expect(mover_a.position.distance_to(mover_start) > 0.05, "collection moving platform follows fixed cycle")

	var chips: Array[DataChip] = []
	for child in chip_root.get_children():
		chips.append(child as DataChip)
	for index in range(6):
		_expect(chips[index].collect(), "chip %d collects once" % (index + 1))
	_expect(int(game.get("collected_count")) == 6, "six unique chips update collection progress")
	_expect(manager.state == PartyModeManager.RunState.QUIZ and paused, "sixth chip opens and pauses first quiz")
	_expect(not chips[0].collect(), "collected chip cannot score twice")
	var paused_time := manager.elapsed_seconds
	await _wait_physics_frames(5)
	_expect(is_equal_approx(manager.elapsed_seconds, paused_time), "collection timer stops during quiz")
	mode_ui.call("_on_option_pressed", 1)
	await process_frame
	_expect(manager.quiz_attempts_by_slot[0] == 1 and manager.state == PartyModeManager.RunState.QUIZ, "wrong collection answer retries")
	mode_ui.call("_on_option_pressed", 0)
	await process_frame
	_expect(manager.is_running() and not paused and player.controls_enabled, "correct collection answer resumes play")
	_expect(manager.quiz_attempts_by_slot[0] == 2, "collection quiz records both attempts")

	var elapsed_before_fall := manager.elapsed_seconds
	game.call("_on_player_fell")
	await _wait_physics_frames(32)
	_expect(manager.falls == 1, "collection fall count increments")
	_expect(int(game.get("collected_count")) == 6, "collected chips persist after respawn")
	_expect(manager.elapsed_seconds > elapsed_before_fall, "collection fall does not reset time")

	for index in range(6, 12):
		chips[index].collect()
	_expect(int(game.get("collected_count")) == 12, "all 12 chips can be collected")
	_expect(manager.state == PartyModeManager.RunState.QUIZ and paused, "last chip opens final quiz")
	mode_ui.call("_on_option_pressed", 0)
	await process_frame
	_expect(manager.state == PartyModeManager.RunState.FINISHED, "correct final answer completes collection mode")
	_expect(finished_results.size() == 1, "collection finish emits once")
	_expect(int(finished_results[0].get("collected_count", 0)) == 12, "collection result contains chip count")
	_expect(finished_results[0].get("quiz_attempts_by_checkpoint", []) == [2, 1], "collection result contains quiz attempts")
	_expect(finished_results[0].has("score") and finished_results[0].has("score_breakdown"), "collection result contains normalized score components")

	game.call("_on_restart_requested")
	await _wait_physics_frames(2)
	_expect(manager.state == PartyModeManager.RunState.COUNTDOWN, "collection restart returns to countdown")
	_expect(int(game.get("collected_count")) == 0 and manager.falls == 0, "collection restart clears progress and falls")
	_expect(not chips[0].is_collected and chips[0].visible, "collection restart restores chips")
	_expect(mover_a.position.distance_to(mover_start) < 0.08, "collection restart resets moving platform phase")

	manager.time_limit_seconds = 0.08
	game.call("_on_restart_requested")
	manager.begin_run_now()
	await _wait_physics_frames(10)
	_expect(manager.state == PartyModeManager.RunState.FAILED, "collection timeout fails unfinished run")
	_expect(finished_results.size() == 2 and not bool(finished_results[1].get("success", true)), "collection timeout emits one failure result")
	call_deferred("_finish")


func _wait_physics_frames(frame_count: int) -> void:
	for _frame in range(frame_count):
		await physics_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		failures.append(label)
		push_error("[FAIL] %s" % label)


func _on_run_finished(result: Dictionary) -> void:
	finished_results.append(result.duplicate(true))


func _finish() -> void:
	paused = false
	Input.action_release("camera_left")
	Input.action_release("camera_right")
	Input.action_release("camera_reset")
	TEST_CLEANUP.stop_all_audio(root)
	if is_instance_valid(game_instance):
		game_instance.queue_free()
		await process_frame
		await process_frame
	await create_timer(0.25, true, false, true).timeout
	if failures.is_empty():
		print("DATA_CHIP_HUNT_SMOKE_TEST_OK")
		quit(0)
	else:
		print("DATA_CHIP_HUNT_SMOKE_TEST_FAILED: %s" % ", ".join(failures))
		quit(1)
