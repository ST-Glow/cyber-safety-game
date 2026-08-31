extends Node

const EXPERIMENT_EVENTS := preload("res://scripts/experiment_event_bridge.gd")

const HUB_SCENE := "res://scenes/digcomp_hub.tscn"
const DIGCOMP_VERSION := "3.0"
const TOP_LEVELS: Array[Dictionary] = [
	{"id": "level_1_party_campaign", "title": "AI派对闯关", "scene_path": "res://scenes/main.tscn"},
	{"id": "level_2_puzzle", "title": "数字策略拼图", "scene_path": "res://scenes/digcomp/puzzle.tscn"},
	{"id": "level_3_matching", "title": "数据与内容匹配", "scene_path": "res://scenes/digcomp/matching.tscn"},
	{"id": "level_4_image_judgment", "title": "安全协作影像判断", "scene_path": "res://scenes/digcomp/image_judgment.tscn"},
]
const DOMAINS: Array[Dictionary] = [
	{"id": "area_1", "title": "信息搜索、评估与管理"},
	{"id": "area_2", "title": "沟通与协作"},
	{"id": "area_3", "title": "数字内容创作"},
	{"id": "area_4", "title": "安全与负责任使用"},
	{"id": "area_5", "title": "问题解决"},
]

var top_level_results: Dictionary = {}
var selection_order: Array[String] = []
var quiz_responses: Dictionary = {}
var quiz_scores: Dictionary = {}
var specialist_scores: Dictionary = {}
var party_summary: Dictionary = {}
var active_top_level_id: String = ""
var session_active: bool = false
var finalized: bool = false


func _ready() -> void:
	_reset_score_containers()


func start_hub(reset_study: bool = false) -> Error:
	if reset_study or not session_active:
		reset_study_session()
	active_top_level_id = ""
	return _change_scene(HUB_SCENE, "数字能力探索大厅")


func reset_study_session() -> void:
	top_level_results.clear()
	selection_order.clear()
	quiz_responses.clear()
	party_summary.clear()
	active_top_level_id = ""
	finalized = false
	session_active = true
	_reset_score_containers()
	var experiment := get_node_or_null("/root/ExperimentSession")
	if experiment:
		experiment.call("reset_session", String(experiment.get("intervention_condition")))
	var campaign := get_node_or_null("/root/CampaignSession")
	if campaign:
		campaign.call("reset_campaign", false)


func get_top_levels() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for level in TOP_LEVELS:
		var copy := level.duplicate(true)
		copy["completed"] = top_level_results.has(String(level.get("id", "")))
		result.append(copy)
	return result


func start_top_level(level_id: String) -> Error:
	var level := _get_top_level(level_id)
	if level.is_empty():
		return ERR_DOES_NOT_EXIST
	active_top_level_id = level_id
	if not selection_order.has(level_id):
		selection_order.append(level_id)
	EXPERIMENT_EVENTS.record(self, "hub_level_selected", "digcomp_hub", {
		"top_level_id": level_id,
		"selection_index": selection_order.find(level_id) + 1,
	})
	if level_id == "level_1_party_campaign":
		var campaign := get_node_or_null("/root/CampaignSession")
		return int(campaign.call("start_campaign", false)) if campaign else ERR_UNAVAILABLE
	return _change_scene(String(level.get("scene_path", "")), String(level.get("title", "")))


func complete_party_campaign(summary: Dictionary) -> Error:
	if not top_level_results.has("level_1_party_campaign"):
		party_summary = summary.duplicate(true)
	return complete_top_level("level_1_party_campaign", {
		"success": true,
		"party_gameplay_score": int(summary.get("average_score", 0)),
		"campaign": summary.duplicate(true),
	})


func complete_top_level(level_id: String, result: Dictionary) -> Error:
	if not top_level_results.has(level_id):
		top_level_results[level_id] = result.duplicate(true)
		EXPERIMENT_EVENTS.record(self, "hub_level_completed", level_id, result)
	active_top_level_id = ""
	return start_hub(false)


