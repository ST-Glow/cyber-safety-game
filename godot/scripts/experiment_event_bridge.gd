extends RefCounted


static func record(context: Node, event_name: String, level_id: String, payload: Dictionary = {}) -> void:
	var session := context.get_node_or_null("/root/ExperimentSession")
	if session:
		session.call("record_event", event_name, level_id, payload)


static func reset_session(context: Node) -> void:
	var session := context.get_node_or_null("/root/ExperimentSession")
	if session:
		session.call("reset_session", String(session.get("intervention_condition")))
