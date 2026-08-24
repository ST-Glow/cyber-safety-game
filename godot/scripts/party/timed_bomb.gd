class_name TimedBomb
extends Node3D

signal exploded(player: PlayerController, source_position: Vector3)

@export var visual_scene: PackedScene
@export var cycle_seconds: float = 12.0
@export var warning_duration: float = 1.2
@export var initial_phase_seconds: float = 0.0
@export var effect_radius: float = 4.0

const EXPLODE_SOUND := preload("res://assets/audio/interface_sfx_pack_1/error_tones/style3/error_style_3_echo_003.ogg")

var _active: bool = false
var _elapsed: float = 0.0
var _previous_phase: float = 0.0
var _area: Area3D
var _visual_root: Node3D
var _warning_disc: MeshInstance3D
var _warning_core: MeshInstance3D
var _warning_label: Label3D
var _particles: CPUParticles3D
var _audio: AudioStreamPlayer3D


func _ready() -> void:
	_build_area()
	_build_visual()
	_build_feedback()
	reset_phase()
	set_active(false)


func _physics_process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	var phase := fposmod(_elapsed + initial_phase_seconds, cycle_seconds)
	if phase < _previous_phase:
		_explode()
	var warning_start := cycle_seconds - warning_duration
	var warning := phase >= warning_start
	_visual_root.visible = warning
	_warning_disc.visible = warning
	_warning_core.visible = warning
	_warning_label.visible = warning
	if warning:
		var ratio := clampf((phase - warning_start) / warning_duration, 0.0, 1.0)
		var pulse := 0.76 + ratio * 0.24 + sin(ratio * 22.0) * 0.035
		_warning_disc.scale = Vector3(pulse, 1.0, pulse)
		_warning_core.scale = Vector3.ONE * lerpf(0.82, 1.28, ratio)
		_warning_label.modulate = Color("fff4b0").lerp(Color("ffffff"), ratio)
		_visual_root.scale = Vector3.ONE * (0.9 + ratio * 0.18)
	_previous_phase = phase


func set_active(value: bool) -> void:
	if value and not _active:
		reset_phase()
	_active = value
	_area.monitoring = value
	set_physics_process(value)
	if not value:
		_visual_root.visible = false
		_warning_disc.visible = false
		_warning_core.visible = false
		_warning_label.visible = false


func reset_phase() -> void:
	_elapsed = 0.0
	_previous_phase = fposmod(initial_phase_seconds, maxf(cycle_seconds, 0.1))
	if _visual_root:
		_visual_root.visible = false
		_visual_root.scale = Vector3.ONE
	if _warning_disc:
		_warning_disc.visible = false
		_warning_disc.scale = Vector3.ONE
	if _warning_core:
		_warning_core.visible = false
		_warning_core.scale = Vector3.ONE
	if _warning_label:
		_warning_label.visible = false


func _explode() -> void:
	_visual_root.visible = false
	_warning_disc.visible = false
	_warning_core.visible = false
	_warning_label.visible = false
	_particles.restart()
	_particles.emitting = true
	_audio.play()
	for body in _area.get_overlapping_bodies():
		if body is PlayerController:
			exploded.emit(body as PlayerController, global_position)


func _build_area() -> void:
	_area = Area3D.new()
	_area.name = "ExplosionArea"
	_area.collision_layer = 2
	_area.collision_mask = 1
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = effect_radius
	collision.shape = shape
	collision.position.y = 0.7
	_area.add_child(collision)
	add_child(_area)


func _build_visual() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "BombVisual"
	_visual_root.position.y = 0.45
	add_child(_visual_root)
	if visual_scene:
		var visual := visual_scene.instantiate() as Node3D
		visual.name = "KayKitBomb"
		visual.scale = Vector3.ONE * 1.3
		_visual_root.add_child(visual)
	_warning_disc = MeshInstance3D.new()
	_warning_disc.name = "WarningDisc"
	var disc := CylinderMesh.new()
	disc.top_radius = effect_radius
	disc.bottom_radius = effect_radius
	disc.height = 0.06
	disc.radial_segments = 48
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.22, 0.16, 0.34)
	material.emission_enabled = true
	material.emission = Color("ff5b4d")
	material.emission_energy_multiplier = 1.2
	disc.material = material
	_warning_disc.mesh = disc
	_warning_disc.position.y = 0.05
	add_child(_warning_disc)

	_warning_core = MeshInstance3D.new()
	_warning_core.name = "WarningCore"
	var core_mesh := CylinderMesh.new()
	core_mesh.top_radius = effect_radius * 0.32
	core_mesh.bottom_radius = effect_radius * 0.32
	core_mesh.height = 0.075
	core_mesh.radial_segments = 32
	var core_material := StandardMaterial3D.new()
	core_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core_material.albedo_color = Color(1.0, 0.83, 0.2, 0.52)
	core_material.emission_enabled = true
	core_material.emission = Color("ffe066")
	core_material.emission_energy_multiplier = 1.8
	core_mesh.material = core_material
	_warning_core.mesh = core_mesh
	_warning_core.position.y = 0.095
	add_child(_warning_core)

	_warning_label = Label3D.new()
	_warning_label.name = "WarningLabel"
	_warning_label.text = "!"
	_warning_label.font_size = 92
	_warning_label.outline_size = 14
	_warning_label.modulate = Color("fff4b0")
	_warning_label.outline_modulate = Color("9a2547")
	_warning_label.position = Vector3(0.0, 2.4, 0.0)
	_warning_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_warning_label)


func _build_feedback() -> void:
	_particles = CPUParticles3D.new()
	_particles.name = "ExplosionParticles"
	_particles.position.y = 0.6
	_particles.amount = 34
	_particles.lifetime = 0.7
	_particles.one_shot = true
	_particles.emitting = false
	_particles.direction = Vector3.UP
	_particles.spread = 180.0
	_particles.initial_velocity_min = 4.0
	_particles.initial_velocity_max = 8.0
	_particles.gravity = Vector3(0.0, -8.0, 0.0)
	var particle_mesh := SphereMesh.new()
	particle_mesh.radius = 0.1
	particle_mesh.height = 0.2
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("ffc34f")
	material.emission_enabled = true
	material.emission = Color("ff594c")
	material.emission_energy_multiplier = 2.3
	particle_mesh.material = material
	_particles.mesh = particle_mesh
	add_child(_particles)
	_audio = AudioStreamPlayer3D.new()
	_audio.stream = EXPLODE_SOUND
	_audio.volume_db = -3.0
	_audio.max_distance = 40.0
	add_child(_audio)
