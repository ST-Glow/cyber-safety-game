class_name GameManager
extends Node

const EXPERIMENT_EVENTS := preload("res://scripts/experiment_event_bridge.gd")
const RUN_SCORING := preload("res://scripts/run_scoring.gd")

const SCORE_SCHEMA_VERSION := 2
const TARGET_TIME_SECONDS := 135.0

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
var _ready_pause_token: int = 0
var _assistant_pause_token: int = 0
var _quiz_pause_token: int = 0
var _result_pause_token: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if not assistant_open and (state == GameState.RUNNING or state == GameState.KNOCKBACK):
		elapsed_seconds += delta
		_refresh_live_score()


func prepare_run() -> void:
	_release_all_pause_requests()
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
	_ready_pause_token = get_node("/root/PauseCoordinator").acquire(self, &"ready")
	state_changed.emit(state)
	EXPERIMENT_EVENTS.record(self, "level_prepared", "ai_training_ground")


func start_run() -> void:
	if state != GameState.READY:
		return
	state = GameState.RUNNING
	get_node("/root/PauseCoordinator").release(_ready_pause_token)
	_ready_pause_token = 0
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
	_quiz_pause_token = get_node("/root/PauseCoordinator").acquire(self, &"quiz")
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
	if value and _assistant_pause_token == 0:
		_assistant_pause_token = get_node("/root/PauseCoordinator").acquire(self, &"assistant")
	elif not value and _assistant_pause_token != 0:
		get_node("/root/PauseCoordinator").release(_assistant_pause_token)
		_assistant_pause_token = 0


func restart_to_ready() -> void:
	prepare_run()


func get_result() -> Dictionary:
	return {
		"level_id": "ai_training_ground",
		"level_name": "基础训练关",
		"success": state == GameState.FINISHED,
		"elapsed_seconds": snappedf(elapsed_seconds, 0.01),
		"obstacle_hits": obstacle_hits,
		"falls": falls,
		"quiz_attempts": quiz_attempts,
		"score": score,
		"normalized_score": score,
		"score_schema_version": SCORE_SCHEMA_VERSION,
		"stars": stars,
		"score_breakdown": {
			"knowledge": knowledge_score,
			"performance": course_score,
			"time": time_score,
			"total": score,
			"maximum": 100,
		},
	}


func _finish_run() -> void:
	var score_breakdown := RUN_SCORING.build_score(
		[quiz_attempts],
		falls,
		maxi(0, obstacle_hits - falls),
		elapsed_seconds,
		TARGET_TIME_SECONDS,
		true
	)
	knowledge_score = int(score_breakdown.get("knowledge", 0))
	course_score = int(score_breakdown.get("performance", 0))
	time_score = int(score_breakdown.get("time", 0))
	score = int(score_breakdown.get("total", 0))
	stars = int(score_breakdown.get("stars", 1))
	state = GameState.FINISHED
	_result_pause_token = get_node("/root/PauseCoordinator").acquire(self, &"result")
	get_node("/root/PauseCoordinator").release(_quiz_pause_token)
	_quiz_pause_token = 0
	state_changed.emit(state)
	var result := get_result()
	EXPERIMENT_EVENTS.record(self, "run_completed", "ai_training_ground", result)
	run_completed.emit(result)


func _refresh_live_score() -> void:
	# During the run, display the currently secured course and time points.
	var non_fall_hits := maxi(0, obstacle_hits - falls)
	course_score = maxi(0, 25 - falls * 2 - non_fall_hits * 2)
	time_score = _get_time_score()
	score = course_score + time_score


func _get_time_score() -> int:
	var completion_ratio := elapsed_seconds / TARGET_TIME_SECONDS
	if completion_ratio <= 0.67:
		return 15
	if completion_ratio <= 0.9:
		return 10
	return 5


func _release_all_pause_requests() -> void:
	get_node("/root/PauseCoordinator").release_owner(self)
	_ready_pause_token = 0
	_assistant_pause_token = 0
	_quiz_pause_token = 0
	_result_pause_token = 0
