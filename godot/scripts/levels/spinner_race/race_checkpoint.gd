class_name RaceCheckpoint
extends Area3D

signal activated(checkpoint_index, spawn_transform, checkpoint)

const CHECKPOINT_SOUND := preload("res://assets/audio/interface_sfx_pack_1/confirm_tones/style6/confirm_style_6_001.ogg")
const TRIGGER_SIZE := Vector3(11.5, 7.0, 2.6)
const TRIGGER_CENTER_Y := 3.5

@export var checkpoint_index: int = 1
@export var respawn_offset: Vector3 = Vector3(0.0, 0.08, -1.25)

var is_activated: bool = false
var _lamp_material: StandardMaterial3D
var _floor_material: StandardMaterial3D
var _elapsed: float = 0.0
var _activation_audio: AudioStreamPlayer3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	_build_checkpoint()
	_build_audio()
	body_entered.connect(_on_body_entered)
	reset_checkpoint()


func _process(delta: float) -> void:
	_elapsed += delta
	if is_activated or _lamp_material == null:
		return
	var pulse := 0.5 + 0.5 * sin(_elapsed * 5.0)
	_lamp_material.emission_energy_multiplier = lerpf(1.0, 2.0, pulse)
	if _floor_material:
		_floor_material.emission_energy_multiplier = lerpf(0.45, 1.05, pulse)


func get_spawn_transform() -> Transform3D:
	return Transform3D(Basis.IDENTITY, global_position + respawn_offset)


func set_activated() -> void:
	is_activated = true
	set_process(false)
	_set_lamp_color(Color("62f5b4"), 2.0)
	_set_floor_color(Color("62f5b4"), 0.7)
	if _activation_audio:
		_activation_audio.play()


func reset_checkpoint() -> void:
	is_activated = false
	set_process(true)
	_elapsed = 0.0
	_set_lamp_color(Color("ffe06a"), 1.2)
	_set_floor_color(Color("ffe06a"), 0.7)


func _on_body_entered(body: Node3D) -> void:
	if is_activated or not body is CharacterBody3D:
		return
	activated.emit(checkpoint_index, get_spawn_transform(), self)


func _build_checkpoint() -> void:
	var trigger_shape := BoxShape3D.new()
	# The trigger is an invisible gate, not the visible lamp bar. It spans the
	# whole track and the player's complete jump arc so jumping or dashing across
	# the checkpoint cannot bypass the quiz.
	trigger_shape.size = TRIGGER_SIZE
	var trigger_collision := CollisionShape3D.new()
	trigger_collision.name = "CheckpointTriggerShape"
	trigger_collision.shape = trigger_shape
	trigger_collision.position.y = TRIGGER_CENTER_Y
	add_child(trigger_collision)

	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(10.7, 0.035, 1.25)
	_floor_material = _make_transparent_material(Color("ffe06a"), 0.38, 0.7)
	floor_mesh.material = _floor_material
	var floor_strip := MeshInstance3D.new()
	floor_strip.name = "CheckpointFloorStrip"
	floor_strip.mesh = floor_mesh
	floor_strip.position.y = 0.035
	add_child(floor_strip)

	for side in [-1.0, 1.0]:
		var post_mesh := CylinderMesh.new()
		post_mesh.top_radius = 0.16
		post_mesh.bottom_radius = 0.22
		post_mesh.height = 2.6
		post_mesh.material = _make_material(Color("6d62e8"), 0.08)
		var post := MeshInstance3D.new()
		post.mesh = post_mesh
		post.position = Vector3(side * 4.6, 1.3, 0.0)
		add_child(post)

	var lamp_mesh := BoxMesh.new()
	lamp_mesh.size = Vector3(7.9, 0.24, 0.28)
	_lamp_material = _make_material(Color("ffe06a"), 1.2)
	lamp_mesh.material = _lamp_material
	var lamp := MeshInstance3D.new()
	lamp.name = "CheckpointLamp"
	lamp.mesh = lamp_mesh
	lamp.position = Vector3(0.0, 2.45, 0.0)
	add_child(lamp)

	var label := Label3D.new()
	label.text = "知识检查点 %d" % checkpoint_index
	label.font_size = 30
	label.outline_size = 7
	label.modulate = Color("fff6d6")
	label.outline_modulate = Color("39305f")
	label.position = Vector3(0.0, 2.9, 0.0)
	add_child(label)


func _set_lamp_color(color: Color, energy: float) -> void:
	if _lamp_material == null:
		return
	_lamp_material.albedo_color = color
	_lamp_material.emission = color
	_lamp_material.emission_energy_multiplier = energy


func _set_floor_color(color: Color, energy: float) -> void:
	if _floor_material == null:
		return
	_floor_material.albedo_color = Color(color.r, color.g, color.b, 0.38)
	_floor_material.emission = color
	_floor_material.emission_energy_multiplier = energy


func _build_audio() -> void:
	_activation_audio = AudioStreamPlayer3D.new()
	_activation_audio.name = "CheckpointAudio"
	_activation_audio.stream = CHECKPOINT_SOUND
	_activation_audio.volume_db = -3.0
	_activation_audio.max_distance = 30.0
	add_child(_activation_audio)


func _make_material(color: Color, emission_strength: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.48
	if emission_strength > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission_strength
	return material


func _make_transparent_material(color: Color, alpha: float, emission_strength: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.roughness = 0.65
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = emission_strength
	return material
