extends "res://scripts/third_person_level_base.gd"

const EXPERIMENT_EVENTS := preload("res://scripts/experiment_event_bridge.gd")
const SCAFFOLD_CONTROLLER_SCRIPT := preload("res://scripts/scaffolding/scaffold_controller.gd")

const RACE_MANAGER_SCRIPT := preload("res://scripts/levels/spinner_race/spinner_race_manager.gd")
const RACE_UI_SCRIPT := preload("res://scripts/levels/spinner_race/spinner_race_ui.gd")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const SWEEPER_SCENE := preload("res://scenes/obstacles/rotating_sweeper.tscn")
const MOVING_PLATFORM_SCENE := preload("res://scenes/obstacles/moving_platform.tscn")
const SIDE_PUSHER_SCENE := preload("res://scenes/obstacles/side_pusher.tscn")
const CHECKPOINT_SCENE := preload("res://scenes/levels/spinner_race/race_checkpoint.tscn")
const CHECKPOINT_QUESTION_1: QuizQuestion = preload("res://resources/quiz/spinner_race/checkpoint_1_ai_capability.tres")
const CHECKPOINT_QUESTION_2: QuizQuestion = preload("res://resources/quiz/spinner_race/checkpoint_2_effective_prompt.tres")
const CHECKPOINT_QUESTION_3: QuizQuestion = preload("res://resources/quiz/spinner_race/checkpoint_3_fact_check.tres")
const CHECKPOINT_QUESTION_4: QuizQuestion = preload("res://resources/quiz/spinner_race/checkpoint_4_responsible_use.tres")

const BLUE_PLATFORM := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/blue/platform_6x6x1_blue.gltf")
const RED_PLATFORM := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/red/platform_6x6x1_red.gltf")
const YELLOW_PLATFORM := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/yellow/platform_6x6x1_yellow.gltf")
const BLUE_PLATFORM_4 := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/blue/platform_4x4x1_blue.gltf")
const GREEN_PLATFORM_4 := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/green/platform_4x4x1_green.gltf")
const RED_PLATFORM_4 := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/red/platform_4x4x1_red.gltf")
const BLUE_ARROW_PLATFORM := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/blue/platform_arrow_4x4x1_blue.gltf")
const YELLOW_ARROW_PLATFORM := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/yellow/platform_arrow_4x4x1_yellow.gltf")
const YELLOW_PADDED_RAIL := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/yellow/railing_straight_padded_yellow.gltf")
const FINISH_SIGN := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/neutral/signage_finish_wide.gltf")
const BLUE_ARCH := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/blue/arch_wide_blue.gltf")
const YELLOW_ARCH := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/yellow/arch_wide_yellow.gltf")
const BLUE_FLAG := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/blue/flag_A_blue.gltf")
const YELLOW_FLAG := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/yellow/flag_A_yellow.gltf")
const UI_FONT: FontFile = preload("res://assets/ui/fonts/noto_sans_sc_ui_600.ttf")

const START_POSITION := Vector3(0.0, 0.08, 10.0)
const COURSE_START_Z := 10.0
const COURSE_FINISH_Z := -123.0
const MOVING_SECTION_PLATFORM_DEPTH := 4.0
const MOVING_SECTION_TRAVEL := 4.0
const BRANCH_CENTER_X := 3.0
const BRANCH_PLATFORM_SIZE := Vector3(5.5, 1.0, 5.0)

var race_manager: SpinnerRaceManager
var race_ui: SpinnerRaceUI
var initial_spawn := Transform3D.IDENTITY
var obstacles: Array[Node] = []
var checkpoints: Array[RaceCheckpoint] = []
var finish_triggered: bool = false
var pending_fall_respawn: bool = false
var pending_checkpoint: RaceCheckpoint
var pending_checkpoint_spawn := Transform3D.IDENTITY
var pending_checkpoint_question: QuizQuestion
var _quiz_pause_token: int = 0
var _result_pause_token: int = 0
var scaffold_controller