func record_quiz_response(question: QuizQuestion, selected_index: int, correct: bool, attempt: int, level_id: String) -> void:
	if question == null:
		return
	var task_id := question.task_id if not question.task_id.is_empty() else "%s_quiz" % level_id
	var first_response := not quiz_responses.has(task_id)
	var hint_count := _hint_count(level_id)
	var payload := {
		"task_id": task_id,
		"task_type": "multiple_choice",
		"digcomp_version": DIGCOMP_VERSION,
		"area_id": question.digcomp_area_id,
		"competence_id": question.competence_id,
		"learning_outcome_id": question.learning_outcome_id,
		"first_response": first_response,
		"selected_index": selected_index,
		"display_order": Array(question.display_order),
		"correct": correct,
		"points_awarded": 1 if first_response and correct else 0,
		"response_time_msec": _quiz_response_time_msec(level_id),
		"attempt_count": attempt,
		"ai_used_before_response": hint_count > 0,
		"hint_count_before_response": hint_count,
		"support_trigger": "manual" if hint_count > 0 else "none",
		"hint_level": mini(hint_count, 3),
		"scaffold_id": "",
	}
	if first_response:
		quiz_responses[task_id] = payload.duplicate(true)
		var area_id := question.digcomp_area_id
		if quiz_scores.has(area_id):
			var score_data: Dictionary = quiz_scores[area_id]
			score_data["maximum"] = int(score_data.get("maximum", 0)) + 1
			if correct:
				score_data["score"] = int(score_data.get("score", 0)) + 1
			quiz_scores[area_id] = score_data
			_record_domain_update(area_id, "checkpoint_quiz")
	EXPERIMENT_EVENTS.record(self, "digcomp_response_submitted", level_id, payload)


func record_specialist_score(level_id: String, area_scores: Dictionary, details: Dictionary = {}) -> void:
	if top_level_results.has(level_id):
		var replay_payload := details.duplicate(true)
		replay_payload["formal_score_locked"] = true
		replay_payload["replay"] = true
		EXPERIMENT_EVENTS.record(self, "digcomp_score_replay_ignored", level_id, replay_payload)
		return
	for area_id in area_scores:
		if specialist_scores.has(area_id):
			specialist_scores[area_id] = clampf(float(area_scores[area_id]), 0.0, 100.0)
			_record_domain_update(String(area_id), level_id)
	var payload := details.duplicate(true)
	payload["digcomp_version"] = DIGCOMP_VERSION
	payload["area_scores"] = area_scores.duplicate(true)
	EXPERIMENT_EVENTS.record(self, "digcomp_score_updated", level_id, payload)


func get_profile() -> Dictionary:
	var domains: Array[Dictionary] = []
	var overall := 0.0
	for domain in DOMAINS:
		var area_id := String(domain.get("id", ""))
		var quiz: Dictionary = quiz_scores[area_id]
		var knowledge_percent := 0.0
		if int(quiz.get("maximum", 0)) > 0:
			knowledge_percent = 100.0 * float(quiz.get("score", 0)) / float(quiz.get("maximum", 1))
		var specialist_percent := float(specialist_scores.get(area_id, 0.0))
		var domain_score := knowledge_percent * 0.4 + specialist_percent * 0.6
		var stars := clampi(int(ceil(domain_score / 20.0)), 1, 5)
		domains.append({
			"area_id": area_id,
			"title": String(domain.get("title", "")),
			"knowledge_score": int(quiz.get("score", 0)),
			"knowledge_maximum": int(quiz.get("maximum", 0)),
			"knowledge_percent": snappedf(knowledge_percent, 0.01),
			"specialist_percent": snappedf(specialist_percent, 0.01),
			"score": snappedf(domain_score, 0.01),
			"stars": stars,
			"status": "优势" if domain_score >= 70.0 else ("发展中" if domain_score >= 40.0 else "需要加强"),
			"learning_advice": _learning_advice(area_id),
		})
		overall += domain_score
	return {
		"digcomp_version": DIGCOMP_VERSION,
		"completed_top_levels": top_level_results.size(),
		"total_top_levels": TOP_LEVELS.size(),
		"selection_order": selection_order.duplicate(),
		"domains": domains,
		"overall_score": snappedf(overall / float(DOMAINS.size()), 0.01),
	}


