class_name AiAssistantServiceNode
extends Node

signal configuration_changed(configured: bool, diagnostic: String)
signal request_started(level_id: String)
signal reply_received(level_id: String, reply: String)
signal request_failed(level_id: String, message: String)

const POLL_INTERVAL := 1.0
const REQUEST_TIMEOUT := 15.0
const TOTAL_TIMEOUT_MSEC := 65000

var _api_base_urls: Array[String] = []
var _api_index: int = 0
var _ticket: String = ""
var _sessions: Dictionary = {}
var _request: HTTPRequest
var _poll_timer: Timer
var _active: Dictionary = {}
var _configured: bool = false
var _diagnostic: String = ""
var _previous_hints: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_request = HTTPRequest.new()
	_request.name = "AssistantHTTPRequest"
	_request.process_mode = Node.PROCESS_MODE_ALWAYS
	_request.timeout = REQUEST_TIMEOUT
	_request.request_completed.connect(_on_request_completed)
	add_child(_request)
	_poll_timer = Timer.new()
	_poll_timer.one_shot = true
	_poll_timer.wait_time = POLL_INTERVAL
	_poll_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_poll_timer.timeout.connect(_poll_status)
	add_child(_poll_timer)
	_load_web_configuration()


func is_configured() -> bool:
	return _configured


func configuration_diagnostic() -> String:
	return _diagnostic


func send_hint(level_id: String, trigger: String, state: Dictionary, message: String) -> Error:
	if not _configured:
		_fail_immediately(level_id, "AI 助手当前不可用：%s" % _diagnostic)
		return ERR_UNCONFIGURED
	if not _active.is_empty():
		_fail_immediately(level_id, "上一条提示仍在生成，请稍候。")
		return ERR_BUSY
	if message.strip_edges().is_empty():
		return ERR_INVALID_PARAMETER
	_active = {
		"level_id": level_id,
		"trigger": trigger,
		"state": state.duplicate(true),
		"message": message.left(800),
		"poll": "",
		"started_msec": Time.get_ticks_msec(),
	}
	request_started.emit(level_id)
	return _post_chat()


func clear_level_session(level_id: String) -> void:
	_sessions.erase(level_id)
	_previous_hints.erase(level_id)
	if String(_active.get("level_id", "")) == level_id:
		_request.cancel_request()
		_poll_timer.stop()
		_active.clear()


func configure_for_test(api_base_url: String, ticket: String) -> void:
	_apply_configuration(api_base_url, ticket)


func get_previous_hints(level_id: String) -> Array:
	return Array(_previous_hints.get(level_id, [])).duplicate(true)


func _load_web_configuration() -> void:
	if not OS.has_feature("web"):
		_set_unconfigured("仅在带课堂票据的网页版中启用")
		return
	var raw: Variant = JavaScriptBridge.eval("JSON.stringify({primaryApiBaseUrl:(window.GODOT_AI_CONFIG&&window.GODOT_AI_CONFIG.primaryApiBaseUrl)||(window.GODOT_AI_CONFIG&&window.GODOT_AI_CONFIG.apiBaseUrl)||'',fallbackApiBaseUrl:(window.GODOT_AI_CONFIG&&window.GODOT_AI_CONFIG.fallbackApiBaseUrl)||'',ticket:(new URLSearchParams(window.location.search)).get('ticket')||''})")
	var parsed: Variant = JSON.parse_string(String(raw))
	if not parsed is Dictionary:
		_set_unconfigured("网页 AI 配置无法读取")
		return
	_apply_configuration(
		String(parsed.get("primaryApiBaseUrl", "")),
		String(parsed.get("ticket", "")),
		String(parsed.get("fallbackApiBaseUrl", ""))
	)


func _apply_configuration(api_base_url: String, ticket: String, fallback_api_base_url: String = "") -> void:
	_api_base_urls.clear()
	_api_index = 0
	var primary := api_base_url.strip_edges().trim_suffix("/")
	var fallback := fallback_api_base_url.strip_edges().trim_suffix("/")
	_ticket = ticket.strip_edges()
	if not _is_allowed_api_url(primary):
		_set_unconfigured("API 地址未配置或不安全")
		return
	_api_base_urls.append(primary)
	if not fallback.is_empty() and fallback != primary:
		if not _is_allowed_api_url(fallback):
			_set_unconfigured("备用 API 地址不安全")
			return
		_api_base_urls.append(fallback)
	if _ticket.is_empty():
		_set_unconfigured("缺少课堂票据")
		return
	_configured = true
	_diagnostic = ""
	configuration_changed.emit(true, "")


