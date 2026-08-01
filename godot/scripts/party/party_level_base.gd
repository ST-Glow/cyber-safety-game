class_name PartyLevelBase
extends Node3D

const SHARED_PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const EXPERIMENT_EVENTS := preload("res://scripts/experiment_event_bridge.gd")

var player: PlayerController
var camera_rig: Node3D
var spring_arm: SpringArm3D
var camera_node: Camera3D
var camera_shake_time: float = 0.0
var camera_shake_strength: float = 0.0
var camera_target_yaw: float = 0.0
var experiment_level_id: String = "party_mode"

const CAMERA_KEY_TURN_SPEED := 1.85
const CAMERA_MOUSE_SENSITIVITY := 0.0045


func _ensure_party_inputs() -> void:
	_add_key_action("move_forward", [KEY_W, KEY_UP])
	_add_key_action("move_back", [KEY_S, KEY_DOWN])
	_add_key_action("move_left", [KEY_A, KEY_LEFT])
	_add_key_action("move_right", [KEY_D, KEY_RIGHT])
	_add_key_action("jump", [KEY_SPACE])
	_add_key_action("dash", [KEY_SHIFT])
	_add_key_action("camera_left", [KEY_Q])
	_add_key_action("camera_right", [KEY_E])
	_add_key_action("camera_reset", [KEY_R])


func _unhandled_input(event: InputEvent) -> void:
	if player == null or not player.controls_enabled or get_tree().paused:
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		camera_target_yaw -= event.relative.x * CAMERA_MOUSE_SENSITIVITY