func get_final_summary() -> Dictionary:
	var party_result: Dictionary = top_level_results.get("level_1_party_campaign", {})
	return {
		"schema_version": 3,
		"hub_session": {
			"completed_levels": top_level_results.size(),
			"total_levels": TOP_LEVELS.size(),
			"selection_order": selection_order.duplicate(),
			"level_results": top_level_results.duplicate(true),
		},
		"level_1_party_campaign": party_summary.duplicate(true),
		"level_2_puzzle": top_level_results.get("level_2_puzzle", {}).duplicate(true),
		"level_3_matching": top_level_results.get("level_3_matching", {}).duplicate(true),
		"level_4_image_judgment": top_level_results.get("level_4_image_judgment", {}).duplicate(true),
		"digcomp_profile": get_profile(),
		"party_gameplay_score": int(party_result.get("party_gameplay_score", 0)),
		"ai_interactions": _ai_interaction_summary(),
		"quiz_first_responses": quiz_responses.duplicate(true),
		"specialist_scores": specialist_scores.duplicate(true),
	}


func all_top_levels_complete() -> bool:
	return top_level_results.size() == TOP_LEVELS.size()


func finalize_if_complete() -> bool:
	if finalized or not all_top_levels_complete():
		return false
	finalized = true
	var summary := get_final_summary()
	EXPERIMENT_EVENTS.record(self, "digcomp_profile_completed", "digcomp_hub", summary.get("digcomp_profile", {}))
	var web_bridge := get_node_or_null("/root/ExperimentWebBridge")
	if web_bridge:
		web_bridge.call_deferred("finalize_campaign", summary)
	return true


func _reset_score_containers() -> void:
	quiz_scores.clear()
	specialist_scores.clear()
	for domain in DOMAINS:
		quiz_scores[String(domain.get("id", ""))] = {"score": 0, "maximum": 0}
		specialist_scores[String(domain.get("id", ""))] = 0.0


func _record_domain_update(area_id: String, source: String) -> void:
	EXPERIMENT_EVENTS.record(self, "digcomp_domain_updated", active_top_level_id if not active_top_level_id.is_empty() else "digcomp_hub", {
		"digcomp_version": DIGCOMP_VERSION,
		"area_id": area_id,
		"source": source,
		"profile": get_profile(),
	})


func _hint_count(level_id: String) -> int:
	var service := get_node_or_null("/root/AiAssistantService")
	if service and service.has_method("get_previous_hints"):
		return Array(service.call("get_previous_hints", level_id)).size()
	return 0


func _quiz_response_time_msec(level_id: String) -> int:
	var experiment := get_node_or_null("/root/ExperimentSession")
	if experiment and experiment.has_method("get_level_time"):
		var timing: Dictionary = experiment.call("get_level_time", level_id)
		return int(round(float(timing.get("quiz_time", 0.0)) * 1000.0))
	return 0


func _ai_interaction_summary() -> Dictionary:
	var summary := {"proactive_invitations": 0, "manual_requests": 0, "accepted": 0, "rejected": 0, "dismissed": 0, "support_started": 0}
	var experiment := get_node_or_null("/root/ExperimentSession")
	if experiment == null:
		return summary
	for event in Array(experiment.get("events")):
		match String(event.get("event_name", "")):
			"scaffold_invitation_shown": summary.proactive_invitations += 1
			"scaffold_accepted": summary.accepted += 1
			"scaffold_rejected": summary.rejected += 1
			"scaffold_dismissed": summary.dismissed += 1
			"support_started":
				summary.support_started += 1
				if String(Dictionary(event.get("payload", {})).get("trigger_reason", "")) == "manual":
					summary.manual_requests += 1
	return summary


func _learning_advice(area_id: String) -> String:
	match area_id:
		"area_1": return "继续练习比较来源、核验日期与证据，并用标签管理资料。"
		"area_2": return "在与人和AI协作时明确目标、限制、分工及最终责任。"
		"area_3": return "发布前核验并编辑内容，同时检查AI标记、版权许可和署名。"
		"area_4": return "坚持数据最小化、账号保护、偏差检查和健康的数字使用习惯。"
		"area_5": return "先定义问题，再比较工具、监控过程，并验证结果和不确定性。"
	return "根据任务反馈继续练习。"


func _get_top_level(level_id: String) -> Dictionary:
	for level in TOP_LEVELS:
		if String(level.get("id", "")) == level_id:
			return level.duplicate(true)
	return {}


func _change_scene(scene_path: String, title: String) -> Error:
	var transition := get_node_or_null("/root/SceneTransition")
	if transition and transition.has_method("request_scene_change"):
		return int(transition.call("request_scene_change", scene_path, title))
	return get_tree().change_scene_to_file(scene_path)
