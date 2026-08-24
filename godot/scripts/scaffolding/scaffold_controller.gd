class_name ScaffoldController
extends Node

signal invitation_requested(context: Dictionary)
signal support_requested(context: Dictionary)

const DEFAULT_CONFIG = preload("res://resources/scaffolding/scaffold_v1.tres")
var config = DEFAULT_CONFIG
var level_id: String = ""
var lesson_id: String = ""
var current_objective: String = ""
var state_provider: Callable
var safety_provider: Callable
var assistant_panel: Node

var _run_started_msec: int = 0
var _last_activity_msec: int = 0
var _last_progress_msec: int = 0
var _cooldown_until_msec: int = 0
var _safe_until_msec: int = 0
var _first_basic_operation: bool = false
var _rules_completed: bool = false
var _quiz_active: bool = false
var _quiz_started_msec: int = 0
var _pending: Dictionary = {}
var _active_support: Dictionary = {}
var _previous_trigger_keys: Dictionary = {}
var _eligible_keys: Dictionary = {}
var _recent_failures: Array[Dictionary] = []
var _recent_quiz_results: Array[Dictionary] = []
var _failure_counts: Dictionary = {}
var _strategy_counts: Dictionary = {}
var _strategy_window_started_msec: Dictionary = {}
var _quiz_error_counts: Dictionary = {}
var _best_progress_value: float = 0.0
var _has_progress_value: bool = false
var _last_observed_progress_value: float = 0.0
var _movement_direction: int = 0
var _movement_reversals: int = 0
var _movement_window_started_msec: int = 0
var _repeated_movement_detected: bool = false
var _intervention_count: int = 0
var _sequence: int = 0
var _choice_after_pending: Dictionary = {}
var _running: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func configure(
	value_level_id: String,
	value_lesson_id: String,
	objective: String,
	value_state_provider: Callable,
	value_safety_provider: Callable,
	panel: Node,
	value_config = DEFAULT_CONFIG
) -> void:
	level_id = value_level_id
	lesson_id = value_lesson_id
	current_objective = objective
	state_provider = value_state_provider
	safety_provider = value_safety_provider
	assistant_panel = panel
	config = value_config if value_config != null else DEFAULT_CONFIG
	if assistant_panel:
		if assistant_panel.has_signal("reminder_decided") and not assistant_panel.is_connected("reminder_decided", _on_reminder_decided):
			assistant_panel.connect("reminder_decided", _on_reminder_decided)
		if assistant_panel.has_signal("open_changed") and not assistant_panel.is_connected("open_changed", _on_panel_open_changed):
			assistant_panel.connect("open_changed", _on_panel_open_changed)
		if assistant_panel.has_signal("manual_opened") and not assistant_panel.is_connected("manual_opened", _on_manual_opened):
			assistant_panel.connect("manual_opened", _on_manual_opened)
	reset_level()


func reset_level() -> void:
	if not _active_support.is_empty():
		if assistant_panel and assistant_panel.has_method("close"):
			assistant_panel.call("close")
		if not _active_support.is_empty():
			_record("support_ended", _active_support)
	if _running:
		_set_activity_mode("none")
		var active_experiment := _experiment()
		if active_experiment:
			active_experiment.call("record_level_time_summary", level_id, config.scaffold_version)
	_running = false
	_run_started_msec = 0
	_last_activity_msec = 0
	_last_progress_msec = 0
	_cooldown_until_msec = 0
	_safe_until_msec = 0
	_first_basic_operation = false
	_rules_completed = false
	_quiz_active = false
	_quiz_started_msec = 0
	_pending.clear()
	_active_support.clear()
	_previous_trigger_keys.clear()
	_eligible_keys.clear()
	_recent_failures.clear()
	_recent_quiz_results.clear()
	_failure_counts.clear()
	_strategy_counts.clear()
	_strategy_window_started_msec.clear()
	_quiz_error_counts.clear()
	_best_progress_value = 0.0
	_has_progress_value = false
	_reset_movement_observation()
	_intervention_count = 0
	_sequence = 0
	_choice_after_pending.clear()
	set_process(false)
	var experiment := _experiment()
	if experiment:
		experiment.call("reset_level_time", level_id)


func begin_run() -> void:
	var now := Time.get_ticks_msec()
	_running = true
	_run_started_msec = now
	_last_activity_msec = now
	_last_progress_msec = now
	_rules_completed = true
	set_process(true)
	_set_activity_mode("gameplay")


