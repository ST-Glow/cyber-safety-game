extends SceneTree

const TEST_CLEANUP := preload("res://tests/test_cleanup.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var scene := load("res://scenes/digcomp/image_judgment.tscn") as PackedScene
	_expect(scene != null, "digital safety checkpoint scene loads")
	if scene == null:
		quit(1)
		return
	var game := scene.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await create_timer(0.62).timeout
	_expect(String(game.get_script().resource_path) == "res://scripts/digcomp/safety_checkpoint.gd", "image judgment is rebuilt as a safety checkpoint")
	_expect(Array(game.get("case_items")).size() == 10, "all ten existing safety cases are retained")
	_expect(game.get("safe_gate") != null and game.get("risk_gate") != null, "safe and risk gates are spatial drop targets")
	_expect(game.get("risk_meter") != null, "system risk meter is present")
	_expect(game.get("assistant_panel") != null, "AI assistant remains available")
	var option_buttons := 0
	for button_node in game.find_children("", "Button", true, false):
		var text := String((button_node as Button).text)
		if text.contains("安全 / 合适") or text.contains("不安全 / 不合适"):
			option_buttons += 1
	_expect(option_buttons == 0, "legacy binary answer buttons are removed")
	var card := game.get("active_case") as Control
	_expect(card != null and card.get("item_id") == "j01", "first visual case file enters the scanner")
	if card != null:
		var touch_start: Vector2 = Vector2(card.global_position) + card.size * 0.5
		var down := InputEventScreenTouch.new()
		down.position = touch_start
		down.pressed = true
		card.call("_gui_input", down)
		_expect(bool(card.get("_dragging")), "touch press picks up the case file")
		var drag := InputEventScreenDrag.new()
		drag.position = touch_start + Vector2(35, -18)
		card.call("_gui_input", drag)
		var up := InputEventScreenTouch.new()
		up.position = drag.position
		up.pressed = false
		card.call("_gui_input", up)
		await create_timer(0.06).timeout
		_expect(not bool(card.get("_dragging")), "touch release uses the same spatial drop flow")
	var time_before := float(game.get("case_time_left"))
	game.call("scan_current_case_for_test")
	await process_frame
	_expect(bool(game.get("scan_used")), "optional evidence scanner activates once per case")
	_expect(float(game.get("case_time_left")) <= time_before - 1.9, "evidence scan costs two seconds")
	_expect(game.get("evidence_layer").get_child_count() == 3, "evidence scan reveals three compact evidence tags")
	game.call("resolve_current_case_for_test", true)
	await create_timer(1.85).timeout
	_expect(int(game.get("judgment_index")) == 1, "correct gate advances to the next case")
	_expect(int(game.get("gameplay_score")) == 100, "correct review awards one hundred points")
	_expect(int(game.get("combo")) == 1, "correct review starts the combo")
	await create_timer(0.15).timeout
	game.call("resolve_current_case_for_test", false)
	await create_timer(0.12).timeout
	_expect(float(game.get("risk_value")) >= 20.0, "wrong gate raises system risk")
	_expect(int(game.get("combo")) == 0, "wrong gate resets the combo")
	_expect(float(game.call("_case_time_limit", 0)) > float(game.call("_case_time_limit", 8)), "emergency cases have tighter review time")
	_expect(int(game.call("_score_multiplier")) >= 1, "combo score multiplier is available")
	_finish(game)


func _finish(game: Node) -> void:
	TEST_CLEANUP.stop_all_audio(root)
	game.queue_free()
	await process_frame
	await create_timer(0.2, true, false, true).timeout
	if failures.is_empty():
		print("SAFETY_CHECKPOINT_SMOKE_TEST_OK")
		quit(0)
	else:
		print("SAFETY_CHECKPOINT_SMOKE_TEST_FAILED: %s" % ", ".join(failures))
		quit(1)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		failures.append(label)
		push_error("[FAIL] %s" % label)
