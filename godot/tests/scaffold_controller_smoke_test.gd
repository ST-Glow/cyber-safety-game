extends SceneTree

const CONTROLLER_SCRIPT := preload("res://scripts/scaffolding/scaffold_controller.gd")
const CONFIG_SCRIPT := preload("res://scripts/scaffolding/scaffold_config.gd")

class MockPanel:
	extends Node
	signal reminder_decided(choice: String)
	signal open_changed(open: bool)
	signal manual_opened
	var invitation_visible := false
	var last_context: Dictionary = {}

	func is_available() -> bool:
		return true

	func is_invitation_visible() -> bool:
		return invitation_visible

	func show_help_offer(context: Dictionary = {}) -> bool:
		invitation_visible = true
		last_context = context.duplicate(true)
		return true

	func hide_help_offer() -> void:
		invitation_visible = false

var failures: Array[String] = []
var controller
var panel: MockPanel
var safe := false
var state := {"current_checkpoint": "cp1", "current_area": "area1"}


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var experiment := root.get_node("ExperimentSession")
	panel = MockPanel.new()
	root.add_child(panel)
	controller = CONTROLLER_SCRIPT.new()
	root.add_child(controller)
	var config = CONFIG_SCRIPT.new()
	config.grace_period_seconds = 0.0
	config.proactive_idle_threshold = 0.01
	config.proactive_no_progress_threshold = 0.02
	config.cooldown_seconds = 0.01
	config.remind_later_seconds = 0.01
	config.safe_window_seconds = 1.0
	config.reactive_failure_threshold = 2
	config.reactive_quiz_error_threshold = 2
	config.max_scaffolds_per_level = 2
	controller.configure("test_level", "lesson", "objective", _state_provider, _safe_provider, panel, config)

	experiment.reset_session("passive")
	controller.begin_run()
	controller.notify_basic_operation({"action": "move"})
	safe = true
	controller.mark_safe_window()
	await create_timer(0.03).timeout
	_expect(not panel.invitation_visible, "passive records eligibility without automatic invitation")

	controller.reset_level()
	experiment.reset_session("active")
	controller.begin_run()
	controller.notify_basic_operation({"action": "move"})
	safe = false
	await create_timer(0.03).timeout
	_expect(not panel.invitation_visible, "unsafe period queues proactive invitation")
	safe = true
	controller.mark_safe_window()
	await process_frame
	_expect(panel.invitation_visible and panel.last_context.trigger_reason in ["idle", "no_progress"], "safe window shows queued proactive invitation")
	panel.reminder_decided.emit("accepted")
	panel.invitation_visible = false
	panel.open_changed.emit(true)
	_expect(paused == false, "controller itself does not pause before level pause callback")
	panel.open_changed.emit(false)
	controller.notify_activity({"action": "move_after_hint"})

	controller.reset_level()
	experiment.reset_session("active")
	controller.begin_run()
	controller.notify_basic_operation({"action": "move"})
	safe = false
	controller.notify_failure("repeated_failure", {"area": "area1"})
	controller.notify_failure("repeated_failure", {"area": "area1"})
	_expect(not panel.invitation_visible, "reactive threshold waits for safe window")
	safe = true
	controller.mark_safe_window()
	await process_frame
	_expect(panel.invitation_visible and panel.last_context.trigger_reason == "repeated_failure", "reactive failures show invitation at safe window")
	panel.reminder_decided.emit("dismissed")
	panel.invitation_visible = false

	controller.reset_level()
	experiment.reset_session("active")
	controller.begin_run()
	controller.notify_basic_operation({"action": "move"})
	controller.notify_failure("repeated_failure", {"area": "area1", "kind": "same_jump"})
	controller.notify_failure("repeated_failure", {"area": "area1", "kind": "same_jump"})
	safe = true
	controller.mark_safe_window()
	await process_frame
	_expect(panel.invitation_visible and panel.last_context.trigger_reason == "repeated_strategy", "same failing strategy is classified separately")
	panel.reminder_decided.emit("rejected")
	panel.invitation_visible = false

	controller.reset_level()
	experiment.reset_session("active")
	controller.begin_run()
	controller.notify_basic_operation({"action": "move"})
	controller.notify_quiz_started()
	controller.notify_quiz_result(false, {"slot": 1})
	controller.notify_quiz_result(false, {"slot": 1})
	controller.notify_quiz_ended()
	await process_frame
	_expect(panel.invitation_visible and panel.last_context.trigger_reason == "quiz_error", "repeated quiz errors use the quiz_error reason")
	panel.reminder_decided.emit("dismissed")
	panel.invitation_visible = false

	var names: Array[String] = []
	for event in experiment.get_snapshot().events:
		names.append(String(event.event_name))
	for required in ["scaffold_eligible", "scaffold_triggered", "scaffold_invitation_shown", "scaffold_dismissed"]:
		_expect(names.has(required), "%s event is recorded" % required)
	call_deferred("_finish")


func _state_provider() -> Dictionary:
	return state.duplicate(true)


func _safe_provider() -> bool:
	return safe


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	controller.queue_free()
	panel.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("SCAFFOLD_CONTROLLER_SMOKE_TEST_OK")
		quit(0)
	else:
		print("SCAFFOLD_CONTROLLER_SMOKE_TEST_FAILED: %s" % ", ".join(failures))
		quit(1)