func _ready() -> void:
	_ensure_third_person_inputs()
	_build_manager()
	_build_world()
	_build_track()
	_spawn_player()
	_build_camera()
	_spawn_obstacles()
	_build_checkpoints()
	_build_finish_trigger()
	_build_ui()
	_connect_signals()
	_build_scaffold_controller()
	_reset_race()


func _process(delta: float) -> void:
	if player == null or camera_rig == null or race_manager == null:
		return
	_update_camera(delta)
	var progress := clampf(
		(COURSE_START_Z - player.global_position.z) / (COURSE_START_Z - COURSE_FINISH_Z),
		0.0,
		1.0
	)
	if scaffold_controller and race_manager.is_running():
		if Vector2(player.velocity.x, player.velocity.z).length() > 0.2:
			scaffold_controller.notify_basic_operation({"action": "move"})
		scaffold_controller.observe_progress_value(
			COURSE_START_Z - player.global_position.z,
			{"progress": roundi(progress * 100.0)}
		)
	race_ui.update_race(
		race_manager.countdown_left,
		race_manager.time_left,
		race_manager.falls,
		race_manager.checkpoint_index,
		race_manager.state,
		progress
	)


func _build_manager() -> void:
	race_manager = RACE_MANAGER_SCRIPT.new() as SpinnerRaceManager
	race_manager.name = "RaceManager"
	add_child(race_manager)


func _build_world() -> void:
	_build_third_person_environment(
		Color("31c9e7"),
		Color("e8fbff"),
		Color("b8f2f4"),
		0.38,
		0.004,
		Color("fff2d5"),
		Vector3(-54.0, -30.0, 0.0),
		85.0
	)
	_build_scenery()


func _build_scenery() -> void:
	var scenery := Node3D.new()
	scenery.name = "SoftTechScenery"
	add_child(scenery)
	var colors := [Color("62dcae"), Color("7ee3c5"), Color("86b8f8"), Color("b79cf7")]
	for index in range(30):
		var hill := MeshInstance3D.new()
		var hill_mesh := SphereMesh.new()
		var radius := 3.8 + float(index % 4) * 1.15
		hill_mesh.radius = radius
		hill_mesh.height = radius * 2.0
		hill_mesh.material = _make_material(colors[index % colors.size()], 0.0, 0.84)
		hill.mesh = hill_mesh
		var side := -1.0 if index % 2 == 0 else 1.0
		hill.position = Vector3(side * (15.0 + float(index % 3) * 4.0), -3.8, 12.0 - float(index) * 4.7)
		scenery.add_child(hill)


