extends PartyLevelBase

const MODE_MANAGER_SCRIPT := preload("res://scripts/party/party_mode_manager.gd")
const MODE_UI_SCRIPT := preload("res://scripts/party/party_mode_ui.gd")
const PATH_HAZARD_SCENE := preload("res://scenes/party/path_hazard.tscn")
const TIMED_BOMB_SCENE := preload("res://scenes/party/timed_bomb.tscn")
const CALIBRATION_ZONE_SCENE := preload("res://scenes/party/signal_calibration_zone.tscn")
const SWEEPER_SCENE := preload("res://scenes/obstacles/rotating_sweeper.tscn")
const SIDE_PUSHER_SCENE := preload("res://scenes/obstacles/side_pusher.tscn")

const QUESTION_1: QuizQuestion = preload("res://resources/quiz/signal_bomb_survival/wave_1_data_bias.tres")
const QUESTION_2: QuizQuestion = preload("res://resources/quiz/signal_bomb_survival/wave_2_human_review.tres")

const BLUE_PLATFORM := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/blue/platform_6x6x1_blue.gltf")
const GREEN_PLATFORM := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/green/platform_6x6x1_green.gltf")
const RED_PLATFORM := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/red/platform_6x6x1_red.gltf")
const YELLOW_PLATFORM := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/yellow/platform_6x6x1_yellow.gltf")
const BLUE_RAIL := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/blue/railing_straight_padded_blue.gltf")
const RED_RAIL := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/red/railing_straight_padded_red.gltf")
const BALL_BLUE := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/blue/ball_blue.gltf")
const BALL_GREEN := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/green/ball_green.gltf")
const BALL_RED := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/red/ball_red.gltf")
const BALL_YELLOW := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/yellow/ball_yellow.gltf")
const BOMB_RED := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/red/bomb_A_red.gltf")
const BOMB_YELLOW := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/yellow/bomb_B_yellow.gltf")
const BOMB_BLUE := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/blue/bomb_A_blue.gltf")
const RED_ARCH := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/red/arch_wide_red.gltf")
const RED_FLAG := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/red/flag_C_red.gltf")
const BLUE_FLAG := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/blue/flag_B_blue.gltf")
const BARRIER := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/neutral/barrier_3x1x4.gltf")
const CONE := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/neutral/cone.gltf")
const STRUCTURE := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/neutral/structure_A.gltf")
const UI_FONT: FontFile = preload("res://assets/ui/fonts/noto_sans_sc_ui_600.ttf")

const LEVEL_ID := "signal_bomb_survival"
const START_POSITION := Vector3(0.0, 0.08, 10.0)
const HIT_COOLDOWN := 0.75

var mode_manager: PartyModeManager
var mode_ui: PartyModeUI
var initial_spawn := Transform3D.IDENTITY
var rolling_balls: Array[PathHazard] = []
var bombs: Array[TimedBomb] = []
var calibration_zones: Array[SignalCalibrationZone] = []
var wave_obstacles: Array[Node3D] = []
var current_wave: int = 0
var wave_calibrated: Array[bool] = [false, false, false]
var quiz_triggered: Array[bool] = [false, false]
var active_question: QuizQuestion
var active_quiz_slot: int = 0
var hit_cooldown_left: float = 0.0
var pending_fall_respawn: bool = false
var _quiz_pause_token: int = 0
var _result_pause_token: int = 0


func _ready() -> void:
	_ensure_party_inputs()
	_build_manager()
	_build_party_world(
		Color("34bfd8"),
		Color("c7eff2"),
		[Color("72c9ee"), Color("f17678"), Color("f4c85f"), Color("9d8cf2")]
	)
	_build_survival_arena()
	_spawn_calibration_zones()
	initial_spawn = _spawn_party_player(START_POSITION)
	_build_party_camera(8.8, -20.0)
	_spawn_rolling_balls()
	_spawn_wave_obstacles()
	_spawn_bombs()
	_build_ui()
	_connect_signals()
	_reset_level()


