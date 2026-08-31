class_name PlayerController
extends CharacterBody3D

signal jump_used
signal dash_used
signal fell
signal knockback_finished

@export var move_speed: float = 7.6
@export var jump_velocity: float = 12.0
@export var gravity: float = 23.0
@export var air_control: float = 0.58
@export var dash_duration: float = 0.22
@export var dash_multiplier: float = 2.5
@export var dash_cooldown: float = 2.5
@export var fall_height: float = -7.0

const RANGER_SCENE := preload("res://assets/characters/kaykit_adventurers/characters/Ranger.glb")
const GENERAL_ANIMATIONS_SCENE := preload("res://assets/character_animations/kaykit_character_animations/rig_medium/Rig_Medium_General.glb")
const MOVEMENT_ANIMATIONS_SCENE := preload("res://assets/character_animations/kaykit_character_animations/rig_medium/Rig_Medium_MovementBasic.glb")
const ADVANCED_MOVEMENT_ANIMATIONS_SCENE := preload("res://assets/character_animations/kaykit_character_animations/rig_medium/Rig_Medium_MovementAdvanced.glb")
const SIMULATION_ANIMATIONS_SCENE := preload("res://assets/character_animations/kaykit_character_animations/rig_medium/Rig_Medium_Simulation.glb")
const JUMP_SOUND := preload("res://assets/audio/kenney_ui_pack/tap-a.ogg")
const LAND_SOUND := preload("res://assets/audio/kenney_ui_pack/click-b.ogg")
const DASH_SOUND := preload("res://assets/audio/kenney_ui_pack/switch-a.ogg")
const HIT_SOUND := preload("res://assets/audio/interface_sfx_pack_1/error_tones/style1/error_style_1_001.ogg")
const MODEL_FORWARD_OFFSET := PI

var camera_node: Camera3D
var controls_enabled: bool = false
var dash_time_left: float = 0.0
var dash_cooldown_left: float = 0.0

var _visual_root: Node3D
var _animation_player: AnimationPlayer
var _last_move_direction := Vector3(0.0, 0.0, -1.0)
var _knockback_active: bool = false
var _knockback_time_left: float = 0.0
var _fall_reported: bool = false
var _was_on_floor: bool = false
var _jump_start_time_left: float = 0.0
var _landing_time_left: float = 0.0
var _current_animation: StringName = &""
var _celebrating: bool = false
var _impact_particles: CPUParticles3D
var _jump_audio: AudioStreamPlayer3D
var _land_audio: AudioStreamPlayer3D
var _dash_audio: AudioStreamPlayer3D
var _hit_audio: AudioStreamPlayer3D
var _visual_feedback_scale := Vector3.ONE
var _animation_token_cache: Dictionary[StringName, StringName] = {}


func _ready() -> void:
	collision_layer = 1
	collision_mask = 3
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(48.0)
	_build_collision()
	_build_visual()
	_build_feedback()


func _physics_process(delta: float) -> void:
	dash_cooldown_left = maxf(0.0, dash_cooldown_left - delta)
	dash_time_left = maxf(0.0, dash_time_left - delta)
	_jump_start_time_left = maxf(0.0, _jump_start_time_left - delta)
	_landing_time_left = maxf(0.0, _landing_time_left - delta)

	if _knockback_active:
		_process_knockback(delta)
	elif controls_enabled:
		_process_controlled_movement(delta)
	else:
		_process_disabled_movement(delta)

	if global_position.y < fall_height and not _fall_reported and not _knockback_active:
		_fall_reported = true
		fell.emit()

	var planar_speed := Vector2(velocity.x, velocity.z).length()
	_update_animation(planar_speed)
	_update_visual_feedback(delta, planar_speed)


func configure_camera(value: Camera3D) -> void:
	camera_node = value


func set_controls_enabled(value: bool) -> void:
	controls_enabled = value
	if value:
		_celebrating = false


func play_celebration() -> void:
	controls_enabled = false
	dash_time_left = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	_celebrating = true
	if _animation_player:
		_animation_player.process_mode = Node.PROCESS_MODE_ALWAYS
		_play_animation_token("Cheering", 1.0)


func is_dashing() -> bool:
	return dash_time_left > 0.0


func is_knocked_back() -> bool:
	return _knockback_active


func get_dash_cooldown_ratio() -> float:
	return clampf(dash_cooldown_left / dash_cooldown, 0.0, 1.0)


