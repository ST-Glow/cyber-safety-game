extends SceneTree

const TEST_CLEANUP := preload("res://tests/test_cleanup.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var scene := load("res://scenes/digcomp/puzzle.tscn") as PackedScene
	_expect(scene != null, "jigsaw scene loads")
	if scene == null:
		quit(1)
		return
	var puzzle := scene.instantiate()
	root.add_child(puzzle)
	current_scene = puzzle
	await process_frame
	_expect(puzzle.get("puzzle_texture") != null, "source image is configured")
	_expect(int(puzzle.get("pieces").size()) == 9, "default 3x3 difficulty creates nine pieces")
	_expect(puzzle.get("assistant_panel") != null, "AI assistant remains available in the jigsaw level")
	_expect(puzzle.get("task_container") != null, "jigsaw workspace builds")

	var pieces: Array = puzzle.get("pieces")
	var distinct_positions: Dictionary = {}
	var has_tab_or_socket := false
	for piece in pieces:
		distinct_positions[Vector2(piece.position).round()] = true
		for point in PackedVector2Array(piece.get("polygon_points")):
			if point.x < -0.5 or point.y < -0.5 or point.x > float(puzzle.get("cell_size").x) + 0.5 or point.y > float(puzzle.get("cell_size").y) + 0.5:
				has_tab_or_socket = true
	_expect(distinct_positions.size() == 9, "pieces start at distinct scattered positions")
	_expect(has_tab_or_socket, "piece outlines include protruding jigsaw tabs")

	var first_piece = pieces[0]
	first_piece.position = first_piece.target_position + Vector2(4, 3)
	puzzle.set("_dragged_piece", first_piece)
	puzzle.set("_drag_target", first_piece.position)
	puzzle.call("_end_drag")
	_expect(first_piece.locked, "piece snaps and locks only when close to its target")
	_expect(int(puzzle.get("placed_count")) == 1, "successful snap advances completion count")

	var second_piece = pieces[1]
	second_piece.position = second_piece.target_position + Vector2(180, 120)
	puzzle.set("_dragged_piece", second_piece)
	puzzle.set("_drag_target", second_piece.position)
	puzzle.call("_end_drag")
	_expect(not second_piece.locked, "far drop does not count as correctly placed")
	_expect(int(puzzle.get("errors")) == 1, "unsuccessful drop is recorded")
	_expect(not bool(puzzle.get("_completed")), "level cannot complete while pieces remain")

	puzzle.call("start_new_puzzle", 4)
	_expect(int(puzzle.get("pieces").size()) == 16, "4x4 difficulty creates sixteen pieces")
	puzzle.call("start_new_puzzle", 5)
	_expect(int(puzzle.get("pieces").size()) == 25, "5x5 difficulty creates twenty-five pieces")

	TEST_CLEANUP.stop_all_audio(root)
	puzzle.queue_free()
	await process_frame
	await create_timer(0.2, true, false, true).timeout
	if failures.is_empty():
		print("JIGSAW_PUZZLE_SMOKE_TEST_OK")
		quit(0)
	else:
		print("JIGSAW_PUZZLE_SMOKE_TEST_FAILED: %s" % ", ".join(failures))
		quit(1)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		failures.append(label)
		push_error("[FAIL] %s" % label)
