class_name PartyModeManager
extends Node

const RUN_SCORING := preload("res://scripts/run_scoring.gd")
const EXPERIMENT_EVENTS := preload("res://scripts/experiment_event_bridge.gd")

signal countdown_changed(seconds_left: int)
signal run_started
signal time_expired
signal fall_registered(fall_count: int)
signal hazard_hit_registered(hit_count: int)
signal assistance_damage_changed(total: int)
signal quiz_opened(slot: int)
signal quiz_answered(slot: int, selected_index: int, correct: bool, attempt: int)
signal run_finished(result: Dictionary)
signal state_changed(new_state: RunState)

enum RunState {
	COUNTDOWN,
	RUNNING,
	QUIZ,
	FINISHED,
	FAILED,
}

@export var level_id: String = "party_mode"
@export var level_name: String = "派对挑战"
@export var countdown_duration: float = 3.0
@export var time_limit_seconds: float = 60.0
@export var quiz_slot_count: int = 2
@export var fixed_duration_success: bool = false

var state: RunState = RunState.COUNTDOWN
var countdown_left: float = 3.0
var elapsed_seconds: float = 0.0
var time_left: float = 60.0
var falls: int = 0
var hazard_hits: int = 0
var active_quiz_slot: int = 0
var quiz_attempts_by_slot: Array[int] = []
var completed_quiz_slots: Array[bool] = []
var assistant_open: bool = false

var _last_countdown_display: int = -1
var _finish_emitted: bool = false
var _timeout_emitted: bool = false
var _assistant_pause_token: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if assistant_open:
		return
	match state:
		RunState.COUNTDOWN:
			countdown_left = maxf(0.0, countdown_left - delta)
			_emit_countdown_if_changed()
			if countdown_left <= 0.0:
				_begin_running()
		RunState.RUNNING:
			elapsed_seconds = minf(time_limit_seconds, elapsed_seconds + delta)
			time_left = maxf(0.0, time_limit_seconds - elapsed_seconds)
			if time_left <= 0.0 and not _timeout_emitted:
				_timeout_emitted = true
				time_expired.emit()


func reset_run() -> void:
	_release_assistant_pause()
	state = RunState.COUNTDOWN
	countdown_left = countdown_duration
	elapsed_seconds = 0.0
	time_left = time_limit_seconds
	falls = 0
	hazard_hits = 0
	assistant_open = false
	active_quiz_slot = 0
	quiz_attempts_by_slot.clear()
	completed_quiz_slots.clear()
	for _index in range(quiz_slot_count):
		quiz_attempts_by_slot.append(0)
		completed_quiz_slots.append(false)
	_last_countdown_display = -1
	_finish_emitted = false
	_timeout_emitted = false
	state_changed.emit(state)
	_emit_countdown_if_changed()
	EXPERIMENT_EVENTS.record(self, "level_prepared", level_id)


func begin_run_now() -> void:
	if state != RunState.COUNTDOWN:
		return
	countdown_left = 0.0
	_begin_running()


func is_running() -> bool:
	return state == RunState.RUNNING and not assistant_open


func set_assistant_open(value: bool) -> void:
	if state in [RunState.QUIZ, RunState.FINISHED, RunState.FAILED]:
		return
	assistant_open = value
	if value and _assistant_pause_token == 0:
		_assistant_pause_token = get_node("/root/PauseCoordinator").acquire(self, &"assistant")
	elif not value:
		_release_assistant_pause()


func open_quiz(slot: int) -> bool:
	if state != RunState.RUNNING or slot < 1 or slot > quiz_slot_count:
		return false
	if completed_quiz_slots[slot - 1]:
		return false
	state = RunState.QUIZ
	active_quiz_slot = slot
	state_changed.emit(state)
	quiz_opened.emit(slot)
	EXPERIMENT_EVENTS.record(self, "quiz_opened", level_id, {"quiz_slot": slot})
	return true


