extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var coordinator := root.get_node_or_null("PauseCoordinator")
	_expect(coordinator != null, "pause coordinator autoload exists")
	if coordinator == null:
		_finish()
		return
	_expect(coordinator.process_mode == Node.PROCESS_MODE_ALWAYS, "pause coordinator always processes")
	_expect(int(coordinator.call("get_active_request_count")) == 0 and not paused, "pause coordinator starts without requests")

	var ready_owner := Node.new()
	ready_owner.name = "ReadyOwner"
	root.add_child(ready_owner)
	var assistant_owner := Node.new()
	assistant_owner.name = "AssistantOwner"
	root.add_child(assistant_owner)
	var ready_token := int(coordinator.call("acquire", ready_owner, &"ready"))
	var assistant_token := int(coordinator.call("acquire", assistant_owner, &"assistant"))
	_expect(ready_token > 0 and assistant_token > ready_token, "pause requests receive unique tokens")
	_expect(paused and int(coordinator.call("get_active_request_count")) == 2, "nested pause requests keep the scene tree paused")
	var reasons: Array = coordinator.call("get_active_reasons")
	_expect(reasons.has(&"ready") and reasons.has(&"assistant"), "pause coordinator exposes active reasons")

	coordinator.call("release", ready_token)
	_expect(paused and int(coordinator.call("get_active_request_count")) == 1, "releasing one nested request preserves remaining pause")
	coordinator.call("release_owner", assistant_owner)
	_expect(not paused and int(coordinator.call("get_active_request_count")) == 0, "releasing an owner clears only its requests")

	var transient_owner := Node.new()
	transient_owner.name = "TransientOwner"
	root.add_child(transient_owner)
	coordinator.call("acquire", transient_owner, &"quiz")
	_expect(paused, "transient owner can acquire a pause request")
	transient_owner.queue_free()
	await process_frame
	await process_frame
	_expect(not paused and int(coordinator.call("get_active_request_count")) == 0, "dead owners are removed through weak references")

	coordinator.call("release", assistant_token)
	ready_owner.queue_free()
	assistant_owner.queue_free()
	await process_frame
	_finish()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("PAUSE_COORDINATOR_SMOKE_TEST_OK")
		quit(0)
	else:
		print("PAUSE_COORDINATOR_SMOKE_TEST_FAILED: %s" % ", ".join(failures))
		quit(1)
