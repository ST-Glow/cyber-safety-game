class_name ThirdPersonLevelBase
extends Node3D

const INPUT_DEFAULTS := preload("res://scripts/input_defaults.gd")

const CAMERA_KEY_TURN_SPEED := 1.85
const CAMERA_MOUSE_SENSITIVITY := 0.0045
const DEFAULT_CAMERA_RIG_OFFSET := Vector3(0.0, 1.65, -1.7)

var player: PlayerController
var camera_rig: Node3D
var spring_arm: SpringArm3D
var camera_node: Camera3D
var camera_shake_time: float = 0.0
var camera_shake_strength: float = 0.0
var camera_target_yaw: float = 0.0


func _ensure_third_person_inputs() -> void:
	INPUT_DEFAULTS.ensure_actions()


func _unhandled_input(event: InputEvent) -> void:
	if player == null or not player.controls_enabled or get_tree().paused:
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		camera_target_yaw -= event.relative.x * CAMERA_MOUSE_SENSITIVITY


func _build_third_person_environment(
	background_color: Color,
	ambient_color: Color,
	fog_color: Color,
	fog_energy: float,
	fog_density: float,
	sun_color: Color,
	sun_rotation_degrees: Vector3,
	shadow_distance: float
) -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = background_color
	environment.background_energy_multiplier = 0.62
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = ambient_color
	environment.ambient_light_energy = 0.66
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = fog_color
	environment.fog_light_energy = fog_energy
	environment.fog_density = fog_density
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = sun_color
	sun.light_energy = 1.08
	sun.rotation_degrees = sun_rotation_degrees
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = shadow_distance
	add_child(sun)


func _build_third_person_camera(length: float, tilt_degrees: float, far_distance: float) -> void:
	camera_rig = Node3D.new()
	camera_rig.name = "CameraRig"
	camera_rig.position = player.global_position + DEFAULT_CAMERA_RIG_OFFSET
	add_child(camera_rig)

	spring_arm = SpringArm3D.new()
	spring_arm.name = "SpringArm3D"
	spring_arm.spring_length = length
	spring_arm.margin = 0.24
	# Dynamic hazards use layer 2. Excluding them prevents camera snapping.
	spring_arm.collision_mask = 1
	spring_arm.rotation_degrees.x = tilt_degrees
	camera_rig.add_child(spring_arm)

	camera_node = Camera3D.new()
	camera_node.name = "ThirdPersonCamera"
	camera_node.current = true
	camera_node.fov = 60.0
	camera_node.near = 0.18
	camera_node.far = far_distance
	spring_arm.add_child(camera_node)
	spring_arm.add_excluded_object(player.get_rid())
	player.configure_camera(camera_node)
	camera_target_yaw = camera_rig.rotation.y


func _update_third_person_camera(delta: float) -> void:
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


func _reset_third_person_camera(target_yaw: float = 0.0) -> void:
	if player == null or camera_rig == null:
		return
	camera_rig.position = player.global_position + DEFAULT_CAMERA_RIG_OFFSET
	camera_target_yaw = target_yaw
	camera_rig.rotation.y = camera_target_yaw
	camera_node.h_offset = 0.0
	camera_node.v_offset = 0.0
	camera_shake_time = 0.0


func _start_third_person_camera_shake(duration: float, strength: float) -> void:
	camera_shake_time = duration
	camera_shake_strength = strength
