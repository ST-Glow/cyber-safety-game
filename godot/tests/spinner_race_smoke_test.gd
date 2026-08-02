extends SceneTree

const TEST_CLEANUP := preload("res://tests/test_cleanup.gd")

var failures: Array[String] = []
var finished_results: Array[Dictionary] = []
var respawn_count: int = 0
var game_instance: Node


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var race_scene := load("res://scenes/levels/spinner_race/spinner_race.tscn") as PackedScene
	_expect(race_scene != null, "spinner_race scene loads")
	_expect(load("res://scenes/main.tscn") != null, "original Demo scene still loads")
	_expect(load("res://scenes/obstacles/moving_platform.tscn") != null, "reusable moving platform scene loads")
	_expect(load("res://scenes/obstacles/side_pusher.tscn") != null, "reusable side pusher scene loads")
	if race_scene == null:
		call_deferred("_finish")
		return

	var game := race_scene.instantiate()
	game_instance = game
	root.add_child(game)
	await process_frame
	await physics_frame

	var manager := game.get_node_or_null("RaceManager") as SpinnerRaceManager
	var player := game.get_node_or_null("RangerPlayer") as PlayerController
	var spinner := game.get_node_or_null("Obstacles/Spinner") as RotatingSweeper
	var mover_a := game.get_node_or_null("Obstacles/MovingPlatformA") as MovingPlatform
	var mover_b := game.get_node_or_null("Obstacles/MovingPlatformB") as MovingPlatform
	var left_route_spinner := game.get_node_or_null("Obstacles/LeftRouteSpinner") as RotatingSweeper
	var right_route_spinner := game.get_node_or_null("Obstacles/RightRouteSpinner") as RotatingSweeper
	var moving_dock_a := game.get_node_or_null("Track/MovingDockA") as StaticBody3D
	var moving_dock_b := game.get_node_or_null("Track/MovingDockB") as StaticBody3D
	var pusher := game.get_node_or_null("Obstacles/SidePusher1") as SidePusher
	var checkpoint := game.get_node_or_null("Checkpoints/Checkpoint1") as RaceCheckpoint
	var finish_trigger := game.get_node_or_null("FinishTrigger") as Area3D
	var race_ui := game.get_node_or_null("RaceUI") as SpinnerRaceUI
	var camera_rig := game.get_node_or_null("CameraRig") as Node3D
	var spring_arm := game.get_node_or_null("CameraRig/SpringArm3D") as SpringArm3D
	_expect(manager != null, "race manager exists")
	_expect(player != null, "shared Ranger player exists")
	_expect(spinner != null, "rotating bar exists")
	_expect(spinner != null and spinner.get_node_or_null("RoundedSweepArm") != null, "spinner uses rounded party-game beam visual")
	_expect(spinner != null and spinner.get_node_or_null("SafetyBand1") != null, "spinner uses compact safety bands instead of a white cover strip")
	_expect(spinner != null and spinner.get_node_or_null("SweepAudio") != null, "spinner has spatial sweep audio")
	_expect(mover_a != null and mover_b != null, "two moving platforms exist")
	_expect(left_route_spinner != null and right_route_spinner != null, "both finish lanes have a spinner")
	_expect(moving_dock_a != null and moving_dock_b != null, "moving section has two staging docks")
	_expect(pusher != null, "side pusher exists")
	_expect(checkpoint != null, "checkpoint exists")
	_expect(checkpoint != null and checkpoint.get_node_or_null("CheckpointAudio") != null, "checkpoint has activation audio")
	_expect(checkpoint != null and checkpoint.get_node_or_null("CheckpointFloorStrip") != null, "checkpoint has a full-width pulsing floor light")
	_expect(finish_trigger != null, "finish trigger exists")
	_expect(race_ui != null, "spinner race quiz UI exists")
	_expect(spring_arm != null and spring_arm.collision_mask == 1, "spinner camera ignores moving hazards")
	_expect(InputMap.has_action("camera_left") and InputMap.has_action("camera_right") and InputMap.has_action("camera_reset"), "spinner race exposes rotate and recenter camera controls")
	_expect(race_ui != null and race_ui.get_node_or_null("CountdownAudio") != null, "race countdown has audio feedback")
	_expect(game.find_children("KayKitPlatformVisual", "Node3D", true, false).size() >= 8, "KayKit platform visuals replace grey boxes")
	_expect(game.find_children("KayKit*Rail*", "Node3D", true, false).size() >= 20, "KayKit padded rail visuals line the pusher lane")
	_expect(game.get_node_or_null("Track/KayKitFinishSign") != null, "KayKit finish sign replaces placeholder finish art")
	_expect(mover_a.get_node_or_null("KayKitPlatformVisual") != null, "moving platform uses KayKit arrow visual")
	_expect(race_ui.option_buttons[0].icon != null, "quiz options use Kenney icons")
	_expect(race_ui.result_overlay.find_child("KenneyResultStar", true, false) != null, "result card uses Kenney star art")
	for question_path in [
		"res://resources/quiz/spinner_race/checkpoint_1_ai_capability.tres",
		"res://resources/quiz/spinner_race/checkpoint_2_effective_prompt.tres",
		"res://resources/quiz/spinner_race/checkpoint_3_fact_check.tres",
		"res://resources/quiz/spinner_race/checkpoint_4_responsible_use.tres",
	]:
		var question := load(question_path) as QuizQuestion
		_expect(question != null and question.options.size() == 3, "%s is a three-option question" % question_path.get_file())
	if manager == null or player == null or spinner == null or mover_a == null or checkpoint == null or race_ui == null:
		call_deferred("_finish")
		return

	manager.race_finished.connect(_on_race_finished)
	manager.player_respawned.connect(_on_player_respawned)
	_expect(manager.state == SpinnerRaceManager.RaceState.COUNTDOWN, "level starts in countdown")
	_expect(not player.controls_enabled, "movement is locked during countdown")
	_expect(is_equal_approx(manager.time_left, 90.0), "race time limit is 90 seconds")
	_expect(_count_collision_shapes(game.get_node("Track")) >= 20, "track platforms have collision shapes")
	_expect(
		moving_dock_a != null and moving_dock_b != null
		and is_zero_approx(moving_dock_a.position.x)
		and is_zero_approx(moving_dock_b.position.x),
		"moving-section staging docks stay centered on the course"
	)
	_expect(
		_z_gap(moving_dock_a.position.z, 4.0, mover_a.position.z, mover_a.platform_size.z) >= 0.2
		and _z_gap(mover_a.position.z, mover_a.platform_size.z, mover_b.position.z, mover_b.platform_size.z) >= 0.2
		and _z_gap(mover_b.position.z, mover_b.platform_size.z, moving_dock_b.position.z, 4.0) >= 0.2,
		"moving-section platform collision bounds do not overlap"
	)
	_expect(
		is_equal_approx(mover_a.position.x, -mover_b.position.x)
		and is_equal_approx(mover_a.movement_offset.x, -mover_b.movement_offset.x)
		and is_equal_approx(mover_a.period_seconds, mover_b.period_seconds)
		and is_equal_approx(mover_a.initial_phase, mover_b.initial_phase),
		"moving platforms remain mirrored throughout their animation"
	)
	_expect(_branch_routes_are_mirrored(game), "left and right finish lanes are mirrored and continuous")
	_expect(
		_route_spinners_are_mirrored(left_route_spinner, right_route_spinner),
		"finish-lane spinners have mirrored geometry and motion"
	)

	var mover_start := mover_a.position
	var spinner_start := spinner.rotation.y
	manager.begin_race_now()
	await _wait_physics_frames(18)
	_expect(manager.state == SpinnerRaceManager.RaceState.RUNNING, "countdown completion starts race")
	_expect(player.controls_enabled, "controls unlock when race starts")
	var camera_yaw_before := camera_rig.rotation.y
	Input.action_press("camera_left")
	for _frame in range(8):
		await process_frame
	Input.action_release("camera_left")
	_expect(not is_equal_approx(camera_rig.rotation.y, camera_yaw_before), "Q/E rotates the spinner-race camera")
	Input.action_press("camera_reset")
	await process_frame
	Input.action_release("camera_reset")
	_expect(absf(angle_difference(float(game.get("camera_target_yaw")), player.get_facing_yaw())) < 0.01, "R recenters the spinner-race camera")
	_expect(mover_a.position.distance_to(mover_start) > 0.15, "moving platform travels on its fixed cycle")
	_expect(not is_equal_approx(spinner.rotation.y, spinner_start), "spinner rotates on its fixed cycle")

	# A checkpoint opens its quiz before changing the saved respawn transform.
	# Enter it near the top of a normal jump instead of calling the handler
	# directly, preventing regressions where jumping can bypass the trigger.
	player.global_position = checkpoint.global_position + Vector3(0.0, 4.0, 0.0)
	player.velocity = Vector3.ZERO
	for _frame in range(12):
		if manager.state == SpinnerRaceManager.RaceState.QUIZ:
			break
		await physics_frame
	var time_before_quiz := manager.elapsed_seconds
	_expect(manager.state == SpinnerRaceManager.RaceState.QUIZ, "checkpoint opens quiz state")
	_expect(paused, "jump-height checkpoint crossing triggers the quiz")
	_expect(paused, "checkpoint quiz pauses the scene tree")
	_expect(not player.controls_enabled, "checkpoint quiz locks movement")
	_expect(manager.checkpoint_index == 0 and not checkpoint.is_activated, "checkpoint is not saved before a correct answer")
	_expect(race_ui.quiz_overlay.visible, "checkpoint quiz card is visible")
	await _wait_physics_frames(6)
	_expect(is_equal_approx(manager.elapsed_seconds, time_before_quiz), "timer stops during checkpoint quiz")

	# Wrong answers explain and retry; correct answers save the checkpoint and resume.
	race_ui.call("_on_option_pressed", 1)
	await process_frame
	_expect(manager.state == SpinnerRaceManager.RaceState.QUIZ, "wrong answer keeps checkpoint quiz open")
	_expect(manager.quiz_attempts_by_checkpoint[0] == 1, "wrong answer records one attempt")
	_expect(not checkpoint.is_activated, "wrong answer does not save checkpoint")
	race_ui.call("_on_option_pressed", 0)
	await process_frame
	_expect(manager.state == SpinnerRaceManager.RaceState.RUNNING, "correct answer resumes race")
	_expect(not paused and player.controls_enabled, "correct answer resumes physics and movement")
	_expect(manager.checkpoint_index == 1, "correct answer updates checkpoint index")
	_expect(checkpoint.is_activated, "correct answer activates checkpoint")
	_expect(not checkpoint.is_processing(), "activated checkpoint stops pulse processing")
	_expect(manager.quiz_attempts_by_checkpoint[0] == 2, "correct retry records both attempts")
	var checkpoint_spawn := manager.checkpoint_transform.origin
	var time_before_fall := manager.elapsed_seconds

	# Falling must add one fall, preserve elapsed time, and respawn at the latest checkpoint.
	player.global_position.y = -8.5
	await _wait_physics_frames(3)
	_expect(manager.falls == 1, "fall count increments once")
	await _wait_physics_frames(32)
	_expect(respawn_count == 1, "fall emits one respawn event")
	_expect(player.global_position.distance_to(checkpoint_spawn) < 0.5, "fall respawns at latest checkpoint")
	_expect(manager.elapsed_seconds > time_before_fall, "fall does not reset race timer")

	# Side push force is deliberate but bounded; it cannot create infinite launch velocity.
	game.call("_on_pusher_hit", player, Vector3.RIGHT)
	await physics_frame
	var lateral_speed := Vector2(player.velocity.x, player.velocity.z).length()
	_expect(lateral_speed >= 5.0 and lateral_speed <= 7.0, "side pusher applies bounded lateral force")
	_expect(manager.obstacle_hits == 1, "spinner race records a real obstacle hit")
	await _wait_physics_frames(24)
	_expect(player.controls_enabled, "controls return after pusher knockback")

	# Reaching the finish early must not bypass the remaining learning checkpoints.
	game.call("_on_finish_body_entered", player)
	await process_frame
	_expect(manager.state == SpinnerRaceManager.RaceState.RUNNING, "finish rejects an incomplete checkpoint sequence")
	_expect(finished_results.is_empty(), "early finish does not emit a result")
	_expect(not bool(game.get("finish_triggered")), "early finish does not consume the one-shot finish guard")
	_expect(not manager.open_checkpoint_quiz(4), "a later checkpoint cannot skip the next required checkpoint")

	# Complete checkpoints 2-4 in order. Their question resources define the
	# correct option, while this manager-level check focuses on progression.
	for checkpoint_index in range(2, 5):
		var question_path := "res://resources/quiz/spinner_race/checkpoint_%d_%s.tres" % [
			checkpoint_index,
			["", "", "effective_prompt", "fact_check", "responsible_use"][checkpoint_index],
		]
		var question := load(question_path) as QuizQuestion
		_expect(question != null, "checkpoint %d question is available for progression" % checkpoint_index)
		_expect(manager.open_checkpoint_quiz(checkpoint_index), "checkpoint %d opens in sequence" % checkpoint_index)
		_expect(manager.submit_quiz_answer(question.correct_index, question.correct_index), "checkpoint %d accepts its correct answer" % checkpoint_index)
		_expect(manager.activate_checkpoint(checkpoint_index, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, -20.0 * checkpoint_index))), "checkpoint %d saves in sequence" % checkpoint_index)

	# Finishing after every checkpoint is immediate and idempotent.
	game.call("_on_finish_body_entered", player)
	game.call("_on_finish_body_entered", player)
	await process_frame
	_expect(manager.state == SpinnerRaceManager.RaceState.FINISHED, "finish ends race immediately")
	_expect(finished_results.size() == 1, "finish can only emit once")
	_expect(bool(finished_results[0].get("success", false)), "finish result is successful")
	_expect(finished_results[0].has("elapsed_seconds") and finished_results[0].has("falls"), "result contains time and falls")
	_expect(finished_results[0].get("quiz_attempts", 0) == 5, "result contains all checkpoint quiz attempts")
	_expect(finished_results[0].has("score") and finished_results[0].has("score_breakdown"), "spinner result contains normalized score components")
	_expect(finished_results[0].get("score") == finished_results[0].get("normalized_score"), "spinner score and normalized score share the 100-point scale")
	_expect(finished_results[0].get("score_schema_version", -1) == 2 and int(finished_results[0].get("score_breakdown", {}).get("maximum", -1)) == 100, "spinner result uses score schema v2")

	# Restart returns mechanisms, checkpoints and results to the initial countdown state.
	game.call("_on_restart_requested")
	await _wait_physics_frames(2)
	_expect(manager.state == SpinnerRaceManager.RaceState.COUNTDOWN, "restart returns to countdown")
	_expect(manager.falls == 0 and manager.obstacle_hits == 0 and manager.checkpoint_index == 0, "restart clears falls, hits and checkpoint")
	_expect(manager.quiz_attempts_by_checkpoint == [0, 0, 0, 0], "restart clears checkpoint quiz attempts")
	_expect(not checkpoint.is_activated, "restart resets checkpoint visuals and state")
	_expect(checkpoint.is_processing(), "restart resumes checkpoint pulse processing")
	_expect(mover_a.position.distance_to(mover_start) < 0.01, "restart resets moving platform phase")
	_expect(is_equal_approx(spinner.rotation.y, spinner.initial_phase), "restart resets spinner phase")
	_expect(not bool(game.get("finish_triggered")), "restart resets one-shot finish guard")

	# A short test deadline exercises the same 90-second timeout branch without waiting 90 seconds.
	manager.time_limit_seconds = 0.08
	game.call("_on_restart_requested")
	manager.begin_race_now()
	await _wait_physics_frames(10)
	_expect(manager.state == SpinnerRaceManager.RaceState.FAILED, "deadline ends unfinished race as failure")
	_expect(finished_results.size() == 2 and not bool(finished_results[1].get("success", true)), "timeout emits one failure result")

	call_deferred("_finish")


