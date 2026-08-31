class_name HubCore
extends Node3D

const UI_FONT: FontFile = preload("res://assets/ui/fonts/noto_sans_sc_ui_600.ttf")

var completed_count: int = 0
var _elapsed: float = 0.0
var _core_material: StandardMaterial3D
var _beam_material: StandardMaterial3D
var _rings: Array[MeshInstance3D] = []
var _line_materials: Array[StandardMaterial3D] = []
var _label: Label3D


func configure(portal_positions: Array, completed_value: int) -> void:
	completed_count = completed_value
	_build_core(portal_positions)


func _process(delta: float) -> void:
	_elapsed += minf(delta, 0.05)
	for index in range(_rings.size()):
		_rings[index].rotation.y += delta * (0.38 + index * 0.17) * (-1.0 if index % 2 else 1.0)
		_rings[index].position.y = 2.05 + index * 0.30 + sin(_elapsed * 1.2 + index) * 0.05
	var pulse := 1.0 + sin(_elapsed * 2.1) * 0.10
	if _core_material:
		_core_material.emission_energy_multiplier = (1.05 + completed_count * 0.24) * pulse
	if _beam_material:
		_beam_material.albedo_color.a = 0.08 + completed_count * 0.035 + sin(_elapsed * 1.8) * 0.015


func _build_core(portal_positions: Array) -> void:
	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 2.1
	base_mesh.bottom_radius = 2.35
	base_mesh.height = 0.34
	base_mesh.material = _material(Color("173b55"), 0.25)
	base.mesh = base_mesh
	base.position.y = 0.17
	add_child(base)
	for line_index in range(portal_positions.size()):
		_add_data_line(Vector3.ZERO, Vector3(portal_positions[line_index]), line_index < completed_count)
	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.72
	sphere.height = 1.44
	_core_material = _material(Color("7dfff1"), 1.1)
	sphere.material = _core_material
	core.mesh = sphere
	core.position.y = 2.35
	add_child(core)
	for index in range(3):
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.95 + index * 0.25
		torus.outer_radius = 1.03 + index * 0.25
		torus.material = _material([Color("4ec9ff"), Color("69e38c"), Color("ffca5f")][index], 0.8)
		ring.mesh = torus
		ring.position.y = 2.05 + index * 0.30
		ring.rotation_degrees = Vector3(18 + index * 19, 0, 8 + index * 24)
		add_child(ring)
		_rings.append(ring)
	var beam := MeshInstance3D.new()
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.42
	beam_mesh.bottom_radius = 0.8
	beam_mesh.height = 7.0
	_beam_material = _material(Color("6ff4e8"), 0.65)
	_beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_material.albedo_color.a = 0.08 + completed_count * 0.035
	beam_mesh.material = _beam_material
	beam.mesh = beam_mesh
	beam.position.y = 5.5
	add_child(beam)
	_label = Label3D.new()
	_label.text = "数字能力核心\n%d / 4 已激活" % completed_count
	_label.font = UI_FONT
	_label.font_size = 42
	_label.outline_size = 9
	_label.modulate = Color("bafff8")
	_label.position = Vector3(0, 4.05, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_label)


func _add_data_line(start_value: Vector3, end_value: Vector3, powered: bool) -> void:
	var flat_start := Vector3(start_value.x, 0.06, start_value.z)
	var flat_end := Vector3(end_value.x, 0.06, end_value.z)
	var midpoint := (flat_start + flat_end) * 0.5
	var distance := flat_start.distance_to(flat_end)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.12 if powered else 0.07, 0.035, distance)
	var color := Color("69ead8") if powered else Color("244e65")
	var material := _material(color, 0.85 if powered else 0.15)
	mesh.material = material
	_line_materials.append(material)
	var line := MeshInstance3D.new()
	line.mesh = mesh
	line.position = midpoint
	line.look_at_from_position(midpoint, flat_end, Vector3.UP)
	add_child(line)


func _material(color: Color, emission: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.35
	material.emission_enabled = emission > 0.0
	material.emission = color
	material.emission_energy_multiplier = emission
	return material
