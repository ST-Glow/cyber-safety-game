extends PartyLevelBase

const MODE_MANAGER_SCRIPT := preload("res://scripts/party/party_mode_manager.gd")
const MODE_UI_SCRIPT := preload("res://scripts/party/party_mode_ui.gd")
const DATA_CHIP_SCENE := preload("res://scenes/party/data_chip.tscn")
const SPRING_PAD_SCENE := preload("res://scenes/party/spring_pad.tscn")
const MOVING_PLATFORM_SCENE := preload("res://scenes/obstacles/moving_platform.tscn")

const QUESTION_1: QuizQuestion = preload("res://resources/quiz/data_chip_hunt/checkpoint_1_training_data.tres")
const QUESTION_2: QuizQuestion = preload("res://resources/quiz/data_chip_hunt/checkpoint_2_prediction.tres")

const COIN_A := preload("res://assets/environments/prototype/kaykit_prototype_bits/models/Coin_A.gltf")
const COIN_B := preload("res://assets/environments/prototype/kaykit_prototype_bits/models/Coin_B.gltf")
const COIN_C := preload("res://assets/environments/prototype/kaykit_prototype_bits/models/Coin_C.gltf")
const BLUE_PLATFORM := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/blue/platform_6x6x1_blue.gltf")
const GREEN_PLATFORM := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/green/platform_6x6x1_green.gltf")
const YELLOW_PLATFORM := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/yellow/platform_6x6x1_yellow.gltf")
const RED_PLATFORM_4 := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/red/platform_4x4x1_red.gltf")
const GREEN_PLATFORM_4 := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/green/platform_4x4x1_green.gltf")
const YELLOW_PLATFORM_4 := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/yellow/platform_4x4x1_yellow.gltf")
const GREEN_SLOPE := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/green/platform_slope_4x6x4_green.gltf")
const BLUE_ARROW_PLATFORM := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/blue/platform_arrow_4x4x1_blue.gltf")
const YELLOW_ARROW_PLATFORM := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/yellow/platform_arrow_4x4x1_yellow.gltf")
const YELLOW_SPRING_PAD := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/yellow/spring_pad_yellow.gltf")
const BLUE_HOOP := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/blue/hoop_angled_blue.gltf")
const YELLOW_HOOP := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/yellow/hoop_angled_yellow.gltf")
const BLUE_PIPE_STRAIGHT := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/blue/pipe_straight_A_blue.gltf")
const BLUE_PIPE_CURVE := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/blue/pipe_90_A_blue.gltf")
const GREEN_ARROW_SIGN := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/green/signage_arrow_stand_green.gltf")
const GREEN_ARCH := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/green/arch_wide_green.gltf")
const GREEN_FLAG := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/green/flag_B_green.gltf")
const YELLOW_FLAG := preload("res://assets/environments/platformer/kaykit_platformer_pack/models/yellow/flag_C_yellow.gltf")
const UI_FONT: FontFile = preload("res://assets/ui/fonts/noto_sans_sc_ui_600.ttf")

const LEVEL_ID := "data_chip_hunt"
const START_POSITION := Vector3(0.0, 0.08, 9.0)
const TARGET_CHIPS := 12

var mode_manager: PartyModeManager
var mode_ui: PartyModeUI
var initial_spawn := Transform3D.IDENTITY
var respawn_transform := Transform3D.IDENTITY
var chips: Array[DataChip] = []
var spring_pads: Array[PartySpringPad] = []
var moving_platforms: Array[MovingPlatform] = []
var collected_count: int = 0
var active_question: QuizQuestion
var active_quiz_slot: int = 0
var quiz_triggered: Array[bool] = [false, false]
var pending_fall_respawn: bool = false
var _quiz_pause_token: int = 0
var _result_pause_token: int = 0


func _ready() -> void:
	_ensure_party_inputs()
	_build_manager()
	_build_party_world(
		Color("32c6dc"),
		Color("baf4e9"),
		[Color("4fd4aa"), Color("7ce3c4"), Color("7ab9ef"), Color("f5c95f")]
	)
	_build_collection_arena()
	initial_spawn = _spawn_party_player(START_POSITION)
	respawn_transform = initial_spawn
	_build_party_camera(8.6, -19.0)
	_spawn_moving_platforms()
	_spawn_spring_pads()
	_spawn_chips()
	_build_ui()
	_connect_signals()
	_reset_level()


