extends Node

signal pause_state_changed(paused: bool, reasons: Array[StringName])

var _next_token: int = 1
var _requests: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	_apply_pause_state()


func _process(_delta: float) -> void:
	_cleanup_invalid_owners()
	_apply_pause_state()


func acquire(owner: Object, reason: StringName) -> int:
	if owner == null or not is_instance_valid(owner):
		push_warning("Pause request ignored because its owner is invalid")
		return 0
	var token := _next_token
	_next_token += 1
	_requests[token] = {
		"owner": weakref(owner),
		"owner_id": owner.get_instance_id(),
		"reason": reason,
	}
	_apply_pause_state()
	return token


func release(token: int) -> void:
	if token <= 0:
		return
	if _requests.erase(token):
		_apply_pause_state()


func release_owner(owner: Object) -> void:
	if owner == null or not is_instance_valid(owner):
		return
	var owner_id := owner.get_instance_id()
	for token in _requests.keys():
		var request: Dictionary = _requests[token]
		if int(request.get("owner_id", 0)) == owner_id:
			_requests.erase(token)
	_apply_pause_state()


func get_active_request_count() -> int:
	_cleanup_invalid_owners()
	return _requests.size()


func get_active_reasons() -> Array[StringName]:
	_cleanup_invalid_owners()
	var reasons: Array[StringName] = []
	for request in _requests.values():
		var reason := StringName((request as Dictionary).get("reason", &""))
		if not reasons.has(reason):
			reasons.append(reason)
	return reasons


func _cleanup_invalid_owners() -> void:
	for token in _requests.keys():
		var request: Dictionary = _requests[token]
		var owner_ref := request.get("owner") as WeakRef
		if owner_ref == null or owner_ref.get_ref() == null:
			_requests.erase(token)


func _apply_pause_state() -> void:
	if get_tree() == null:
		return
	var should_pause := not _requests.is_empty()
	if get_tree().paused == should_pause:
		return
	get_tree().paused = should_pause
	pause_state_changed.emit(should_pause, get_active_reasons())