func get_facing_direction() -> Vector3:
	return _last_move_direction.normalized()


func get_facing_yaw() -> float:
	var facing := get_facing_direction()
	return atan2(-facing.x, -facing.z)


func begin_knockback(force: Vector3, duration: float = 0.7) -> void:
	if _knockback_active:
		return
	_knockback_active = true
	_knockback_time_left = duration
	controls_enabled = false
	dash_time_left = 0.0
	velocity = force
	_play_audio(_hit_audio)
	burst_impact_particles()


func respawn_at(spawn_transform: Transform3D) -> void:
	global_transform = spawn_transform
	velocity = Vector3.ZERO
	dash_time_left = 0.0
	_knockback_active = false
	_knockback_time_left = 0.0
	_fall_reported = false
	_jump_start_time_left = 0.0
	_landing_time_left = 0.0
	_celebrating = false
	_visual_feedback_scale = Vector3.ONE
	if _visual_root:
		_visual_root.rotation = Vector3(0.0, MODEL_FORWARD_OFFSET, 0.0)
		_visual_root.scale = Vector3.ONE
	if _animation_player:
		_animation_player.process_mode = Node.PROCESS_MODE_INHERIT
	controls_enabled = true


func burst_impact_particles() -> void:
	if _impact_particles:
		_impact_particles.restart()
		_impact_particles.emitting = true


func _process_controlled_movement(delta: float) -> void:
	var horizontal_input := Input.get_axis("move_left", "move_right")
	var backward_input := maxf(Input.get_action_strength("move_back"), Input.get_action_strength("move_backward"))
	var forward_input := Input.get_action_strength("move_forward")
	var input_vector := Vector2(horizontal_input, backward_input - forward_input).limit_length()
	var movement_direction := _camera_relative_direction(input_vector)
	var control_factor := 1.0 if is_on_floor() else air_control
	var target_speed := move_speed * (dash_multiplier if dash_time_left > 0.0 else 1.0)

	var sprint_requested := Input.is_action_just_pressed("dash") or Input.is_action_just_pressed("sprint")
	# Web browsers can deliver Shift as an already-held physical key when the
	# canvas regains focus. Accept that first held frame as a sprint request too.
	sprint_requested = sprint_requested or (Input.is_action_pressed("sprint") and dash_time_left <= 0.0)
	if sprint_requested and dash_cooldown_left <= 0.0:
		dash_time_left = dash_duration
		dash_cooldown_left = dash_cooldown
		if movement_direction.length_squared() < 0.01:
			movement_direction = _last_move_direction
		_play_audio(_dash_audio)
		dash_used.emit()
		target_speed = move_speed * dash_multiplier

	if movement_direction.length_squared() > 0.01:
		_last_move_direction = movement_direction
		velocity.x = move_toward(velocity.x, movement_direction.x * target_speed, move_speed * 15.0 * control_factor * delta)
		velocity.z = move_toward(velocity.z, movement_direction.z * target_speed, move_speed * 15.0 * control_factor * delta)
		var target_yaw := atan2(-movement_direction.x, -movement_direction.z) + MODEL_FORWARD_OFFSET
		_visual_root.rotation.y = lerp_angle(_visual_root.rotation.y, target_yaw, 1.0 - exp(-14.0 * delta))
	else:
		var deceleration := move_speed * (17.0 if is_on_floor() else 2.8) * delta
		velocity.x = move_toward(velocity.x, 0.0, deceleration)
		velocity.z = move_toward(velocity.z, 0.0, deceleration)

	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity
			_jump_start_time_left = 0.16
			_play_audio(_jump_audio)
			jump_used.emit()
	else:
		velocity.y -= gravity * delta

	var before_floor := is_on_floor()
	move_and_slide()
	var after_floor := is_on_floor()
	if after_floor and not before_floor and velocity.y <= 0.1:
		_landing_time_left = 0.18
		_play_audio(_land_audio)
	_was_on_floor = after_floor


func _process_disabled_movement(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, move_speed * 18.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, move_speed * 18.0 * delta)
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()


func _process_knockback(delta: float) -> void:
	_knockback_time_left -= delta
	velocity.y -= gravity * delta
	_visual_root.rotate_y(delta * 8.0)
	move_and_slide()
	if _knockback_time_left <= 0.0:
		_knockback_active = false
		var recovery_yaw := atan2(-_last_move_direction.x, -_last_move_direction.z) + MODEL_FORWARD_OFFSET
		_visual_root.rotation.y = recovery_yaw
		knockback_finished.emit()