func _process(delta: float) -> void:
	_update_party_camera(delta)
	hit_cooldown_left = maxf(0.0, hit_cooldown_left - delta)
	if mode_manager == null or mode_ui == null:
		return
	if mode_manager.is_running():
		if mode_manager.elapsed_seconds >= 20.0 and not quiz_triggered[0]:
			if wave_calibrated[0]:
				_open_wave_quiz(1, QUESTION_1)
			else:
				_fail_missing_calibration(1)
		elif mode_manager.elapsed_seconds >= 40.0 and not quiz_triggered[1]:
			if wave_calibrated[1]:
				_open_wave_quiz(2, QUESTION_2)
			else:
				_fail_missing_calibration(2)
		else:
			_set_wave(_wave_for_time(mode_manager.elapsed_seconds))
	var state_text := "生存中"
	if mode_manager.is_running() and current_wave > 0 and not wave_calibrated[current_wave - 1]:
		state_text = "前往发光校准区"
	match mode_manager.state:
		PartyModeManager.RunState.COUNTDOWN:
			state_text = "等待波次"
		PartyModeManager.RunState.QUIZ:
			state_text = "答题暂停"
		PartyModeManager.RunState.FINISHED:
			state_text = "全部完成"
		PartyModeManager.RunState.FAILED:
			state_text = "挑战结束"
	mode_ui.update_hud(
		mode_manager.time_left,
		state_text,
		"波次 %d / 3  ·  校准 %d / 3" % [maxi(current_wave, 1), wave_calibrated.count(true)],
		"受击 %d   掉落 %d" % [mode_manager.hazard_hits, mode_manager.falls],
		clampf(mode_manager.elapsed_seconds / mode_manager.time_limit_seconds, 0.0, 1.0)
	)


func _build_manager() -> void:
	mode_manager = MODE_MANAGER_SCRIPT.new() as PartyModeManager
	mode_manager.name = "ModeManager"
	mode_manager.level_id = LEVEL_ID
	mode_manager.level_name = "信号炸弹生存赛"
	mode_manager.countdown_duration = 3.0
	mode_manager.time_limit_seconds = 60.0
	mode_manager.fixed_duration_success = true
	mode_manager.quiz_slot_count = 2
	add_child(mode_manager)


