class_name SignalCalibrationZone
extends Area3D

signal calibrated(wave_index: int)

@export var wave_index: int = 1
@export var zone_color: Color = Color("62eadb")
@export var radius: float = 2.4

var _active: bool = false
var _completed: bool = false
var _visual_root: Node3D
var _disc: MeshInstance3D
var _core: MeshInstance3D
var _label: Label3D
var _pulse_time: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	monitorable = false
	_build_collision()
	_build_visual()
	body_entered.connect(_on_body_entered)
	reset_zone()


func _process(delta: float) -> void:
	if not _active:
		return
	_pulse_time += delta
	var pulse := 1.0 + sin(_pulse_time * 5.2) * 0.08
	_disc.scale = Vector3(pulse, 1.0, pulse)
	_core.position.y = 1.8 + sin(_pulse_time * 3.8) * 0.22
	_label.modulate.a = 0.84 + sin(_pulse_time * 5.2) * 0.16


func set_active(value: bool) -> void:
	_active = value and not _completed
	monitoring = _active
	set_process(_active)
	if _active:
		_visual_root.visible = true
		_label.modulate = Color.WHITE
		_label.text = "第%d波：进入这里校准" % wave_index
	elif _completed:
		_visual_root.visible = true
		_label.modulate = Color(0.55, 1.0, 0.72, 0.72)
		_label.text = "第%d波 已校准" % wave_index
	else:
		_visual_root.visible = false


func reset_zone() -> void:
	_completed = false
	_pulse_time = 0.0
	if is_node_ready():
		set_active(false)
		_disc.scale = Vector3.ONE


func is_completed() -> bool:
	return _completed


func _on_body_entered(body: Node3D) -> void:
	if not _active or _completed or not body is PlayerController:
		return
	_completed = true
	_active = false
	monitoring = false
	set_process(false)
	_visual_root.visible = true
	_label.modulate = Color(0.55, 1.0, 0.72, 0.78)
	_label.text = "第%d波 已校准" % wave_index
	calibrated.emit(wave_index)


func _build_collision() -> void:
	var collision := CollisionShape3D.new()
	collision.name = "CalibrationCollision"
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 4.5
	collision.shape = shape
	collision.position.y = 2.0
	add_child(collision)


func _build_visual() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "CalibrationVisual"
	add_child(_visual_root)

	_disc = MeshInstance3D.new()
	_disc.name = "SignalDisc"
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = radius
	disc_mesh.bottom_radius = radius
	disc_mesh.height = 0.08
	disc_mesh.radial_segments = 48
	disc_mesh.material = _make_material(Color(zone_color, 0.34), zone_color, 1.8, true)
	_disc.mesh = disc_mesh
	_disc.position.y = 0.07
	_visual_root.add_child(_disc)

	var ring := MeshInstance3D.new()
	ring.name = "SignalRing"
	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = radius + 0.18
	ring_mesh.bottom_radius = radius + 0.18
	ring_mesh.height = 0.035
	ring_mesh.radial_segments = 48
	ring_mesh.material = _make_material(Color(zone_color, 0.58), zone_color, 2.4, true)
	ring.mesh = ring_mesh
	ring.position.y = 0.035
	ring.scale = Vector3(1.0, 1.0, 1.0)
	_visual_root.add_child(ring)

	_core = MeshInstance3D.new()
	_core.name = "SignalCore"
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.42
	core_mesh.height = 0.84
	core_mesh.material = _make_material(zone_color, zone_color, 2.8, false)
	_core.mesh = core_mesh
	_core.position.y = 1.8
	_visual_root.add_child(_core)

	var beam := MeshInstance3D.new()
	beam.name = "SignalBeam"
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.10
	beam_mesh.bottom_radius = 0.10
	beam_mesh.height = 3.0
	beam_mesh.radial_segments = 20
	beam_mesh.material = _make_material(Color(zone_color, 0.40), zone_color, 2.0, true)
	beam.mesh = beam_mesh
	beam.position.y = 1.5
	_visual_root.add_child(beam)

	_label = Label3D.new()
	_label.name = "CalibrationLabel"
	_label.text = "第%d波：进入这里校准" % wave_index
	_label.font_size = 52
	_label.outline_size = 10
	_label.modulate = Color("ffffff")
	_label.outline_modulate = Color("17304d")
	_label.position = Vector3(0.0, 3.6, 0.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_visual_root.add_child(_label)


func _make_material(
	albedo: Color,
	emission_color: Color,
	emission_energy: float,
	transparent: bool
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = albedo
	material.emission_enabled = true
	material.emission = emission_color
	material.emission_energy_multiplier = emission_energy
	return material
