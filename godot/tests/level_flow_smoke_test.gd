extends SceneTree

const TEST_CLEANUP := preload("res://tests/test_cleanup.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var campaign := root.get_node_or_null("CampaignSession")
	var scene_transition := root.get_node_or_null("SceneTransition")
	_expect(campaign != null, "campaign session autoload exists")
	_expect(scene_transition != null, "scene transition autoload exists")
	if scene_transition:
		_expect(scene_transition.has_method("request_scene_change"), "transition exposes scene-change API")
		_expect(scene_transition.has_method("show_milestone"), "transition exposes milestone feedback API")
	if campaign:
		_expect(bool(campaign.call("validate_level_registry")), "campaign level registry validates at startup")
		var levels: Array = campaign.call("get_levels_in_menu_order")
		_expect(levels.size() == 4, "campaign registry enumerates exactly four levels")
		var expected_ids := ["ai_training_ground", "spinner_race", "data_chip_hunt", "signal_bomb_survival"]
		for index in range(levels.size()):
			var level: Dictionary = levels[index]
			_expect(String(level.get("id", "")) == expected_ids[index], "campaign registry preserves level menu order %d" % (index + 1))
			for field in ["id", "scene_path", "kicker", "title", "detail", "menu_order", "final_level"]:
				_expect(level.has(field), "campaign level %d contains %s metadata" % [index + 1, field])
		var spinner_metadata: Dictionary = campaign.call("get_level_by_scene_path", "res://scenes/levels/spinner_race/spinner_race.tscn")
		_expect(String(spinner_metadata.get("id", "")) == "spinner_race", "campaign registry supports scene-path lookup")
		var final_metadata: Dictionary = campaign.call("get_level_by_id", "signal_bomb_survival")
		_expect(bool(final_metadata.get("final_level", false)), "campaign registry identifies the final level")
		if scene_transition:
			scene_transition.call("_set_transition_copy", String(spinner_metadata.get("scene_path", "")), "", "")
			var transition_title := scene_transition.get("transition_title") as Label
			_expect(transition_title != null and transition_title.text == String(spinner_metadata.get("title", "")), "scene transition reads copy from campaign metadata")
		var campaign_start_error := int(campaign.call("start_campaign"))
		_expect(campaign_start_error == OK, "campaign starts through the public run-mode API")
	if campaign == null:
		quit(1)
		return
	await process_frame
	await process_frame
	await physics_frame
	var first_level := current_scene
	_expect(first_level != null and first_level.name == "AITrainingGround", "campaign opens the first registered level")
	_expect(bool(campaign.call("is_campaign_run")), "campaign run mode remains active")
	if first_level == null:
		quit(1)
		return

	var manager := first_level.get_node_or_null("GameManager") as GameManager
	var player := first_level.get_node_or_null("RangerPlayer") as PlayerController
	var ui := first_level.get_node_or_null("GameUI")
	_expect(manager != null and player != null and ui != null, "first level systems exist")
	_expect(ui.has_signal("next_level_requested"), "result UI exposes next-level action")
	if manager == null or player == null or ui == null:
		quit(1)
		return

	first_level.call("_on_start_requested")
	first_level.call("_on_finish_body_entered", player)
	first_level.call("_on_quiz_choice_selected", 0)
	await process_frame
	_expect(manager.state == GameManager.GameState.FINISHED, "first level completes before transition")

	ui.emit_signal("next_level_requested")
	await process_frame
	await process_frame
	await physics_frame
	_expect(current_scene != null and current_scene.name == "SpinnerRace", "next-level action opens spinner_race")
	if scene_transition:
		_expect(not bool(scene_transition.call("is_transitioning")), "headless transition completes without leaking busy state")
	if current_scene:
		var race_manager := current_scene.get_node_or_null("RaceManager") as SpinnerRaceManager
		var race_player := current_scene.get_node_or_null("RangerPlayer") as PlayerController
		var race_ui := current_scene.get_node_or_null("RaceUI") as SpinnerRaceUI
		_expect(race_manager != null, "spinner_race manager is active")
		_expect(race_player != null, "shared player is active in spinner_race")
		_expect(not paused, "first-level pause state is cleared during transition")
		await _wait_physics_frames(190)
		_expect(race_manager.state == SpinnerRaceManager.RaceState.RUNNING, "spinner_race countdown advances automatically")
		_expect(race_player.controls_enabled, "spinner_race unlocks movement after countdown")
		for checkpoint_index in range(1, 5):
			race_manager.open_checkpoint_quiz(checkpoint_index)
			race_manager.submit_quiz_answer(0, 0)
			race_manager.activate_checkpoint(checkpoint_index, Transform3D.IDENTITY)
		race_manager.try_finish()
		await process_frame
		_expect(race_manager.state == SpinnerRaceManager.RaceState.FINISHED, "spinner_race can complete before transition")
		race_ui.emit_signal("next_level_requested")
		await process_frame
		await process_frame
		await physics_frame

	_expect(current_scene != null and current_scene.name == "DataChipHunt", "spinner_race next action opens data_chip_hunt")
	if current_scene:
		var collection_manager := current_scene.get_node_or_null("ModeManager") as PartyModeManager
		var collection_ui := current_scene.get_node_or_null("ModeUI") as PartyModeUI
		_expect(collection_manager != null and collection_ui != null, "collection mode systems are active")
		collection_manager.begin_run_now()
		for quiz_slot in range(1, 3):
			collection_manager.open_quiz(quiz_slot)
			collection_manager.submit_quiz_answer(0, 0)
		collection_manager.finish(true, {"collected_count": 12, "target_count": 12})
		await process_frame
		collection_ui.emit_signal("next_level_requested")
		await process_frame
		await process_frame
		await physics_frame

	_expect(current_scene != null and current_scene.name == "SignalBombSurvival", "collection next action opens signal_bomb_survival")
	if current_scene:
		var survival_manager := current_scene.get_node_or_null("ModeManager") as PartyModeManager
		var survival_ui := current_scene.get_node_or_null("ModeUI") as PartyModeUI
		_expect(survival_manager != null and survival_ui != null, "survival mode systems are active")
		survival_manager.begin_run_now()
		for quiz_slot in range(1, 3):
			survival_manager.open_quiz(quiz_slot)
			survival_manager.submit_quiz_answer(0, 0)
		survival_manager.finish(true, {"survived_seconds": 60.0, "wave_reached": 3})
		await process_frame
		var summary: Dictionary = campaign.call("get_campaign_summary") if campaign else {}
		_expect(int(summary.get("completed_levels", 0)) == 4, "campaign summary contains all four levels")
		_expect(int(summary.get("average_score", 0)) > 0, "campaign summary includes a normalized average score")
		_expect(survival_ui.result_overlay.visible, "final campaign result is visible")
		survival_ui.emit_signal("restart_campaign_requested")
		await process_frame
		await process_frame
		await physics_frame
		_expect(current_scene != null and current_scene.name == "AITrainingGround", "restart-all returns to first level")
		var reset_summary: Dictionary = campaign.call("get_campaign_summary") if campaign else {}
		_expect(int(reset_summary.get("completed_levels", -1)) == 0, "restart-all clears campaign results")

	TEST_CLEANUP.stop_all_audio(root)
	await create_timer(0.25, true, false, true).timeout
	if failures.is_empty():
		print("LEVEL_FLOW_SMOKE_TEST_OK")
		quit(0)
	else:
		print("LEVEL_FLOW_SMOKE_TEST_FAILED: %s" % ", ".join(failures))
		quit(1)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		failures.append(label)
		push_error("[FAIL] %s" % label)


func _wait_physics_frames(frame_count: int) -> void:
	for _frame in range(frame_count):
		await physics_frame
