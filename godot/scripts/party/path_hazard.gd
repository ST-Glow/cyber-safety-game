class_name PathHazard
extends Area3D

signal hit_player(player: PlayerController, source_position: Vector3)

@export var visual_scene: PackedScene
@export var path_start: Vector3 = Vector3(-15.0, 0.85, 0.0)
@export var path_end: Vector3 = Vector3(15.0, 0.85, 0.0)
@export var period_seconds: float = 4.0
@export_range(0.0, 0.999, 0.01) var initial_phase: float = 0.0
@export var radius: float = 0.9
@export var visual_scale: Vector3 = Vector3.ONE

var _elapsed: float = 0.0
var _active: bool = false
var _visual_root: Node3D
var _path_preview: MeshInstance3D
var _path_material: StandardMaterial3D


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	monitoring = false
	_build_collision()
	_build_path_preview()
	_build_visual()
	body_entered.connect(_on_body_entered)
	reset_phase()
	set_active(false)


func _physics_process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	var phase := fposmod(_elapsed / maxf(period_seconds, 0.1) + initial_phase, 1.0)
	position = path_start.lerp(path_end, phase)
	var travel_distance := path_start.distance_to(path_end)
	_visual_root.rotate_x(delta * travel_distance / maxf(radius * period_seconds, 0.2))
	if _path_material:
		var pulse := 0.5 + 0.5 * sin(phase * TAU)
		_path_material.emission_energy_multiplier = lerpf(0.18, 0.48, pulse)


func set_active(value: bool) -> void:
	_active = value
	monitoring = value
	visible = value
	if _path_preview:
		_path_preview.visible = value
	set_physics_process(value)


func reset_phase() -> void:
	_elapsed = 0.0
	position = path_start.lerp(path_end, initial_phase)
	if _visual_root:
		_visual_root.rotation = Vector3.ZERO


func _on_body_entered(body: Node3D) -> void:
	if _active and body is PlayerController:
		hit_player.emit(body as PlayerController, global_position)


func _build_collision() -> void:
	var collision := CollisionShape3D.new()
	collision.name = "HazardShape"
	var shape := SphereShape3D.new()
	shape.radius = radius
	collision.shape = shape
	add_child(collision)


func _build_visual() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "BallVisual"
	add_child(_visual_root)
	if visual_scene:
		var visual := visual_scene.instantiate() as Node3D
		visual.name = "KayKitBall"
		visual.scale = visual_scale
		_visual_root.add_child(visual)
	else:
		var mesh_instance := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = radius
		mesh.height = radius * 2.0
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("ff6f64")
		mesh.material = material
		mesh_instance.mesh = mesh
		_visual_root.add_child(mesh_instance)


func _build_path_preview() -> void:
	var direction := path_end - path_start
	var distance := direction.length()
	if distance < 0.1 or get_parent() == null:
		return
	var strip_mesh := BoxMesh.new()
	strip_mesh.size = Vector3(maxf(radius * 0.5, 0.32), 0.025, distance)
	_path_material = StandardMaterial3D.new()
	_path_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_path_material.albedo_color = Color(0.45, 0.91, 1.0, 0.16)
	_path_material.emission_enabled = true
	_path_material.emission = Color("72e8ff")
	_path_material.emission_energy_multiplier = 0.25
	_path_material.roughness = 0.75
	strip_mesh.material = _path_material
	_path_preview = MeshInstance3D.new()
	_path_preview.name = "PathPreview"
	_path_preview.mesh = strip_mesh
	add_child(_path_preview)
	_path_preview.top_level = true
	_path_preview.global_position = get_parent().to_global((path_start + path_end) * 0.5 + Vector3(0.0, -0.78, 0.0))
	_path_preview.global_rotation.y = atan2(direction.x, direction.z)
