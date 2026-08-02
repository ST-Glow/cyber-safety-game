extends "res://scripts/third_person_level_base.gd"

const GAME_MANAGER_SCRIPT := preload("res://scripts/game_manager.gd")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const SWEEPER_SCENE := preload("res://scenes/obstacles/rotating_sweeper.tscn")
const GATE_SCENE := preload("res://scenes/obstacles/rising_gate.tscn")
const BRIDGE_SCENE := preload("res://scenes/obstacles/tilt_bridge.tscn")
const UI_SCRIPT := preload("res://scripts/game_ui.gd")
const QUIZ_RESOURCE := preload("res://resources/quiz/generative_ai.tres")
const BLUE_PLATFORM := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/blue/platform_6x6x1_blue.gltf")
const RED_PLATFORM := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/red/platform_6x6x1_red.gltf")
const YELLOW_PLATFORM := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/yellow/platform_6x6x1_yellow.gltf")
const BLUE_ARCH := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/blue/arch_wide_blue.gltf")
const YELLOW_ARCH := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/yellow/arch_wide_yellow.gltf")
const BLUE_FLAG := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/blue/flag_A_blue.gltf")
const YELLOW_FLAG := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/yellow/flag_A_yellow.gltf")
const BLUE_PADDED_RAIL := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/blue/railing_straight_padded_blue.gltf")
const YELLOW_PADDED_RAIL := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/yellow/railing_straight_padded_yellow.gltf")
const BLUE_ARROW_SIGN := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/blue/signage_arrow_stand_blue.gltf")
const YELLOW_ARROW_SIGN := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/yellow/signage_arrow_stand_yellow.gltf")
const FINISH_SIGN := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/neutral/signage_finish_wide.gltf")

const SPAWN_POSITION := Vector3(0.0, 0.08, 5.0)
const COURSE_START_Z := 5.0
const COURSE_FINISH_Z := -59.0

var game_manager: GameManager
var ui: GameUI
var spawn_transform := Transform3D.IDENTITY
var obstacles: Array[Node] = []
var finish_triggered: bool = false


func _ready() -> void:
	_ensure_third_person_inputs()
	game_manager = GAME_MANAGER_SCRIPT.new()
	game_manager.name = "GameManager"
	add_child(game_manager)
	_build_world()
	_build_track()
	_spawn_player()
	_build_camera()
	_spawn_obstacles()
	_build_finish_trigger()
	_build_ui()
	_connect_game_signals()
	_reset_level()
	game_manager.prepare_run()
	ui.show_ready()


func _process(delta: float) -> void:
	if player == null or camera_rig == null:
		return
	_update_camera(delta)
	var progress := clampf((COURSE_START_Z - player.global_position.z) / (COURSE_START_Z - COURSE_FINISH_Z), 0.0, 1.0)
	ui.update_hud(
		progress,
		game_manager.elapsed_seconds,
		game_manager.score,
		player.dash_cooldown_left,
		player.dash_cooldown
	)


func _build_world() -> void:
	_build_third_person_environment(
		Color("37c9e8"),
		Color("dff8ff"),
		Color("bfe9ee"),
		0.32,
		0.0042,
		Color("fff3d8"),
		Vector3(-52.0, -28.0, 0.0),
		74.0
	)
	_build_scenery()


func _build_scenery() -> void:
	var scenery := Node3D.new()
	scenery.name = "SoftTechScenery"
	add_child(scenery)
	var hill_colors := [Color("62dcae"), Color("7ee3c5"), Color("89b9f8"), Color("b9a1fb")]
	for index in range(18):
		var sphere := MeshInstance3D.new()
		var sphere_mesh := SphereMesh.new()
		var radius := 3.5 + float(index % 4) * 1.1
		sphere_mesh.radius = radius
		sphere_mesh.height = radius * 2.0
		sphere_mesh.material = _make_material(hill_colors[index % hill_colors.size()], 0.0, 0.82)
		sphere.mesh = sphere_mesh
		var side := -1.0 if index % 2 == 0 else 1.0
		sphere.position = Vector3(side * (14.0 + float(index % 3) * 4.0), -3.6, 9.0 - float(index) * 4.6)
		scenery.add_child(sphere)

	for cloud_index in range(8):
		var cloud := MeshInstance3D.new()
		var cloud_mesh := SphereMesh.new()
		cloud_mesh.radius = 1.4 + float(cloud_index % 2) * 0.5
		cloud_mesh.height = 1.8
		cloud_mesh.material = _make_material(Color("d7edf2"), 0.0, 1.0)
		cloud.mesh = cloud_mesh
		cloud.scale = Vector3(1.85, 0.55, 0.86)
		cloud.position = Vector3(-18.0 + float(cloud_index % 4) * 12.0, 13.0 + float(cloud_index % 3) * 2.4, -14.0 - float(cloud_index) * 10.0)
		scenery.add_child(cloud)


