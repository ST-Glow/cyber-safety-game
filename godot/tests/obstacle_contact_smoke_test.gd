extends SceneTree

var failures: Array[String] = []
var pusher_hit_count: int = 0
var gate_hit_count: int = 0
var test_root: Node3D


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var player_scene := load("res://scenes/player/player.tscn") as PackedScene
	var pusher_scene := load("res://scenes/obstacles/side_pusher.tscn") as PackedScene
	var gate_scene := load("res://scenes/obstacles/rising_gate.tscn") as PackedScene
	var sweeper_scene := load("res://scenes/obstacles/rotating_sweeper.tscn") as PackedScene
	_expect(player_scene != null and pusher_scene != null and gate_scene != null and sweeper_scene != null, "reusable contact scenes load")
	if player_scene == null or pusher_scene == null or gate_scene == null or sweeper_scene == null:
		call_deferred("_finish")
		return

	test_root = Node3D.new()
	root.add_child(test_root)
	var player := player_scene.instantiate() as PlayerController
	player.fall_height = -100.0
	player.position = Vector3(-50.0, 0.0, 0.0)
	test_root.add_child(player)
	var pusher := pusher_scene.instantiate() as SidePusher
	pusher.movement_offset = Vector3.ZERO
	test_root.add_child(pusher)
	var gate := gate_scene.instantiate() as RisingGate
	gate.position.x = 20.0
	test_root.add_child(gate)
	var sweeper := sweeper_scene.instantiate() as RotatingSweeper
	sweeper.position.x = 40.0
	test_root.add_child(sweeper)
	await process_frame
	await physics_frame

	pusher.hit_player.connect(_on_pusher_hit)
	gate.hit_player.connect(_on_gate_hit)
	var pusher_body_shape := pusher.get_node("PusherCollision").shape as BoxShape3D
	var pusher_hit_shape := pusher.get_node("HitArea/PusherHitCollision").shape as BoxShape3D
	_expect(pusher_hit_shape.size.x > pusher_body_shape.size.x, "pusher hit area extends beyond its solid body")
	_expect(pusher_hit_shape.size.z > pusher_body_shape.size.z, "pusher hit area has contact depth margin")
	_expect(pusher.get_node_or_null("DirectionArrowFront") != null and pusher.get_node_or_null("DirectionArrowBack") != null, "pusher direction warning is visible from both sides")
	_expect(pusher.find_children("WarningBand_*", "MeshInstance3D", false, false).size() == 4, "pusher has pulsing safety bands")
	_expect(sweeper.get_node_or_null("DangerZone") != null, "sweeper shows its full ground danger radius")
	_expect(sweeper.find_children("WarningBeacon*", "MeshInstance3D", false, false).size() == 8, "sweeper danger boundary has warning beacons")

	player.global_position = pusher.global_position
	player.velocity = Vector3.ZERO
	await _wait_physics_frames(3)
	_expect(pusher_hit_count == 1, "pusher emits one hit from a real Area3D contact")

	var gate_body_shape := gate.get_node("GateCollision").shape as BoxShape3D
	var gate_hit_shape := gate.get_node("HitArea/GateHitCollision").shape as BoxShape3D
	_expect(gate_hit_shape.size.x > gate_body_shape.size.x, "gate hit area extends beyond its solid body")
	_expect(gate_hit_shape.size.z > gate_body_shape.size.z, "gate hit area has contact depth margin")
	_expect(gate.get_node_or_null("GateWarningBandFront") != null and gate.get_node_or_null("GateWarningBandBack") != null, "gate status warning is visible from both sides")
	player.global_position = gate.global_position + Vector3(0.0, -1.0, 0.0)
	player.velocity = Vector3.ZERO
	await _wait_physics_frames(3)
	_expect(gate_hit_count == 1, "gate emits one hit from a real Area3D contact")
	call_deferred("_finish")


func _wait_physics_frames(frame_count: int) -> void:
	for _frame in range(frame_count):
		await physics_frame


func _on_pusher_hit(_player: PlayerController, _direction: Vector3) -> void:
	pusher_hit_count += 1


func _on_gate_hit(_player: PlayerController, _source_position: Vector3) -> void:
	gate_hit_count += 1


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if is_instance_valid(test_root):
		test_root.queue_free()
		await process_frame
		await process_frame
	if failures.is_empty():
		print("OBSTACLE_CONTACT_SMOKE_TEST_OK")
		quit(0)
	else:
		print("OBSTACLE_CONTACT_SMOKE_TEST_FAILED: %s" % ", ".join(failures))
		quit(1)