func _build_survival_arena() -> void:
	var arena := Node3D.new()
	arena.name = "SurvivalArena"
	add_child(arena)
	var platform_scenes: Array[PackedScene] = [BLUE_PLATFORM, GREEN_PLATFORM, YELLOW_PLATFORM, RED_PLATFORM]
	for x_index in range(5):
		for z_index in range(5):
			var x_value := -12.0 + float(x_index) * 6.0
			var z_value := -12.0 + float(z_index) * 6.0
			var visual_scene := platform_scenes[(x_index + z_index) % platform_scenes.size()]
			_create_party_platform(
				arena,
				Vector3(6.0, 1.0, 6.0),
				Vector3(x_value, -0.5, z_value),
				visual_scene,
				"ArenaTile_%d_%d" % [x_index, z_index],
				Vector3(6.0, 1.0, 6.0)
			)

	# Four paired collision segments leave visible fall gaps in the middle of each edge.
	for rail_data in [
		[Vector3(-15.2, 0.25, -10.0), Vector3(0.5, 1.5, 10.0)],
		[Vector3(-15.2, 0.25, 10.0), Vector3(0.5, 1.5, 10.0)],
		[Vector3(15.2, 0.25, -10.0), Vector3(0.5, 1.5, 10.0)],
		[Vector3(15.2, 0.25, 10.0), Vector3(0.5, 1.5, 10.0)],
		[Vector3(-10.0, 0.25, -15.2), Vector3(10.0, 1.5, 0.5)],
		[Vector3(10.0, 0.25, -15.2), Vector3(10.0, 1.5, 0.5)],
		[Vector3(-10.0, 0.25, 15.2), Vector3(10.0, 1.5, 0.5)],
		[Vector3(10.0, 0.25, 15.2), Vector3(10.0, 1.5, 0.5)],
	]:
		_create_party_collision_box(arena, rail_data[1], rail_data[0], "ArenaRailCollision")

	var rail_index := 0
	for coordinate in [-14.0, -12.0, -10.0, -8.0, -6.0, 6.0, 8.0, 10.0, 12.0, 14.0]:
		_add_party_visual(arena, BLUE_RAIL, Vector3(-14.7, 0.0, coordinate), Vector3.ONE, "BlueLeftRail%d" % rail_index, Vector3(0.0, 90.0, 0.0))
		_add_party_visual(arena, RED_RAIL, Vector3(14.7, 0.0, coordinate), Vector3.ONE, "RedRightRail%d" % rail_index, Vector3(0.0, 90.0, 0.0))
		_add_party_visual(arena, RED_RAIL, Vector3(coordinate, 0.0, -14.7), Vector3.ONE, "RedBackRail%d" % rail_index)
		_add_party_visual(arena, BLUE_RAIL, Vector3(coordinate, 0.0, 14.7), Vector3.ONE, "BlueFrontRail%d" % rail_index)
		rail_index += 1

	_add_party_visual(arena, RED_ARCH, Vector3(0.0, 0.0, 14.0), Vector3.ONE * 1.8, "SurvivalArch")
	for flag_position in [Vector3(-5.2, 0.0, 12.8), Vector3(5.2, 0.0, 12.8)]:
		_add_party_visual(arena, RED_FLAG, flag_position, Vector3.ONE * 1.25, "RedArenaFlag")
	for flag_position in [Vector3(-13.2, 0.0, -13.2), Vector3(13.2, 0.0, -13.2)]:
		_add_party_visual(arena, BLUE_FLAG, flag_position, Vector3.ONE * 1.25, "BlueArenaFlag")
	for corner in [Vector3(-18.0, 0.0, -18.0), Vector3(18.0, 0.0, -18.0), Vector3(-18.0, 0.0, 18.0), Vector3(18.0, 0.0, 18.0)]:
		_add_party_visual(arena, STRUCTURE, corner, Vector3.ONE * 1.2, "ArenaStructure")
	for decoration in [Vector3(-12.5, 0.0, 3.0), Vector3(12.5, 0.0, -3.0)]:
		_add_party_visual(arena, BARRIER, decoration, Vector3.ONE, "ArenaBarrier", Vector3(0.0, 90.0, 0.0))
	for cone_position in [Vector3(-4.0, 0.0, 13.0), Vector3(4.0, 0.0, 13.0), Vector3(-13.0, 0.0, -4.0), Vector3(13.0, 0.0, 4.0)]:
		_add_party_visual(arena, CONE, cone_position, Vector3.ONE * 1.2, "ArenaCone")
	_add_party_floor_marker(arena, Vector3.ZERO, 3.1, Color("8fe8ff"), "RespawnCenterMarker")
	var arena_beacons := [
		[Vector3(-13.2, 0.0, 13.2), Color("5ad6ef")],
		[Vector3(13.2, 0.0, 13.2), Color("ff7468")],
		[Vector3(-13.2, 0.0, -13.2), Color("ffe066")],
		[Vector3(13.2, 0.0, -13.2), Color("8b79f5")],
	]
	for beacon_index in range(arena_beacons.size()):
		var beacon_data = arena_beacons[beacon_index]
		_add_party_beacon(arena, beacon_data[0], beacon_data[1], "ArenaBeacon%d" % (beacon_index + 1), 3.4)
	_add_course_label(arena, "信号炸弹生存赛", Vector3(0.0, 4.8, 13.5), Color("fff4d6"))