func _build_track() -> void:
	var track := Node3D.new()
	track.name = "Track"
	add_child(track)

	# Section 1: short, reachable jumps. Heights and gaps remain below the Ranger's normal jump arc.
	_create_double_tile(track, Vector3(0.0, -1.0, 8.0), BLUE_PLATFORM, "StartDeck")
	_create_platform_box(track, Vector3(5.0, 1.0, 5.0), Vector3(0.0, -0.5, 1.5), Color("47a7ef"), "JumpPlatform1", BLUE_PLATFORM_4)
	_create_platform_box(track, Vector3(5.0, 1.6, 5.0), Vector3(1.5, -0.2, -5.0), Color("6a75ef"), "JumpPlatform2", RED_PLATFORM_4)
	_create_platform_box(track, Vector3(5.0, 1.2, 5.0), Vector3(-1.5, -0.4, -11.5), Color("4fc8d5"), "JumpPlatform3", BLUE_PLATFORM_4)
	_create_double_tile(track, Vector3(0.0, -1.0, -18.0), RED_PLATFORM, "SpinnerEntry")

	# Section 2: a circular arena for the rotating sweeper.
	_create_static_cylinder(track, 7.25, 1.0, Vector3(0.0, -0.5, -31.0), Color("f06f72"), "SpinnerArena")
	_create_double_tile(track, Vector3(0.0, -1.0, -43.0), BLUE_PLATFORM, "MovingEntry")

	# Section 3: centered staging decks and a mirrored pair of moving platforms.
	_create_platform_box(track, Vector3(4.5, 1.0, MOVING_SECTION_PLATFORM_DEPTH), Vector3(0.0, -0.5, -49.0), Color("5a9ff1"), "MovingDockA", BLUE_PLATFORM_4)
	_create_platform_box(track, Vector3(4.5, 1.0, MOVING_SECTION_PLATFORM_DEPTH), Vector3(0.0, -0.5, -62.0), Color("5a9ff1"), "MovingDockB", BLUE_PLATFORM_4)
	_create_double_tile(track, Vector3(0.0, -1.0, -68.0), BLUE_PLATFORM, "PusherEntry")

	# Section 4: a wide lane with three reusable, side-to-side pushers.
	for z_position in [-74.0, -80.0, -86.0, -92.0]:
		_create_double_tile(track, Vector3(0.0, -1.0, z_position), YELLOW_PLATFORM, "PusherLane")
	_create_static_box(track, Vector3(0.42, 1.3, 27.0), Vector3(-6.25, 0.15, -81.0), Color("edae31"), "PusherLeftRail", null, false)
	_create_static_box(track, Vector3(0.42, 1.3, 27.0), Vector3(6.25, 0.15, -81.0), Color("edae31"), "PusherRightRail", null, false)
	var railing_index := 0
	for railing_z in range(-93, -67, 2):
		_add_imported_visual(track, YELLOW_PADDED_RAIL, Vector3(-5.45, 0.0, float(railing_z)), Vector3.ONE, "KayKitLeftRail%d" % railing_index, Vector3(0.0, 90.0, 0.0))
		_add_imported_visual(track, YELLOW_PADDED_RAIL, Vector3(5.45, 0.0, float(railing_z)), Vector3.ONE, "KayKitRightRail%d" % railing_index, Vector3(0.0, -90.0, 0.0))
		railing_index += 1

	# Section 5: two equal, continuous lanes with mirrored spinner challenges.
	_create_double_tile(track, Vector3(0.0, -1.0, -98.0), YELLOW_PLATFORM, "RouteSplit")
	var branch_z_positions: Array[float] = [-103.5, -108.5, -113.5, -118.5]
	var left_positions: Array[Vector3] = []
	var right_positions: Array[Vector3] = []
	for z_position in branch_z_positions:
		left_positions.append(Vector3(-BRANCH_CENTER_X, -0.5, z_position))
		right_positions.append(Vector3(BRANCH_CENTER_X, -0.5, z_position))
	for index in range(left_positions.size()):
		_create_platform_box(track, BRANCH_PLATFORM_SIZE, left_positions[index], Color("45d0a9"), "LeftRoute%d" % (index + 1), GREEN_PLATFORM_4)
	for index in range(right_positions.size()):
		_create_platform_box(track, BRANCH_PLATFORM_SIZE, right_positions[index], Color("ff8066"), "RightRoute%d" % (index + 1), RED_PLATFORM_4)
	_create_double_tile(track, Vector3(0.0, -1.0, -124.0), YELLOW_PLATFORM, "FinishDeck")

	_add_imported_visual(track, BLUE_ARCH, Vector3(0.0, 0.0, 9.5), Vector3.ONE * 1.8, "StartArch")
	_add_imported_visual(track, FINISH_SIGN, Vector3(0.0, 0.0, -125.5), Vector3.ONE, "KayKitFinishSign")
	for flag_position in [Vector3(-5.0, 0.0, 7.0), Vector3(5.0, 0.0, 7.0)]:
		_add_imported_visual(track, BLUE_FLAG, flag_position, Vector3.ONE * 1.25, "StartFlag")
	for flag_position in [Vector3(-5.0, 0.0, -123.0), Vector3(5.0, 0.0, -123.0)]:
		_add_imported_visual(track, YELLOW_FLAG, flag_position, Vector3.ONE * 1.25, "FinishFlag")
	_add_course_label(track, "旋转障碍冲刺", Vector3(0.0, 4.6, 9.0), Color("fff6d6"))
	_add_course_label(track, "左侧路线", Vector3(-BRANCH_CENTER_X, 2.6, -101.5), Color("d6fff1"))
	_add_course_label(track, "右侧路线", Vector3(BRANCH_CENTER_X, 2.6, -101.5), Color("fff0cc"))


