extends SceneTree

const TEST_CLEANUP := preload("res://tests/test_cleanup.gd")

var failures: Array[String] = []
var finished_results: Array[Dictionary] = []
var game_instance: Node


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var level_scene := load("res://scenes/levels/signal_bomb_survival/signal_bomb_survival.tscn") as PackedScene
	_expect(level_scene != null, "signal_bomb_survival scene loads")
	_expect(load("res://scenes/party/path_hazard.tscn") != null, "reusable path hazard scene loads")
	_expect(load("res://scenes/party/timed_bomb.tscn") != null, "reusable timed bomb scene loads")
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
	var ball_root := game.get_node_or_null("RollingBalls")
	var bomb_root := game.get_node_or_null("TimedBombs")
	var calibration_root := game.get_node_or_null("CalibrationZones")
	var spinner := game.get_node_or_null("WaveObstacles/ArenaSpinner") as RotatingSweeper
	var pusher := game.get_node_or_null("WaveObstacles/ArenaPusherA") as SidePusher
	var spring_arm := game.get_node_or_null("CameraRig/SpringArm3D") as SpringArm3D
	_expect(manager != null, "survival manager exists")
	_expect(player != null, "shared Ranger player exists in survival mode")
	_expect(mode_ui != null and mode_ui.final_level, "final party UI exists")
	_expect(ball_root != null and ball_root.get_child_count() == 4, "four deterministic rolling balls exist")
	_expect(bomb_root != null and bomb_root.get_child_count() == 6, "six timed bomb positions exist")
	_expect(calibration_root != null and calibration_root.get_child_count() == 3, "three fixed wave calibration zones exist")
	_expect(spinner != null and pusher != null, "survival reuses spinner and side pusher")
	_expect(spring_arm != null and spring_arm.collision_mask == 1, "survival camera ignores active hazards")
	_expect(game.find_children("*Rail*", "Node3D", true, false).size() >= 40, "KayKit padded rails surround the arena")
	_expect(game.find_children("KayKitBall", "Node3D", true, false).size() == 4, "KayKit colored ball art is used")
	_expect(game.find_children("KayKitBomb", "Node3D", true, false).size() == 6, "KayKit bomb art is used")
	_expect(game.find_children("ArenaBeacon*", "Node3D", true, false).size() == 4, "arena corners use color-coded navigation beacons")
	_expect(game.get_node_or_null("SurvivalArena/RespawnCenterMarker") != null, "arena center respawn position is visibly marked")
	for question_path in [
		"res://resources/quiz/signal_bomb_survival/wave_1_data_bias.tres",
		"res://resources/quiz/signal_bomb_survival/wave_2_human_review.tres",
	]:
		var question := load(question_path) as QuizQuestion
		_expect(question != null and question.options.size() == 3, "%s is a three-option question" % question_path.get_file())
	if manager == null or player == null or mode_ui == null or ball_root == null or bomb_root == null or calibration_root == null or spinner == null:
		call_deferred("_finish")
		return

	manager.run_finished.connect(_on_run_finished)
	_expect(manager.state == PartyModeManager.RunState.COUNTDOWN, "survival starts in countdown")
	_expect(not player.controls_enabled, "survival movement is locked during countdown")
	_expect(is_equal_approx(manager.time_left, 60.0), "survival duration is 60 seconds")
	manager.begin_run_now()
	await physics_frame
	_expect(manager.is_running() and player.controls_enabled, "survival starts after countdown")
	_expect(not manager.finish(true), "survival cannot finish before both learning checkpoints")
	_expect(int(game.get("current_wave")) == 1, "first ball wave activates")
	var zone_one := calibration_root.get_child(0) as SignalCalibrationZone
	var zone_two := calibration_root.get_child(1) as SignalCalibrationZone
	var zone_three := calibration_root.get_child(2) as SignalCalibrationZone
	_expect(zone_one.monitoring and zone_one.visible, "wave one calibration zone activates at the start")
	zone_one.call("_on_body_entered", player)
	_expect(bool(game.get("wave_calibrated")[0]), "entering the wave one zone records calibration")
	var first_ball := ball_root.get_child(0) as PathHazard
	_expect(first_ball.get_node_or_null("PathPreview") != null, "rolling ball route is previewed on the floor")
	var ball_start := first_ball.position
	await _wait_physics_frames(12)
	_expect(first_ball.position.distance_to(ball_start) > 0.1, "rolling ball follows fixed path")
	_expect(not spinner.visible, "spinner remains inactive in wave one")

	manager.elapsed_seconds = 20.01
	manager.time_left = 39.99
	game.call("_process", 0.0)
	await process_frame
	_expect(manager.state == PartyModeManager.RunState.QUIZ and paused, "20-second checkpoint opens first quiz")
	var paused_time := manager.elapsed_seconds
	await _wait_physics_frames(5)
	_expect(is_equal_approx(manager.elapsed_seconds, paused_time), "survival timer pauses during quiz")
	mode_ui.call("_on_option_pressed", 1)
	await process_frame
	_expect(manager.quiz_attempts_by_slot[0] == 1 and manager.state == PartyModeManager.RunState.QUIZ, "wrong survival answer retries")
	mode_ui.call("_on_option_pressed", 0)
	await process_frame
	_expect(manager.is_running() and not paused, "correct first survival answer resumes")
	_expect(int(game.get("current_wave")) == 2 and spinner.visible, "spinner and pushers activate in wave two")
	_expect(zone_two.monitoring, "wave two activates a different calibration zone")
	zone_two.call("_on_body_entered", player)
	_expect(bool(game.get("wave_calibrated")[1]), "wave two calibration is recorded")

	game.set("hit_cooldown_left", 0.0)
	game.call("_on_ball_hit", player, player.global_position - Vector3.RIGHT)
	await physics_frame
	var first_hit_count := manager.hazard_hits
	var lateral_speed := Vector2(player.velocity.x, player.velocity.z).length()
	_expect(first_hit_count == 1, "hazard hit increments once")
	_expect(lateral_speed <= 7.5, "rolling ball force is bounded")
	game.call("_on_ball_hit", player, player.global_position - Vector3.RIGHT)
	_expect(manager.hazard_hits == first_hit_count, "0.75-second cooldown blocks repeated hits")
	await _wait_physics_frames(50)
	_expect(player.controls_enabled, "controls return after survival knockback")

	var elapsed_before_fall := manager.elapsed_seconds
	game.call("_on_player_fell")
	await _wait_physics_frames(32)
	_expect(manager.falls == 1, "survival fall count increments")
	_expect(manager.elapsed_seconds > elapsed_before_fall, "survival fall does not reset timer")
	_expect(player.global_position.distance_to(Vector3(0.0, 0.08, 10.0)) < 0.6, "survival fall respawns at center checkpoint")

	manager.elapsed_seconds = 40.01
	manager.time_left = 19.99
	game.call("_process", 0.0)
	await process_frame
	_expect(manager.state == PartyModeManager.RunState.QUIZ and paused, "40-second checkpoint opens second quiz")
	mode_ui.call("_on_option_pressed", 0)
	await process_frame
	_expect(manager.is_running() and int(game.get("current_wave")) == 3, "correct second answer activates bomb wave")
	_expect(zone_three.monitoring, "wave three activates the final calibration zone")
	zone_three.call("_on_body_entered", player)
	_expect(bool(game.get("wave_calibrated")[2]), "wave three calibration is recorded")
	var phased_bomb := bomb_root.get_child(5) as TimedBomb
	phased_bomb.call("_physics_process", 1.0)
	_expect(phased_bomb.get_node("WarningDisc").visible, "bomb shows warning before explosion")
	_expect(phased_bomb.get_node("WarningCore").visible and phased_bomb.get_node("WarningLabel").visible, "bomb warning includes a pulsing core and overhead alert")
	phased_bomb.call("_physics_process", 1.2)
	_expect(not phased_bomb.get_node("WarningDisc").visible, "bomb warning resets after deterministic explosion")

	game.set("hit_cooldown_left", 0.0)
	game.call("_on_bomb_exploded", player, player.global_position - Vector3.RIGHT)
	await physics_frame
	lateral_speed = Vector2(player.velocity.x, player.velocity.z).length()
	_expect(lateral_speed <= 8.6, "bomb horizontal force is capped at 8.5")
	_expect(player.velocity.y <= 4.6, "bomb vertical force is capped at 4.5")

	game.call("_on_time_expired")
	game.call("_on_time_expired")
	await process_frame
	_expect(manager.state == PartyModeManager.RunState.FINISHED, "60-second survival completes successfully")
	_expect(finished_results.size() == 1, "survival finish emits once")
	_expect(bool(finished_results[0].get("success", false)), "survival result is successful")
	_expect(int(finished_results[0].get("calibrated_count", 0)) == 3, "successful result requires all three calibrations")
	_expect(finished_results[0].has("hazard_hits") and finished_results[0].has("quiz_attempts_by_wave"), "survival result contains mode metrics")
	_expect(finished_results[0].has("score") and int(finished_results[0].get("score_breakdown", {}).get("time", 0)) == 15, "survival result uses fixed-duration scoring")
	var campaign := root.get_node_or_null("CampaignSession")
	var campaign_summary: Dictionary = campaign.call("get_campaign_summary") if campaign else {}
	_expect(campaign_summary.get("completed_levels", 0) >= 1, "final result is stored in campaign summary")

	game.call("_on_restart_requested")
	await _wait_physics_frames(2)
	_expect(manager.state == PartyModeManager.RunState.COUNTDOWN, "survival restart returns to countdown")
	_expect(manager.hazard_hits == 0 and manager.falls == 0, "survival restart clears hits and falls")
	_expect(int(game.get("current_wave")) == 0 and not first_ball.visible, "survival restart disables all hazards")
	_expect(game.get("wave_calibrated") == [false, false, false], "survival restart clears calibration progress")
	_expect(is_equal_approx(spinner.rotation.y, spinner.initial_phase), "survival restart resets spinner phase")

	manager.begin_run_now()
	await physics_frame
	manager.elapsed_seconds = 20.01
	manager.time_left = 39.99
	game.call("_process", 0.0)
	await process_frame
	_expect(manager.state == PartyModeManager.RunState.FAILED, "idle player fails when the first calibration window closes")
	_expect(finished_results.size() == 2 and not bool(finished_results[1].get("success", true)), "idle run records one failed result")
	_expect(String(finished_results[1].get("failure_reason", "")).contains("第1波"), "idle failure explains the missing first-wave calibration")
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
	if is_instance_valid(game_instance):
		TEST_CLEANUP.stop_all_audio(game_instance)
		game_instance.queue_free()
		await process_frame
		await process_frame
	if failures.is_empty():
		print("SIGNAL_BOMB_SURVIVAL_SMOKE_TEST_OK")
		quit(0)
	else:
		print("SIGNAL_BOMB_SURVIVAL_SMOKE_TEST_FAILED: %s" % ", ".join(failures))
		quit(1)
