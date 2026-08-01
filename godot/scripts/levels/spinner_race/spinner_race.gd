extends Node3D

const EXPERIMENT_EVENTS := preload("res://scripts/experiment_event_bridge.gd")
const INPUT_DEFAULTS := preload("res://scripts/input_defaults.gd")

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

var race_manager: SpinnerRaceManager
var player: PlayerController
var race_ui: SpinnerRaceUI
var camera_rig: Node3D
var spring_arm: SpringArm3D
var camera_node: Camera3D
var initial_spawn := Transform3D.IDENTITY
var obstacles: Array[Node] = []
var checkpoints: Array[RaceCheckpoint] = []
var finish_triggered: bool = false
var pending_fall_respawn: bool = false
var pending_checkpoint: RaceCheckpoint
var pending_checkpoint_spawn := Transform3D.IDENTITY
var pending_checkpoint_question: QuizQuestion
var camera_shake_time: float = 0.0
var camera_shake_strength: float = 0.0
var camera_target_yaw: float = 0.0

const CAMERA_KEY_TURN_SPEED := 1.85
const CAMERA_MOUSE_SENSITIVITY := 0.0045


func _ready() -> void:
	# A previous level can finish while the global SceneTree is paused. This level
	# owns its countdown, so always start from an active tree even when opened via
	# a scene transition instead of directly with F6.
	get_tree().paused = false
	INPUT_DEFAULTS.ensure_actions()
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
	race_ui.update_race(
		race_manager.countdown_left,
		race_manager.time_left,
		race_manager.falls,
		race_manager.checkpoint_index,
		race_manager.state,
		progress
	)


func _unhandled_input(event: InputEvent) -> void:
	if player == null or not player.controls_enabled or get_tree().paused:
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		camera_target_yaw -= event.relative.x * CAMERA_MOUSE_SENSITIVITY


func _build_manager() -> void:
	race_manager = RACE_MANAGER_SCRIPT.new() as SpinnerRaceManager
	race_manager.name = "RaceManager"
	add_child(race_manager)