func _spawn_player() -> void:
	player = PLAYER_SCENE.instantiate() as PlayerController
	player.name = "RangerPlayer"
	player.position = START_POSITION
	add_child(player)
	initial_spawn = player.global_transform


func _build_camera() -> void:
	_build_third_person_camera(8.2, -18.5, 165.0)


func _spawn_obstacles() -> void:
	var obstacle_root := Node3D.new()
	obstacle_root.name = "Obstacles"
	add_child(obstacle_root)

	var spinner := SWEEPER_SCENE.instantiate() as RotatingSweeper
	spinner.name = "Spinner"
	spinner.position = Vector3(0.0, 0.0, -31.0)
	spinner.arm_length = 12.0
	spinner.arm_height = 0.42
	spinner.arm_center_y = 0.9
	spinner.period_seconds = 4.0
	spinner.initial_phase = 0.2
	spinner.hit_player.connect(_on_spinner_hit)
	obstacle_root.add_child(spinner)
	obstacles.append(spinner)

	var moving_a := MOVING_PLATFORM_SCENE.instantiate() as MovingPlatform
	moving_a.name = "MovingPlatformA"
	moving_a.position = Vector3(0.0, -0.45, -53.25)
	moving_a.platform_size = Vector3(4.5, 0.9, MOVING_SECTION_PLATFORM_DEPTH)
	moving_a.movement_offset = Vector3(-MOVING_SECTION_TRAVEL, 0.0, 0.0)
	moving_a.period_seconds = 4.5
	moving_a.initial_phase = 0.0
	moving_a.visual_scene = BLUE_ARROW_PLATFORM
	obstacle_root.add_child(moving_a)
	obstacles.append(moving_a)

	var moving_b := MOVING_PLATFORM_SCENE.instantiate() as MovingPlatform
	moving_b.name = "MovingPlatformB"
	moving_b.position = Vector3(0.0, -0.45, -57.75)
	moving_b.platform_size = Vector3(4.5, 0.9, MOVING_SECTION_PLATFORM_DEPTH)
	moving_b.movement_offset = Vector3(MOVING_SECTION_TRAVEL, 0.0, 0.0)
	moving_b.period_seconds = 4.5
	moving_b.initial_phase = 0.0
	moving_b.visual_scene = YELLOW_ARROW_PLATFORM
	obstacle_root.add_child(moving_b)
	obstacles.append(moving_b)

	var pusher_z := [-74.0, -82.0, -90.0]
	for index in range(pusher_z.size()):
		var pusher := SIDE_PUSHER_SCENE.instantiate() as SidePusher
		pusher.name = "SidePusher%d" % (index + 1)
		pusher.position = Vector3(-4.4, 0.0, pusher_z[index])
		pusher.movement_offset = Vector3(8.8, 0.0, 0.0)
		pusher.period_seconds = 3.3 + float(index) * 0.35
		pusher.initial_phase = float(index) * 1.7
		pusher.hit_player.connect(_on_pusher_hit)
		obstacle_root.add_child(pusher)
		obstacles.append(pusher)

	var left_route_spinner := SWEEPER_SCENE.instantiate() as RotatingSweeper
	left_route_spinner.name = "LeftRouteSpinner"
	left_route_spinner.position = Vector3(-BRANCH_CENTER_X, 0.0, -110.0)
	left_route_spinner.arm_length = 3.8
	left_route_spinner.arm_height = 0.38
	left_route_spinner.arm_center_y = 0.85
	left_route_spinner.period_seconds = 2.6
	left_route_spinner.initial_phase = PI - 1.0
	left_route_spinner.rotation_direction = -1.0
	left_route_spinner.hit_player.connect(_on_spinner_hit)
	obstacle_root.add_child(left_route_spinner)
	obstacles.append(left_route_spinner)

	var right_route_spinner := SWEEPER_SCENE.instantiate() as RotatingSweeper
	right_route_spinner.name = "RightRouteSpinner"
	right_route_spinner.position = Vector3(BRANCH_CENTER_X, 0.0, -110.0)
	right_route_spinner.arm_length = 3.8
	right_route_spinner.arm_height = 0.38
	right_route_spinner.arm_center_y = 0.85
	right_route_spinner.period_seconds = 2.6
	right_route_spinner.initial_phase = 1.0
	right_route_spinner.rotation_direction = 1.0
	right_route_spinner.hit_player.connect(_on_spinner_hit)
	obstacle_root.add_child(right_route_spinner)
	obstacles.append(right_route_spinner)


