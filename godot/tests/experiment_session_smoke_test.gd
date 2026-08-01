extends SceneTree

var failures: Array[String] = []
var test_manager: PartyModeManager


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var experiment := root.get_node_or_null("ExperimentSession")
	_expect(experiment != null, "experiment session autoload exists")
	if experiment == null:
		quit(1)
		return
	experiment.call("reset_session", "active")
	var metadata: Dictionary = experiment.call("get_metadata")
	_expect(metadata.get("condition", "") == "active", "active intervention condition can be assigned")
	_expect(not metadata.has("student_name") and not metadata.has("student_id"), "session metadata contains no student identity")
	_expect(not experiment.call("set_intervention_condition", "invalid"), "unknown intervention conditions are rejected")

	test_manager = PartyModeManager.new()
	test_manager.level_id = "event_test"
	test_manager.level_name = "Event Test"
	test_manager.quiz_slot_count = 1
	root.add_child(test_manager)
	await process_frame
	test_manager.reset_run()
	test_manager.begin_run_now()
	test_manager.register_fall()
	test_manager.register_hazard_hit()
	test_manager.open_quiz(1)
	test_manager.submit_quiz_answer(0, 0)
	test_manager.finish(true)
	await process_frame

	var snapshot: Dictionary = experiment.call("get_snapshot")
	var event_names: Array[String] = []
	for event in snapshot.get("events", []):
		event_names.append(String(event.get("event_name", "")))
	for required_name in [
		"session_started",
		"level_prepared",
		"run_started",
		"player_fell",
		"obstacle_hit",
		"quiz_opened",
		"quiz_answered",
		"run_completed",
	]:
		_expect(event_names.has(required_name), "%s is recorded" % required_name)
	var latest_event: Dictionary = snapshot.get("events", [])[-1]
	_expect(latest_event.get("schema_version", 0) == 1, "events carry a stable schema version")
	_expect(latest_event.has("elapsed_msec") and latest_event.has("payload"), "events contain relative time and payload")
	call_deferred("_finish")


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if is_instance_valid(test_manager):
		test_manager.queue_free()
		await process_frame
		await process_frame
	if failures.is_empty():
		print("EXPERIMENT_SESSION_SMOKE_TEST_OK")
		quit(0)
	else:
		print("EXPERIMENT_SESSION_SMOKE_TEST_FAILED: %s" % ", ".join(failures))
		quit(1)
