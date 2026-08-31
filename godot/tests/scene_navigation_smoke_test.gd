extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var navigation := root.get_node_or_null("SceneNavigation")
	_expect(navigation != null, "global scene navigation autoload exists")
	if navigation == null:
		quit(1)
		return
	_expect(navigation.get("back_button") != null, "global return button is constructed")
	_expect(String(navigation.call("destination_for_scene", "res://scenes/main_menu.tscn")).is_empty(), "main menu does not show a redundant return button")
	_expect(String(navigation.call("destination_for_scene", "res://scenes/digcomp_hub.tscn")) == "res://scenes/main_menu.tscn", "hub return destination is the main menu")

	var digcomp := root.get_node_or_null("DigCompSession")
	digcomp.call("reset_study_session")
	for path in [
		"res://scenes/main.tscn",
		"res://scenes/levels/spinner_race/spinner_race.tscn",
		"res://scenes/levels/data_chip_hunt/data_chip_hunt.tscn",
		"res://scenes/levels/signal_bomb_survival/signal_bomb_survival.tscn",
		"res://scenes/digcomp/puzzle.tscn",
		"res://scenes/digcomp/matching.tscn",
		"res://scenes/digcomp/image_judgment.tscn",
	]:
		_expect(String(navigation.call("destination_for_scene", path)) == "res://scenes/digcomp_hub.tscn", "study scene returns to hub: %s" % path.get_file())

	if failures.is_empty():
		print("SCENE_NAVIGATION_SMOKE_TEST_OK")
		quit(0)
	else:
		print("SCENE_NAVIGATION_SMOKE_TEST_FAILED: %s" % ", ".join(failures))
		quit(1)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		failures.append(label)
		push_error("[FAIL] %s" % label)