func _build_checkpoints() -> void:
	var checkpoint_root := Node3D.new()
	checkpoint_root.name = "Checkpoints"
	add_child(checkpoint_root)
	var definitions := [
		[1, Vector3(0.0, 0.0, -18.0)],
		[2, Vector3(0.0, 0.0, -43.0)],
		[3, Vector3(0.0, 0.0, -68.0)],
		[4, Vector3(0.0, 0.0, -98.0)],
	]
	for definition in definitions:
		var checkpoint := CHECKPOINT_SCENE.instantiate() as RaceCheckpoint
		checkpoint.name = "Checkpoint%d" % definition[0]
		checkpoint.checkpoint_index = definition[0]
		checkpoint.position = definition[1]
		checkpoint.activated.connect(_on_checkpoint_activated)
		checkpoint_root.add_child(checkpoint)
		checkpoints.append(checkpoint)


func _build_finish_trigger() -> void:
	var finish_area := Area3D.new()
	finish_area.name = "FinishTrigger"
	finish_area.position = Vector3(0.0, 1.5, COURSE_FINISH_Z)
	finish_area.collision_layer = 0
	finish_area.collision_mask = 1
	var shape := BoxShape3D.new()
	shape.size = Vector3(11.0, 3.0, 2.2)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	finish_area.add_child(collision)
	finish_area.body_entered.connect(_on_finish_body_entered)
	add_child(finish_area)


func _build_ui() -> void:
	race_ui = RACE_UI_SCRIPT.new() as SpinnerRaceUI
	race_ui.name = "RaceUI"
	add_child(race_ui)
	race_ui.configure_result_action(CampaignSession.is_campaign_run())
	race_ui.restart_requested.connect(_on_restart_requested)
	race_ui.next_level_requested.connect(_on_next_level_requested)
	race_ui.quiz_choice_selected.connect(_on_quiz_choice_selected)
	race_ui.assistant_toggled.connect(_on_assistant_toggled)
	race_ui.configure_assistant("spinner_race", _get_ai_assistant_state)


func _build_scaffold_controller() -> void:
	scaffold_controller = SCAFFOLD_CONTROLLER_SCRIPT.new()
	scaffold_controller.name = "ScaffoldController"
	add_child(scaffold_controller)
	scaffold_controller.configure(
		"spinner_race",
		"responsible_ai_checkpoints",
		"通过四个检查点并完成每个 AI 知识题，在限时内抵达终点",
		_get_ai_assistant_state,
		_is_scaffold_safe,
		race_ui.assistant_widget
	)
	race_ui.configure_assistant("spinner_race", scaffold_controller.get_ai_context)


func _connect_signals() -> void:
	player.fell.connect(_on_player_fell)
	player.jump_used.connect(_on_jump_used)
	player.dash_used.connect(_on_dash_used)
	player.knockback_finished.connect(_on_knockback_finished)
	race_manager.countdown_changed.connect(_on_countdown_changed)
	race_manager.race_started.connect(_on_race_started)
	race_manager.checkpoint_updated.connect(_on_checkpoint_updated)
	race_manager.race_finished.connect(_on_race_finished)


func _on_race_started() -> void:
	player.set_controls_enabled(true)
	_set_obstacles_active(true)
	scaffold_controller.begin_run()