func _build_party_world(background: Color, fog_color: Color, scenery_colors: Array[Color]) -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = background
	environment.background_energy_multiplier = 0.62
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("e9fbff")
	environment.ambient_light_energy = 0.66
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = fog_color
	environment.fog_light_energy = 0.38
	environment.fog_density = 0.006
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color("fff2d8")
	sun.light_energy = 1.08
	sun.rotation_degrees = Vector3(-54.0, -28.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 82.0
	add_child(sun)

	var scenery := Node3D.new()
	scenery.name = "PartyScenery"
	add_child(scenery)
	for index in range(24):
		var hill := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		var radius := 3.4 + float(index % 4) * 1.05
		mesh.radius = radius
		mesh.height = radius * 2.0
		mesh.material = _make_party_material(scenery_colors[index % scenery_colors.size()], 0.0, 0.86)
		hill.mesh = mesh
		var side := -1.0 if index % 2 == 0 else 1.0
		hill.position = Vector3(side * (18.0 + float(index % 3) * 5.0), -4.2, 13.0 - float(index) * 3.5)
		scenery.add_child(hill)


func _spawn_party_player(start_position: Vector3) -> Transform3D:
	player = SHARED_PLAYER_SCENE.instantiate() as PlayerController
	player.name = "RangerPlayer"
	player.position = start_position
	add_child(player)
	return player.global_transform


func _connect_party_player_events(level_id: String) -> void:
	experiment_level_id = level_id
	if not player.jump_used.is_connected(_record_party_jump):
		player.jump_used.connect(_record_party_jump)
	if not player.dash_used.is_connected(_record_party_dash):
		player.dash_used.connect(_record_party_dash)


func _record_party_jump() -> void:
	EXPERIMENT_EVENTS.record(self, "jump_used", experiment_level_id)


func _record_party_dash() -> void:
	EXPERIMENT_EVENTS.record(self, "dash_used", experiment_level_id)


func _build_party_camera(length: float = 8.2, tilt_degrees: float = -18.5) -> void:
	camera_rig = Node3D.new()
	camera_rig.name = "CameraRig"
	camera_rig.position = player.global_position + Vector3(0.0, 1.65, -1.7)
	add_child(camera_rig)
	spring_arm = SpringArm3D.new()
	spring_arm.name = "SpringArm3D"
	spring_arm.spring_length = length
	spring_arm.margin = 0.24
	# Dynamic hazards use layer 2. Keeping them out of the camera mask prevents
	# sweepers and pushers from snapping the camera toward the player.
	spring_arm.collision_mask = 1
	spring_arm.rotation_degrees.x = tilt_degrees
	camera_rig.add_child(spring_arm)
	camera_node = Camera3D.new()
	camera_node.name = "ThirdPersonCamera"
	camera_node.current = true
	camera_node.fov = 60.0
	camera_node.near = 0.18
	camera_node.far = 150.0
	spring_arm.add_child(camera_node)
	spring_arm.add_excluded_object(player.get_rid())
	player.configure_camera(camera_node)
	camera_target_yaw = camera_rig.rotation.y


func _update_party_camera(delta: float) -> void:
	if player == null or camera_rig == null:
		return
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


func _reset_party_camera() -> void:
	if player == null or camera_rig == null:
		return
	camera_rig.position = player.global_position + Vector3(0.0, 1.65, -1.7)
	camera_target_yaw = 0.0
	camera_rig.rotation.y = camera_target_yaw
	camera_node.h_offset = 0.0
	camera_node.v_offset = 0.0
	camera_shake_time = 0.0


func _start_party_camera_shake(duration: float, strength: float) -> void:
	camera_shake_time = duration
	camera_shake_strength = strength


func _create_party_platform(
	parent: Node3D,
	size: Vector3,
	position_value: Vector3,
	visual_scene: PackedScene,
	name_value: String,
	native_size: Vector3 = Vector3(4.0, 1.0, 4.0),
	rotation_value: Vector3 = Vector3.ZERO
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name_value
	body.position = position_value
	body.rotation_degrees = rotation_value
	body.collision_layer = 1
	body.collision_mask = 1
	parent.add_child(body)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	if visual_scene:
		var visual := visual_scene.instantiate() as Node3D
		visual.name = "KayKitVisual"
		visual.position.y = -size.y * 0.5
		visual.scale = Vector3(
			size.x / native_size.x,
			size.y / native_size.y,
			size.z / native_size.z
		)
		body.add_child(visual)
	return body


func _create_party_collision_box(parent: Node3D, size: Vector3, position_value: Vector3, name_value: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name_value
	body.position = position_value
	body.collision_layer = 1
	body.collision_mask = 1
	parent.add_child(body)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	return body


func _add_party_visual(
	parent: Node3D,
	scene: PackedScene,
	position_value: Vector3,
	scale_value: Vector3,
	name_value: String,
	rotation_value: Vector3 = Vector3.ZERO
) -> Node3D:
	if scene == null:
		return null
	var visual := scene.instantiate() as Node3D
	visual.name = name_value
	visual.position = position_value
	visual.scale = scale_value
	visual.rotation_degrees = rotation_value
	parent.add_child(visual)
	return visual


func _add_party_beacon(
	parent: Node3D,
	position_value: Vector3,
	color: Color,
	name_value: String,
	height: float = 3.2
) -> Node3D:
	var beacon := Node3D.new()
	beacon.name = name_value
	beacon.position = position_value
	parent.add_child(beacon)

	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.42
	base_mesh.bottom_radius = 0.5
	base_mesh.height = 0.16
	base_mesh.material = _make_party_material(color.darkened(0.18), 0.15, 0.58)
	var base := MeshInstance3D.new()
	base.name = "BeaconBase"
	base.mesh = base_mesh
	base.position.y = 0.08
	beacon.add_child(base)

	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.075
	pole_mesh.bottom_radius = 0.11
	pole_mesh.height = height
	pole_mesh.material = _make_party_material(color, 0.55, 0.38)
	var pole := MeshInstance3D.new()
	pole.name = "BeaconPole"
	pole.mesh = pole_mesh
	pole.position.y = height * 0.5
	beacon.add_child(pole)

	var cap_mesh := SphereMesh.new()
	cap_mesh.radius = 0.24
	cap_mesh.height = 0.48
	cap_mesh.material = _make_party_material(color.lightened(0.2), 1.5, 0.32)
	var cap := MeshInstance3D.new()
	cap.name = "BeaconLight"
	cap.mesh = cap_mesh
	cap.position.y = height
	beacon.add_child(cap)
	return beacon


func _add_party_floor_marker(
	parent: Node3D,
	position_value: Vector3,
	radius: float,
	color: Color,
	name_value: String
) -> MeshInstance3D:
	var marker_mesh := CylinderMesh.new()
	marker_mesh.top_radius = radius
	marker_mesh.bottom_radius = radius
	marker_mesh.height = 0.025
	marker_mesh.radial_segments = 40
	var marker_material := StandardMaterial3D.new()
	marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker_material.albedo_color = Color(color.r, color.g, color.b, 0.18)
	marker_material.roughness = 0.72
	marker_material.emission_enabled = true
	marker_material.emission = color
	marker_material.emission_energy_multiplier = 0.38
	marker_mesh.material = marker_material
	var marker := MeshInstance3D.new()
	marker.name = name_value
	marker.mesh = marker_mesh
	marker.position = position_value + Vector3.UP * 0.025
	parent.add_child(marker)
	return marker


func _make_party_material(color: Color, emission_strength: float = 0.0, roughness: float = 0.55) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if emission_strength > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission_strength
	return material


func _add_key_action(action_name: StringName, keycodes: Array) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name, 0.2)
	for keycode in keycodes:
		var input_event := InputEventKey.new()
		input_event.physical_keycode = keycode
		if not InputMap.action_has_event(action_name, input_event):
			InputMap.action_add_event(action_name, input_event)