func _build_world() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("31c9e7")
	environment.background_energy_multiplier = 0.62
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("e8fbff")
	environment.ambient_light_energy = 0.66
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("b8f2f4")
	environment.fog_light_energy = 0.38
	environment.fog_density = 0.004
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color("fff2d5")
	sun.light_energy = 1.08
	sun.rotation_degrees = Vector3(-54.0, -30.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 85.0
	add_child(sun)
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

	# Section 3: two moving platforms and safe staging decks.
	_create_platform_box(track, Vector3(4.5, 1.0, 5.0), Vector3(-3.0, -0.5, -49.0), Color("5a9ff1"), "MovingDockA", BLUE_PLATFORM_4)
	_create_platform_box(track, Vector3(4.5, 1.0, 5.0), Vector3(3.0, -0.5, -62.0), Color("5a9ff1"), "MovingDockB", BLUE_PLATFORM_4)
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

	# Section 5: the left branch is broad and safe; the right branch is shorter but guarded.
	_create_double_tile(track, Vector3(0.0, -1.0, -98.0), YELLOW_PLATFORM, "RouteSplit")
	for safe_position in [Vector3(-3.5, -0.5, -104.0), Vector3(-6.0, -0.5, -111.0), Vector3(-6.0, -0.5, -118.0)]:
		_create_platform_box(track, Vector3(6.0, 1.0, 6.0), safe_position, Color("45d0a9"), "SafeRoute", GREEN_PLATFORM_4)
	for shortcut_position in [Vector3(3.5, -0.5, -104.0), Vector3(3.5, -0.5, -111.0), Vector3(3.0, -0.5, -118.0)]:
		_create_platform_box(track, Vector3(4.2, 1.0, 5.5), shortcut_position, Color("ff8066"), "ShortcutRoute", RED_PLATFORM_4)
	_create_double_tile(track, Vector3(0.0, -1.0, -124.0), YELLOW_PLATFORM, "FinishDeck")

	_add_imported_visual(track, BLUE_ARCH, Vector3(0.0, 0.0, 9.5), Vector3.ONE * 1.8, "StartArch")
	_add_imported_visual(track, FINISH_SIGN, Vector3(0.0, 0.0, -125.5), Vector3.ONE, "KayKitFinishSign")
	for flag_position in [Vector3(-5.0, 0.0, 7.0), Vector3(5.0, 0.0, 7.0)]:
		_add_imported_visual(track, BLUE_FLAG, flag_position, Vector3.ONE * 1.25, "StartFlag")
	for flag_position in [Vector3(-5.0, 0.0, -123.0), Vector3(5.0, 0.0, -123.0)]:
		_add_imported_visual(track, YELLOW_FLAG, flag_position, Vector3.ONE * 1.25, "FinishFlag")
	_add_course_label(track, "旋转障碍冲刺", Vector3(0.0, 4.6, 9.0), Color("fff6d6"))
	_add_course_label(track, "安全路线", Vector3(-6.0, 2.6, -101.5), Color("d6fff1"))
	_add_course_label(track, "危险捷径", Vector3(3.5, 2.6, -101.5), Color("fff0cc"))


func _spawn_player() -> void:
	player = PLAYER_SCENE.instantiate() as PlayerController
	player.name = "RangerPlayer"
	player.position = START_POSITION
	add_child(player)
	initial_spawn = player.global_transform


func _build_camera() -> void:
	camera_rig = Node3D.new()
	camera_rig.name = "CameraRig"
	camera_rig.position = player.global_position + Vector3(0.0, 1.65, -1.7)
	add_child(camera_rig)
	spring_arm = SpringArm3D.new()
	spring_arm.name = "SpringArm3D"
	spring_arm.spring_length = 8.2
	spring_arm.margin = 0.24
	spring_arm.collision_mask = 1
	spring_arm.rotation_degrees.x = -18.5
	camera_rig.add_child(spring_arm)
	camera_node = Camera3D.new()
	camera_node.name = "ThirdPersonCamera"
	camera_node.current = true
	camera_node.fov = 60.0
	camera_node.near = 0.18
	camera_node.far = 165.0
	spring_arm.add_child(camera_node)
	spring_arm.add_excluded_object(player.get_rid())
	player.configure_camera(camera_node)
	camera_target_yaw = camera_rig.rotation.y


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
	moving_a.position = Vector3(1.0, -0.45, -50.5)
	moving_a.platform_size = Vector3(5.0, 0.9, 5.0)
	moving_a.movement_offset = Vector3(-5.5, 0.0, 0.0)
	moving_a.period_seconds = 4.2
	moving_a.initial_phase = 0.0
	moving_a.visual_scene = BLUE_ARROW_PLATFORM
	obstacle_root.add_child(moving_a)
	obstacles.append(moving_a)

	var moving_b := MOVING_PLATFORM_SCENE.instantiate() as MovingPlatform
	moving_b.name = "MovingPlatformB"
	moving_b.position = Vector3(-1.0, -0.45, -57.5)
	moving_b.platform_size = Vector3(5.0, 0.9, 5.0)
	moving_b.movement_offset = Vector3(5.5, 0.0, 0.0)
	moving_b.period_seconds = 4.7
	moving_b.initial_phase = PI
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

	var shortcut_spinner := SWEEPER_SCENE.instantiate() as RotatingSweeper
	shortcut_spinner.name = "ShortcutSpinner"
	shortcut_spinner.position = Vector3(3.5, 0.0, -110.0)
	shortcut_spinner.arm_length = 3.8
	shortcut_spinner.arm_height = 0.38
	shortcut_spinner.arm_center_y = 0.85
	shortcut_spinner.period_seconds = 2.6
	shortcut_spinner.initial_phase = 1.0
	shortcut_spinner.hit_player.connect(_on_spinner_hit)
	obstacle_root.add_child(shortcut_spinner)
	obstacles.append(shortcut_spinner)


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
	race_ui.restart_requested.connect(_on_restart_requested)
	race_ui.next_level_requested.connect(_on_next_level_requested)
	race_ui.quiz_choice_selected.connect(_on_quiz_choice_selected)


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


func _on_countdown_changed(seconds_left: int) -> void:
	race_ui.show_countdown(seconds_left)


func _on_player_fell() -> void:
	if not race_manager.register_fall():
		return
	pending_fall_respawn = true
	player.begin_knockback(Vector3(0.0, 2.5, 0.0), 0.42)
	_start_camera_shake(0.38, 0.2)


func _on_spinner_hit(hit_player: PlayerController, source_position: Vector3) -> void:
	if hit_player != player or not race_manager.is_running() or player.is_knocked_back():
		return
	race_manager.register_obstacle_hit()
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
	race_manager.register_obstacle_hit()
	var direction := push_direction.normalized()
	player.begin_knockback(direction * 6.0 + Vector3.UP * 2.6, 0.34)
	_start_camera_shake(0.28, 0.17)


func _on_jump_used() -> void:
	EXPERIMENT_EVENTS.record(self, "jump_used", "spinner_race")


func _on_dash_used() -> void:
	EXPERIMENT_EVENTS.record(self, "dash_used", "spinner_race")


func _on_knockback_finished() -> void:
	if pending_fall_respawn:
		pending_fall_respawn = false
		player.respawn_at(race_manager.checkpoint_transform)
		player.set_controls_enabled(race_manager.is_running())
		race_manager.notify_respawn()
		camera_rig.position = player.global_position + Vector3(0.0, 1.65, -1.7)
	elif race_manager.is_running():
		player.set_controls_enabled(true)


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
	get_tree().paused = true
	race_ui.show_quiz(question, checkpoint_index)


func _on_quiz_choice_selected(selected_index: int) -> void:
	if pending_checkpoint == null or pending_checkpoint_question == null:
		return
	var correct := race_manager.submit_quiz_answer(
		selected_index,
		pending_checkpoint_question.correct_index
	)
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
	get_tree().paused = false
	player.set_controls_enabled(race_manager.is_running())


func _on_checkpoint_updated(checkpoint_index: int, _spawn_transform: Transform3D) -> void:
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
	get_tree().paused = false
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
	var change_error := CampaignSession.load_next_level("spinner_race")
	if change_error != OK:
		push_error("Unable to open data_chip_hunt: %s" % error_string(change_error))


func _reset_race() -> void:
	get_tree().paused = false
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
	camera_rig.position = player.global_position + Vector3(0.0, 1.65, -1.7)
	camera_target_yaw = 0.0
	camera_rig.rotation.y = camera_target_yaw
	camera_node.h_offset = 0.0
	camera_node.v_offset = 0.0
	camera_shake_time = 0.0
	race_manager.reset_race(initial_spawn)
	race_ui.reset_view()


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
	if player.controls_enabled and not get_tree().paused:
		var turn_input := Input.get_axis("camera_left", "camera_right")
		camera_target_yaw -= turn_input * CAMERA_KEY_TURN_SPEED * delta
		if Input.is_action_just_pressed("camera_reset"):
			camera_target_yaw = player.get_facing_yaw()
	camera_rig.rotation.y = lerp_angle(
		camera_rig.rotation.y,
		camera_target_yaw,
		1.0 - exp(-9.0 * delta)
	)
	var camera_forward := -camera_rig.global_basis.z
	camera_forward.y = 0.0
	camera_forward = camera_forward.normalized()
	var desired_position := player.global_position + Vector3.UP * 1.65 + camera_forward * 1.7
	camera_rig.global_position = camera_rig.global_position.lerp(desired_position, 1.0 - exp(-7.5 * delta))
	var target_fov := 64.0 if player.is_dashing() else 60.0
	camera_node.fov = lerpf(camera_node.fov, target_fov, 1.0 - exp(-8.0 * delta))
	if camera_shake_time > 0.0:
		camera_shake_time = maxf(0.0, camera_shake_time - delta)
		var phase := camera_shake_time * 52.0
		camera_node.h_offset = sin(phase) * camera_shake_strength
		camera_node.v_offset = cos(phase * 1.37) * camera_shake_strength * 0.65
	else:
		camera_node.h_offset = move_toward(camera_node.h_offset, 0.0, delta * 2.0)
		camera_node.v_offset = move_toward(camera_node.v_offset, 0.0, delta * 2.0)


func _start_camera_shake(duration: float, strength: float) -> void:
	camera_shake_time = duration
	camera_shake_strength = strength


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
