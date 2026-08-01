class_name GameManager
extends Node

const EXPERIMENT_EVENTS := preload("res://scripts/experiment_event_bridge.gd")

signal run_started
signal jump_used
signal dash_used
signal obstacle_hit
signal player_respawned
signal quiz_answered(selected_index, correct, attempt)
signal run_completed(result)
signal state_changed(new_state)

enum GameState {
	READY,
	RUNNING,
	KNOCKBACK,
	QUIZ,
	FINISHED,
}

var state: GameState = GameState.READY
var elapsed_seconds: float = 0.0
var obstacle_hits: int = 0
var falls: int = 0
var quiz_attempts: int = 0
var score: int = 40
var stars: int = 1
var assistant_open: bool = false
var knowledge_score: int = 0
var course_score: int = 25
var time_score: int = 15


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if not assistant_open and state in [GameState.RUNNING, GameState.KNOCKBACK]:
		elapsed_seconds += delta
		_refresh_live_score()


func prepare_run() -> void:
	state = GameState.READY
	elapsed_seconds = 0.0
	obstacle_hits = 0
	falls = 0
	quiz_attempts = 0
	score = 40
	stars = 1
	knowledge_score = 0
	course_score = 25
	time_score = 15
	assistant_open = false
	get_tree().paused = true
	state_changed.emit(state)
	EXPERIMENT_EVENTS.record(self, "level_prepared", "ai_training_ground")


func start_run() -> void:
	if state != GameState.READY:
		return
	state = GameState.RUNNING
	get_tree().paused = false
	state_changed.emit(state)
	run_started.emit()
	EXPERIMENT_EVENTS.record(self, "run_started", "ai_training_ground")


func can_control_player() -> bool:
	return state == GameState.RUNNING and not assistant_open


func notify_jump() -> void:
	if state == GameState.RUNNING:
		jump_used.emit()
		EXPERIMENT_EVENTS.record(self, "jump_used", "ai_training_ground")


func notify_dash() -> void:
	if state == GameState.RUNNING:
		dash_used.emit()
		EXPERIMENT_EVENTS.record(self, "dash_used", "ai_training_ground")


func register_obstacle_hit() -> bool:
	if state != GameState.RUNNING:
		return false
	state = GameState.KNOCKBACK
	obstacle_hits += 1
	_refresh_live_score()
	state_changed.emit(state)
	obstacle_hit.emit()
	EXPERIMENT_EVENTS.record(self, "obstacle_hit", "ai_training_ground", {"obstacle_hits": obstacle_hits})
	return true


func register_fall() -> bool:
	if state != GameState.RUNNING:
		return false
	state = GameState.KNOCKBACK
	obstacle_hits += 1
	falls += 1
	_refresh_live_score()
	state_changed.emit(state)
	obstacle_hit.emit()
	EXPERIMENT_EVENTS.record(self, "player_fell", "ai_training_ground", {
		"falls": falls,
		"obstacle_hits": obstacle_hits,
	})
	return true


func finish_respawn() -> void:
	if state != GameState.KNOCKBACK:
		return
	state = GameState.RUNNING
	state_changed.emit(state)
	player_respawned.emit()
	EXPERIMENT_EVENTS.record(self, "player_respawned", "ai_training_ground", {"falls": falls})


func open_quiz() -> bool:
	if state != GameState.RUNNING:
		return false
	state = GameState.QUIZ
	get_tree().paused = true
	state_changed.emit(state)
	EXPERIMENT_EVENTS.record(self, "quiz_opened", "ai_training_ground", {"quiz_slot": 1})
	return true


func submit_quiz_answer(selected_index: int, correct_index: int) -> bool:
	if state != GameState.QUIZ:
		return false
	quiz_attempts += 1
	var correct := selected_index == correct_index
	quiz_answered.emit(selected_index, correct, quiz_attempts)
	EXPERIMENT_EVENTS.record(self, "quiz_answered", "ai_training_ground", {
		"quiz_slot": 1,
		"selected_index": selected_index,
		"correct": correct,
		"attempt": quiz_attempts,
	})
	if correct:
		_finish_run()
	return correct


func set_assistant_open(value: bool) -> void:
	if state in [GameState.QUIZ, GameState.FINISHED]:
		return
	assistant_open = value
	get_tree().paused = value or state == GameState.READY


func restart_to_ready() -> void:
	get_tree().paused = false
	prepare_run()


func get_result() -> Dictionary:
	var normalized_score := int(round(float(score) / 55.0 * 100.0))
	return {
		"level_id": "ai_training_ground",
		"level_name": "基础训练关",
		"success": state == GameState.FINISHED,
		"elapsed_seconds": snappedf(elapsed_seconds, 0.01),
		"obstacle_hits": obstacle_hits,
		"falls": falls,
		"quiz_attempts": quiz_attempts,
		"score": score,
		"normalized_score": normalized_score,
		"stars": stars,
		"score_breakdown": {
			"knowledge": knowledge_score,
			"performance": course_score,
			"time": time_score,
			"total": score,
			"maximum": 55,
		},
	}


func _finish_run() -> void:
	knowledge_score = 15 if quiz_attempts == 1 else (10 if quiz_attempts == 2 else 5)
	course_score = maxi(0, 25 - obstacle_hits * 2)
	time_score = _get_time_score()
	score = knowledge_score + course_score + time_score
	stars = 3 if score >= 47 else (2 if score >= 36 else 1)
	state = GameState.FINISHED
	get_tree().paused = true
	state_changed.emit(state)
	var result := get_result()
	EXPERIMENT_EVENTS.record(self, "run_completed", "ai_training_ground", result)
	run_completed.emit(result)


func _refresh_live_score() -> void:
	# During the run, display the currently secured course and time points.
	course_score = maxi(0, 25 - obstacle_hits * 2)
	time_score = _get_time_score()
	score = course_score + time_score


func _get_time_score() -> int:
	if elapsed_seconds <= 90.0:
		return 15
	if elapsed_seconds <= 120.0:
		return 10
	return 5
