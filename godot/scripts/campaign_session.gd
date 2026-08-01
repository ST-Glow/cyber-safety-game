extends Node

const EXPERIMENT_EVENTS := preload("res://scripts/experiment_event_bridge.gd")

signal level_result_recorded(level_id: String, result: Dictionary)
signal campaign_reset

const FIRST_LEVEL_ID := "ai_training_ground"
const LEVEL_ORDER: Array[String] = [
	"ai_training_ground",
	"spinner_race",
	"data_chip_hunt",
	"signal_bomb_survival",
]
const LEVEL_SCENES := {
	"ai_training_ground": "res://scenes/main.tscn",
	"spinner_race": "res://scenes/levels/spinner_race/spinner_race.tscn",
	"data_chip_hunt": "res://scenes/levels/data_chip_hunt/data_chip_hunt.tscn",
	"signal_bomb_survival": "res://scenes/levels/signal_bomb_survival/signal_bomb_survival.tscn",
}
const LEVEL_TITLES := {
	"ai_training_ground": "AI认知训练区",
	"spinner_race": "旋转障碍冲刺",
	"data_chip_hunt": "AI芯片收集赛",
	"signal_bomb_survival": "信号炸弹生存赛",
}

var level_results: Dictionary = {}


func record_level_result(level_id: String, result: Dictionary) -> void:
	if not LEVEL_ORDER.has(level_id):
		push_warning("Unknown campaign level id: %s" % level_id)
	var stored_result := result.duplicate(true)
	stored_result["level_id"] = level_id
	level_results[level_id] = stored_result
	EXPERIMENT_EVENTS.record(self, "level_result_recorded", level_id, stored_result)
	level_result_recorded.emit(level_id, stored_result.duplicate(true))


func load_next_level(current_level_id: String) -> Error:
	var current_index := LEVEL_ORDER.find(current_level_id)
	if current_index < 0 or current_index >= LEVEL_ORDER.size() - 1:
		return ERR_DOES_NOT_EXIST
	return load_level(LEVEL_ORDER[current_index + 1])


func load_level(level_id: String) -> Error:
	var scene_path := String(LEVEL_SCENES.get(level_id, ""))
	if scene_path.is_empty():
		return ERR_DOES_NOT_EXIST
	get_tree().paused = false
	var transition := get_node_or_null("/root/SceneTransition")
	if transition and transition.has_method("request_scene_change"):
		return int(transition.call(
			"request_scene_change",
			scene_path,
			String(LEVEL_TITLES.get(level_id, "AI训练场"))
		))
	return get_tree().change_scene_to_file(scene_path)


func reset_campaign() -> void:
	level_results.clear()
	get_tree().paused = false
	EXPERIMENT_EVENTS.reset_session(self)
	campaign_reset.emit()


func restart_campaign() -> Error:
	reset_campaign()
	return load_level(FIRST_LEVEL_ID)


func get_campaign_summary() -> Dictionary:
	var ordered_results: Array[Dictionary] = []
	var total_elapsed := 0.0
	var total_falls := 0
	var total_quiz_attempts := 0
	var total_normalized_score := 0.0
	var successful_levels := 0
	for level_id in LEVEL_ORDER:
		if not level_results.has(level_id):
			continue
		var result: Dictionary = level_results[level_id]
		ordered_results.append(result.duplicate(true))
		total_elapsed += float(result.get("elapsed_seconds", 0.0))
		total_falls += int(result.get("falls", 0))
		total_quiz_attempts += int(result.get("quiz_attempts", 0))
		total_normalized_score += _get_normalized_score(result)
		if bool(result.get("success", true)):
			successful_levels += 1
	var average_score := 0
	if not ordered_results.is_empty():
		average_score = int(round(total_normalized_score / float(ordered_results.size())))
	return {
		"completed_levels": ordered_results.size(),
		"total_levels": LEVEL_ORDER.size(),
		"successful_levels": successful_levels,
		"total_elapsed_seconds": snappedf(total_elapsed, 0.01),
		"total_falls": total_falls,
		"total_quiz_attempts": total_quiz_attempts,
		"average_score": average_score,
		"level_results": ordered_results,
	}


func _get_normalized_score(result: Dictionary) -> float:
	if result.has("normalized_score"):
		return float(result["normalized_score"])
	return float(result.get("score", 0))
