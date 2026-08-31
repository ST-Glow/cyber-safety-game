extends Node

const EXPERIMENT_EVENTS := preload("res://scripts/experiment_event_bridge.gd")

signal level_result_recorded(level_id: String, result: Dictionary)
signal campaign_reset

enum RunMode {
	SINGLE_LEVEL,
	CAMPAIGN,
}

const FIRST_LEVEL_ID := "ai_training_ground"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const LEVELS: Array[Dictionary] = [
	{
		"id": "ai_training_ground",
		"scene_path": "res://scenes/main.tscn",
		"kicker": "第 1 关",
		"title": "AI认知训练区",
		"detail": "跑、跳、冲刺，完成基础训练",
		"menu_order": 1,
		"final_level": false,
	},
	{
		"id": "spinner_race",
		"scene_path": "res://scenes/levels/spinner_race/spinner_race.tscn",
		"kicker": "第 2 关",
		"title": "旋转障碍冲刺",
		"detail": "通过检查点，跨越固定周期机关",
		"menu_order": 2,
		"final_level": false,
	},
	{
		"id": "data_chip_hunt",
		"scene_path": "res://scenes/levels/data_chip_hunt/data_chip_hunt.tscn",
		"kicker": "第 3 关",
		"title": "AI芯片收集赛",
		"detail": "探索三条路线，收集全部 12 枚芯片",
		"menu_order": 3,
		"final_level": false,
	},
	{
		"id": "signal_bomb_survival",
		"scene_path": "res://scenes/levels/signal_bomb_survival/signal_bomb_survival.tscn",
		"kicker": "最终关",
		"title": "信号炸弹生存赛",
		"detail": "观察预警，在固定波次中坚持 60 秒",
		"menu_order": 4,
		"final_level": true,
	},
]

var level_results: Dictionary = {}
var run_mode: RunMode = RunMode.SINGLE_LEVEL
var active_level_id: String = ""


func _ready() -> void:
	if not validate_level_registry():
		push_error("Campaign level registry validation failed")


func get_level_by_id(level_id: String) -> Dictionary:
	for level in LEVELS:
		if String(level.get("id", "")) == level_id:
			return level.duplicate(true)
	return {}


func get_level_by_scene_path(scene_path: String) -> Dictionary:
	for level in LEVELS:
		if String(level.get("scene_path", "")) == scene_path:
			return level.duplicate(true)
	return {}


func get_levels_in_menu_order() -> Array[Dictionary]:
	var ordered_levels: Array[Dictionary] = []
	for level in LEVELS:
		ordered_levels.append(level.duplicate(true))
	ordered_levels.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("menu_order", 0)) < int(right.get("menu_order", 0))
	)
	return ordered_levels


func validate_level_registry() -> bool:
	var valid := true
	var ids: Dictionary = {}
	var scene_paths: Dictionary = {}
	var menu_orders: Dictionary = {}
	var final_count := 0
	for level in LEVELS:
		var level_id := String(level.get("id", ""))
		var scene_path := String(level.get("scene_path", ""))
		var menu_order := int(level.get("menu_order", 0))
		if level_id.is_empty() or scene_path.is_empty() or menu_order <= 0:
			push_error("Campaign level metadata is incomplete: %s" % level)
			valid = false
		if ids.has(level_id) or scene_paths.has(scene_path) or menu_orders.has(menu_order):
			push_error("Campaign level metadata must use unique ids, paths, and menu order: %s" % level_id)
			valid = false
		ids[level_id] = true
		scene_paths[scene_path] = true
		menu_orders[menu_order] = true
		if not ResourceLoader.exists(scene_path, "PackedScene"):
			push_error("Campaign level scene does not exist: %s" % scene_path)
			valid = false
		if bool(level.get("final_level", false)):
			final_count += 1
	if final_count != 1:
		push_error("Campaign level metadata must identify exactly one final level")
		valid = false
	return valid


func record_level_result(level_id: String, result: Dictionary) -> void:
	if get_level_by_id(level_id).is_empty():
		push_warning("Unknown campaign level id: %s" % level_id)
	var stored_result := result.duplicate(true)
	stored_result["level_id"] = level_id
	level_results[level_id] = stored_result
	EXPERIMENT_EVENTS.record(self, "level_result_recorded", level_id, stored_result)
	level_result_recorded.emit(level_id, stored_result.duplicate(true))


func is_campaign_run() -> bool:
	return run_mode == RunMode.CAMPAIGN


func start_single_level(level_id: String) -> Error:
	if get_level_by_id(level_id).is_empty():
		return ERR_DOES_NOT_EXIST
	run_mode = RunMode.SINGLE_LEVEL
	active_level_id = level_id
	reset_campaign()
	return load_level(level_id)


func start_campaign(reset_experiment: bool = true) -> Error:
	run_mode = RunMode.CAMPAIGN
	active_level_id = FIRST_LEVEL_ID
	reset_campaign(reset_experiment)
	return load_level(FIRST_LEVEL_ID)


func return_to_menu() -> Error:
	run_mode = RunMode.SINGLE_LEVEL
	active_level_id = ""
	reset_campaign()
	return _change_scene(MAIN_MENU_SCENE, "AI训练场大挑战")


func load_next_level(current_level_id: String) -> Error:
	if not is_campaign_run():
		return ERR_UNAVAILABLE
	var ordered_levels := get_levels_in_menu_order()
	var current_index := -1
	for index in range(ordered_levels.size()):
		if String(ordered_levels[index].get("id", "")) == current_level_id:
			current_index = index
			break
	if current_index < 0 or current_index >= ordered_levels.size() - 1:
		return ERR_DOES_NOT_EXIST
	return load_level(String(ordered_levels[current_index + 1].get("id", "")))


func load_level(level_id: String) -> Error:
	var level := get_level_by_id(level_id)
	var scene_path := String(level.get("scene_path", ""))
	if scene_path.is_empty():
		return ERR_DOES_NOT_EXIST
	active_level_id = level_id
	return _change_scene(scene_path, String(level.get("title", "AI训练场")))


func _change_scene(scene_path: String, title: String) -> Error:
	var transition := get_node_or_null("/root/SceneTransition")
	if transition and transition.has_method("request_scene_change"):
		return int(transition.call(
			"request_scene_change",
			scene_path,
			title
		))
	return get_tree().change_scene_to_file(scene_path)


func reset_campaign(reset_experiment: bool = true) -> void:
	level_results.clear()
	if reset_experiment:
		EXPERIMENT_EVENTS.reset_session(self)
	campaign_reset.emit()


func restart_campaign() -> Error:
	run_mode = RunMode.CAMPAIGN
	active_level_id = FIRST_LEVEL_ID
	reset_campaign()
	return load_level(FIRST_LEVEL_ID)


func get_campaign_summary() -> Dictionary:
	var ordered_levels := get_levels_in_menu_order()
	var ordered_results: Array[Dictionary] = []
	var total_elapsed := 0.0
	var total_falls := 0
	var total_quiz_attempts := 0
	var total_normalized_score := 0.0
	var successful_levels := 0
	for level in ordered_levels:
		var level_id := String(level.get("id", ""))
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
		"total_levels": ordered_levels.size(),
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