func _on_countdown_changed(seconds_left: int) -> void:
	race_ui.show_countdown(seconds_left)


func _on_player_fell() -> void:
	if not race_manager.register_fall():
		return
	pending_fall_respawn = true
	scaffold_controller.notify_failure("repeated_failure", {"checkpoint": race_manager.checkpoint_index, "area": _current_area(), "kind": "fall"})
	player.begin_knockback(Vector3(0.0, 2.5, 0.0), 0.42)
	_start_camera_shake(0.38, 0.2)


func _on_spinner_hit(hit_player: PlayerController, source_position: Vector3) -> void:
	if hit_player != player or not race_manager.is_running() or player.is_knocked_back():
		return
	if race_manager.register_obstacle_hit():
		scaffold_controller.notify_failure("repeated_failure", {"checkpoint": race_manager.checkpoint_index, "area": _current_area(), "kind": "spinner_hit"})
	var direction := player.global_position - source_position
	direction.y = 0.0
	if direction.length_squared() < 0.05:
		direction = Vector3(0.75, 0.0, 0.4)
	direction = direction.normalized()
	player.begin_knockback(direction * 6.8 + Vector3.UP * 4.2, 0.42)
	_start_camera_shake(0.34, 0.2)


func _on_pusher_hit(hit_player: PlayerController, push_direction: Vector3) -> void:
	if hit_player != player or not race_manager.is_running() or player.is_knocked_back():
		return
	if race_manager.register_obstacle_hit():
		scaffold_controller.notify_failure("repeated_failure", {"checkpoint": race_manager.checkpoint_index, "area": _current_area(), "kind": "pusher_hit"})
	var direction := push_direction.normalized()
	player.begin_knockback(direction * 6.0 + Vector3.UP * 2.6, 0.34)
	_start_camera_shake(0.28, 0.17)


func _on_jump_used() -> void:
	EXPERIMENT_EVENTS.record(self, "jump_used", "spinner_race")
	scaffold_controller.notify_basic_operation({"action": "jump"})


func _on_dash_used() -> void:
	EXPERIMENT_EVENTS.record(self, "dash_used", "spinner_race")
	scaffold_controller.notify_basic_operation({"action": "dash"})


func _on_knockback_finished() -> void:
	if pending_fall_respawn:
		pending_fall_respawn = false
		player.respawn_at(race_manager.checkpoint_transform)
		player.set_controls_enabled(race_manager.is_running())
		race_manager.notify_respawn()
		camera_rig.position = player.global_position + Vector3(0.0, 1.65, -1.7)
	elif race_manager.is_running():
		player.set_controls_enabled(true)
	scaffold_controller.mark_safe_window()


func _on_checkpoint_activated(checkpoint_index: int, spawn_transform: Transform3D, checkpoint: RaceCheckpoint) -> void:
	var question := _get_checkpoint_question(checkpoint_index)
	if question == null:
		push_error("Missing quiz question for checkpoint %d" % checkpoint_index)
		return
	pending_checkpoint = checkpoint
	pending_checkpoint_spawn = spawn_transform
	pending_checkpoint_question = question
	if not race_manager.open_checkpoint_quiz(checkpoint_index):
		_clear_pending_checkpoint()
		return
	player.set_controls_enabled(false)
	_quiz_pause_token = get_node("/root/PauseCoordinator").acquire(self, &"quiz")
	race_ui.show_quiz(question, checkpoint_index)
	scaffold_controller.notify_quiz_started()


func _on_quiz_choice_selected(selected_index: int) -> void:
	if pending_checkpoint == null or pending_checkpoint_question == null:
		return
	var correct := race_manager.submit_quiz_answer(
		selected_index,
		pending_checkpoint_question.correct_index
	)
	scaffold_controller.notify_quiz_result(correct, {"checkpoint": pending_checkpoint.checkpoint_index, "selected_index": selected_index})
	if not correct:
		race_ui.show_wrong_answer(selected_index, pending_checkpoint_question.explanation)
		return
	if race_manager.activate_checkpoint(
		pending_checkpoint.checkpoint_index,
		pending_checkpoint_spawn
	):
		pending_checkpoint.set_activated()
	race_ui.hide_quiz()
	_clear_pending_checkpoint()
	get_node("/root/PauseCoordinator").release(_quiz_pause_token)
	_quiz_pause_token = 0
	player.set_controls_enabled(race_manager.is_running())
	scaffold_controller.notify_quiz_ended()


