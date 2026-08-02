class_name SpinnerRaceManager
extends Node

const RUN_SCORING := preload("res://scripts/run_scoring.gd")
const EXPERIMENT_EVENTS := preload("res://scripts/experiment_event_bridge.gd")

signal countdown_changed(seconds_left)
signal race_started
signal checkpoint_updated(checkpoint_index, spawn_transform)
signal fall_registered(fall_count)
signal obstacle_hit_registered(hit_count)
signal player_respawned(checkpoint_index)
signal checkpoint_quiz_opened(checkpoint_index)
signal quiz_answered(checkpoint_index, selected_index, correct, attempt)
signal race_finished(result)
signal state_changed(new_state)

enum RaceState {
	COUNTDOWN,
	RUNNING,
	QUIZ,
	FINISHED,
	FAILED,
}

@export var countdown_duration: float = 3.0
@export var time_limit_seconds: float = 90.0

var state: RaceState = RaceState.COUNTDOWN
var countdown_left: float = 3.0
var elapsed_seconds: float = 0.0
var time_left: float = 90.0
var falls: int = 0
var obstacle_hits: int = 0
var checkpoint_index: int = 0
var checkpoint_transform := Transform3D.IDENTITY
var active_quiz_checkpoint: int = 0
var quiz_attempts_by_checkpoint: Array[int] = [0, 0, 0, 0]

var _last_countdown_display: int = -1
var _finish_emitted: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	match state:
		RaceState.COUNTDOWN:
			countdown_left = maxf(0.0, countdown_left - delta)
			_emit_countdown_if_changed()
			if countdown_left <= 0.0:
				_begin_running()
		RaceState.RUNNING:
			elapsed_seconds = minf(time_limit_seconds, elapsed_seconds + delta)
			time_left = maxf(0.0, time_limit_seconds - elapsed_seconds)
			if time_left <= 0.0:
				_finish(false)


func reset_race(initial_spawn: Transform3D) -> void:
	state = RaceState.COUNTDOWN
	countdown_left = countdown_duration
	elapsed_seconds = 0.0
	time_left = time_limit_seconds
	falls = 0
	obstacle_hits = 0
	checkpoint_index = 0
	checkpoint_transform = initial_spawn
	active_quiz_checkpoint = 0
	quiz_attempts_by_checkpoint = [0, 0, 0, 0]
	_finish_emitted = false
	_last_countdown_display = -1
	state_changed.emit(state)
	_emit_countdown_if_changed()
	EXPERIMENT_EVENTS.record(self, "level_prepared", "spinner_race")


func begin_race_now() -> void:
	if state != RaceState.COUNTDOWN:
		return
	countdown_left = 0.0
	_begin_running()


func is_running() -> bool:
	return state == RaceState.RUNNING


func open_checkpoint_quiz(new_checkpoint_index: int) -> bool:
	if state != RaceState.RUNNING:
		return false
	# Checkpoints are part of the learning flow, so they must be completed in
	# course order. Accepting any larger index would let a shortcut skip quizzes.
	if new_checkpoint_index != checkpoint_index + 1:
		return false
	if new_checkpoint_index > quiz_attempts_by_checkpoint.size():
		return false
	state = RaceState.QUIZ
	active_quiz_checkpoint = new_checkpoint_index
	state_changed.emit(state)
	checkpoint_quiz_opened.emit(new_checkpoint_index)
	EXPERIMENT_EVENTS.record(self, "quiz_opened", "spinner_race", {"checkpoint_index": new_checkpoint_index})
	return true


func submit_quiz_answer(selected_index: int, correct_index: int) -> bool:
	if state != RaceState.QUIZ or active_quiz_checkpoint <= 0:
		return false
	var checkpoint_slot := active_quiz_checkpoint - 1
	quiz_attempts_by_checkpoint[checkpoint_slot] += 1
	var correct := selected_index == correct_index
	quiz_answered.emit(
		active_quiz_checkpoint,
		selected_index,
		correct,
		quiz_attempts_by_checkpoint[checkpoint_slot]
	)
	EXPERIMENT_EVENTS.record(self, "quiz_answered", "spinner_race", {
		"checkpoint_index": active_quiz_checkpoint,
		"selected_index": selected_index,
		"correct": correct,
		"attempt": quiz_attempts_by_checkpoint[checkpoint_slot],
	})
	if correct:
		state = RaceState.RUNNING
		active_quiz_checkpoint = 0
		state_changed.emit(state)
	return correct