func _build_track() -> void:
	var track := Node3D.new()
	track.name = "Track"
	add_child(track)

	var tile_z_positions := [6.0, 0.0, -6.0, -12.0, -18.0, -24.0, -30.0, -50.0, -56.0, -62.0]
	for z_position in tile_z_positions:
		var model_scene: PackedScene = BLUE_PLATFORM
		if z_position <= -50.0:
			model_scene = YELLOW_PLATFORM
		elif z_position <= -18.0:
			model_scene = RED_PLATFORM
		for x_position in [-3.0, 3.0]:
			_create_platform_tile(track, Vector3(x_position, -1.0, z_position), model_scene)

	_create_static_box(track, Vector3(0.46, 1.0, 37.0), Vector3(-6.22, 0.42, -12.0), Color("4d83ea"), "LeftRunRail", false)
	_create_static_box(track, Vector3(0.46, 1.0, 37.0), Vector3(6.22, 0.42, -12.0), Color("4d83ea"), "RightRunRail", false)
	_create_static_box(track, Vector3(0.46, 1.0, 18.0), Vector3(-6.22, 0.42, -56.0), Color("f2b632"), "LeftFinishRail", false)
	_create_static_box(track, Vector3(0.46, 1.0, 18.0), Vector3(6.22, 0.42, -56.0), Color("f2b632"), "RightFinishRail", false)
	var railing_index := 0
	for railing_z in range(-30, 7, 2):
		_add_imported_visual(track, BLUE_PADDED_RAIL, Vector3(-5.45, 0.0, float(railing_z)), Vector3.ONE, "BlueLeftRail%d" % railing_index, Vector3(0.0, 90.0, 0.0))
		_add_imported_visual(track, BLUE_PADDED_RAIL, Vector3(5.45, 0.0, float(railing_z)), Vector3.ONE, "BlueRightRail%d" % railing_index, Vector3(0.0, 90.0, 0.0))
		railing_index += 1
	for railing_z in range(-64, -47, 2):
		_add_imported_visual(track, YELLOW_PADDED_RAIL, Vector3(-5.45, 0.0, float(railing_z)), Vector3.ONE, "YellowLeftRail%d" % railing_index, Vector3(0.0, 90.0, 0.0))
		_add_imported_visual(track, YELLOW_PADDED_RAIL, Vector3(5.45, 0.0, float(railing_z)), Vector3.ONE, "YellowRightRail%d" % railing_index, Vector3(0.0, 90.0, 0.0))
		railing_index += 1

	_add_imported_visual(track, BLUE_ARCH, Vector3(0.0, 0.0, 3.0), Vector3(1.8, 1.8, 1.8), "StartArch")
	_add_imported_visual(track, YELLOW_ARCH, Vector3(0.0, 0.0, -58.0), Vector3(1.8, 1.8, 1.8), "FinishArch")
	_add_imported_visual(track, BLUE_ARROW_SIGN, Vector3(-4.5, 0.0, -15.5), Vector3.ONE * 1.2, "CourseArrowA")
	_add_imported_visual(track, YELLOW_ARROW_SIGN, Vector3(4.5, 0.0, -49.5), Vector3.ONE * 1.2, "CourseArrowB")
	_add_imported_visual(track, FINISH_SIGN, Vector3(0.0, 0.0, -60.0), Vector3.ONE, "KayKitFinishSign")
	for flag_data in [
		[Vector3(-5.15, 0.0, 1.0), BLUE_FLAG],
		[Vector3(5.15, 0.0, 1.0), BLUE_FLAG],
		[Vector3(-5.15, 0.0, -57.0), YELLOW_FLAG],
		[Vector3(5.15, 0.0, -57.0), YELLOW_FLAG],
	]:
		_add_imported_visual(track, flag_data[1], flag_data[0], Vector3.ONE * 1.25, "CourseFlag")

	var start_label := Label3D.new()
	start_label.text = "AI TRAINING LAB"
	start_label.font_size = 44
	start_label.outline_size = 8
	start_label.modulate = Color("fff6d6")
	start_label.outline_modulate = Color("443890")
	start_label.position = Vector3(0.0, 4.55, 2.8)
	track.add_child(start_label)

	var finish_label := Label3D.new()
	finish_label.text = "AI CHECKPOINT"
	finish_label.font_size = 40
	finish_label.outline_size = 8
	finish_label.modulate = Color("fff6c8")
	finish_label.outline_modulate = Color("b54852")
	finish_label.position = Vector3(0.0, 4.55, -58.2)
	track.add_child(finish_label)


