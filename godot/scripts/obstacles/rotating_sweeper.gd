class_name RotatingSweeper
extends AnimatableBody3D

signal hit_player(player, source_position)

const SWEEP_SOUND := preload("res://assets/audio/kenney_ui_pack/switch-a.ogg")

@export var period_seconds: float = 3.2
@export var initial_phase: float = 0.0
@export var arm_length: float = 10.5
@export var arm_height: float = 0.45
@export var arm_center_y: float = 0.82

var _elapsed: float = 0.0
var _sweep_sound_time: float = 0.0
var _sweep_audio: AudioStreamPlayer3D
var _danger_zone_material: StandardMaterial3D
var _warning_beacon_material: StandardMaterial3D


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	_build_visuals_and_collision()
	rotation.y = initial_phase


func _physics_process(delta: float) -> void:
	_elapsed += delta
	_sweep_sound_time += delta
	rotation.y = initial_phase + TAU * fmod(_elapsed, period_seconds) / period_seconds
	_update_warning_feedback()
	var sound_interval := maxf(period_seconds * 0.5, 0.35)
	if _sweep_sound_time >= sound_interval:
		_sweep_sound_time = fmod(_sweep_sound_time, sound_interval)
		_play_sweep_sound()


func reset_phase() -> void:
	_elapsed = 0.0
	_sweep_sound_time = 0.0
	rotation.y = initial_phase
	_update_warning_feedback()
	if _sweep_audio:
		_sweep_audio.stop()


func _build_visuals_and_collision() -> void:
	_build_danger_zone()

	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.78
	base_mesh.bottom_radius = 0.9
	base_mesh.height = 0.28
	base_mesh.material = _make_material(Color("453aa8"), 0.04)
	var base_visual := MeshInstance3D.new()
	base_visual.name = "SpinnerBase"
	base_visual.mesh = base_mesh
	base_visual.position.y = 0.14
	add_child(base_visual)

	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.46
	post_mesh.bottom_radius = 0.58
	post_mesh.height = 1.55
	post_mesh.material = _make_material(Color("6a5cf5"), 0.08)
	var post_visual := MeshInstance3D.new()
	post_visual.name = "SpinnerPost"
	post_visual.mesh = post_mesh
	post_visual.position.y = 0.78
	add_child(post_visual)

	var cap_mesh := SphereMesh.new()
	cap_mesh.radius = 0.58
	cap_mesh.height = 1.16
	cap_mesh.material = _make_material(Color("ffd84a"), 0.08)
	var cap_visual := MeshInstance3D.new()
	cap_visual.name = "SpinnerCap"
	cap_visual.mesh = cap_mesh
	cap_visual.position.y = 1.62
	add_child(cap_visual)

	# The old white box stripe covered most of the arm from the chase-camera
	# angle. A rounded coral beam with small yellow bands remains readable at
	# close range without looking like an untextured placeholder.
	var arm_radius := maxf(0.2, arm_height * 0.52)
	var arm_mesh := CapsuleMesh.new()
	arm_mesh.radius = arm_radius
	arm_mesh.height = maxf(arm_length, arm_radius * 2.0)
	arm_mesh.radial_segments = 20
	arm_mesh.rings = 4
	arm_mesh.material = _make_material(Color("f15f61"), 0.03)
	var arm_visual := MeshInstance3D.new()
	arm_visual.name = "RoundedSweepArm"
	arm_visual.mesh = arm_mesh
	arm_visual.position.y = arm_center_y
	arm_visual.rotation_degrees.z = 90.0
	add_child(arm_visual)

	for band_index in range(5):
		var band_mesh := CylinderMesh.new()
		band_mesh.top_radius = arm_radius * 1.07
		band_mesh.bottom_radius = arm_radius * 1.07
		band_mesh.height = 0.18
		band_mesh.radial_segments = 20
		band_mesh.material = _make_material(Color("ffd85a"), 0.04)
		var band_visual := MeshInstance3D.new()
		band_visual.name = "SafetyBand%d" % (band_index + 1)
		band_visual.mesh = band_mesh
		band_visual.position = Vector3(lerpf(-arm_length * 0.34, arm_length * 0.34, float(band_index) / 4.0), arm_center_y, 0.0)
		band_visual.rotation_degrees.z = 90.0
		add_child(band_visual)

	var arm_shape := BoxShape3D.new()
	arm_shape.size = Vector3(arm_length, arm_radius * 2.0, arm_radius * 2.0)
	var arm_collision := CollisionShape3D.new()
	arm_collision.name = "SweepArmCollision"
	arm_collision.shape = arm_shape
	arm_collision.position.y = arm_center_y
	add_child(arm_collision)

	var hit_area := Area3D.new()
	hit_area.name = "HitArea"
	hit_area.collision_layer = 0
	hit_area.collision_mask = 1
	var area_shape := CollisionShape3D.new()
	var hit_shape := BoxShape3D.new()
	hit_shape.size = arm_shape.size + Vector3(0.24, 0.16, 0.16)
	area_shape.shape = hit_shape
	area_shape.position.y = arm_center_y
	hit_area.add_child(area_shape)
	hit_area.body_entered.connect(_on_body_entered)
	add_child(hit_area)

	_sweep_audio = AudioStreamPlayer3D.new()
	_sweep_audio.name = "SweepAudio"
	_sweep_audio.stream = SWEEP_SOUND
	_sweep_audio.volume_db = -10.0
	_sweep_audio.max_distance = 22.0
	_sweep_audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(_sweep_audio)


