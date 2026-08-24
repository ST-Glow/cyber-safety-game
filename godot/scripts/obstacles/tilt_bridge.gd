class_name TiltBridge
extends AnimatableBody3D

@export var period_seconds: float = 4.8
@export var initial_phase: float = 0.0
@export var tilt_radians: float = 0.12
@export var bridge_size: Vector3 = Vector3(10.0, 0.8, 14.0)

var _elapsed: float = 0.0


func _ready() -> void:
	collision_layer = 1
	collision_mask = 1
	_build_bridge()
	_apply_phase()


func _physics_process(delta: float) -> void:
	_elapsed += delta
	_apply_phase()


func reset_phase() -> void:
	_elapsed = 0.0
	_apply_phase()


func _apply_phase() -> void:
	rotation.z = sin(TAU * _elapsed / period_seconds + initial_phase) * tilt_radians


func _build_bridge() -> void:
	var body_shape := BoxShape3D.new()
	body_shape.size = bridge_size
	var collision := CollisionShape3D.new()
	collision.shape = body_shape
	add_child(collision)

	var plank_depth := bridge_size.z / 8.0 - 0.08
	for index in range(8):
		var plank_mesh := BoxMesh.new()
		plank_mesh.size = Vector3(bridge_size.x, bridge_size.y, plank_depth)
		var color := Color("48d8dc") if index % 2 == 0 else Color("7869f8")
		plank_mesh.material = _make_material(color)
		var plank := MeshInstance3D.new()
		plank.mesh = plank_mesh
		plank.position.z = -bridge_size.z * 0.5 + plank_depth * 0.5 + index * (bridge_size.z / 8.0)
		add_child(plank)

	for side in [-1.0, 1.0]:
		var edge_mesh := BoxMesh.new()
		edge_mesh.size = Vector3(0.24, 0.2, bridge_size.z)
		edge_mesh.material = _make_material(Color("ffe06a"))
		var edge := MeshInstance3D.new()
		edge.mesh = edge_mesh
		edge.position = Vector3(side * (bridge_size.x * 0.5 - 0.12), bridge_size.y * 0.62, 0.0)
		add_child(edge)


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.58
	return material

