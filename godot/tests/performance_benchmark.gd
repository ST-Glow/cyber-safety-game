extends SceneTree

const TEST_CLEANUP := preload("res://tests/test_cleanup.gd")
const SCENARIOS := {
	"main": "res://scenes/main.tscn",
	"spinner": "res://scenes/levels/spinner_race/spinner_race.tscn",
	"collection": "res://scenes/levels/data_chip_hunt/data_chip_hunt.tscn",
	"survival": "res://scenes/levels/signal_bomb_survival/signal_bomb_survival.tscn",
}

var _scenario := "main"
var _warmup_seconds := 5.0
var _sample_seconds := 30.0
var _previous_max_fps := 0


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--scenario="):
			_scenario = argument.trim_prefix("--scenario=")
		elif argument.begins_with("--warmup="):
			_warmup_seconds = maxf(0.0, float(argument.trim_prefix("--warmup=")))
		elif argument.begins_with("--sample="):
			_sample_seconds = maxf(0.1, float(argument.trim_prefix("--sample=")))
	call_deferred("_run")


func _run() -> void:
	if not SCENARIOS.has(_scenario):
		push_error("Unknown performance scenario: %s" % _scenario)
		quit(2)
		return

	_previous_max_fps = Engine.max_fps
	Engine.max_fps = 60
	var load_started_usec := Time.get_ticks_usec()
	var packed_scene := load(String(SCENARIOS[_scenario])) as PackedScene
	if packed_scene == null:
		push_error("Unable to load performance scenario: %s" % _scenario)
		quit(2)
		return
	var game := packed_scene.instantiate()
	root.add_child(game)
	await process_frame
	var scene_ready_ms := float(Time.get_ticks_usec() - load_started_usec) / 1000.0
	_activate_scenario(game)
	await process_frame
	await physics_frame
	await _wait_wall_seconds(_warmup_seconds)

	var frame_samples: Array[float] = []
	var process_samples: Array[float] = []
	var physics_samples: Array[float] = []
	var draw_call_samples: Array[float] = []
	var sample_deadline := Time.get_ticks_usec() + int(_sample_seconds * 1000000.0)
	var previous_frame_usec := Time.get_ticks_usec()
	while Time.get_ticks_usec() < sample_deadline:
		await process_frame
		var now_usec := Time.get_ticks_usec()
		frame_samples.append(float(now_usec - previous_frame_usec) / 1000.0)
		previous_frame_usec = now_usec
		process_samples.append(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0)
		physics_samples.append(float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
		draw_call_samples.append(float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))

	var result := {
		"scenario": _scenario,
		"scene_ready_ms": snappedf(scene_ready_ms, 0.001),
		"frames": frame_samples.size(),
		"frame_median_ms": snappedf(_percentile(frame_samples, 0.5), 0.001),
		"frame_p95_ms": snappedf(_percentile(frame_samples, 0.95), 0.001),
		"process_median_ms": snappedf(_percentile(process_samples, 0.5), 0.001),
		"physics_median_ms": snappedf(_percentile(physics_samples, 0.5), 0.001),
		"draw_calls_median": int(round(_percentile(draw_call_samples, 0.5))),
		"static_memory_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"object_count": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resource_count": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
	}
	print("PERF_RESULT=%s" % JSON.stringify(result))

	TEST_CLEANUP.stop_all_audio(root)
	game.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.25, true, false, true).timeout
	Engine.max_fps = _previous_max_fps
	quit(0)


func _activate_scenario(game: Node) -> void:
	match _scenario:
		"main":
			game.call("_on_start_requested")
		"spinner":
			var manager := game.get_node("RaceManager") as SpinnerRaceManager
			manager.begin_race_now()
		"collection":
			var manager := game.get_node("ModeManager") as PartyModeManager
			manager.begin_run_now()
		"survival":
			var manager := game.get_node("ModeManager") as PartyModeManager
			manager.begin_run_now()
			game.call("_set_wave", 3)


func _wait_wall_seconds(duration: float) -> void:
	var deadline := Time.get_ticks_usec() + int(duration * 1000000.0)
	while Time.get_ticks_usec() < deadline:
		await process_frame


func _percentile(values: Array[float], ratio: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted_values := values.duplicate()
	sorted_values.sort()
	var index := clampi(int(ceil(float(sorted_values.size()) * ratio)) - 1, 0, sorted_values.size() - 1)
	return sorted_values[index]
