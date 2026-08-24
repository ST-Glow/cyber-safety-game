extends Node

var _finalized: bool = false


func _ready() -> void:
	if not OS.has_feature("web"):
		return
	var session := get_node_or_null("/root/ExperimentSession")
	if session:
		session.session_reset.connect(_on_session_reset)
		session.event_recorded.connect(_on_event_recorded)


func is_production() -> bool:
	if not OS.has_feature("web"):
		return false
	return bool(JavaScriptBridge.eval("Boolean(window.GodotExperimentBridge&&window.GodotExperimentBridge.isProduction())"))


func consent_status() -> String:
	if not OS.has_feature("web"):
		return "not_required"
	return String(JavaScriptBridge.eval("(window.GodotExperimentBridge&&window.GodotExperimentBridge.getConsentStatus())||'pending'"))


func finalize_campaign(campaign_summary: Dictionary) -> void:
	if _finalized or not OS.has_feature("web"):
		return
	_finalized = true
	_call_bridge("finalizeCampaign", campaign_summary)


func _on_session_reset(metadata: Dictionary) -> void:
	_finalized = false
	_call_bridge("beginSession", metadata)


func _on_event_recorded(event: Dictionary) -> void:
	_call_bridge("appendEvent", event)


func _call_bridge(method_name: String, value: Dictionary) -> void:
	if not OS.has_feature("web"):
		return
	var json_argument := JSON.stringify(JSON.stringify(value))
	JavaScriptBridge.eval(
		"if(window.GodotExperimentBridge){window.GodotExperimentBridge.%s(%s);}" % [method_name, json_argument]
	)
