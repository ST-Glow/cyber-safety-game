class_name MovingPlatform
extends AnimatableBody3D

@export var movement_offset: Vector3 = Vector3(4.0, 0.0, 0.0)
@export var period_seconds: float = 3.6
@export var initial_phase: float = 0.0
@export var platform_size: Vector3 = Vector3(5.0, 0.8, 5.0)
@export var platform_color: Color = Color("42d6d1")
@export var visual_scene: PackedScene

var _origin_position := Vector3.ZERO
var _elapsed: float = 0.0


func _ready() -> void:
	collision_layer = 1
	collision_mask = 1
	sync_to_physics = true
	_origin_position = position
	_build_platform()
	_apply_phase()


func _physics_process(delta: float) -> void:
	_elapsed += delta
	_apply_phase()


func reset_phase() -> void:
	_elapsed = 0.0
	_apply_phase()


func _apply_phase() -> void:
	var phase := TAU * _elapsed / maxf(0.1, period_seconds) + initial_phase
	var travel := (1.0 - cos(phase)) * 0.5
	position = _origin_position + movement_offset * travel


func _build_platform() -> void:
	var shape := BoxShape3D.new()
	shape.size = platform_size
	var collision := CollisionShape3D.new()
	collision.name = "PlatformCollision"
	collision.shape = shape
	add_child(collision)

	if visual_scene:
		var kaykit_visual := visual_scene.instantiate() as Node3D
		kaykit_visual.name = "KayKitPlatformVisual"
		kaykit_visual.position.y = -platform_size.y * 0.5
		kaykit_visual.scale = Vector3(
			platform_size.x / 4.0,
			platform_size.y,
			platform_size.z / 4.0
		)
		add_child(kaykit_visual)
	else:
		var mesh := BoxMesh.new()
		mesh.size = platform_size
		mesh.material = _make_material(platform_color)
		var visual := MeshInstance3D.new()
		visual.name = "PlatformVisual"
		visual.mesh = mesh
		add_child(visual)


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.5
	return material