func _process(delta: float) -> void:
	_update_party_camera(delta)
	if mode_manager == null or mode_ui == null:
		return
	var state_text := "收集中"
	match mode_manager.state:
		PartyModeManager.RunState.COUNTDOWN:
			state_text = "等待出发"
		PartyModeManager.RunState.QUIZ:
			state_text = "答题暂停"
		PartyModeManager.RunState.FINISHED:
			state_text = "已完成"
		PartyModeManager.RunState.FAILED:
			state_text = "挑战结束"
	mode_ui.update_hud(
		mode_manager.time_left,
		state_text,
		"AI芯片  %d / %d" % [collected_count, TARGET_CHIPS],
		"掉落  %d" % mode_manager.falls,
		float(collected_count) / float(TARGET_CHIPS)
	)


func _build_manager() -> void:
	mode_manager = MODE_MANAGER_SCRIPT.new() as PartyModeManager
	mode_manager.name = "ModeManager"
	mode_manager.level_id = LEVEL_ID
	mode_manager.level_name = "AI芯片收集赛"
	mode_manager.countdown_duration = 3.0
	mode_manager.time_limit_seconds = 75.0
	mode_manager.quiz_slot_count = 2
	add_child(mode_manager)


func _build_collection_arena() -> void:
	var track := Node3D.new()
	track.name = "CollectionArena"
	add_child(track)

	# Shared start hub. All three routes remain visible and can be attempted in any order.
	for x_value in [-9.0, -3.0, 3.0, 9.0]:
		for z_value in [9.0, 3.0]:
			_create_party_platform(
				track,
				Vector3(6.0, 1.0, 6.0),
				Vector3(x_value, -0.5, z_value),
				GREEN_PLATFORM,
				"HubPlatform",
				Vector3(6.0, 1.0, 6.0)
			)

	# Route A: forgiving stepped platforms with KayKit slope scenery.
	var west_positions := [
		Vector3(-10.0, -0.5, -3.0),
		Vector3(-10.0, 0.1, -9.0),
		Vector3(-10.0, 0.7, -15.0),
		Vector3(-10.0, 1.3, -21.0),
	]
	for index in range(west_positions.size()):
		_create_party_platform(
			track,
			Vector3(6.0, 1.0, 6.0),
			west_positions[index],
			GREEN_PLATFORM if index % 2 == 0 else BLUE_PLATFORM,
			"SlopeRoute%d" % (index + 1),
			Vector3(6.0, 1.0, 6.0)
		)
	_add_party_visual(track, GREEN_SLOPE, Vector3(-14.2, -0.1, -12.0), Vector3.ONE * 0.85, "KayKitSlopeScenery", Vector3(0.0, 90.0, 0.0))

	# Route B: elevated spring course. Normal jumps remain possible, while pads offer a faster line.
	var spring_platforms := [
		[Vector3(0.0, -0.5, -3.0), GREEN_PLATFORM_4],
		[Vector3(0.0, 1.5, -9.0), YELLOW_PLATFORM_4],
		[Vector3(0.0, 3.5, -15.0), RED_PLATFORM_4],
		[Vector3(0.0, 1.5, -21.0), YELLOW_PLATFORM_4],
	]
	for index in range(spring_platforms.size()):
		_create_party_platform(
			track,
			Vector3(5.0, 1.0, 5.0),
			spring_platforms[index][0],
			spring_platforms[index][1],
			"SpringRoute%d" % (index + 1)
		)
	_add_party_visual(track, BLUE_HOOP, Vector3(0.0, 3.2, -6.2), Vector3.ONE * 1.2, "BlueFlightHoop")
	_add_party_visual(track, YELLOW_HOOP, Vector3(0.0, 5.2, -12.4), Vector3.ONE * 1.2, "YellowFlightHoop")

	# Route C: two reusable moving platforms, framed by pipes and arrow signage.
	for route_position in [Vector3(10.0, -0.5, -3.0), Vector3(10.0, -0.5, -15.0)]:
		_create_party_platform(track, Vector3(5.0, 1.0, 5.0), route_position, BLUE_PLATFORM, "MovingDock", Vector3(6.0, 1.0, 6.0))
	_add_party_visual(track, BLUE_PIPE_STRAIGHT, Vector3(14.1, 0.0, -8.5), Vector3.ONE * 1.15, "PipeStraight", Vector3(0.0, 0.0, 90.0))
	_add_party_visual(track, BLUE_PIPE_CURVE, Vector3(14.1, 0.0, -16.5), Vector3.ONE * 1.15, "PipeCurve", Vector3(0.0, 90.0, 0.0))
	_add_party_visual(track, GREEN_ARROW_SIGN, Vector3(7.2, 0.0, 0.0), Vector3.ONE * 1.3, "MovingRouteSign")

	# Far bridge connects all routes so missed chips can be approached from either side.
	for x_value in [-12.0, -6.0, 0.0, 6.0, 12.0]:
		_create_party_platform(track, Vector3(6.0, 1.0, 6.0), Vector3(x_value, -0.5, -27.0), YELLOW_PLATFORM, "FarBridge", Vector3(6.0, 1.0, 6.0))

	_add_party_visual(track, GREEN_ARCH, Vector3(0.0, 0.0, 11.5), Vector3.ONE * 1.8, "CollectionStartArch")
	var route_guides := [
		[Vector3(-10.0, 0.0, 0.2), Color("55dfab"), "SlopeRouteBeacon"],
		[Vector3(0.0, 0.0, 0.2), Color("ffd85a"), "SpringRouteBeacon"],
		[Vector3(10.0, 0.0, 0.2), Color("54b8f5"), "MovingRouteBeacon"],
	]
	for route_guide in route_guides:
		_add_party_floor_marker(track, route_guide[0], 2.15, route_guide[1], "%sMarker" % route_guide[2])
		_add_party_beacon(track, route_guide[0] + Vector3(-2.0, 0.0, 0.0), route_guide[1], "%sLeft" % route_guide[2], 2.7)
		_add_party_beacon(track, route_guide[0] + Vector3(2.0, 0.0, 0.0), route_guide[1], "%sRight" % route_guide[2], 2.7)
	for flag_position in [Vector3(-11.0, 0.0, 7.0), Vector3(11.0, 0.0, 7.0)]:
		_add_party_visual(track, GREEN_FLAG, flag_position, Vector3.ONE * 1.3, "GreenRouteFlag")
	for flag_position in [Vector3(-13.0, 0.0, -27.0), Vector3(13.0, 0.0, -27.0)]:
		_add_party_visual(track, YELLOW_FLAG, flag_position, Vector3.ONE * 1.3, "YellowBridgeFlag")
	_add_course_label(track, "AI芯片收集赛", Vector3(0.0, 4.8, 10.8), Color("fff7d1"))
	_add_course_label(track, "坡道区", Vector3(-10.0, 3.5, 0.0), Color("d8fff0"))
	_add_course_label(track, "弹簧区", Vector3(0.0, 3.5, 0.0), Color("fff1b7"))
	_add_course_label(track, "移动区", Vector3(10.0, 3.5, 0.0), Color("d8efff"))