func activate_checkpoint(new_index: int, spawn_transform: Transform3D) -> bool:
	if state != RaceState.RUNNING or new_index != checkpoint_index + 1:
		return false
	checkpoint_index = new_index
	checkpoint_transform = spawn_transform
	checkpoint_updated.emit(checkpoint_index, checkpoint_transform)
	EXPERIMENT_EVENTS.record(self, "checkpoint_completed", "spinner_race", {"checkpoint_index": checkpoint_index})
	return true


func register_fall() -> bool:
	if state != RaceState.RUNNING:
		return false
	falls += 1
	fall_registered.emit(falls)
	EXPERIMENT_EVENTS.record(self, "player_fell", "spinner_race", {"falls": falls})
	return true


func register_obstacle_hit() -> bool:
	if state != RaceState.RUNNING:
		return false
	obstacle_hits += 1
	obstacle_hit_registered.emit(obstacle_hits)
	EXPERIMENT_EVENTS.record(self, "obstacle_hit", "spinner_race", {"obstacle_hits": obstacle_hits})
	return true


func notify_respawn() -> void:
	if state == RaceState.RUNNING:
		player_respawned.emit(checkpoint_index)
		EXPERIMENT_EVENTS.record(self, "player_respawned", "spinner_race", {"checkpoint_index": checkpoint_index})


func try_finish() -> bool:
	if state != RaceState.RUNNING or _finish_emitted:
		return false
	if checkpoint_index != quiz_attempts_by_checkpoint.size():
		return false
	_finish(true)
	return true


func get_result(success: bool) -> Dictionary:
	var score_breakdown := RUN_SCORING.build_score(
		quiz_attempts_by_checkpoint,
		falls,
		obstacle_hits,
		elapsed_seconds,
		time_limit_seconds,
		success
	)
	return {
		"level_id": "spinner_race",
		"level_name": "旋转障碍冲刺",
		"success": success,
		"elapsed_seconds": snappedf(elapsed_seconds, 0.01),
		"time_left": snappedf(time_left, 0.01),
		"falls": falls,
		"obstacle_hits": obstacle_hits,
		"checkpoint_index": checkpoint_index,
		"quiz_attempts_by_checkpoint": quiz_attempts_by_checkpoint.duplicate(),
		"quiz_attempts": _get_total_quiz_attempts(),
		"score": int(score_breakdown.get("total", 0)),
		"normalized_score": int(score_breakdown.get("total", 0)),
		"score_schema_version": 2,
		"stars": int(score_breakdown.get("stars", 1)),
		"score_breakdown": score_breakdown,
	}


func _begin_running() -> void:
	if state != RaceState.COUNTDOWN:
		return
	state = RaceState.RUNNING
	countdown_left = 0.0
	_last_countdown_display = 0
	countdown_changed.emit(0)
	state_changed.emit(state)
	race_started.emit()
	EXPERIMENT_EVENTS.record(self, "run_started", "spinner_race")


func _finish(success: bool) -> void:
	if _finish_emitted:
		return
	_finish_emitted = true
	state = RaceState.FINISHED if success else RaceState.FAILED
	state_changed.emit(state)
	var result := get_result(success)
	EXPERIMENT_EVENTS.record(self, "run_completed", "spinner_race", result)
	race_finished.emit(result)


func _emit_countdown_if_changed() -> void:
	var display_value := ceili(countdown_left)
	if display_value == _last_countdown_display:
		return
	_last_countdown_display = display_value
	countdown_changed.emit(display_value)


func _get_total_quiz_attempts() -> int:
	var total := 0
	for attempt_count in quiz_attempts_by_checkpoint:
		total += attempt_count
	return total
