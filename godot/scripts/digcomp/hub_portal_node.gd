class_name HubPortalNode
extends Area3D

const UI_FONT: FontFile = preload("res://assets/ui/fonts/noto_sans_sc_ui_600.ttf")

var level_id: String = ""
var title_text: String = ""
var short_text: String = ""
var accent: Color = Color("4ec9ff")
var completed: bool = false
var icon_kind: int = 0
var near_player: bool = false
var _near_amount: float = 0.0
var _elapsed: float = 0.0
var _visual_root: Node3D
var _icon_root: Node3D
var _outer_ring: MeshInstance3D
var _inner_ring: MeshInstance3D
var _beam_material: StandardMaterial3D
var _glow_materials: Array[StandardMaterial3D] = []
var _label: Label3D
var _particles: CPUParticles3D


func configure(id_value: String, title_value: String, description_value: String, color_value: Color, kind_value: int, is_completed: bool) -> void:
	level_id = id_value
	title_text = title_value
	short_text = description_value
	accent = color_value
	icon_kind = kind_value
	completed = is_completed
	_build_portal()


func _process(delta: float) -> void:
	_elapsed += minf(delta, 0.05)
	_near_amount = move_toward(_near_amount, 1.0 if near_player else 0.0, delta * 3.2)
	if _outer_ring:
		_outer_ring.rotate_y(delta * (0.50 + _near_amount * 0.65))
	if _inner_ring:
		_inner_ring.rotate_y(-delta * (0.78 + _near_amount * 0.8))
	if _icon_root:
		_icon_root.position.y = 2.35 + sin(_elapsed * 1.7) * (0.10 + _near_amount * 0.06)
		_icon_root.scale = Vector3.ONE * (1.0 + _near_amount * 0.18)
	var energy := (1.2 if completed else 0.72) + _near_amount * 1.25 + sin(_elapsed * 2.4) * 0.08
	for material in _glow_materials:
		material.emission_energy_multiplier = energy
	if _beam_material:
		_beam_material.albedo_color.a = 0.07 + _near_amount * 0.13 + (0.06 if completed else 0.0)
	if _particles:
		_particles.amount = 28 if near_player else (20 if completed else 12)


func set_player_near(value: bool) -> void:
	near_player = value
	if _label:
		_label.modulate = accent.lightened(0.35 if value else 0.18)