func _is_allowed_api_url(value: String) -> bool:
	if value.begins_with("https://"):
		return true
	return value.begins_with("http://127.0.0.1:") or value.begins_with("http://localhost:")


func _set_unconfigured(reason: String) -> void:
	_configured = false
	_diagnostic = reason
	configuration_changed.emit(false, reason)


func _post_chat() -> Error:
	var level_id := String(_active.level_id)
	var payload := {
		"ticket": _ticket,
		"level_id": level_id,
		"trigger": String(_active.trigger),
		"message": String(_active.message),
		"state": _active.state,
	}
	if _sessions.has(level_id):
		payload["session"] = _sessions[level_id]
	return _send_json("/api/coze/chat", payload)


func _poll_status() -> void:
	if _active.is_empty():
		return
	if Time.get_ticks_msec() - int(_active.started_msec) > TOTAL_TIMEOUT_MSEC:
		_finish_error("AI 回复超时，请稍后再试。")
		return
	_send_json("/api/coze/chat/status", {
		"ticket": _ticket,
		"level_id": String(_active.level_id),
		"poll": String(_active.poll),
	})


func _send_json(path: String, payload: Dictionary) -> Error:
	_active["request_path"] = path
	_active["request_payload"] = payload.duplicate(true)
	_active["fallback_attempted"] = false
	return _send_active_request()


func _send_active_request() -> Error:
	var path := String(_active.get("request_path", ""))
	var payload: Dictionary = _active.get("request_payload", {})
	var error := _request.request(
		_api_base_urls[_api_index] + path,
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	if error != OK:
		if _try_fallback():
			return OK
		_finish_error("无法连接 AI 助手，请继续挑战或稍后再试。")
	return error


func _try_fallback() -> bool:
	if _api_base_urls.size() < 2 or _api_index > 0 or bool(_active.get("fallback_attempted", false)):
		return false
	_active["fallback_attempted"] = true
	_api_index = 1
	call_deferred("_send_active_request")
	return true


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _active.is_empty():
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		if not _try_fallback():
			_finish_error("AI 助手网络异常，请继续挑战或稍后再试。")
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if response_code < 200 or response_code >= 300 or not parsed is Dictionary:
		if response_code >= 500 and _try_fallback():
			return
		var code := String(parsed.get("code", "")) if parsed is Dictionary else ""
		_finish_error(_friendly_error(code, response_code))
		return
	if String(parsed.get("status", "")) == "pending":
		_active["poll"] = String(parsed.get("poll", _active.get("poll", "")))
		_poll_timer.start()
		return
	var level_id := String(_active.level_id)
	var session := String(parsed.get("session", ""))
	if not session.is_empty():
		_sessions[level_id] = session
	var reply := String(parsed.get("reply", "")).strip_edges()
	var hints: Array = _previous_hints.get(level_id, [])
	if not reply.is_empty():
		hints.append(reply.left(500))
		while hints.size() > 3:
			hints.pop_front()
		_previous_hints[level_id] = hints
	_active.clear()
	reply_received.emit(level_id, reply)


func _friendly_error(code: String, response_code: int) -> String:
	match code:
		"ticket_expired", "ticket_signature_invalid":
			return "课堂链接已失效，请向老师获取新链接。"
		"coze_rate_limited":
			return "提问较频繁，请稍后再试。"
		"coze_not_configured", "agent_prompts_not_configured":
			return "AI 助手尚未完成服务端配置。"
		"agent_session_level_mismatch", "agent_poll_level_mismatch":
			return "关卡会话已失效，请重新打开本关助手。"
	if response_code >= 500:
		return "AI 助手暂时不可用，请继续挑战或稍后再试。"
	return "请求未能完成，请稍后再试。"


func _finish_error(message: String) -> void:
	var level_id := String(_active.get("level_id", ""))
	_active.clear()
	request_failed.emit(level_id, message)


func _fail_immediately(level_id: String, message: String) -> void:
	request_failed.emit.call_deferred(level_id, message)