func _count_collision_shapes(node: Node) -> int:
	var count := 1 if node is CollisionShape3D else 0
	for child in node.get_children():
		count += _count_collision_shapes(child)
	return count


func _z_gap(first_z: float, first_depth: float, second_z: float, second_depth: float) -> float:
	return absf(first_z - second_z) - (first_depth + second_depth) * 0.5


func _branch_routes_are_mirrored(game: Node) -> bool:
	var track := game.get_node("Track")
	var left_routes := track.find_children("LeftRoute*", "StaticBody3D", true, false)
	var right_routes := track.find_children("RightRoute*", "StaticBody3D", true, false)
	if left_routes.size() != 4 or right_routes.size() != 4:
		return false
	for left_route in left_routes:
		var has_mirror := false
		for right_route in right_routes:
			var left_box := _find_box_shape(left_route)
			var right_box := _find_box_shape(right_route)
			if (
				is_equal_approx(left_route.position.z, right_route.position.z)
				and is_equal_approx(left_route.position.x, -right_route.position.x)
				and left_box != null
				and right_box != null
				and left_box.size == right_box.size
			):
				has_mirror = true
				break
		if not has_mirror:
			return false
	return _route_is_continuous(left_routes) and _route_is_continuous(right_routes)


func _find_box_shape(body: Node) -> BoxShape3D:
	for child in body.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D:
			return child.shape as BoxShape3D
	return null