func end_run() -> void:
	_running = false
	set_process(false)
	_pending.clear()
	if assistant_panel and assistant_panel.has_method("hide_help_offer"):
		assistant_panel.call("hide_help_offer")
	_set_activity_mode("none")
	var experiment := _experiment()
	if experiment:
		experiment.call("record_level_time_summary", level_id, config.scaffold_version)


func notify_basic_operation(choice: Dictionary = {}) -> void:
	_first_basic_operation = true
	notify_activity(choice)


func notify_activity(choice: Dictionary = {}) -> void:
	_last_activity_msec = Time.get_ticks_msec()
	_record_choice_after_if_needed(choice)


func notify_progress(details: Dictionary = {}) -> void:
	_last_progress_msec = Time.get_ticks_msec()
	_last_activity_msec = _last_progress_msec
	_pending.clear()
	_failure_counts.clear()
	_strategy_counts.clear()
	_strategy_window_started_msec.clear()
	_quiz_error_counts.clear()
	_previous_trigger_keys.clear()
	_eligible_keys.clear()
	_reset_movement_observation()
	_record_choice_after_if_needed(details)


func observe_progress_value(value: float, details: Dictionary = {}) -> void:
	if not _has_progress_value:
		_has_progress_value = true
		_best_progress_value = value
		_last_observed_progress_value = value
		_movement_window_started_msec = Time.get_ticks_msec()
		return
	_observe_movement_direction(value)
	if value < _best_progress_value + config.progress_distance_epsilon:
		return
	_best_progress_value = value
	var progress_details := details.duplicate(true)
	progress_details["progress_value"] = value
	notify_progress(progress_details)


func notify_failure(reason: String = "repeated_failure", details: Dictionary = {}) -> void:
	if not _running:
		return
	var failure := details.duplicate(true)
	failure["reason"] = reason
	failure["elapsed_seconds"] = _elapsed_run_seconds()
	_recent_failures.append(failure)
	_trim_history(_recent_failures)
	var key := _location_key(details)
	_failure_counts[key] = int(_failure_counts.get(key, 0)) + 1
	var repeated_strategy := reason == "repeated_strategy"
	var strategy := str(details.get("strategy", details.get("kind", "")))
	if not strategy.is_empty():
		var strategy_key := "%s|%s" % [key, strategy]
		var now := Time.get_ticks_msec()
		var window_start := int(_strategy_window_started_msec.get(strategy_key, now))
		if float(now - window_start) / 1000.0 > config.repeated_strategy_window_seconds:
			_strategy_counts[strategy_key] = 0
			window_start = now
		_strategy_window_started_msec[strategy_key] = window_start
		_strategy_counts[strategy_key] = int(_strategy_counts.get(strategy_key, 0)) + 1
		repeated_strategy = repeated_strategy or int(_strategy_counts[strategy_key]) >= config.reactive_failure_threshold
	if int(_failure_counts[key]) >= config.reactive_failure_threshold:
		_consider_trigger("repeated_strategy" if repeated_strategy else "repeated_failure", "reactive", details)


func notify_quiz_started() -> void:
	_quiz_active = true
	_quiz_started_msec = Time.get_ticks_msec()
	_set_activity_mode("quiz")


func notify_quiz_result(correct: bool, details: Dictionary = {}) -> void:
	var result := details.duplicate(true)
	result["correct"] = correct
	result["elapsed_seconds"] = _elapsed_run_seconds()
	_recent_quiz_results.append(result)
	_trim_history(_recent_quiz_results)
	var key := "quiz:%s" % str(details.get("slot", details.get("checkpoint", "current")))
	if correct:
		_quiz_error_counts.erase(key)
		notify_progress(result)
	else:
		_quiz_error_counts[key] = int(_quiz_error_counts.get(key, 0)) + 1
		if int(_quiz_error_counts[key]) >= config.reactive_quiz_error_threshold:
			_consider_trigger("quiz_error", "reactive", details)


func notify_quiz_ended() -> void:
	_quiz_active = false
	mark_safe_window()
	_set_activity_mode("gameplay")


func mark_safe_window() -> void:
	_safe_until_msec = Time.get_ticks_msec() + int(config.safe_window_seconds * 1000.0)
	_try_show_pending()


