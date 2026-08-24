class_name ScaffoldConfig
extends Resource

@export var scaffold_version: String = "v1"
@export_range(0.0, 300.0, 1.0) var grace_period_seconds: float = 20.0
@export_range(1.0, 300.0, 1.0) var proactive_idle_threshold: float = 30.0
@export_range(1.0, 300.0, 1.0) var proactive_no_progress_threshold: float = 45.0
@export_range(1.0, 300.0, 1.0) var quiz_hesitation_threshold: float = 25.0
@export_range(1, 20, 1) var reactive_failure_threshold: int = 2
@export_range(1, 20, 1) var reactive_quiz_error_threshold: int = 2
@export_range(1.0, 300.0, 1.0) var repeated_strategy_window_seconds: float = 30.0
@export_range(0.0, 600.0, 1.0) var cooldown_seconds: float = 60.0
@export_range(0.0, 600.0, 1.0) var remind_later_seconds: float = 30.0
@export_range(0, 20, 1) var max_scaffolds_per_level: int = 3
@export var allowed_hint_levels: Array[int] = [1, 2, 3]
@export_range(0.01, 100.0, 0.01) var progress_distance_epsilon: float = 1.5
@export_range(1.0, 120.0, 1.0) var repeated_movement_window_seconds: float = 20.0
@export_range(0.1, 10.0, 0.1) var safe_window_seconds: float = 3.0


func max_allowed_hint_level() -> int:
	var result := 1
	for level in allowed_hint_levels:
		result = maxi(result, clampi(level, 1, 3))
	return result