func _route_is_continuous(route_nodes: Array[Node]) -> bool:
	var centers: Array[float] = []
	var platform_depth := 0.0
	for route_node in route_nodes:
		var box := _find_box_shape(route_node)
		if box == null:
			return false
		platform_depth = box.size.z
		centers.append(route_node.position.z)
	centers.sort()
	for index in range(1, centers.size()):
		if not is_equal_approx(centers[index] - centers[index - 1], platform_depth):
			return false
	return true


func _route_spinners_are_mirrored(left_spinner: RotatingSweeper, right_spinner: RotatingSweeper) -> bool:
	if left_spinner == null or right_spinner == null:
		return false
	return (
		is_equal_approx(left_spinner.position.x, -right_spinner.position.x)
		and is_equal_approx(left_spinner.position.z, right_spinner.position.z)
		and is_equal_approx(left_spinner.arm_length, right_spinner.arm_length)
		and is_equal_approx(left_spinner.arm_height, right_spinner.arm_height)
		and is_equal_approx(left_spinner.arm_center_y, right_spinner.arm_center_y)
		and is_equal_approx(left_spinner.period_seconds, right_spinner.period_seconds)
		and is_equal_approx(left_spinner.initial_phase, PI - right_spinner.initial_phase)
		and is_equal_approx(left_spinner.rotation_direction, -right_spinner.rotation_direction)
	)


func _wait_physics_frames(frame_count: int) -> void:
	for _frame in range(frame_count):
		await physics_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		failures.append(label)
		push_error("[FAIL] %s" % label)


func _on_race_finished(result: Dictionary) -> void:
	finished_results.append(result.duplicate(true))


func _on_player_respawned(_checkpoint_index: int) -> void:
	respawn_count += 1


func _finish() -> void:
	paused = false
	for action in ["move_forward", "move_back", "move_left", "move_right", "jump", "dash", "camera_left", "camera_right", "camera_reset"]:
		Input.action_release(action)
	TEST_CLEANUP.stop_all_audio(root)
	if is_instance_valid(game_instance):
		game_instance.queue_free()
		await process_frame
		await process_frame
	await create_timer(0.25, true, false, true).timeout
	if failures.is_empty():
		print("SPINNER_RACE_SMOKE_TEST_OK")
		quit(0)
	else:
		print("SPINNER_RACE_SMOKE_TEST_FAILED: %s" % ", ".join(failures))
		quit(1)
