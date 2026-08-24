class_name SidePusher
extends AnimatableBody3D

signal hit_player(player, push_direction)

@export var movement_offset: Vector3 = Vector3(9.0, 0.0, 0.0)
@export var period_seconds: float = 3.4
@export var initial_phase: float = 0.0
@export var pusher_size: Vector3 = Vector3(2.4, 2.3, 0.9)
@export var pusher_color: Color = Color("ff7468")

const HIT_AREA_MARGIN := Vector3(0.34, 0.22, 0.34)

var _origin_position := Vector3.ZERO
var _elapsed: float = 0.0
var _push_direction := Vector3.RIGHT
var _warning_material: StandardMaterial3D


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	sync_to_physics = true
	_origin_position = position
	_build_pusher()
	_apply_phase()
	_update_warning_feedback()


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
	var direction_sign := signf(sin(phase))
	if absf(direction_sign) > 0.1:
		_push_direction = movement_offset.normalized() * direction_sign


func _build_pusher() -> void:
	var shape := BoxShape3D.new()
	shape.size = pusher_size
	var collision := CollisionShape3D.new()
	collision.name = "PusherCollision"
	collision.shape = shape
	add_child(collision)

	var mesh := BoxMesh.new()
	mesh.size = pusher_size
	mesh.material = _make_material(pusher_color, 0.12)
	var visual := MeshInstance3D.new()
	visual.name = "PusherVisual"
	visual.mesh = mesh
	add_child(visual)

	_warning_material = _make_material(Color("ffe36b"), 1.1)
	for face_sign in [-1.0, 1.0]:
		var arrow := Label3D.new()
		arrow.name = "DirectionArrowFront" if face_sign > 0.0 else "DirectionArrowBack"
		arrow.text = "↔"
		arrow.font_size = 72
		arrow.outline_size = 10
		arrow.modulate = Color("fff1a8")
		arrow.outline_modulate = Color("8d3653")
		arrow.position = Vector3(0.0, 0.0, face_sign * pusher_size.z * 0.515)
		arrow.rotation_degrees.y = 180.0 if face_sign < 0.0 else 0.0
		add_child(arrow)
		for band_index in [-1, 1]:
			var band_mesh := BoxMesh.new()
			band_mesh.size = Vector3(pusher_size.x * 0.92, 0.12, 0.035)
			band_mesh.material = _warning_material
			var band := MeshInstance3D.new()
			band.name = "WarningBand_%s_%s" % ["Front" if face_sign > 0.0 else "Back", band_index]
			band.mesh = band_mesh
			band.position = Vector3(0.0, float(band_index) * pusher_size.y * 0.36, face_sign * pusher_size.z * 0.52)
			add_child(band)

	var hit_area := Area3D.new()
	hit_area.name = "HitArea"
	hit_area.collision_layer = 0
	hit_area.collision_mask = 1
	var hit_collision := CollisionShape3D.new()
	hit_collision.name = "PusherHitCollision"
	var hit_shape := BoxShape3D.new()
	hit_shape.size = pusher_size + HIT_AREA_MARGIN
	hit_collision.shape = hit_shape
	hit_area.add_child(hit_collision)
	hit_area.body_entered.connect(_on_body_entered)
	add_child(hit_area)


func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		hit_player.emit(body, _push_direction)


func _update_warning_feedback() -> void:
	if _warning_material == null:
		return
	var phase := TAU * _elapsed / maxf(period_seconds, 0.1) + initial_phase
	_warning_material.emission_energy_multiplier = 0.75 + absf(sin(phase)) * 1.25


func _make_material(color: Color, emission_strength: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.46
	if emission_strength > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission_strength
	return material