func _build_portal() -> void:
	monitoring = true
	monitorable = true
	collision_layer = 0
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 3.05
	cylinder.height = 3.0
	shape.shape = cylinder
	shape.position.y = 1.5
	add_child(shape)
	_visual_root = Node3D.new()
	_visual_root.name = "PortalVisual"
	add_child(_visual_root)
	_add_cylinder(Vector3(4.8, 0.38, 4.8), Vector3(0, 0.18, 0), accent.darkened(0.58), 0.12, "PlatformBase")
	_add_cylinder(Vector3(4.1, 0.18, 4.1), Vector3(0, 0.42, 0), accent.darkened(0.22), 0.65, "EnergyDeck")
	_outer_ring = _add_torus(2.25, 0.10, Vector3(0, 0.58, 0), accent, "OuterRing")
	_inner_ring = _add_torus(1.55, 0.075, Vector3(0, 0.66, 0), accent.lightened(0.2), "InnerRing")
	for pylon_index in range(3):
		var angle := -PI * 0.5 + float(pylon_index - 1) * 0.72
		var pylon_pos := Vector3(cos(angle) * 1.75, 0.95, sin(angle) * 1.75)
		_add_cylinder(Vector3(0.22, 1.9, 0.22), pylon_pos, accent, 0.85, "Pylon%d" % pylon_index)
		_add_sphere(0.24, pylon_pos + Vector3.UP * 1.08, accent.lightened(0.28), 1.25, "PylonLight%d" % pylon_index)
	var beam := MeshInstance3D.new()
	beam.name = "EnergyColumn"
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 1.18
	beam_mesh.bottom_radius = 1.48
	beam_mesh.height = 4.2
	beam_mesh.radial_segments = 32
	_beam_material = StandardMaterial3D.new()
	_beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_material.albedo_color = Color(accent.r, accent.g, accent.b, 0.08)
	_beam_material.emission_enabled = true
	_beam_material.emission = accent
	_beam_material.emission_energy_multiplier = 0.45
	beam_mesh.material = _beam_material
	beam.mesh = beam_mesh
	beam.position.y = 2.55
	_visual_root.add_child(beam)
	_icon_root = Node3D.new()
	_icon_root.name = "TaskIcon"
	_visual_root.add_child(_icon_root)
	_build_icon()
	_label = Label3D.new()
	_label.name = "PortalLabel"
	_label.text = "%02d  %s\n%s" % [icon_kind + 1, title_text, "已完成" if completed else "靠近查看"]
	_label.font = UI_FONT
	_label.font_size = 40
	_label.outline_size = 8
	_label.modulate = accent.lightened(0.2)
	_label.position = Vector3(0, 4.35, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_visual_root.add_child(_label)
	_build_particles()


func _build_icon() -> void:
	match icon_kind:
		0:
			_add_icon_torus(0.48, 0.10, Vector3(-0.08, 0.08, 0), accent)
			_add_icon_box(Vector3(0.15, 0.75, 0.15), Vector3(0.45, -0.38, 0), accent, Vector3(0, 0, -42))
		1:
			for index in range(4):
				var x := -0.34 if index % 2 == 0 else 0.34
				var y := 0.32 if index < 2 else -0.32
				_add_icon_box(Vector3(0.58, 0.58, 0.22), Vector3(x, y, 0), accent.lightened(0.06 * index))
		2:
			for index in range(3):
				var height := 0.52 + index * 0.30
				_add_icon_box(Vector3(0.32, height, 0.26), Vector3((index - 1) * 0.48, -0.42 + height * 0.5, 0), accent.lightened(0.06 * index))
		3:
			_add_icon_torus(0.62, 0.10, Vector3.ZERO, accent)
			_add_icon_box(Vector3(0.18, 0.86, 0.18), Vector3.ZERO, accent.lightened(0.3), Vector3(0, 0, 45))
			_add_icon_box(Vector3(0.18, 0.86, 0.18), Vector3.ZERO, accent.lightened(0.3), Vector3(0, 0, -45))


func _build_particles() -> void:
	_particles = CPUParticles3D.new()
	_particles.name = "PortalParticles"
	_particles.amount = 12
	_particles.lifetime = 2.4
	_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_particles.emission_ring_radius = 1.9
	_particles.emission_ring_inner_radius = 0.8
	_particles.direction = Vector3.UP
	_particles.spread = 22.0
	_particles.initial_velocity_min = 0.45
	_particles.initial_velocity_max = 1.4
	_particles.gravity = Vector3.ZERO
	var mesh := SphereMesh.new()
	mesh.radius = 0.045
	mesh.height = 0.09
	mesh.material = _material(accent.lightened(0.24), 1.5)
	_particles.mesh = mesh
	_particles.position.y = 0.55
	_visual_root.add_child(_particles)


func _add_cylinder(size_value: Vector3, position_value: Vector3, color: Color, emission: float, name_value: String) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = size_value.x * 0.5
	mesh.bottom_radius = size_value.z * 0.5
	mesh.height = size_value.y
	mesh.radial_segments = 32
	var material := _material(color, emission)
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = name_value
	node.mesh = mesh
	node.position = position_value
	_visual_root.add_child(node)
	return node


func _add_sphere(radius: float, position_value: Vector3, color: Color, emission: float, name_value: String) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var material := _material(color, emission)
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = name_value
	node.mesh = mesh
	node.position = position_value
	_visual_root.add_child(node)
	return node


func _add_torus(radius: float, thickness: float, position_value: Vector3, color: Color, name_value: String) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = maxf(0.05, radius - thickness)
	mesh.outer_radius = radius
	mesh.rings = 24
	mesh.ring_segments = 48
	mesh.material = _material(color, 0.9)
	var node := MeshInstance3D.new()
	node.name = name_value
	node.mesh = mesh
	node.position = position_value
	_visual_root.add_child(node)
	return node


func _add_icon_torus(radius: float, thickness: float, position_value: Vector3, color: Color) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - thickness
	mesh.outer_radius = radius
	mesh.material = _material(color, 1.35)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = position_value
	node.rotation_degrees.x = 90
	_icon_root.add_child(node)


func _add_icon_box(size_value: Vector3, position_value: Vector3, color: Color, rotation_value: Vector3 = Vector3.ZERO) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size_value
	mesh.material = _material(color, 1.2)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = position_value
	node.rotation_degrees = rotation_value
	_icon_root.add_child(node)


func _material(color: Color, emission: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.34
	material.emission_enabled = emission > 0.0
	material.emission = color
	material.emission_energy_multiplier = emission
	_glow_materials.append(material)
	return material