func submit_quiz_answer(selected_index: int, correct_index: int) -> bool:
	if state != RunState.QUIZ or active_quiz_slot <= 0:
		return false
	var slot := active_quiz_slot
	var slot_index := slot - 1
	quiz_attempts_by_slot[slot_index] += 1
	var correct := selected_index == correct_index
	quiz_answered.emit(slot, selected_index, correct, quiz_attempts_by_slot[slot_index])
	EXPERIMENT_EVENTS.record(self, "quiz_answered", level_id, {
		"quiz_slot": slot,
		"selected_index": selected_index,
		"correct": correct,
		"attempt": quiz_attempts_by_slot[slot_index],
	})
	if correct:
		completed_quiz_slots[slot_index] = true
		active_quiz_slot = 0
		state = RunState.RUNNING
		state_changed.emit(state)
	return correct


func register_fall() -> bool:
	if state != RunState.RUNNING:
		return false
	falls += 1
	fall_registered.emit(falls)
	assistance_damage_changed.emit(falls + hazard_hits)
	EXPERIMENT_EVENTS.record(self, "player_fell", level_id, {"falls": falls})
	return true


func register_hazard_hit() -> bool:
	if state != RunState.RUNNING:
		return false
	hazard_hits += 1
	hazard_hit_registered.emit(hazard_hits)
	assistance_damage_changed.emit(falls + hazard_hits)
	EXPERIMENT_EVENTS.record(self, "obstacle_hit", level_id, {"hazard_hits": hazard_hits})
	return true


func finish(success: bool, extra_result: Dictionary = {}) -> bool:
	if _finish_emitted or state not in [RunState.RUNNING, RunState.QUIZ]:
		return false
	if success and completed_quiz_slots.has(false):
		return false
	_finish_emitted = true
	_release_assistant_pause()
	assistant_open = false
	state = RunState.FINISHED if success else RunState.FAILED
	active_quiz_slot = 0
	state_changed.emit(state)
	var result := get_result(success, extra_result)
	EXPERIMENT_EVENTS.record(self, "run_completed", level_id, result)
	run_finished.emit(result)
	return true


func get_result(success: bool, extra_result: Dictionary = {}) -> Dictionary:
	var score_breakdown := RUN_SCORING.build_score(
		quiz_attempts_by_slot,
		falls,
		hazard_hits,
		elapsed_seconds,
		time_limit_seconds,
		success,
		fixed_duration_success
	)
	var result := {
		"level_id": level_id,
		"level_name": level_name,
		"success": success,
		"elapsed_seconds": snappedf(elapsed_seconds, 0.01),
		"time_left": snappedf(time_left, 0.01),
		"falls": falls,
		"hazard_hits": hazard_hits,
		"quiz_attempts_by_slot": quiz_attempts_by_slot.duplicate(),
		"quiz_attempts": _get_total_quiz_attempts(),
		"score": int(score_breakdown.get("total", 0)),
		"normalized_score": int(score_breakdown.get("total", 0)),
		"score_schema_version": 2,
		"stars": int(score_breakdown.get("stars", 1)),
		"score_breakdown": score_breakdown,
	}
	result.merge(extra_result, true)
	return result


func _begin_running() -> void:
	if state != RunState.COUNTDOWN:
		return
	state = RunState.RUNNING
	countdown_left = 0.0
	_last_countdown_display = 0
	countdown_changed.emit(0)
	state_changed.emit(state)
	run_started.emit()
	EXPERIMENT_EVENTS.record(self, "run_started", level_id)


func _emit_countdown_if_changed() -> void:
	var display_value := ceili(countdown_left)
	if display_value == _last_countdown_display:
		return
	_last_countdown_display = display_value
	countdown_changed.emit(display_value)


func _get_total_quiz_attempts() -> int:
	var total := 0
	for attempt_count in quiz_attempts_by_slot:
		total += attempt_count
	return total


func _release_assistant_pause() -> void:
	if _assistant_pause_token != 0:
		get_node("/root/PauseCoordinator").release(_assistant_pause_token)
		_assistant_pause_token = 0
