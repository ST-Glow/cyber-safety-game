class_name PartyLevelBase
extends "res://scripts/third_person_level_base.gd"

const SHARED_PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const EXPERIMENT_EVENTS := preload("res://scripts/experiment_event_bridge.gd")

var experiment_level_id: String = "party_mode"


func _ensure_party_inputs() -> void:
	_ensure_third_person_inputs()


func _build_party_world(background: Color, fog_color: Color, scenery_colors: Array[Color]) -> void:
	_build_third_person_environment(
		background,
		Color("e9fbff"),
		fog_color,
		0.38,
		0.006,
		Color("fff2d8"),
		Vector3(-54.0, -28.0, 0.0),
		82.0
	)

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
	_build_third_person_camera(length, tilt_degrees, 150.0)


func _update_party_camera(delta: float) -> void:
	_update_third_person_camera(delta)


func _reset_party_camera() -> void:
	_reset_third_person_camera()


func _start_party_camera_shake(duration: float, strength: float) -> void:
	_start_third_person_camera_shake(duration, strength)


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
