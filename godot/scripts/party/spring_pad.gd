class_name PartySpringPad
extends Area3D

signal bounced(player: PlayerController)

@export var visual_scene: PackedScene
@export var bounce_velocity: float = 15.5
@export var retrigger_delay: float = 0.35

const BOUNCE_SOUND := preload("res://assets/audio/kenney_ui_pack/tap-b.ogg")

var _cooldown_left: float = 0.0
var _visual_root: Node3D
var _audio: AudioStreamPlayer3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	_build_collision()
	_build_visual()
	_audio = AudioStreamPlayer3D.new()
	_audio.stream = BOUNCE_SOUND
	_audio.volume_db = -4.0
	_audio.max_distance = 30.0
	add_child(_audio)
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.009) * 0.035
	_visual_root.scale = Vector3(pulse, 1.0, pulse)


func reset_pad() -> void:
	_cooldown_left = 0.0
	_visual_root.scale = Vector3.ONE


func _on_body_entered(body: Node3D) -> void:
	if _cooldown_left > 0.0 or not body is PlayerController:
		return
	var bounced_player := body as PlayerController
	_cooldown_left = retrigger_delay
	bounced_player.velocity.y = maxf(bounced_player.velocity.y, bounce_velocity)
	bounced_player.burst_impact_particles()
	_audio.play()
	bounced.emit(bounced_player)


func _build_collision() -> void:
	var collision := CollisionShape3D.new()
	collision.name = "BounceShape"
	var shape := CylinderShape3D.new()
	shape.radius = 1.35
	shape.height = 0.45
	collision.shape = shape
	collision.position.y = 0.25
	add_child(collision)


func _build_visual() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "SpringPadVisual"
	add_child(_visual_root)
	if visual_scene:
		var visual := visual_scene.instantiate() as Node3D
		visual.name = "KayKitSpringPad"
		visual.scale = Vector3.ONE * 1.25
		_visual_root.add_child(visual)