func get_ai_context() -> Dictionary:
	var state: Dictionary = state_provider.call() if state_provider.is_valid() else {}
	state["condition"] = _condition()
	state["level_id"] = level_id
	state["lesson_id"] = lesson_id
	state["current_objective"] = current_objective
	state["current_checkpoint"] = str(state.get("current_checkpoint", state.get("checkpoint", "")))
	state["current_area"] = str(state.get("current_area", ""))
	state["recent_failures"] = _recent_failures.duplicate(true)
	state["recent_quiz_results"] = _recent_quiz_results.duplicate(true)
	state["elapsed_without_progress"] = snappedf(_seconds_since(_last_progress_msec), 0.1)
	state["previous_hints"] = _assistant_service().call("get_previous_hints", level_id) if _assistant_service() else []
	state["allowed_hint_level"] = config.max_allowed_hint_level()
	return state


func _process(_delta: float) -> void:
	if not _running or not _active_support.is_empty():
		return
	if not _pending.is_empty():
		_try_show_pending()
		return
	var now := Time.get_ticks_msec()
	if now < _cooldown_until_msec or not _proactive_protection_complete():
		return
	if _quiz_active:
		if _quiz_started_msec > 0 and _seconds_since(_quiz_started_msec) >= config.quiz_hesitation_threshold:
			_consider_trigger("no_progress", "proactive", {"source": "quiz_hesitation"})
		return
	if _seconds_since(_last_activity_msec) >= config.proactive_idle_threshold:
		_consider_trigger("idle", "proactive")
	elif _repeated_movement_detected and _seconds_since(_last_progress_msec) >= config.repeated_movement_window_seconds:
		_consider_trigger("no_progress", "proactive", {"source": "repeated_movement"})
	elif _seconds_since(_last_progress_msec) >= config.proactive_no_progress_threshold:
		_consider_trigger("no_progress", "proactive")


func _consider_trigger(reason: String, family: String, details: Dictionary = {}) -> void:
	var context := _base_event_payload(reason, details)
	context["trigger_family"] = family
	var trigger_key := "%s|%s" % [reason, _location_key(context)]
	if _eligible_keys.has(trigger_key):
		return
	_eligible_keys[trigger_key] = true
	_record("scaffold_eligible", context)
	if _condition() != "active" or _intervention_count >= config.max_scaffolds_per_level:
		return
	if Time.get_ticks_msec() < _cooldown_until_msec or not _pending.is_empty():
		return
	if _previous_trigger_keys.has(trigger_key):
		return
	_previous_trigger_keys[trigger_key] = true
	_sequence += 1
	context["scaffold_id"] = "%s-%d" % [level_id, _sequence]
	context["intervention_index"] = _intervention_count + 1
	context["trigger_key"] = trigger_key
	_pending = context
	_record("scaffold_triggered", context)
	_try_show_pending()


func _try_show_pending() -> void:
	if _pending.is_empty() or assistant_panel == null:
		return
	if not assistant_panel.call("is_available") or assistant_panel.call("is_invitation_visible"):
		return
	if not _is_safe_window():
		return
	if assistant_panel.call("show_help_offer", _pending):
		_record("scaffold_invitation_shown", _pending)
		invitation_requested.emit(_pending.duplicate(true))


func _is_safe_window() -> bool:
	if _quiz_active:
		return false
	if safety_provider.is_valid() and not bool(safety_provider.call()):
		return false
	return Time.get_ticks_msec() <= _safe_until_msec


func _on_reminder_decided(choice: String) -> void:
	if _pending.is_empty():
		return
	var context := _pending.duplicate(true)
	match choice:
		"accepted":
			_intervention_count += 1
			context["intervention_index"] = _intervention_count
			_active_support = context
			_record("scaffold_accepted", context)
			_record("choice_before_scaffold", _with_choice(context, _current_choice()))
			_record("support_started", context)
			_set_activity_mode("scaffold")
			support_requested.emit(context.duplicate(true))
		"rejected":
			_record("scaffold_rejected", context)
			_cooldown_until_msec = Time.get_ticks_msec() + int(config.cooldown_seconds * 1000.0)
		"dismissed":
			_record("scaffold_dismissed", context)
			_cooldown_until_msec = Time.get_ticks_msec() + int(config.remind_later_seconds * 1000.0)
			var trigger_key := str(context.get("trigger_key", ""))
			_previous_trigger_keys.erase(trigger_key)
			_eligible_keys.erase(trigger_key)
	_pending.clear()