func _spawn_rolling_balls() -> void:
	var root := Node3D.new()
	root.name = "RollingBalls"
	add_child(root)
	var definitions := [
		["BlueBall", Vector3(-17.0, 0.9, -8.0), Vector3(17.0, 0.9, -8.0), 4.0, 0.0, BALL_BLUE],
		["RedBall", Vector3(17.0, 0.9, 8.0), Vector3(-17.0, 0.9, 8.0), 4.4, 0.45, BALL_RED],
		["GreenBall", Vector3(-6.0, 0.9, -17.0), Vector3(-6.0, 0.9, 17.0), 5.0, 0.18, BALL_GREEN],
		["YellowBall", Vector3(6.0, 0.9, 17.0), Vector3(6.0, 0.9, -17.0), 5.3, 0.68, BALL_YELLOW],
	]
	for definition in definitions:
		var ball := PATH_HAZARD_SCENE.instantiate() as PathHazard
		ball.name = definition[0]
		ball.path_start = definition[1]
		ball.path_end = definition[2]
		ball.period_seconds = definition[3]
		ball.initial_phase = definition[4]
		ball.visual_scene = definition[5]
		ball.radius = 0.95
		ball.visual_scale = Vector3.ONE * 1.05
		ball.hit_player.connect(_on_ball_hit)
		root.add_child(ball)
		rolling_balls.append(ball)


func _spawn_wave_obstacles() -> void:
	var root := Node3D.new()
	root.name = "WaveObstacles"
	add_child(root)
	var spinner := SWEEPER_SCENE.instantiate() as RotatingSweeper
	spinner.name = "ArenaSpinner"
	spinner.position = Vector3.ZERO
	spinner.arm_length = 11.0
	spinner.arm_height = 0.42
	spinner.arm_center_y = 0.88
	spinner.period_seconds = 4.5
	spinner.initial_phase = 0.35
	spinner.hit_player.connect(_on_spinner_hit)
	root.add_child(spinner)
	wave_obstacles.append(spinner)

	var pusher_definitions := [
		["ArenaPusherA", Vector3(-9.0, 0.8, -5.0), Vector3(18.0, 0.0, 0.0), 3.7, 0.0],
		["ArenaPusherB", Vector3(9.0, 0.8, 5.0), Vector3(-18.0, 0.0, 0.0), 4.1, 1.8],
	]
	for definition in pusher_definitions:
		var pusher := SIDE_PUSHER_SCENE.instantiate() as SidePusher
		pusher.name = definition[0]
		pusher.position = definition[1]
		pusher.movement_offset = definition[2]
		pusher.period_seconds = definition[3]
		pusher.initial_phase = definition[4]
		pusher.pusher_size = Vector3(2.5, 2.0, 1.0)
		pusher.hit_player.connect(_on_pusher_hit)
		root.add_child(pusher)
		wave_obstacles.append(pusher)


func _spawn_bombs() -> void:
	var root := Node3D.new()
	root.name = "TimedBombs"
	add_child(root)
	var positions := [
		Vector3(-9.0, 0.0, -9.0), Vector3(0.0, 0.0, -9.0), Vector3(9.0, 0.0, -9.0),
		Vector3(-6.0, 0.0, 6.0), Vector3(6.0, 0.0, 6.0), Vector3(0.0, 0.0, 0.0),
	]
	var visuals: Array[PackedScene] = [BOMB_RED, BOMB_YELLOW, BOMB_BLUE]
	for index in range(positions.size()):
		var bomb := TIMED_BOMB_SCENE.instantiate() as TimedBomb
		bomb.name = "TimedBomb%d" % (index + 1)
		bomb.position = positions[index]
		bomb.visual_scene = visuals[index % visuals.size()]
		bomb.cycle_seconds = 12.0
		bomb.warning_duration = 1.2
		bomb.initial_phase_seconds = float(index) * 2.0
		bomb.effect_radius = 4.0
		bomb.exploded.connect(_on_bomb_exploded)
		root.add_child(bomb)
		bombs.append(bomb)