func _spawn_moving_platforms() -> void:
	var root := Node3D.new()
	root.name = "MovingPlatforms"
	add_child(root)
	var definitions := [
		["MovingPlatformA", Vector3(10.0, -0.45, -9.0), Vector3(-5.0, 0.0, 0.0), 4.2, 0.0, BLUE_ARROW_PLATFORM],
		["MovingPlatformB", Vector3(10.0, -0.45, -21.0), Vector3(5.0, 0.0, 0.0), 4.8, PI, YELLOW_ARROW_PLATFORM],
	]
	for definition in definitions:
		var moving := MOVING_PLATFORM_SCENE.instantiate() as MovingPlatform
		moving.name = definition[0]
		moving.position = definition[1]
		moving.platform_size = Vector3(5.0, 0.9, 5.0)
		moving.movement_offset = definition[2]
		moving.period_seconds = definition[3]
		moving.initial_phase = definition[4]
		moving.visual_scene = definition[5]
		root.add_child(moving)
		moving_platforms.append(moving)


func _spawn_spring_pads() -> void:
	var root := Node3D.new()
	root.name = "SpringPads"
	add_child(root)
	for pad_position in [Vector3(0.0, 0.02, -4.6), Vector3(0.0, 2.02, -10.7)]:
		var pad := SPRING_PAD_SCENE.instantiate() as PartySpringPad
		pad.name = "SpringPad%d" % (spring_pads.size() + 1)
		pad.position = pad_position
		pad.visual_scene = YELLOW_SPRING_PAD
		root.add_child(pad)
		spring_pads.append(pad)


