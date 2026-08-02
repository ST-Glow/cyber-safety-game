class_name RunScoring
extends RefCounted

const KNOWLEDGE_MAX := 60
const PERFORMANCE_MAX := 25
const TIME_MAX := 15


static func build_score(
	quiz_attempts: Array,
	fall_count: int,
	hazard_hit_count: int,
	elapsed_seconds: float,
	time_limit_seconds: float,
	success: bool,
	fixed_duration_success: bool = false
) -> Dictionary:
	var knowledge_score := _score_quizzes(quiz_attempts)
	var performance_score := maxi(0, PERFORMANCE_MAX - fall_count * 2 - hazard_hit_count * 2)
	var time_score := _score_time(elapsed_seconds, time_limit_seconds, success, fixed_duration_success)
	var total_score := knowledge_score + performance_score + time_score
	return {
		"knowledge": knowledge_score,
		"performance": performance_score,
		"time": time_score,
		"total": total_score,
		"maximum": 100,
		"stars": 3 if total_score >= 85 else (2 if total_score >= 65 else 1),
	}


static func _score_quizzes(quiz_attempts: Array) -> int:
	if quiz_attempts.is_empty():
		return 0
	var earned_ratio := 0.0
	for attempt_value in quiz_attempts:
		var attempts := int(attempt_value)
		if attempts == 1:
			earned_ratio += 1.0
		elif attempts == 2:
			earned_ratio += 2.0 / 3.0
		elif attempts >= 3:
			earned_ratio += 1.0 / 3.0
	return int(round(KNOWLEDGE_MAX * earned_ratio / float(quiz_attempts.size())))


static func _score_time(elapsed: float, time_limit: float, success: bool, fixed_duration: bool) -> int:
	if not success:
		return 0
	if fixed_duration:
		return TIME_MAX
	var completion_ratio := elapsed / maxf(time_limit, 0.001)
	if completion_ratio <= 0.67:
		return 15
	if completion_ratio <= 0.9:
		return 10
	return 5
