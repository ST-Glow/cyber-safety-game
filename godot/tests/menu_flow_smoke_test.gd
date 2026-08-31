extends SceneTree

const TEST_CLEANUP := preload("res://tests/test_cleanup.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var campaign := root.get_node_or_null("CampaignSession")
	_expect(campaign != null, "campaign session autoload exists")
	if campaign == null:
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	_expect(
		String(ProjectSettings.get_setting("application/run/main_scene", "")) == "res://scenes/main_menu.tscn",
		"F5 main scene is the level menu"
	)
	var menu_scene := load("res://scenes/main_menu.tscn") as PackedScene
	_expect(menu_scene != null, "main menu scene loads")
	if menu_scene == null:
		quit(1)
		return

	var menu: Variant = menu_scene.instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	await process_frame
	_expect(menu.level_buttons.size() == 4, "menu exposes four single-level entries")
	_expect(menu.campaign_button != null, "menu exposes the campaign entry")
	_expect(menu.hub_button != null, "menu exposes the DigComp formal hub entry")

	var first_button := menu.level_buttons.get("ai_training_ground") as Button
	_expect(first_button != null, "first-level menu button exists")
	if first_button:
		await _click_button(first_button)
	await _wait_scene_change()
	_expect(current_scene != null and current_scene.name == "AITrainingGround", "mouse click opens a single level")
	_expect(not bool(campaign.call("is_campaign_run")), "single-level click selects standalone run mode")
	if current_scene and current_scene.name == "AITrainingGround":
		var main_level := current_scene
		var manager := main_level.get_node_or_null("GameManager") as GameManager
		var player := main_level.get_node_or_null("RangerPlayer") as PlayerController
		var ui := main_level.get_node_or_null("GameUI") as GameUI
		_expect(ui != null and ui.next_button != null and ui.next_button.text == "返回主菜单", "standalone result action returns to menu")
		if manager and player and ui:
			main_level.call("_on_start_requested")
			main_level.call("_on_finish_body_entered", player)
			main_level.call("_on_quiz_choice_selected", 0)
			main_level.call("_on_quiz_choice_selected", 0)
			await process_frame
			ui.next_level_requested.emit()
			await _wait_scene_change()
			_expect(current_scene != null and current_scene.name == "MainMenu", "standalone completion returns to menu")

	var returned_menu: Variant = current_scene
	if returned_menu:
		await process_frame
		await _click_button(returned_menu.campaign_button)
		await _wait_scene_change()
		_expect(current_scene != null and current_scene.name == "AITrainingGround", "campaign button starts at the first level")
		_expect(bool(campaign.call("is_campaign_run")), "campaign button selects campaign run mode")
		if current_scene:
			var campaign_ui := current_scene.get_node_or_null("GameUI") as GameUI
			_expect(campaign_ui != null and campaign_ui.next_button.text == "进入下一关", "campaign result action advances the flow")
	else:
		_expect(false, "returned scene is the main menu")

	var menu_error := int(campaign.call("return_to_menu"))
	_expect(menu_error == OK, "public return-to-menu API accepts navigation")
	await _wait_scene_change()
	_expect(current_scene != null and current_scene.name == "MainMenu", "public return-to-menu API opens the menu")
	_expect(not paused, "menu navigation releases all pause requests")

	TEST_CLEANUP.stop_all_audio(root)
	await create_timer(0.25, true, false, true).timeout
	if failures.is_empty():
		print("MENU_FLOW_SMOKE_TEST_OK")
		quit(0)
	else:
		print("MENU_FLOW_SMOKE_TEST_FAILED: %s" % ", ".join(failures))
		quit(1)


func _click_button(button: Button) -> void:
	await process_frame
	var position := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	Input.parse_input_event(motion)
	await process_frame
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = position
	press.global_position = position
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = position
	release.global_position = position
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame


func _wait_scene_change() -> void:
	await process_frame
	await process_frame
	await process_frame
	await physics_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		failures.append(label)
		push_error("[FAIL] %s" % label)
