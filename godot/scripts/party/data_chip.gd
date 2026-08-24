class_name DataChip
extends Area3D

signal collected(chip_id: int, chip: DataChip)

@export var chip_id: int = 0
@export var visual_scene: PackedScene
@export var visual_scale: Vector3 = Vector3.ONE * 1.45
@export var bob_height: float = 0.22
@export var bob_speed: float = 2.2
@export var spin_speed: float = 2.4

const COLLECT_SOUND := preload("res://assets/audio/interface_sfx_pack_1/cursor_tones/cursor_style_2.ogg")

var is_collected: bool = false
var _base_y: float = 0.0
var _time: float = 0.0
var _visual_root: Node3D
var _collision: CollisionShape3D
var _particles: CPUParticles3D
var _audio: AudioStreamPlayer3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	_build_collision()
	_build_visual()
	_build_feedback()
	_base_y = position.y
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if is_collected:
		return
	_time += delta
	position.y = _base_y + sin(_time * bob_speed + float(chip_id) * 0.47) * bob_height
	_visual_root.rotate_y(delta * spin_speed)


func collect() -> bool:
	if is_collected:
		return false
	is_collected = true
	set_process(false)
	monitoring = false
	_collision.set_deferred("disabled", true)
	_visual_root.visible = false
	_particles.restart()
	_particles.emitting = true
	_audio.play()
	collected.emit(chip_id, self)
	return true


func reset_chip() -> void:
	is_collected = false
	set_process(true)
	_time = 0.0
	position.y = _base_y
	_visual_root.rotation = Vector3.ZERO
	_visual_root.visible = true
	monitoring = true
	_collision.set_deferred("disabled", false)


func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		collect()


func _build_collision() -> void:
	_collision = CollisionShape3D.new()
	_collision.name = "CollectShape"
	var shape := SphereShape3D.new()
	shape.radius = 0.72
	_collision.shape = shape
	add_child(_collision)


func _build_visual() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "ChipVisual"
	add_child(_visual_root)
	if visual_scene:
		var visual := visual_scene.instantiate() as Node3D
		visual.name = "KayKitCoin"
		visual.scale = visual_scale
		_visual_root.add_child(visual)
	else:
		var mesh_instance := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.42
		mesh.bottom_radius = 0.42
		mesh.height = 0.16
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("ffe15c")
		material.emission_enabled = true
		material.emission = Color("ffb83e")
		material.emission_energy_multiplier = 1.5
		mesh.material = material
		mesh_instance.mesh = mesh
		mesh_instance.rotation_degrees.z = 90.0
		_visual_root.add_child(mesh_instance)


func _build_feedback() -> void:
	_particles = CPUParticles3D.new()
	_particles.name = "CollectParticles"
	_particles.amount = 18
	_particles.lifetime = 0.5
	_particles.one_shot = true
	_particles.emitting = false
	_particles.direction = Vector3.UP
	_particles.spread = 145.0
	_particles.initial_velocity_min = 2.8
	_particles.initial_velocity_max = 5.0
	_particles.gravity = Vector3(0.0, -7.5, 0.0)
	var particle_mesh := SphereMesh.new()
	particle_mesh.radius = 0.06
	particle_mesh.height = 0.12
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("fff07a")
	material.emission_enabled = true
	material.emission = Color("48e7da")
	material.emission_energy_multiplier = 2.0
	particle_mesh.material = material
	_particles.mesh = particle_mesh
	add_child(_particles)
	_audio = AudioStreamPlayer3D.new()
	_audio.name = "CollectAudio"
	_audio.stream = COLLECT_SOUND
	_audio.volume_db = -4.0
	_audio.max_distance = 30.0
	add_child(_audio)