func _spawn_calibration_zones() -> void:
	var root := Node3D.new()
	root.name = "CalibrationZones"
	add_child(root)
	var definitions := [
		[Vector3(-9.0, 0.0, -9.0), Color("5ad6ef")],
		[Vector3(9.0, 0.0, -9.0), Color("ffe066")],
		[Vector3(-9.0, 0.0, 9.0), Color("9d8cf2")],
	]
	for index in range(definitions.size()):
		var zone := CALIBRATION_ZONE_SCENE.instantiate() as SignalCalibrationZone
		zone.name = "Wave%dCalibrationZone" % (index + 1)
		zone.wave_index = index + 1
		zone.position = definitions[index][0]
		zone.zone_color = definitions[index][1]
		zone.calibrated.connect(_on_calibration_completed)
		root.add_child(zone)
		calibration_zones.append(zone)


func _build_ui() -> void:
	mode_ui = MODE_UI_SCRIPT.new() as PartyModeUI
	mode_ui.name = "ModeUI"
	mode_ui.mode_kicker = "SIGNAL BOMB SURVIVAL"
	mode_ui.mode_title = "信号炸弹生存赛"
	mode_ui.objective_text = "每20秒到达发光信号区完成校准，同时躲避机关并坚持60秒"
	mode_ui.final_level = true
	add_child(mode_ui)
	mode_ui.configure_result_action(CampaignSession.is_campaign_run())


func _connect_signals() -> void:
	_connect_party_player_events(LEVEL_ID)
	player.fell.connect(_on_player_fell)
	player.knockback_finished.connect(_on_knockback_finished)
	mode_manager.countdown_changed.connect(_on_countdown_changed)
	mode_manager.run_started.connect(_on_run_started)
	mode_manager.time_expired.connect(_on_time_expired)
	mode_manager.run_finished.connect(_on_run_finished)
	mode_ui.quiz_choice_selected.connect(_on_quiz_choice_selected)
	mode_ui.restart_requested.connect(_on_restart_requested)
	mode_ui.restart_campaign_requested.connect(_on_restart_campaign_requested)


func _on_countdown_changed(seconds_left: int) -> void:
	mode_ui.show_countdown(seconds_left)


func _on_run_started() -> void:
	mode_ui.hide_countdown()
	player.set_controls_enabled(true)
	_set_wave(1)


func _open_wave_quiz(slot: int, question: QuizQuestion) -> void:
	if not mode_manager.open_quiz(slot):
		return
	quiz_triggered[slot - 1] = true
	active_quiz_slot = slot
	active_question = question
	player.set_controls_enabled(false)
	_quiz_pause_token = get_node("/root/PauseCoordinator").acquire(self, &"quiz")
	mode_ui.show_quiz(question, slot, 2)


func _on_quiz_choice_selected(selected_index: int) -> void:
	if active_question == null or active_quiz_slot <= 0:
		return
	var completed_slot := active_quiz_slot
	var correct := mode_manager.submit_quiz_answer(selected_index, active_question.correct_index)
	if not correct:
		mode_ui.show_wrong_answer(selected_index, active_question.explanation)
		return
	active_question = null
	active_quiz_slot = 0
	mode_ui.hide_quiz()
	get_node("/root/PauseCoordinator").release(_quiz_pause_token)
	_quiz_pause_token = 0
	_set_wave(completed_slot + 1)
	player.set_controls_enabled(true)


func _on_calibration_completed(wave_index: int) -> void:
	if not mode_manager.is_running() or wave_index != current_wave:
		return
	var calibration_index := wave_index - 1
	if calibration_index < 0 or calibration_index >= wave_calibrated.size() or wave_calibrated[calibration_index]:
		return
	wave_calibrated[calibration_index] = true
	EXPERIMENT_EVENTS.record(self, "signal_calibrated", LEVEL_ID, {
		"wave": wave_index,
		"elapsed_seconds": snappedf(mode_manager.elapsed_seconds, 0.01),
	})
	_show_milestone(
		"第%d波信号校准完成" % wave_index,
		"继续躲避机关，等待知识检查点"
	)


func _on_ball_hit(hit_player: PlayerController, source_position: Vector3) -> void:
	if hit_player != player:
		return
	_apply_radial_hit(source_position, 7.4, 3.8)


