extends SceneTree

const GAME_MANAGER := preload("res://scripts/game_manager.gd")
const SPINNER_MANAGER := preload("res://scripts/levels/spinner_race/spinner_race_manager.gd")
const PARTY_MANAGER := preload("res://scripts/party/party_mode_manager.gd")
const ASSISTANT_PANEL := preload("res://scripts/ui/ai_assistant_panel.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var service := root.get_node("AiAssistantService")
	_expect(not service.is_configured(), "native run without a classroom ticket disables automatic AI prompts")

	var first = GAME_MANAGER.new()
	root.add_child(first)
	first.prepare_run()
	first.start_run()
	var first_totals: Array[int] = []
	first.assistance_damage_changed.connect(func(total: int) -> void: first_totals.append(total))
	for _index in range(3):
		first.register_obstacle_hit()
		first.finish_respawn()
	_expect(first_totals == [1, 2, 3], "first level exposes the third effective damage threshold")
	first.set_assistant_open(true)
	_expect(paused and first.assistant_open, "first-level assistant acquires a global pause token")
	first.set_assistant_open(false)
	_expect(not paused and not first.assistant_open, "closing first-level assistant releases its pause token")
	first.prepare_run()
	_expect(first.obstacle_hits == 0 and first.falls == 0, "replay resets first-level damage counters")
	first.start_run()
	first.queue_free()

	var spinner = SPINNER_MANAGER.new()
	root.add_child(spinner)
	spinner.reset_race(Transform3D.IDENTITY)
	spinner.begin_race_now()
	var spinner_totals: Array[int] = []
	spinner.assistance_damage_changed.connect(func(total: int) -> void: spinner_totals.append(total))
	spinner.register_obstacle_hit()
	spinner.register_fall()
	spinner.register_obstacle_hit()
	_expect(spinner_totals == [1, 2, 3], "spinner damage combines obstacle hits and falls")
	spinner.set_assistant_open(true)
	_expect(paused and spinner.assistant_open, "spinner assistant pauses its timer and scene")
	spinner.set_assistant_open(false)
	_expect(not paused, "spinner assistant resumes without locking the game")
	spinner.queue_free()

	var party = PARTY_MANAGER.new()
	root.add_child(party)
	party.reset_run()
	party.begin_run_now()
	var party_totals: Array[int] = []
	party.assistance_damage_changed.connect(func(total: int) -> void: party_totals.append(total))
	party.register_hazard_hit()
	party.register_fall()
	party.register_hazard_hit()
	_expect(party_totals == [1, 2, 3], "party damage combines hazard hits and falls")
	party.set_assistant_open(true)
	_expect(paused and party.assistant_open, "party assistant pauses its timer and scene")
	party.set_assistant_open(false)
	_expect(not paused, "party assistant resumes without locking the game")
	party.queue_free()

	service.configure_for_test("http://127.0.0.1:8787", "test-ticket")
	var invitation_manager = GAME_MANAGER.new()
	root.add_child(invitation_manager)
	invitation_manager.prepare_run()
	invitation_manager.start_run()
	var panel = ASSISTANT_PANEL.new()
	root.add_child(panel)
	await process_frame
	panel.configure("ai_training_ground", func() -> Dictionary: return {})
	panel.open_changed.connect(invitation_manager.set_assistant_open)
	_expect(panel.show_help_offer({"trigger_reason": "no_progress"}), "lightweight invitation can be shown")
	_expect(panel.is_invitation_visible() and not panel.overlay.visible and not paused, "invitation does not pause gameplay or open the AI overlay")
	panel.call("_accept_offer")
	_expect(panel.overlay.visible and paused, "accepting the invitation opens AI and pauses gameplay")
	panel.close()
	service.clear_level_session("ai_training_ground")
	_expect(not paused, "closing accepted support resumes gameplay")
	panel.queue_free()
	invitation_manager.queue_free()
	call_deferred("_finish")


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("AI_ASSISTANT_SMOKE_TEST_OK")
		quit(0)
	else:
		print("AI_ASSISTANT_SMOKE_TEST_FAILED: %s" % ", ".join(failures))
		quit(1)
