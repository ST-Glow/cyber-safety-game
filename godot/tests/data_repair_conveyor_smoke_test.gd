extends SceneTree

const TEST_CLEANUP := preload("res://tests/test_cleanup.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var scene := load("res://scenes/digcomp/matching.tscn") as PackedScene
	_expect(scene != null, "data repair conveyor scene loads")
	if scene == null:
		quit(1)
		return
	var game := scene.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await process_frame

	_expect(game is DataRepairConveyor, "matching level uses conveyor gameplay instead of static lists")
	_expect(int(game.get("pair_items").size()) == 10, "all ten existing teaching pairs are retained")
	var visual_metadata_complete := true
	for item in game.get("pair_items"):
		visual_metadata_complete = visual_metadata_complete and item.has("problem_icon") and item.has("problem_short") and item.has("solution_icon") and item.has("solution_short")
	_expect(visual_metadata_complete, "all teaching pairs provide compact factory icons and labels")
	_expect(float(game.get("total_time_seconds")) == 90.0, "default time limit is 90 seconds")
	_expect(int(game.get("starting_energy")) == 3, "default energy is three")
	_expect(float(game.get("guide_duration_seconds")) <= 5.0, "quick guide lasts no more than five seconds")
	_expect(game.get("assistant_panel") != null, "AI assistant remains available")
	_expect(game.get("factory_backdrop") != null and game.get("tool_dock") != null, "matching level renders a factory and mechanical tool dock")
	_expect(game.get("freeze_button") != null, "combo freeze reward is available")

	game.call("skip_guide_for_test")
	await process_frame
	await process_frame
	var problems: Array = game.get("active_problems")
	var solutions: Array = game.get("solution_cards")
	_expect(problems.size() >= 1 and problems.size() <= 3, "one to three moving problems are active")
	_expect(solutions.size() <= 4, "no more than four solution cards are shown")
	if not problems.is_empty():
		_expect(problems[0].get("_icon") != null, "moving fault modules are icon-led game objects")
	if not solutions.is_empty():
		_expect(solutions[0].get("_icon") != null, "repair tools are icon-led draggable chips")
	if not solutions.is_empty():
		var touch_card = solutions[0]
		var touch_start := Vector2(touch_card.global_position) + Vector2(20.0, 20.0)
		var touch_down := InputEventScreenTouch.new()
		touch_down.position = touch_start
		touch_down.pressed = true
		touch_card.call("_gui_input", touch_down)
		_expect(bool(touch_card.get("_dragging")), "touch press starts dragging a solution card")
		var touch_drag := InputEventScreenDrag.new()
		touch_drag.position = touch_start + Vector2(18.0, -12.0)
		touch_card.call("_gui_input", touch_drag)
		var touch_up := InputEventScreenTouch.new()
		touch_up.position = touch_drag.position
		touch_up.pressed = false
		touch_card.call("_gui_input", touch_up)
		_expect(not bool(touch_card.get("_dragging")), "touch release ends dragging and uses the same drop path")
	if problems.is_empty():
		_finish(game)
		return

	var moving_problem = problems[0]
	var start_x := float(moving_problem.position.x)
	await create_timer(0.12).timeout
	_expect(float(moving_problem.position.x) > start_x, "problem card continuously moves toward the fault zone")

	var correct_solution = null
	for card in solutions:
		if String(card.get("solution_id")) == String(moving_problem.get("item_id")):
			correct_solution = card
			break
	_expect(correct_solution != null, "active problem always has a draggable repair card")
	if correct_solution != null:
		game.call("_attempt_match", moving_problem, correct_solution)
		await create_timer(1.15).timeout
		_expect(int(game.get("completed_ids").size()) == 1, "correct drag repairs and locks one pair")
		_expect(int(game.get("gameplay_score")) == 10, "first correct match awards ten points")
		_expect(int(game.get("evidence_progress").get("completed_count")) == 1, "repair lights one evidence-chain node")

	problems = game.get("active_problems")
	solutions = game.get("solution_cards")
	if not problems.is_empty():
		var next_problem = problems[0]
		var wrong_solution = null
		for card in solutions:
			if String(card.get("solution_id")) != String(next_problem.get("item_id")):
				wrong_solution = card
				break
		_expect(wrong_solution != null, "solution tray includes comparison choices")
		if wrong_solution != null:
			game.call("_attempt_match", next_problem, wrong_solution)
			await create_timer(0.35).timeout
			_expect(int(game.get("error_count")) == 1, "wrong drag records an error")
			_expect(int(game.get("gameplay_score")) == 5, "wrong drag deducts five points")
			_expect(int(game.get("combo")) == 0, "wrong drag breaks the combo")

	var energy_before := int(game.get("energy"))
	game.call("force_problem_expired_for_test")
	await create_timer(0.35).timeout
	_expect(int(game.get("energy")) == energy_before - 1, "missed problem costs one energy")
	_expect(int(game.call("_combo_multiplier", 2)) == 2 and int(game.call("_combo_multiplier", 4)) == 3, "combo multiplier starts at two correct and caps at three")

	_finish(game)


func _finish(game: Node) -> void:
	TEST_CLEANUP.stop_all_audio(root)
	game.queue_free()
	await process_frame
	await create_timer(0.2, true, false, true).timeout
	if failures.is_empty():
		print("DATA_REPAIR_CONVEYOR_SMOKE_TEST_OK")
		quit(0)
	else:
		print("DATA_REPAIR_CONVEYOR_SMOKE_TEST_FAILED: %s" % ", ".join(failures))
		quit(1)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		failures.append(label)
		push_error("[FAIL] %s" % label)