func _spawn_player() -> void:
	player = PLAYER_SCENE.instantiate() as PlayerController
	player.name = "RangerPlayer"
	player.position = SPAWN_POSITION
	add_child(player)
	spawn_transform = player.global_transform
	player.jump_used.connect(game_manager.notify_jump)
	player.dash_used.connect(game_manager.notify_dash)
	player.fell.connect(_on_player_fell)
	player.knockback_finished.connect(_on_knockback_finished)


func _build_camera() -> void:
	_build_third_person_camera(8.2, -18.5, 95.0)


func _spawn_obstacles() -> void:
	var obstacle_root := Node3D.new()
	obstacle_root.name = "Obstacles"
	add_child(obstacle_root)

	var sweeper := SWEEPER_SCENE.instantiate() as RotatingSweeper
	sweeper.name = "CognitionSweeper"
	sweeper.position = Vector3(0.0, 0.0, -10.5)
	sweeper.period_seconds = 3.2
	sweeper.initial_phase = 0.35
	sweeper.hit_player.connect(_on_obstacle_hit)
	obstacle_root.add_child(sweeper)
	obstacles.append(sweeper)

	var phases := [0.0, TAU / 3.0, TAU * 2.0 / 3.0]
	var gate_colors := [Color("23ced8"), Color("7767f5"), Color("ff7264")]
	for index in range(3):
		var gate := GATE_SCENE.instantiate() as RisingGate
		gate.name = "RisingGate%d" % (index + 1)
		gate.position = Vector3(-4.0 + index * 4.0, 0.0, -25.5)
		gate.initial_phase = phases[index]
		gate.period_seconds = 3.6
		gate.gate_color = gate_colors[index]
		gate.hit_player.connect(_on_obstacle_hit)
		obstacle_root.add_child(gate)
		obstacles.append(gate)

	var bridge := BRIDGE_SCENE.instantiate() as TiltBridge
	bridge.name = "SoftTiltBridge"
	bridge.position = Vector3(0.0, -0.4, -40.0)
	bridge.period_seconds = 4.8
	bridge.initial_phase = 0.0
	obstacle_root.add_child(bridge)
	obstacles.append(bridge)


func _build_finish_trigger() -> void:
	var finish_area := Area3D.new()
	finish_area.name = "FinishQuizTrigger"
	finish_area.position = Vector3(0.0, 1.5, COURSE_FINISH_Z)
	finish_area.collision_layer = 0
	finish_area.collision_mask = 1
	var shape := BoxShape3D.new()
	shape.size = Vector3(10.0, 3.0, 2.0)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	finish_area.add_child(collision)
	finish_area.body_entered.connect(_on_finish_body_entered)
	add_child(finish_area)


func _build_ui() -> void:
	ui = UI_SCRIPT.new() as GameUI
	ui.name = "GameUI"
	add_child(ui)
	ui.configure_result_action(CampaignSession.is_campaign_run())
	ui.start_requested.connect(_on_start_requested)
	ui.restart_requested.connect(_on_restart_requested)
	ui.next_level_requested.connect(_on_next_level_requested)
	ui.quiz_choice_selected.connect(_on_quiz_choice_selected)
	ui.assistant_toggled.connect(_on_assistant_toggled)