func _on_spinner_hit(hit_player: PlayerController, source_position: Vector3) -> void:
	if hit_player != player:
		return
	_apply_radial_hit(source_position, 7.0, 3.8)


func _on_pusher_hit(hit_player: PlayerController, push_direction: Vector3) -> void:
	if hit_player != player or hit_cooldown_left > 0.0 or not mode_manager.is_running():
		return
	if not mode_manager.register_hazard_hit():
		return
	hit_cooldown_left = HIT_COOLDOWN
	var direction := push_direction.normalized()
	player.begin_knockback(direction * 7.2 + Vector3.UP * 3.4, 0.45)
	_start_party_camera_shake(0.34, 0.22)


func _on_bomb_exploded(hit_player: PlayerController, source_position: Vector3) -> void:
	if hit_player != player:
		return
	_apply_radial_hit(source_position, 8.5, 4.5)


func _apply_radial_hit(source_position: Vector3, horizontal_force: float, vertical_force: float) -> void:
	if hit_cooldown_left > 0.0 or not mode_manager.is_running():
		return
	if not mode_manager.register_hazard_hit():
		return
	hit_cooldown_left = HIT_COOLDOWN
	var direction := player.global_position - source_position
	direction.y = 0.0
	if direction.length_squared() < 0.05:
		direction = Vector3(0.8, 0.0, 0.6)
	direction = direction.normalized()
	player.begin_knockback(direction * minf(horizontal_force, 8.5) + Vector3.UP * minf(vertical_force, 4.5), 0.45)
	_start_party_camera_shake(0.42, 0.25)


func _on_player_fell() -> void:
	if not mode_manager.register_fall():
		return
	pending_fall_respawn = true
	player.begin_knockback(Vector3(0.0, 2.5, 0.0), 0.42)
	_start_party_camera_shake(0.38, 0.2)


func _on_knockback_finished() -> void:
	if pending_fall_respawn:
		pending_fall_respawn = false
		player.respawn_at(initial_spawn)
		player.set_controls_enabled(mode_manager.is_running())
		_reset_party_camera()
	elif mode_manager.is_running():
		player.set_controls_enabled(true)


func _on_time_expired() -> void:
	player.set_controls_enabled(false)
	if wave_calibrated.has(false):
		_fail_missing_calibration(wave_calibrated.find(false) + 1)
	else:
		mode_manager.finish(true, _get_mode_metrics())


func _fail_missing_calibration(wave_index: int) -> void:
	if not mode_manager.is_running():
		return
	player.set_controls_enabled(false)
	var metrics := _get_mode_metrics()
	metrics["failure_reason"] = "未在限定时间内完成第%d波信号校准" % wave_index
	metrics["failure_title"] = "信号校准失败"
	mode_manager.finish(false, metrics)


func _on_run_finished(result: Dictionary) -> void:
	if _result_pause_token == 0:
		_result_pause_token = get_node("/root/PauseCoordinator").acquire(self, &"result")
	_set_all_hazards_inactive()
	CampaignSession.record_level_result(LEVEL_ID, result)
	if bool(result.get("success", false)):
		player.play_celebration()
	else:
		player.set_controls_enabled(false)
	var metrics := "生存时间  %.2f 秒\n信号校准  %d / 3    受击  %d 次\n掉落  %d 次    答题  %d 次" % [
		float(result.get("survived_seconds", 0.0)),
		int(result.get("calibrated_count", 0)),
		int(result.get("hazard_hits", 0)),
		int(result.get("falls", 0)),
		int(result.get("quiz_attempts", 0)),
	]
	var failure_reason := String(result.get("failure_reason", ""))
	if not failure_reason.is_empty():
		metrics += "\n失败原因：%s" % failure_reason
	var campaign_summary := CampaignSession.get_campaign_summary() if CampaignSession.is_campaign_run() else {}
	mode_ui.show_result(result, metrics, campaign_summary)