func _on_manual_opened() -> void:
	if not _active_support.is_empty():
		return
	_sequence += 1
	_active_support = _base_event_payload("manual")
	_active_support["scaffold_id"] = "%s-manual-%d" % [level_id, _sequence]
	_active_support["intervention_index"] = _intervention_count
	_record("choice_before_scaffold", _with_choice(_active_support, _current_choice()))
	_record("support_started", _active_support)
	_set_activity_mode("scaffold")


func _on_panel_open_changed(open: bool) -> void:
	if open or _active_support.is_empty():
		return
	var ended := _active_support.duplicate(true)
	_record("support_ended", ended)
	_choice_after_pending = ended
	_active_support.clear()
	_cooldown_until_msec = Time.get_ticks_msec() + int(config.cooldown_seconds * 1000.0)
	_set_activity_mode("quiz" if _quiz_active else "gameplay")


func _record_choice_after_if_needed(choice: Dictionary) -> void:
	if _choice_after_pending.is_empty() or choice.is_empty():
		return
	_record("choice_after_scaffold", _with_choice(_choice_after_pending, choice))
	_choice_after_pending.clear()


func _proactive_protection_complete() -> bool:
	return _rules_completed and _first_basic_operation and _seconds_since(_run_started_msec) >= config.grace_period_seconds


func _base_event_payload(reason: String, details: Dictionary = {}) -> Dictionary:
	var state := get_ai_context()
	var payload := {
		"scaffold_id": "",
		"scaffold_level": config.max_allowed_hint_level(),
		"trigger_reason": reason,
		"scaffold_version": config.scaffold_version,
		"current_checkpoint": state.get("current_checkpoint", ""),
		"current_area": state.get("current_area", ""),
		"intervention_index": _intervention_count,
	}
	payload.merge(details, true)
	return payload


func _with_choice(context: Dictionary, choice: Dictionary) -> Dictionary:
	var result := context.duplicate(true)
	result["choice"] = choice.duplicate(true)
	return result


func _current_choice() -> Dictionary:
	var state: Dictionary = state_provider.call() if state_provider.is_valid() else {}
	var choice: Variant = state.get("current_choice", {})
	return choice.duplicate(true) if choice is Dictionary else {"value": str(choice)}


func _location_key(details: Dictionary) -> String:
	var checkpoint := str(details.get("current_checkpoint", details.get("checkpoint", "")))
	var area := str(details.get("current_area", details.get("area", "")))
	if checkpoint.is_empty() and area.is_empty() and state_provider.is_valid():
		var state: Dictionary = state_provider.call()
		checkpoint = str(state.get("current_checkpoint", state.get("checkpoint", "")))
		area = str(state.get("current_area", ""))
	return "%s:%s" % [checkpoint, area]


func _elapsed_run_seconds() -> float:
	return _seconds_since(_run_started_msec)


func _seconds_since(ticks_msec: int) -> float:
	if ticks_msec <= 0:
		return 0.0
	return maxf(0.0, float(Time.get_ticks_msec() - ticks_msec) / 1000.0)


func _trim_history(history: Array[Dictionary]) -> void:
	while history.size() > 8:
		history.pop_front()


func _observe_movement_direction(value: float) -> void:
	var delta := value - _last_observed_progress_value
	if absf(delta) < config.progress_distance_epsilon:
		return
	var now := Time.get_ticks_msec()
	if _movement_window_started_msec <= 0 or float(now - _movement_window_started_msec) / 1000.0 > config.repeated_movement_window_seconds:
		_reset_movement_observation()
		_movement_window_started_msec = now
	var direction := 1 if delta > 0.0 else -1
	if _movement_direction != 0 and direction != _movement_direction:
		_movement_reversals += 1
		_repeated_movement_detected = _movement_reversals >= 2
	_movement_direction = direction
	_last_observed_progress_value = value


func _reset_movement_observation() -> void:
	_last_observed_progress_value = _best_progress_value
	_movement_direction = 0
	_movement_reversals = 0
	_movement_window_started_msec = 0
	_repeated_movement_detected = false


func _condition() -> String:
	var experiment := _experiment()
	return str(experiment.get("intervention_condition")) if experiment else "unassigned"


func _record(event_name: String, payload: Dictionary) -> void:
	var experiment := _experiment()
	if experiment:
		experiment.call("record_event", event_name, level_id, payload)


func _set_activity_mode(mode: String) -> void:
	var experiment := _experiment()
	if experiment:
		experiment.call("set_activity_mode", level_id, mode)


func _experiment() -> Node:
	return get_node_or_null("/root/ExperimentSession")


func _assistant_service() -> Node:
	return get_node_or_null("/root/AiAssistantService")