func _connect_game_signals() -> void:
	game_manager.run_completed.connect(_on_run_completed)


func _on_start_requested() -> void:
	_reset_level()
	ui.show_running()
	game_manager.start_run()
	player.set_controls_enabled(true)


func _on_restart_requested() -> void:
	game_manager.restart_to_ready()
	_reset_level()
	ui.show_running()
	game_manager.start_run()
	player.set_controls_enabled(true)


func _on_next_level_requested() -> void:
	if game_manager.state != GameManager.GameState.FINISHED:
		return
	var change_error := CampaignSession.load_next_level("ai_training_ground") if CampaignSession.is_campaign_run() else CampaignSession.return_to_menu()
	if change_error != OK:
		push_error("Unable to leave ai_training_ground: %s" % error_string(change_error))


func _on_assistant_toggled(open: bool) -> void:
	game_manager.set_assistant_open(open)
	player.set_controls_enabled(game_manager.can_control_player())


func _on_player_fell() -> void:
	if not game_manager.register_fall():
		return
	player.begin_knockback(Vector3(0.0, 3.0, 0.0), 0.52)
	_start_camera_shake(0.42, 0.22)


func _on_obstacle_hit(hit_player: PlayerController, source_position: Vector3) -> void:
	if hit_player != player or not game_manager.register_obstacle_hit():
		return
	var knock_direction := player.global_position - source_position
	knock_direction.y = 0.0
	if knock_direction.length_squared() < 0.05:
		knock_direction = Vector3(0.8, 0.0, 0.6)
	knock_direction = knock_direction.normalized()
	player.begin_knockback(knock_direction * 9.2 + Vector3.UP * 7.4, 0.7)
	_start_camera_shake(0.7, 0.34)


func _on_knockback_finished() -> void:
	player.respawn_at(spawn_transform)
	game_manager.finish_respawn()


func _on_finish_body_entered(body: Node3D) -> void:
	if body != player or finish_triggered:
		return
	if game_manager.open_quiz():
		finish_triggered = true
		player.set_controls_enabled(false)
		ui.show_quiz(QUIZ_RESOURCE)


func _on_quiz_choice_selected(selected_index: int) -> void:
	var correct := game_manager.submit_quiz_answer(selected_index, QUIZ_RESOURCE.correct_index)
	if not correct:
		ui.show_wrong_answer(selected_index, QUIZ_RESOURCE.explanation)


func _on_run_completed(result: Dictionary) -> void:
	CampaignSession.record_level_result("ai_training_ground", result)
	player.play_celebration()
	ui.show_result(result)


func _reset_level() -> void:
	finish_triggered = false
	player.respawn_at(spawn_transform)
	player.set_controls_enabled(false)
	for obstacle in obstacles:
		if obstacle.has_method("reset_phase"):
			obstacle.call("reset_phase")
	_reset_third_person_camera()


func _update_camera(delta: float) -> void:
	_update_third_person_camera(delta)


func _start_camera_shake(duration: float, strength: float) -> void:
	_start_third_person_camera_shake(duration, strength)


func _create_platform_tile(parent: Node3D, tile_position: Vector3, model_scene: PackedScene) -> void:
	var body := StaticBody3D.new()
	body.name = "PlatformTile"
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
	else:
		var fallback := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(6.0, 1.0, 6.0)
		mesh.material = _make_material(Color("3daee9"), 0.0, 0.55)
		fallback.mesh = mesh
		fallback.position.y = 0.5
		body.add_child(fallback)


func _create_static_box(parent: Node3D, size: Vector3, box_position: Vector3, color: Color, box_name: String, show_visual: bool = true) -> void:
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
	if show_visual:
		var mesh := BoxMesh.new()
		mesh.size = size
		mesh.material = _make_material(color, 0.08, 0.5)
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


func _make_material(color: Color, emission_strength: float = 0.0, roughness: float = 0.55) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if emission_strength > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission_strength
	return material