func _on_checkpoint_updated(checkpoint_index: int, _spawn_transform: Transform3D) -> void:
	scaffold_controller.notify_progress({"checkpoint": checkpoint_index})
	scaffold_controller.mark_safe_window()
	_show_milestone(
		"检查点 %d / 4 已保存" % checkpoint_index,
		"跌落后将从这里重新出发"
	)


func _on_finish_body_entered(body: Node3D) -> void:
	if body != player or finish_triggered:
		return
	if race_manager.try_finish():
		finish_triggered = true


func _on_race_finished(result: Dictionary) -> void:
	scaffold_controller.end_run()
	if _result_pause_token == 0:
		_result_pause_token = get_node("/root/PauseCoordinator").acquire(self, &"result")
	CampaignSession.record_level_result("spinner_race", result)
	if bool(result.get("success", false)):
		player.play_celebration()
	else:
		player.set_controls_enabled(false)
	_set_obstacles_active(false)
	race_ui.show_result(result)


func _on_restart_requested() -> void:
	_reset_race()


func _on_next_level_requested() -> void:
	if race_manager.state != SpinnerRaceManager.RaceState.FINISHED:
		return
	var change_error := CampaignSession.load_next_level("spinner_race") if CampaignSession.is_campaign_run() else CampaignSession.return_to_menu()
	if change_error != OK:
		push_error("Unable to leave spinner_race: %s" % error_string(change_error))


func _reset_race() -> void:
	get_node("/root/PauseCoordinator").release_owner(self)
	_quiz_pause_token = 0
	_result_pause_token = 0
	if scaffold_controller:
		scaffold_controller.reset_level()
	get_node("/root/AiAssistantService").clear_level_session("spinner_race")
	finish_triggered = false
	pending_fall_respawn = false
	_clear_pending_checkpoint()
	player.respawn_at(initial_spawn)
	player.set_controls_enabled(false)
	for obstacle in obstacles:
		if obstacle.has_method("reset_phase"):
			obstacle.call("reset_phase")
	for checkpoint in checkpoints:
		checkpoint.reset_checkpoint()
	_set_obstacles_active(false)
	_reset_third_person_camera()
	race_manager.reset_race(initial_spawn)
	race_ui.reset_view()


func _on_assistant_toggled(open: bool) -> void:
	race_manager.set_assistant_open(open)
	player.set_controls_enabled(race_manager.is_running())


func _get_ai_assistant_state() -> Dictionary:
	return {
		"checkpoint": race_manager.checkpoint_index,
		"obstacle_hits": race_manager.obstacle_hits,
		"falls": race_manager.falls,
		"remaining_time": snappedf(race_manager.time_left, 0.1),
		"current_checkpoint": race_manager.checkpoint_index,
		"current_area": _current_area(),
		"current_choice": {"movement": "moving" if Vector2(player.velocity.x, player.velocity.z).length() > 0.2 else "waiting"},
	}


func _current_area() -> String:
	return "checkpoint_%d_section" % clampi(race_manager.checkpoint_index + 1, 1, 4)


func _is_scaffold_safe() -> bool:
	return race_manager.is_running() and player.is_on_floor() and not player.is_dashing() and not player.is_knocked_back() and Vector2(player.velocity.x, player.velocity.z).length() < 1.5


func _get_checkpoint_question(checkpoint_index: int) -> QuizQuestion:
	match checkpoint_index:
		1:
			return CHECKPOINT_QUESTION_1
		2:
			return CHECKPOINT_QUESTION_2
		3:
			return CHECKPOINT_QUESTION_3
		4:
			return CHECKPOINT_QUESTION_4
	return null