func _on_restart_requested() -> void:
	_reset_level()


func _on_restart_campaign_requested() -> void:
	var change_error := CampaignSession.restart_campaign() if CampaignSession.is_campaign_run() else CampaignSession.return_to_menu()
	if change_error != OK:
		push_error("Unable to leave signal_bomb_survival: %s" % error_string(change_error))


func _reset_level() -> void:
	get_node("/root/PauseCoordinator").release_owner(self)
	_quiz_pause_token = 0
	_result_pause_token = 0
	current_wave = 0
	wave_calibrated = [false, false, false]
	quiz_triggered = [false, false]
	active_question = null
	active_quiz_slot = 0
	hit_cooldown_left = 0.0
	pending_fall_respawn = false
	for ball in rolling_balls:
		ball.set_active(false)
		ball.reset_phase()
	for obstacle in wave_obstacles:
		if obstacle.has_method("reset_phase"):
			obstacle.call("reset_phase")
		_set_wave_obstacle_active(obstacle, false)
	for bomb in bombs:
		bomb.set_active(false)
		bomb.reset_phase()
	for zone in calibration_zones:
		zone.reset_zone()
	player.respawn_at(initial_spawn)
	player.set_controls_enabled(false)
	_reset_party_camera()
	mode_manager.reset_run()
	mode_ui.reset_view(mode_manager.time_limit_seconds)


func _wave_for_time(elapsed: float) -> int:
	if elapsed >= 40.0:
		return 3
	if elapsed >= 20.0:
		return 2
	return 1


func _set_wave(wave: int) -> void:
	if wave == current_wave:
		return
	current_wave = clampi(wave, 1, 3)
	var wave_details := [
		"观察彩球的固定路线",
		"旋转杆与推板已加入",
		"注意地面的炸弹预警圈",
	]
	_show_milestone(
		"第 %d 波 / 3" % current_wave,
		wave_details[current_wave - 1]
	)
	for ball in rolling_balls:
		ball.set_active(true)
	for obstacle in wave_obstacles:
		_set_wave_obstacle_active(obstacle, current_wave >= 2)
	for bomb in bombs:
		bomb.set_active(current_wave >= 3)
	for zone in calibration_zones:
		zone.set_active(zone.wave_index == current_wave and not wave_calibrated[zone.wave_index - 1])


func _show_milestone(title_text: String, detail_text: String) -> void:
	var transition := get_node_or_null("/root/SceneTransition")
	if transition and transition.has_method("show_milestone"):
		transition.call("show_milestone", title_text, detail_text)


func _set_all_hazards_inactive() -> void:
	for ball in rolling_balls:
		ball.set_active(false)
	for obstacle in wave_obstacles:
		_set_wave_obstacle_active(obstacle, false)
	for bomb in bombs:
		bomb.set_active(false)
	for zone in calibration_zones:
		zone.set_active(false)


func _set_wave_obstacle_active(obstacle: Node3D, active: bool) -> void:
	obstacle.visible = active
	obstacle.set_physics_process(active)
	if obstacle is CollisionObject3D:
		(obstacle as CollisionObject3D).collision_layer = 2 if active else 0
	for child in obstacle.get_children():
		if child is Area3D:
			(child as Area3D).monitoring = active


func _get_mode_metrics() -> Dictionary:
	return {
		"survived_seconds": snappedf(mode_manager.elapsed_seconds, 0.01),
		"wave_reached": maxi(current_wave, 1),
		"calibrated_count": wave_calibrated.count(true),
		"target_calibrations": wave_calibrated.size(),
		"calibrations_by_wave": wave_calibrated.duplicate(),
		"quiz_attempts_by_wave": mode_manager.quiz_attempts_by_slot.duplicate(),
	}


func _add_course_label(parent: Node3D, text: String, position_value: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = UI_FONT
	label.font_size = 40
	label.outline_size = 8
	label.modulate = color
	label.outline_modulate = Color("3b315f")
	label.position = position_value
	parent.add_child(label)