func _camera_relative_direction(input_vector: Vector2) -> Vector3:
	if input_vector.length_squared() < 0.001:
		return Vector3.ZERO
	var forward := Vector3(0.0, 0.0, -1.0)
	var right := Vector3(1.0, 0.0, 0.0)
	if camera_node:
		forward = -camera_node.global_basis.z
		forward.y = 0.0
		forward = forward.normalized()
		right = camera_node.global_basis.x
		right.y = 0.0
		right = right.normalized()
	# Input.get_vector returns a negative Y value for the forward action.
	return (right * input_vector.x + forward * -input_vector.y).normalized()


func _build_collision() -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.52
	capsule.height = 2.15
	var collision := CollisionShape3D.new()
	collision.name = "CapsuleCollision"
	collision.shape = capsule
	collision.position.y = 1.075
	add_child(collision)


func _build_visual() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "VisualRoot"
	_visual_root.rotation.y = MODEL_FORWARD_OFFSET
	add_child(_visual_root)

	var ranger_scene: PackedScene = RANGER_SCENE
	if ranger_scene == null:
		push_error("Ranger.glb could not be loaded.")
		_build_fallback_character()
		return
	var ranger := ranger_scene.instantiate()
	ranger.name = "RangerModel"
	_visual_root.add_child(ranger)
	_animation_player = _find_animation_player(ranger)
	if _animation_player == null:
		# The Ranger GLB contains the compatible Rig_Medium skeleton but no named
		# playback library after import. Attach a player to that same hierarchy so
		# the external KayKit animation tracks can target its bones.
		_animation_player = AnimationPlayer.new()
		_animation_player.name = "MVPAnimationPlayer"
		_animation_player.root_node = NodePath("..")
		ranger.add_child(_animation_player)
	_copy_animation_set(GENERAL_ANIMATIONS_SCENE, "General")
	_copy_animation_set(MOVEMENT_ANIMATIONS_SCENE, "MovementBasic")
	_copy_animation_set(ADVANCED_MOVEMENT_ANIMATIONS_SCENE, "MovementAdvanced")
	_copy_animation_set(SIMULATION_ANIMATIONS_SCENE, "Simulation")
	_play_animation_token("Idle", 1.0)


func _build_fallback_character() -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.52
	mesh.height = 2.15
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("28c8da")
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position.y = 1.075
	_visual_root.add_child(visual)


func _build_feedback() -> void:
	_impact_particles = CPUParticles3D.new()
	_impact_particles.name = "ImpactParticles"
	_impact_particles.position.y = 1.0
	_impact_particles.amount = 18
	_impact_particles.lifetime = 0.46
	_impact_particles.one_shot = true
	_impact_particles.emitting = false
	_impact_particles.direction = Vector3.UP
	_impact_particles.spread = 145.0
	_impact_particles.initial_velocity_min = 3.5
	_impact_particles.initial_velocity_max = 6.5
	_impact_particles.gravity = Vector3(0.0, -9.0, 0.0)
	var particle_mesh := SphereMesh.new()
	particle_mesh.radius = 0.075
	particle_mesh.height = 0.15
	var particle_material := StandardMaterial3D.new()
	particle_material.albedo_color = Color("ffdf57")
	particle_material.emission_enabled = true
	particle_material.emission = Color("ff764f")
	particle_material.emission_energy_multiplier = 1.8
	particle_mesh.material = particle_material
	_impact_particles.mesh = particle_mesh
	add_child(_impact_particles)

	_jump_audio = _make_audio_player(JUMP_SOUND, -7.0)
	_land_audio = _make_audio_player(LAND_SOUND, -9.0)
	_dash_audio = _make_audio_player(DASH_SOUND, -5.0)
	_hit_audio = _make_audio_player(HIT_SOUND, -4.0)