func _spawn_chips() -> void:
	var root := Node3D.new()
	root.name = "DataChips"
	add_child(root)
	var chip_positions := [
		Vector3(-10.0, 1.0, -3.0), Vector3(-10.0, 1.6, -9.0), Vector3(-10.0, 2.2, -15.0), Vector3(-10.0, 2.8, -21.0),
		Vector3(0.0, 1.0, -3.0), Vector3(0.0, 3.0, -9.0), Vector3(0.0, 5.0, -15.0), Vector3(0.0, 3.0, -21.0),
		Vector3(10.0, 1.0, -3.0), Vector3(10.0, 1.1, -9.0), Vector3(10.0, 1.0, -15.0), Vector3(10.0, 1.1, -21.0),
	]
	var coin_scenes: Array[PackedScene] = [COIN_A, COIN_B, COIN_C]
	for index in range(chip_positions.size()):
		var chip := DATA_CHIP_SCENE.instantiate() as DataChip
		chip.name = "DataChip%02d" % (index + 1)
		chip.chip_id = index + 1
		chip.position = chip_positions[index]
		chip.visual_scene = coin_scenes[index % coin_scenes.size()]
		chip.collected.connect(_on_chip_collected)
		root.add_child(chip)
		chips.append(chip)


func _build_ui() -> void:
	mode_ui = MODE_UI_SCRIPT.new() as PartyModeUI
	mode_ui.name = "ModeUI"
	mode_ui.mode_kicker = "DATA CHIP HUNT"
	mode_ui.mode_title = "AI芯片收集赛"
	mode_ui.objective_text = "在75秒内探索三条路线，收集全部12枚AI芯片"
	add_child(mode_ui)


func _connect_signals() -> void:
	_connect_party_player_events(LEVEL_ID)
	player.fell.connect(_on_player_fell)
	player.knockback_finished.connect(_on_knockback_finished)
	mode_manager.countdown_changed.connect(_on_countdown_changed)
	mode_manager.run_started.connect(_on_run_started)
	mode_manager.time_expired.connect(_on_time_expired)
	mode_manager.run_finished.connect(_on_run_finished)
	mode_ui.quiz_choice_selected.connect(_on_quiz_choice_selected)
	mode_ui.restart_requested.connect(_on_restart_requested)
	mode_ui.next_level_requested.connect(_on_next_level_requested)


func _on_countdown_changed(seconds_left: int) -> void:
	mode_ui.show_countdown(seconds_left)


func _on_run_started() -> void:
	mode_ui.hide_countdown()
	player.set_controls_enabled(true)
	_set_moving_platforms_active(true)


func _on_chip_collected(_chip_id: int, chip: DataChip) -> void:
	if not mode_manager.is_running():
		chip.reset_chip()
		return
	collected_count += 1
	if collected_count == 6 and not quiz_triggered[0]:
		quiz_triggered[0] = true
		_show_milestone("已收集 6 / 12", "知识检查点已解锁")
		_open_quiz(1, QUESTION_1)
	elif collected_count == TARGET_CHIPS and not quiz_triggered[1]:
		quiz_triggered[1] = true
		_show_milestone("12枚芯片全部收集", "完成最后一道知识题即可通关")
		_open_quiz(2, QUESTION_2)


func _open_quiz(slot: int, question: QuizQuestion) -> void:
	if not mode_manager.open_quiz(slot):
		return
	active_quiz_slot = slot
	active_question = question
	player.set_controls_enabled(false)
	_quiz_pause_token = get_node("/root/PauseCoordinator").acquire(self, &"quiz")
	mode_ui.show_quiz(question, slot, 2)