func _build_danger_zone() -> void:
	var warning_radius := arm_length * 0.5 + 0.42
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = warning_radius
	disc_mesh.bottom_radius = warning_radius
	disc_mesh.height = 0.035
	disc_mesh.radial_segments = 48
	_danger_zone_material = _make_transparent_emissive_material(Color("ff6d63"), 0.13, 0.28)
	disc_mesh.material = _danger_zone_material
	var disc := MeshInstance3D.new()
	disc.name = "DangerZone"
	disc.mesh = disc_mesh
	disc.position.y = 0.035
	add_child(disc)

	_warning_beacon_material = _make_material(Color("ffe36b"), 1.1)
	for index in range(8):
		var angle := TAU * float(index) / 8.0
		var beacon_mesh := SphereMesh.new()
		beacon_mesh.radius = 0.11
		beacon_mesh.height = 0.22
		beacon_mesh.material = _warning_beacon_material
		var beacon := MeshInstance3D.new()
		beacon.name = "WarningBeacon%d" % (index + 1)
		beacon.mesh = beacon_mesh
		beacon.position = Vector3(cos(angle) * warning_radius, 0.16, sin(angle) * warning_radius)
		add_child(beacon)


func _update_warning_feedback() -> void:
	var pulse := 0.5 + 0.5 * sin(_elapsed * TAU * 2.0 / maxf(period_seconds, 0.2))
	if _danger_zone_material:
		var zone_color := Color("ff6d63")
		zone_color.a = lerpf(0.09, 0.18, pulse)
		_danger_zone_material.albedo_color = zone_color
		_danger_zone_material.emission_energy_multiplier = lerpf(0.18, 0.42, pulse)
	if _warning_beacon_material:
		_warning_beacon_material.emission_energy_multiplier = lerpf(0.7, 1.8, pulse)


func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		hit_player.emit(body, global_position)


func _play_sweep_sound() -> void:
	if _sweep_audio == null or _sweep_audio.stream == null:
		return
	_sweep_audio.pitch_scale = clampf(3.2 / maxf(period_seconds, 0.5), 0.82, 1.22)
	_sweep_audio.play()


func _make_material(color: Color, emission_strength: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.52
	if emission_strength > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission_strength
	return material


func _make_transparent_emissive_material(color: Color, alpha: float, emission_strength: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.roughness = 0.7
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = emission_strength
	return material