func _make_audio_player(audio_stream: AudioStream, volume_db: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = audio_stream
	player.volume_db = volume_db
	player.max_distance = 35.0
	add_child(player)
	return player


func _play_audio(player: AudioStreamPlayer3D) -> void:
	if player and player.stream:
		player.play()


func _copy_animation_set(source_scene: PackedScene, library_name: String) -> void:
	_animation_token_cache.clear()
	if source_scene == null:
		push_warning("Animation library could not be loaded: %s" % library_name)
		return
	var source_root := source_scene.instantiate()
	var source_player := _find_animation_player(source_root)
	if source_player == null:
		source_root.free()
		return
	if not _animation_player.has_animation_library(library_name):
		_animation_player.add_animation_library(library_name, AnimationLibrary.new())
	var target_library := _animation_player.get_animation_library(library_name)
	for source_name in source_player.get_animation_list():
		var clean_name := String(source_name)
		if clean_name.contains("/"):
			clean_name = clean_name.get_slice("/", clean_name.get_slice_count("/") - 1)
		if target_library.has_animation(clean_name):
			target_library.remove_animation(clean_name)
		var animation := source_player.get_animation(source_name)
		if animation:
			target_library.add_animation(clean_name, animation.duplicate(true))
	source_root.free()


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var result := _find_animation_player(child)
		if result:
			return result
	return null


func _update_animation(planar_speed: float) -> void:
	if _animation_player == null:
		return
	if _celebrating:
		_play_animation_token("Cheering", 1.0)
	elif _knockback_active:
		_play_animation_token("Hit_A", 1.1)
	elif is_dashing() and is_on_floor():
		_play_animation_token("Dodge_Forward", 1.15)
	elif not is_on_floor():
		if _jump_start_time_left > 0.0:
			_play_animation_token("Jump_Start", 1.1)
		else:
			_play_animation_token("Jump_Full_Short", 1.0)
	elif _landing_time_left > 0.0:
		_play_animation_token("Jump_Land", 1.15)
	elif planar_speed > 0.7:
		var speed_ratio := planar_speed / maxf(move_speed, 0.1)
		_play_animation_token("Running_A", clampf(0.86 + speed_ratio * 0.22, 0.9, 1.5))
	else:
		_play_animation_token("Idle", 1.0)


func _update_visual_feedback(delta: float, planar_speed: float) -> void:
	if _visual_root == null:
		return
	var target_scale := Vector3.ONE
	var target_pitch := 0.0
	var target_roll := 0.0
	if _knockback_active:
		target_scale = Vector3(0.94, 1.05, 0.94)
		target_pitch = -0.12
	elif _landing_time_left > 0.0 and is_on_floor():
		var landing_ratio := clampf(_landing_time_left / 0.18, 0.0, 1.0)
		target_scale = Vector3(1.0 + landing_ratio * 0.07, 1.0 - landing_ratio * 0.1, 1.0 + landing_ratio * 0.07)
	elif not is_on_floor():
		var rise_ratio := clampf(velocity.y / maxf(jump_velocity, 0.1), -1.0, 1.0)
		target_scale = Vector3(0.97, 1.045, 0.97)
		target_pitch = -rise_ratio * 0.07
	elif is_dashing():
		target_scale = Vector3(0.96, 0.98, 1.08)
		target_pitch = 0.14
	elif planar_speed > 0.7:
		target_pitch = clampf(planar_speed / maxf(move_speed, 0.1), 0.0, 1.0) * 0.045

	if controls_enabled and planar_speed > 0.3:
		var local_velocity := _visual_root.global_transform.basis.orthonormalized().transposed() * velocity
		target_roll = clampf(-local_velocity.x / maxf(move_speed, 0.1), -1.0, 1.0) * 0.07

	_visual_feedback_scale = _visual_feedback_scale.lerp(target_scale, 1.0 - exp(-13.0 * delta))
	_visual_root.scale = _visual_feedback_scale
	_visual_root.rotation.x = lerp_angle(_visual_root.rotation.x, target_pitch, 1.0 - exp(-11.0 * delta))
	_visual_root.rotation.z = lerp_angle(_visual_root.rotation.z, target_roll, 1.0 - exp(-11.0 * delta))


func _play_animation_token(token: String, speed: float) -> void:
	var resolved := _resolve_animation(token)
	if resolved == &"":
		return
	if _current_animation != resolved:
		_current_animation = resolved
		_animation_player.play(resolved, 0.12, speed)
	else:
		_animation_player.speed_scale = speed


func _resolve_animation(token: StringName) -> StringName:
	if _animation_token_cache.has(token):
		return _animation_token_cache[token]
	var lower_token := String(token).to_lower()
	for animation_name in _animation_player.get_animation_list():
		var lower_name := String(animation_name).to_lower()
		if lower_name.ends_with(lower_token) or lower_name.contains(lower_token):
			_animation_token_cache[token] = animation_name
			return animation_name
	_animation_token_cache[token] = &""
	return &""