func _on_quiz_choice_selected(selected_index: int) -> void:
	if active_question == null or active_quiz_slot <= 0:
		return
	var completed_slot := active_quiz_slot
	var correct := mode_manager.submit_quiz_answer(selected_index, active_question.correct_index)
	if not correct:
		mode_ui.show_wrong_answer(selected_index, active_question.explanation)
		return
	active_question = null
	active_quiz_slot = 0
	mode_ui.hide_quiz()
	get_node("/root/PauseCoordinator").release(_quiz_pause_token)
	_quiz_pause_token = 0
	if completed_slot == 2:
		player.set_controls_enabled(false)
		mode_manager.finish(true, _get_mode_metrics())
	else:
		respawn_transform = initial_spawn
		player.set_controls_enabled(true)


func _on_player_fell() -> void:
	if not mode_manager.register_fall():
		return
	pending_fall_respawn = true
	player.begin_knockback(Vector3(0.0, 2.5, 0.0), 0.42)
	_start_party_camera_shake(0.38, 0.2)


func _on_knockback_finished() -> void:
	if pending_fall_respawn:
		pending_fall_respawn = false
		player.respawn_at(respawn_transform)
		player.set_controls_enabled(mode_manager.is_running())
		_reset_party_camera()
	elif mode_manager.is_running():
		player.set_controls_enabled(true)


func _on_time_expired() -> void:
	player.set_controls_enabled(false)
	mode_manager.finish(false, _get_mode_metrics())


func _on_run_finished(result: Dictionary) -> void:
	if _result_pause_token == 0:
		_result_pause_token = get_node("/root/PauseCoordinator").acquire(self, &"result")
	_set_moving_platforms_active(false)
	CampaignSession.record_level_result(LEVEL_ID, result)
	if bool(result.get("success", false)):
		player.play_celebration()
	else:
		player.set_controls_enabled(false)
	var metrics := "收集芯片  %d / %d\n用时  %.2f 秒\n掉落  %d 次\n答题  %d 次" % [
		int(result.get("collected_count", 0)),
		int(result.get("target_count", TARGET_CHIPS)),
		float(result.get("elapsed_seconds", 0.0)),
		int(result.get("falls", 0)),
		int(result.get("quiz_attempts", 0)),
	]
	mode_ui.show_result(result, metrics)


func _on_restart_requested() -> void:
	_reset_level()


func _on_next_level_requested() -> void:
	if mode_manager.state != PartyModeManager.RunState.FINISHED:
		return
	var change_error := CampaignSession.load_next_level(LEVEL_ID)
	if change_error != OK:
		push_error("Unable to open signal_bomb_survival: %s" % error_string(change_error))


func _reset_level() -> void:
	get_node("/root/PauseCoordinator").release_owner(self)
	_quiz_pause_token = 0
	_result_pause_token = 0
	collected_count = 0
	active_question = null
	active_quiz_slot = 0
	quiz_triggered = [false, false]
	pending_fall_respawn = false
	respawn_transform = initial_spawn
	for chip in chips:
		chip.reset_chip()
	for pad in spring_pads:
		pad.reset_pad()
	for moving in moving_platforms:
		moving.reset_phase()
	player.respawn_at(initial_spawn)
	player.set_controls_enabled(false)
	_set_moving_platforms_active(false)
	_reset_party_camera()
	mode_manager.reset_run()
	mode_ui.reset_view(mode_manager.time_limit_seconds)


func _set_moving_platforms_active(active: bool) -> void:
	for moving in moving_platforms:
		moving.set_physics_process(active)


func _show_milestone(title_text: String, detail_text: String) -> void:
	var transition := get_node_or_null("/root/SceneTransition")
	if transition and transition.has_method("show_milestone"):
		transition.call("show_milestone", title_text, detail_text)


func _get_mode_metrics() -> Dictionary:
	return {
		"collected_count": collected_count,
		"target_count": TARGET_CHIPS,
		"quiz_attempts_by_checkpoint": mode_manager.quiz_attempts_by_slot.duplicate(),
	}


func _add_course_label(parent: Node3D, text: String, position_value: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = UI_FONT
	label.font_size = 38
	label.outline_size = 8
	label.modulate = color
	label.outline_modulate = Color("30416c")
	label.position = position_value
	parent.add_child(label)
