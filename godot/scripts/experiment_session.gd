extends Node

signal event_recorded(event: Dictionary)
signal session_reset(metadata: Dictionary)

const SCHEMA_VERSION := 2
const VALID_CONDITIONS: Array[String] = ["unassigned", "active", "passive"]
const VALID_ACTIVITY_MODES: Array[String] = ["none", "gameplay", "quiz", "scaffold"]

var session_id: String = ""
var intervention_condition: String = "unassigned"
var events: Array[Dictionary] = []
var _started_ticks_msec: int = 0
var _level_times: Dictionary = {}


func _ready() -> void:
	reset_session(_web_condition())


func _web_condition() -> String:
	if not OS.has_feature("web"):
		return "unassigned"
	var value := String(JavaScriptBridge.eval("(window.GodotExperimentBridge&&window.GodotExperimentBridge.getAssignment().condition)||''"))
	return value if VALID_CONDITIONS.has(value) else "unassigned"


func reset_session(condition: String = "unassigned") -> void:
	intervention_condition = condition if VALID_CONDITIONS.has(condition) else "unassigned"
	_started_ticks_msec = Time.get_ticks_msec()
	# This identifier is generated locally and contains no student information.
	session_id = "%x-%08x" % [Time.get_unix_time_from_system(), randi()]
	events.clear()
	_level_times.clear()
	var metadata := get_metadata()
	session_reset.emit(metadata)
	record_event("session_started", "campaign", metadata)


func set_intervention_condition(condition: String) -> bool:
	if not VALID_CONDITIONS.has(condition):
		return false
	intervention_condition = condition
	record_event("condition_assigned", "campaign", {"condition": condition})
	return true


func record_event(event_name: String, level_id: String, payload: Dictionary = {}) -> Dictionary:
	var event := {
		"schema_version": SCHEMA_VERSION,
		"session_id": session_id,
		"condition": intervention_condition,
		"event_name": event_name,
		"level_id": level_id,
		"elapsed_msec": maxi(0, Time.get_ticks_msec() - _started_ticks_msec),
		"payload": payload.duplicate(true),
	}
	events.append(event)
	event_recorded.emit(event.duplicate(true))
	return event


func get_metadata() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"session_id": session_id,
		"condition": intervention_condition,
	}


func get_snapshot() -> Dictionary:
	return {
		"metadata": get_metadata(),
		"events": events.duplicate(true),
	}


func reset_level_time(level_id: String) -> void:
	_level_times[level_id] = _new_level_time()


func set_activity_mode(level_id: String, mode: String) -> void:
	if not VALID_ACTIVITY_MODES.has(mode):
		return
	if not _level_times.has(level_id):
		_level_times[level_id] = _new_level_time()
	_flush_level_time(level_id)
	_level_times[level_id]["mode"] = mode
	_level_times[level_id]["mode_started_msec"] = Time.get_ticks_msec()


func get_level_time(level_id: String) -> Dictionary:
	if not _level_times.has(level_id):
		return {"gameplay_time": 0.0, "quiz_time": 0.0, "scaffold_time": 0.0}
	_flush_level_time(level_id)
	var timing: Dictionary = _level_times[level_id]
	return {
		"gameplay_time": snappedf(float(timing.gameplay_msec) / 1000.0, 0.001),
		"quiz_time": snappedf(float(timing.quiz_msec) / 1000.0, 0.001),
		"scaffold_time": snappedf(float(timing.scaffold_msec) / 1000.0, 0.001),
	}


func record_level_time_summary(level_id: String, scaffold_version: String = "v1") -> Dictionary:
	var payload := get_level_time(level_id)
	payload["scaffold_version"] = scaffold_version
	return record_event("level_time_summary", level_id, payload)


func _new_level_time() -> Dictionary:
	return {
		"mode": "none",
		"mode_started_msec": Time.get_ticks_msec(),
		"gameplay_msec": 0,
		"quiz_msec": 0,
		"scaffold_msec": 0,
	}


func _flush_level_time(level_id: String) -> void:
	var timing: Dictionary = _level_times[level_id]
	var now := Time.get_ticks_msec()
	var delta := maxi(0, now - int(timing.mode_started_msec))
	match String(timing.mode):
		"gameplay":
			timing.gameplay_msec = int(timing.gameplay_msec) + delta
		"quiz":
			timing.quiz_msec = int(timing.quiz_msec) + delta
		"scaffold":
			timing.scaffold_msec = int(timing.scaffold_msec) + delta
	timing.mode_started_msec = now
	_level_times[level_id] = timing
