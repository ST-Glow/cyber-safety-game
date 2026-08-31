extends SceneTree

const TEST_CLEANUP := preload("res://tests/test_cleanup.gd")
const SAMPLE_QUESTION: QuizQuestion = preload("res://resources/quiz/spinner_race/checkpoint_3_fact_check.tres")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var digcomp := root.get_node_or_null("DigCompSession")
	_expect(digcomp != null, "DigComp session autoload exists")
	if digcomp == null:
		quit(1)
		return
	digcomp.call("reset_study_session")
	var levels: Array = digcomp.call("get_top_levels")
	_expect(levels.size() == 4, "hub registry contains four freely selectable tasks")
	_expect(String(levels[0].get("id", "")) == "level_1_party_campaign", "existing four-stage campaign is the first hub task")
	for level in levels:
		_expect(ResourceLoader.exists(String(level.get("scene_path", ""))), "hub task scene exists: %s" % String(level.get("id", "")))

	var hub_scene := load("res://scenes/digcomp_hub.tscn") as PackedScene
	var hub := hub_scene.instantiate()
	root.add_child(hub)
	current_scene = hub
	await process_frame
	_expect(hub.find_child("GuideNPC", true, false) != null, "3D hub contains the guide NPC")
	_expect(hub.find_child("DigCompCore", true, false) != null, "3D hub contains the central DigComp energy core")
	for level in levels:
		_expect(hub.find_child("Portal_%s" % String(level.get("id", "")), true, false) != null, "3D hub contains portal for %s" % String(level.get("id", "")))
	for action_name in ["move_forward", "move_backward", "move_left", "move_right", "jump", "sprint", "interact", "task_help"]:
		_expect(InputMap.has_action(action_name), "Mission Control input map exposes %s" % action_name)
	_expect(hub.get("assistant_panel") != null, "AI assistant is available in the hub")
	var hub_player = hub.get("player")
	_expect(hub_player != null, "hub spawns a controllable player")
	_expect(hub_player != null and bool(hub_player.get("controls_enabled")), "hub enables movement immediately without an intro countdown")
	_expect(hub.get("progress_bar") != null, "hub HUD exposes the four-task progress bar")
	var progress_card := hub.find_child("ProgressCard", true, false) as Control
	var controls_guide := hub.find_child("PersistentControlsGuide", true, false) as Control
	for viewport_size in [Vector2i(1920, 1080), Vector2i(1600, 900), Vector2i(1366, 768)]:
		root.size = viewport_size
		await process_frame
		var viewport_rect := Rect2(Vector2.ZERO, Vector2(viewport_size))
		_expect(progress_card != null and viewport_rect.encloses(progress_card.get_global_rect()), "compact hub status stays inside %dx%d" % [viewport_size.x, viewport_size.y])
		_expect(controls_guide != null and viewport_rect.encloses(controls_guide.get_global_rect()), "persistent controls guide stays inside %dx%d" % [viewport_size.x, viewport_size.y])
	_expect(controls_guide != null and controls_guide.visible and is_equal_approx(controls_guide.modulate.a, 1.0), "hub controls guide remains visible")
	root.size = Vector2i(1280, 720)
	await process_frame
	if hub_player:
		var movement_start: Vector3 = hub_player.global_position
		Input.action_press("move_forward")
		for frame in range(8):
			await physics_frame
		Input.action_release("move_forward")
		_expect(hub_player.global_position.distance_to(movement_start) > 0.1, "WASD input physically moves the hub player")
		for settle_frame in range(45):
			await physics_frame
		Input.action_press("sprint")
		Input.action_press("move_forward")
		await physics_frame
		Input.action_release("move_forward")
		Input.action_release("sprint")
		_expect(bool(hub_player.call("is_dashing")), "Shift sprint activates the shared movement burst")
		for landing_frame in range(120):
			if hub_player.is_on_floor():
				break
			await physics_frame
		await process_frame
		Input.action_press("jump")
		for jump_frame in range(3):
			await physics_frame
		Input.action_release("jump")
		_expect(hub_player.velocity.y > 0.0, "Space jump produces upward velocity in the hub")
	hub.call("_on_portal_near", hub_player, "level_2_puzzle")
	await process_frame
	_expect(String(hub.get("active_portal_id")) == "level_2_puzzle", "approaching a portal selects only the nearby task")
	_expect(hub.get("portal_card") != null and bool(hub.get("portal_card").visible), "nearby portal slides in the compact task card")
	hub.call("_on_portal_left", hub_player, "level_2_puzzle")
	await create_timer(0.28).timeout
	_expect(String(hub.get("active_portal_id")).is_empty(), "leaving a portal clears the nearby task")
	_expect(hub.get("portal_card") != null and not bool(hub.get("portal_card").visible), "leaving a portal hides the compact task card")
	hub.call("_show_level_guide", "level_4_image_judgment")
	await process_frame
	_expect(hub.get("instruction_overlay") != null, "task selection opens a mission briefing before scene navigation")
	_expect(String(hub.get("pending_level_id")) == "level_4_image_judgment", "mission briefing preserves the selected task")
	_expect(hub_player != null and not bool(hub_player.get("controls_enabled")), "mission briefing safely pauses hub movement")
	if hub.get("instruction_overlay") != null:
		var guide_overlay = hub.get("instruction_overlay")
		_expect(guide_overlay.find_child("*", true, false) != null, "mission briefing builds visible objective and operation content")
	hub.call("_close_guide")
	await process_frame
	_expect(hub_player != null and bool(hub_player.get("controls_enabled")), "closing mission briefing returns control to the player")
	hub.queue_free()
	await process_frame

	for scene_path in ["res://scenes/digcomp/puzzle.tscn", "res://scenes/digcomp/matching.tscn", "res://scenes/digcomp/image_judgment.tscn"]:
		var scene := load(scene_path) as PackedScene
		var task := scene.instantiate()
		root.add_child(task)
		await process_frame
		_expect(task.get("assistant_panel") != null, "AI assistant is available in %s" % scene_path.get_file())
		_expect(task.get("task_container") != null, "specialist task UI builds in %s" % scene_path.get_file())
		task.queue_free()
		await process_frame

	digcomp.call("record_quiz_response", SAMPLE_QUESTION, SAMPLE_QUESTION.correct_index, true, 1, "spinner_race")
	digcomp.call("record_quiz_response", SAMPLE_QUESTION, 2, false, 2, "spinner_race")
	var quiz_score: Dictionary = digcomp.get("quiz_scores").get("area_1", {})
	_expect(int(quiz_score.get("maximum", 0)) == 1, "retries do not increase the formal knowledge maximum")
	_expect(int(quiz_score.get("score", 0)) == 1, "first correct response stays locked after replay")
	digcomp.get("quiz_scores")["area_1"] = {"score": 1, "maximum": 2}
	digcomp.get("specialist_scores")["area_1"] = 80.0
	var profile: Dictionary = digcomp.call("get_profile")
	var first_domain: Dictionary = Array(profile.get("domains", []))[0]
	_expect(is_equal_approx(float(first_domain.get("score", 0.0)), 68.0), "domain score applies 40 percent knowledge and 60 percent specialist evidence")
	_expect(int(first_domain.get("stars", 0)) == 4, "68-point domain score converts to four stars")
	_expect(profile.has("overall_score"), "profile exposes equal-weight overall score")

	TEST_CLEANUP.stop_all_audio(root)
	await create_timer(0.25, true, false, true).timeout
	if failures.is_empty():
		print("DIGCOMP_HUB_SMOKE_TEST_OK")
		quit(0)
	else:
		print("DIGCOMP_HUB_SMOKE_TEST_FAILED: %s" % ", ".join(failures))
		quit(1)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		failures.append(label)
		push_error("[FAIL] %s" % label)