func _clear_pending_checkpoint() -> void:
	pending_checkpoint = null
	pending_checkpoint_spawn = Transform3D.IDENTITY
	pending_checkpoint_question = null


func _show_milestone(title_text: String, detail_text: String) -> void:
	var transition := get_node_or_null("/root/SceneTransition")
	if transition and transition.has_method("show_milestone"):
		transition.call("show_milestone", title_text, detail_text)


func _set_obstacles_active(active: bool) -> void:
	for obstacle in obstacles:
		obstacle.set_physics_process(active)


func _update_camera(delta: float) -> void:
	_update_third_person_camera(delta)


func _start_camera_shake(duration: float, strength: float) -> void:
	_start_third_person_camera_shake(duration, strength)


func _create_double_tile(parent: Node3D, center: Vector3, model_scene: PackedScene, prefix: String) -> void:
	for x_offset in [-3.0, 3.0]:
		_create_platform_tile(parent, center + Vector3(x_offset, 0.0, 0.0), model_scene, prefix)


func _create_platform_tile(parent: Node3D, tile_position: Vector3, model_scene: PackedScene, tile_name: String) -> void:
	var body := StaticBody3D.new()
	body.name = tile_name
	body.position = tile_position
	body.collision_layer = 1
	body.collision_mask = 1
	parent.add_child(body)
	var shape := BoxShape3D.new()
	shape.size = Vector3(6.0, 1.0, 6.0)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = 0.5
	body.add_child(collision)
	if model_scene:
		var model := model_scene.instantiate()
		model.name = "KayKitPlatformVisual"
		body.add_child(model)


func _create_platform_box(parent: Node3D, size: Vector3, box_position: Vector3, color: Color, box_name: String, visual_scene: PackedScene = null) -> void:
	_create_static_box(parent, size, box_position, color, box_name, visual_scene)


func _create_static_box(parent: Node3D, size: Vector3, box_position: Vector3, color: Color, box_name: String, visual_scene: PackedScene = null, show_fallback_visual: bool = true) -> void:
	var body := StaticBody3D.new()
	body.name = box_name
	body.position = box_position
	body.collision_layer = 1
	body.collision_mask = 1
	parent.add_child(body)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	if visual_scene:
		var kaykit_visual := visual_scene.instantiate() as Node3D
		kaykit_visual.name = "KayKitPlatformVisual"
		kaykit_visual.position.y = -size.y * 0.5
		kaykit_visual.scale = Vector3(size.x / 4.0, size.y, size.z / 4.0)
		body.add_child(kaykit_visual)
	elif show_fallback_visual:
		var mesh := BoxMesh.new()
		mesh.size = size
		mesh.material = _make_material(color, 0.08, 0.5)
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		body.add_child(visual)


func _create_static_cylinder(parent: Node3D, radius: float, height: float, cylinder_position: Vector3, color: Color, body_name: String) -> void:
	var body := StaticBody3D.new()
	body.name = body_name
	body.position = cylinder_position
	body.collision_layer = 1
	body.collision_mask = 1
	parent.add_child(body)
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 48
	mesh.material = _make_material(color, 0.06, 0.52)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	body.add_child(visual)


func _add_imported_visual(parent: Node3D, scene: PackedScene, visual_position: Vector3, visual_scale: Vector3, visual_name: String, visual_rotation_degrees: Vector3 = Vector3.ZERO) -> void:
	if scene == null:
		return
	var visual := scene.instantiate() as Node3D
	visual.name = visual_name
	visual.position = visual_position
	visual.scale = visual_scale
	visual.rotation_degrees = visual_rotation_degrees
	parent.add_child(visual)


func _add_course_label(parent: Node3D, text: String, label_position: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = UI_FONT
	label.font_size = 42
	label.outline_size = 8
	label.modulate = color
	label.outline_modulate = Color("443890")
	label.position = label_position
	parent.add_child(label)


func _make_material(color: Color, emission_strength: float = 0.0, roughness: float = 0.55) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if emission_strength > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission_strength
	return material
