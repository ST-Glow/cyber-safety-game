class_name RisingGate
extends AnimatableBody3D

signal hit_player(player, source_position)

@export var period_seconds: float = 3.6
@export var initial_phase: float = 0.0
@export var closed_center_y: float = 1.35
@export var open_center_y: float = 4.75
@export var gate_color: Color = Color("20c8d8")

var _elapsed: float = 0.0
var _lamp_material: StandardMaterial3D
var _warning_band_material: StandardMaterial3D

const HIT_AREA_MARGIN := Vector3(0.28, 0.22, 0.28)


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	_build_gate()
	_apply_phase()


func _physics_process(delta: float) -> void:
	_elapsed += delta
	_apply_phase()


func reset_phase() -> void:
	_elapsed = 0.0
	_apply_phase()


func _apply_phase() -> void:
	var wave := (sin(TAU * _elapsed / period_seconds + initial_phase) + 1.0) * 0.5
	var eased := smoothstep(0.08, 0.92, wave)
	position.y = lerpf(closed_center_y, open_center_y, eased)
	_update_warning_feedback(eased)


func _build_gate() -> void:
	var panel_size := Vector3(3.35, 2.7, 0.72)
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = panel_size
	panel_mesh.material = _make_material(gate_color, 0.15)
	var panel := MeshInstance3D.new()
	panel.mesh = panel_mesh
	add_child(panel)

	_lamp_material = _make_material(Color("ff685f"), 1.6)
	for x_offset in [-1.28, 0.0, 1.28]:
		var lamp_mesh := SphereMesh.new()
		lamp_mesh.radius = 0.13
		lamp_mesh.height = 0.26
		lamp_mesh.material = _lamp_material
		var lamp := MeshInstance3D.new()
		lamp.mesh = lamp_mesh
		lamp.position = Vector3(x_offset, -0.88, -0.39)
		add_child(lamp)

	_warning_band_material = _make_material(Color("ffe36b"), 1.0)
	for side in [-1.0, 1.0]:
		var band_mesh := BoxMesh.new()
		band_mesh.size = Vector3(3.0, 0.13, 0.04)
		band_mesh.material = _warning_band_material
		var band := MeshInstance3D.new()
		band.name = "GateWarningBandFront" if side > 0.0 else "GateWarningBandBack"
		band.mesh = band_mesh
		band.position = Vector3(0.0, 0.72, side * 0.385)
		add_child(band)

	var body_shape := BoxShape3D.new()
	body_shape.size = panel_size
	var body_collision := CollisionShape3D.new()
	body_collision.name = "GateCollision"
	body_collision.shape = body_shape
	add_child(body_collision)

	var hit_area := Area3D.new()
	hit_area.name = "HitArea"
	hit_area.collision_layer = 0
	hit_area.collision_mask = 1
	var hit_shape := CollisionShape3D.new()
	hit_shape.name = "GateHitCollision"
	var hit_box := BoxShape3D.new()
	hit_box.size = panel_size + HIT_AREA_MARGIN
	hit_shape.shape = hit_box
	hit_area.add_child(hit_shape)
	hit_area.body_entered.connect(_on_body_entered)
	add_child(hit_area)


func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		hit_player.emit(body, global_position)


func _update_warning_feedback(open_ratio: float) -> void:
	var safe_color := Color("63f2b5")
	var danger_color := Color("ff685f")
	var status_color := danger_color.lerp(safe_color, smoothstep(0.45, 0.82, open_ratio))
	if _lamp_material:
		_lamp_material.albedo_color = status_color
		_lamp_material.emission = status_color
		_lamp_material.emission_energy_multiplier = 1.1 + (1.0 - open_ratio) * 1.2
	if _warning_band_material:
		_warning_band_material.emission_energy_multiplier = 0.65 + (1.0 - open_ratio) * 1.25


func _make_material(color: Color, emission_strength: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.46
	if emission_strength > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission_strength
	return material
