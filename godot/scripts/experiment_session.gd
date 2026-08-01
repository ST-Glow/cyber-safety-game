extends Node

signal event_recorded(event: Dictionary)
signal session_reset(metadata: Dictionary)

const SCHEMA_VERSION := 1
const VALID_CONDITIONS: Array[String] = ["unassigned", "control", "active", "passive"]

var session_id: String = ""
var intervention_condition: String = "unassigned"
var events: Array[Dictionary] = []
var _started_ticks_msec: int = 0


func _ready() -> void:
	reset_session()


func reset_session(condition: String = "unassigned") -> void:
	intervention_condition = condition if VALID_CONDITIONS.has(condition) else "unassigned"
	_started_ticks_msec = Time.get_ticks_msec()
	# This identifier is generated locally and contains no student information.
	session_id = "%x-%08x" % [Time.get_unix_time_from_system(), randi()]
	events.clear()
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
