extends SceneTree

var failures := 0
var total_checks := 0
var test_stage := "تهيئة الاختبارات"
var test_completed := false

func _initialize() -> void:
	call_deferred("_run_tests")
	call_deferred("_watch_test_timeout")

func _watch_test_timeout() -> void:
	await create_timer(60.0).timeout
	if not test_completed:
		push_error("Gameplay test timed out at stage: " + test_stage)
		quit(124)

func _stage(label: String) -> void:
	test_stage = label
	print("TEST STAGE: ", label)

func _check(condition: bool, label: String) -> void:
	total_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func _run_tests() -> void:
	_stage("اختبار حركة اللاعب والحفظ")
	var player := CharacterBody3D.new()
	player.set_script(load("res://scripts/player.gd"))
	player.set("build_visuals", false)
	root.add_child(player)
	await process_frame
	var follow_camera: Camera3D = player.get("camera")
	_check(is_instance_valid(follow_camera) and follow_camera.position.z >= 3.0, "third-person camera keeps the player and nearby world in frame")

	player.call("set_mobile_move", Vector2(0.05, 0.0))
	_check(Vector2(player.get("move_vector")).length() == 0.0, "deadzone ignores tiny joystick drift")

	player.call("set_mobile_move", Vector2(0.5, 0.0))
	var half_strength: float = Vector2(player.get("move_vector")).length()
	_check(half_strength > 0.0 and half_strength < 0.5, "partial joystick tilt produces slow movement")

	player.call("set_mobile_move", Vector2(1.0, 0.0))
	var full_strength: float = Vector2(player.get("move_vector")).length()
	_check(is_equal_approx(full_strength, 1.0), "full joystick tilt reaches full input")

	_check(half_strength < full_strength, "movement input scales progressively")
	_check(float(player.get("acceleration")) < 8.0 and float(player.get("deceleration")) < 13.0, "player movement uses gentler acceleration and braking")
	player.call("set_mobile_move", Vector2(4.0, 0.0))
	_check(is_equal_approx(Vector2(player.get("move_vector")).length(), 1.0), "joystick input is clamped at full tilt")
	player.call("set_mobile_move", Vector2(0.0, 1.0))
	var vertical: Vector2 = player.get("move_vector")
	_check(vertical.x == 0.0 and vertical.y > 0.0, "joystick direction is preserved")

	# Exercise the real touch-control event path. Screen-touch positions are in
	# viewport coordinates and must be transformed into the joystick Control.
	var touch_controls := Node.new()
	touch_controls.set_script(load("res://scripts/mobile_controls.gd"))
	root.add_child(touch_controls)
	var test_stick := Control.new()
	test_stick.position = Vector2(140.0, 120.0)
	test_stick.size = Vector2(138.0, 138.0)
	touch_controls.add_child(test_stick)
	touch_controls.set("stick_base", test_stick)
	touch_controls.set("target", player)
	await process_frame
	var stick_screen_transform: Transform2D = test_stick.get_global_transform_with_canvas()
	var stick_screen_center: Vector2 = stick_screen_transform * (test_stick.size * 0.5)
	var simulated_touch := InputEventScreenTouch.new()
	simulated_touch.index = 7
	simulated_touch.pressed = true
	simulated_touch.position = stick_screen_center + Vector2(46.0, 0.0)
	touch_controls.call("_on_stick_input", simulated_touch)
	_check(Vector2(player.get("move_vector")).x > 0.95 and absf(Vector2(player.get("move_vector")).y) < 0.05, "screen-space joystick touch maps to the correct local direction")
	var simulated_drag := InputEventScreenDrag.new()
	simulated_drag.index = 7
	simulated_drag.position = stick_screen_center + Vector2(0.0, -46.0)
	touch_controls.call("_on_stick_input", simulated_drag)
	_check(Vector2(player.get("move_vector")).y < -0.95 and absf(Vector2(player.get("move_vector")).x) < 0.05, "screen-space joystick drag keeps its local direction")
	var simulated_release := InputEventScreenTouch.new()
	simulated_release.index = 7
	simulated_release.pressed = false
	simulated_release.position = stick_screen_center
	touch_controls.call("_on_stick_input", simulated_release)
	_check(Vector2(player.get("move_vector")) == Vector2.ZERO, "joystick releases to neutral after touch ends")
	touch_controls.queue_free()
	await process_frame
	player.global_position = Vector3(0, 0, -65)
	_check(bool(player.call("is_in_water")), "player enters the sea swimming zone")
	player.call("request_jump")
	player.call("_physics_process", 0.016)
	_check(float(player.get("velocity").y) > 2.0, "mobile jump button propels the player upward while swimming")
	player.global_position = Vector3(0, 0, -40)
	player.call("_physics_process", 0.016)
	_check(not bool(player.call("is_in_water")), "player leaves the swimming zone at the shore")

	player.call("set_mobile_run", true)
	_check(player.get("running") == true, "run button state is accepted")
	player.call("set_mobile_run", false)
	_check(player.get("running") == false, "run button release is accepted")
	player.call("request_jump")
	_check(float(player.get("jump_buffer_time")) >= 0.0 and player.get("jump_requested") == true, "jump input is buffered for responsive landing jumps")
	player.call("toggle_crouch")
	_check(player.get("crouching") == true, "player can enter crouch stance")
	player.call("toggle_crouch")
	_check(player.get("crouching") == false, "player can leave crouch stance")
	# A dedicated dodge-button tap should work while stationary and use facing direction.
	player.global_position = Vector3.ZERO
	player.call("set_mobile_move", Vector2.ZERO)
	player.set("dodge_cooldown", 0.0)
	player.call("request_dodge")
	_check(player.get("dodge_requested") == true, "player accepts a dodge-button tap while standing still")
	player.call("_physics_process", 0.016)
	_check(float(player.get("dodge_time")) > 0.20 and float(player.get("dodge_cooldown")) > 1.0, "stationary dodge starts and applies its cooldown")
	var expected_dodge_direction: Vector3 = -player.global_transform.basis.z
	var actual_dodge_direction: Vector3 = player.get("dodge_direction")
	_check(actual_dodge_direction.dot(expected_dodge_direction.normalized()) > 0.99, "stationary dodge follows the player's facing direction")
	player.call("request_attack")
	var first_attack_time: float = player.get("attack_time")
	player.call("request_attack")
	_check(float(player.get("attack_time")) <= first_attack_time and float(player.get("attack_cooldown")) > 0.0, "melee attack has a cooldown instead of unlimited button spam")

	var saver := Node.new()
	saver.set_script(load("res://scripts/save_manager.gd"))
	root.add_child(saver)
	var sample_progress := {"mahdia_world": {"player_position": [12.5, 0.0, -7.25], "player_rotation_y": 1.2}, "mahdia_life": {"money": 135, "hunger": 72.0}}
	var save_result: Error = saver.call("save_progress", sample_progress)
	_check(save_result == OK, "world progress save returns success")
	var loaded_progress: Dictionary = saver.call("load_progress")
	var loaded_world: Dictionary = loaded_progress.get("mahdia_world", {})
	var loaded_life: Dictionary = loaded_progress.get("mahdia_life", {})
	_check(loaded_world.get("player_position", []) == [12.5, 0.0, -7.25], "player position survives save and load")
	_check(is_equal_approx(float(loaded_world.get("player_rotation_y", 0.0)), 1.2), "player rotation survives save and load")
	_check(int(loaded_life.get("money", 0)) == 135 and is_equal_approx(float(loaded_life.get("hunger", 0.0)), 72.0), "life progress remains in the same save file")

	_stage("اختبار المركبات واللياقة")
	# Exercise the vehicle lifecycle without constructing render meshes in headless CI.
	var car := CharacterBody3D.new()
	car.set_script(load("res://scripts/vehicle.gd"))
	car.set("build_visuals", false)
	root.add_child(car)
	await process_frame
	car.call("enter_vehicle", player)
	_check(car.get("driver") == player, "player can enter the vehicle")
	_check(not player.is_physics_processing(), "player movement is suspended while driving")
	car.call("exit_vehicle")
	_check(car.get("driver") == null, "player can exit the vehicle")
	_check(player.is_physics_processing() and player.visible, "player control and visibility return after exiting")
	var detailed_car := CharacterBody3D.new()
	detailed_car.set_script(load("res://scripts/vehicle.gd"))
	detailed_car.set("build_visuals", false)
	root.add_child(detailed_car)
	await process_frame
	_check(detailed_car.get("wheels").size() == 0, "headless vehicle test skips render-only wheel meshes")
	_check(float(detailed_car.get("braking_deceleration")) > float(detailed_car.get("acceleration")), "vehicle brakes harder than it accelerates")
	_check(float(detailed_car.get("coasting_deceleration")) < float(detailed_car.get("braking_deceleration")), "vehicle coasts down more gently than active braking")
	_check(float(detailed_car.get("max_steering_angle")) > 0.0, "vehicle exposes a bounded front-wheel steering angle")
	_check(detailed_car.get_child_count() == 1 and detailed_car.get_child(0) is CollisionShape3D, "vehicle keeps its collision body when visuals are disabled")
	detailed_car.queue_free()

	var stamina_player := CharacterBody3D.new()
	stamina_player.set_script(load("res://scripts/player.gd"))
	stamina_player.set("build_visuals", false)
	root.add_child(stamina_player)
	await process_frame
	var life := Node.new()
	life.set_script(load("res://scripts/life_manager.gd"))
	life.set("player", stamina_player)
	life.set("base_run_speed", 4.8)
	life.set("base_walk_speed", 2.6)
	root.add_child(life)
	life.set_process(false)
	life.set("energy", 100.0)
	life.call("_apply_stamina", 2.0, true)
	_check(is_equal_approx(float(life.get("energy")), 82.0), "sprinting consumes energy at a predictable rate")
	life.set("energy", 0.0)
	life.call("_apply_stamina", 1.0, true)
	_check(is_equal_approx(float(stamina_player.get("run_speed")), 2.6), "empty energy prevents sprint speed")
	life.call("_apply_stamina", 2.0, false)
	_check(is_equal_approx(float(life.get("energy")), 10.0) and is_equal_approx(float(stamina_player.get("run_speed")), 4.8), "resting restores energy and sprint speed")

	_stage("اختبار السكان والذاكرة والسلوك")
	var resident := CharacterBody3D.new()
	resident.set_script(load("res://scripts/npc.gd"))
	resident.set("build_visuals", false)
	resident.set("personality", "curious")
	resident.set("display_name", "ليلى")
	resident.call("set_ai_context", player, null, Vector3(5, 0, 0), 7, saver)
	root.add_child(resident)
	await process_frame
	_check(not str(resident.get("ai_state")).is_empty(), "NPC starts with an autonomous AI state")
	_stage("إنشاء شخصية مرئية وفحص مفاصلها")
	# Build one rendered resident to verify the new articulated skeleton is present.
	var visual_resident := CharacterBody3D.new()
	visual_resident.set_script(load("res://scripts/npc.gd"))
	visual_resident.set("build_visuals", true)
	visual_resident.call("set_ai_context", player, null, Vector3(8, 0, 0), 12, saver)
	root.add_child(visual_resident)
	await process_frame
	_check(is_instance_valid(visual_resident.get("left_elbow")) and is_instance_valid(visual_resident.get("right_elbow")), "resident arms contain independent elbow joints")
	_check(is_instance_valid(visual_resident.get("left_knee")) and is_instance_valid(visual_resident.get("right_knee")), "resident legs contain independent knee joints")
	_check(is_instance_valid(visual_resident.get("eye_white_left")) and is_instance_valid(visual_resident.get("mouth_visual")), "resident face contains layered eyes and an animated mouth")
	_check(is_instance_valid(visual_resident.get("brow_left")) and is_instance_valid(visual_resident.get("head_visual")), "resident face supports expressive brows and independent head motion")
	_check(float(visual_resident.get("conversation_gesture_elapsed")) >= 0.0, "resident has an independent conversation gesture clock")
	visual_resident.set("ai_state", "socializing")
	var gesture_before := float(visual_resident.get("conversation_gesture_side"))
	visual_resident.call("_animate", 1.5, false)
	_check(float(visual_resident.get("conversation_gesture_side")) != gesture_before, "resident alternates hand gestures during a conversation")
	_check(absf(float(visual_resident.get("left_arm").rotation.x)) > 0.05 or absf(float(visual_resident.get("right_arm").rotation.x)) > 0.05, "conversation animation moves the resident's arms")
	visual_resident.queue_free()
	player.global_position = Vector3(100, 0, 100)
	resident.set("target_position", Vector3(22, 0, 0))
	resident.set("ai_state", "commuting")
	var previous_goal_elapsed := float(resident.get("goal_refresh_elapsed"))
	resident.call("_update_autonomous_decisions", 4.0)
	_check(resident.get("target_position") == Vector3(22, 0, 0), "resident keeps a long-distance destination instead of replacing it every few seconds")
	_check(is_equal_approx(float(resident.get("goal_refresh_elapsed")) - previous_goal_elapsed, 4.0), "daily goal refresh waits for a longer interval while player awareness remains responsive")
	player.global_position = Vector3.ZERO
	resident.call("on_player_interacted")
	_check(int(resident.get("memory_meetings")) == 1, "NPC remembers an individual player meeting")
	_check(float(resident.get("trust")) > 0.0 and float(resident.get("social_need")) < 0.45, "resident relationship and social need react to conversation")
	_check(saver.call("load_progress").get("mahdia_npc_memory", {}).get("resident_07", {}).has("trust"), "resident trust is stored in persistent memory")
	resident.call("_record_experience", "social", "تحدثت مع جار", 0.08)
	resident.call("_reflect_on_experiences")
	_check(resident.get("long_term_memories").size() >= 2, "resident stores separate episodes instead of only counters")
	_check(float(resident.get("learned_preferences").get("social", 0.0)) > 0.0, "resident reflection learns a preference from repeated experiences")
	_check(saver.call("load_progress").get("mahdia_npc_memory", {}).get("resident_07", {}).has("episodic_memories"), "episodic memories and learned preferences persist to disk")
	var returning_resident := CharacterBody3D.new()
	returning_resident.set_script(load("res://scripts/npc.gd"))
	returning_resident.set("build_visuals", false)
	returning_resident.call("set_ai_context", player, null, Vector3(5, 0, 0), 7, saver)
	_check(int(returning_resident.get("memory_meetings")) == 1, "NPC memory persists across recreated game sessions")
	returning_resident.queue_free()
	resident.set("energy", 0.8)
	resident.set("hunger", 0.2)
	resident.set("stress", 0.0)
	resident.set("ai_state", "idle")
	_check(str(resident.call("get_dialogue")).contains("أخبار المهدية"), "NPC dialogue reflects its own personality when basic needs are stable")
	resident.set("social_need", 1.0)
	resident.set("curiosity", 0.1)
	resident.set("energy", 0.8)
	resident.call("_choose_daily_goal", 8.0)
	_check(str(resident.get("ai_state")) == "socializing", "resident chooses social contact when its social need is strongest")
	resident.set("social_need", 0.1)
	resident.set("energy", 0.05)
	resident.call("_choose_daily_goal", 15.0)
	_check(str(resident.get("ai_state")) == "resting", "resident prioritizes recovery when its energy is depleted")
	var nearby_resident := CharacterBody3D.new()
	nearby_resident.set_script(load("res://scripts/npc.gd"))
	nearby_resident.set("build_visuals", false)
	nearby_resident.set("display_name", "سامي")
	nearby_resident.call("set_ai_context", player, null, Vector3(5, 0, 0), 8, saver)
	root.add_child(nearby_resident)
	await process_frame
	nearby_resident.global_position = Vector3(0.8, 0, 0.8)
	resident.set("ai_state", "socializing")
	resident.set("social_need", 0.8)
	resident.call("_update_social_awareness")
	var relationships: Dictionary = resident.get("resident_relationships")
	_check(relationships.has("resident_08"), "NPC recognizes a nearby resident and creates a relationship")
	_check(float(resident.get("social_need")) < 0.8, "nearby conversation reduces social need")
	resident.set("crowd_check_elapsed", 1.0)
	var crowd_direction: Vector3 = resident.call("_avoid_resident_crowding", Vector3(1, 0, 0))
	_check(crowd_direction.x < 0.99 and crowd_direction.z < -0.1 and crowd_direction.length() > 0.9, "pedestrians steer away from nearby residents instead of overlapping")
	var live_observation: Dictionary = resident.call("get_world_observation")
	_check(live_observation.has("weather") and live_observation.has("time_hour") and live_observation.has("nearby_residents"), "resident builds a live observation of weather, time and nearby people")
	_check((live_observation.get("nearby_residents", []) as Array).size() > 0, "resident perception includes nearby individual activity")
	player.global_position = Vector3(100, 0, 100)
	resident.call("_on_ai_thought", resident, "لاحظت أن جاري قريب وأريد التحدث إليه", {"goal": "التواصل مع الجيران", "action": "work", "reason": "حان وقت عملي"}, true)
	_check(str(resident.get("ai_thought")).contains("جاري قريب"), "resident stores an inference returned by the AI model")
	_check(str(resident.get("ai_state")) == "commuting" and resident.get("target_position") == resident.get("work_position"), "AI-selected safe action changes the resident's autonomous destination")
	resident.call("_save_memory")
	_check(str(saver.call("load_progress").get("mahdia_npc_memory", {}).get("resident_07", {}).get("ai_thought", "")).contains("جاري قريب"), "resident preserves its last real-AI thought across sessions")
	player.global_position = Vector3.ZERO
	resident.call("_save_memory")
	_check(saver.call("load_progress").get("mahdia_npc_memory", {}).get("resident_07", {}).get("relationships", {}).has("resident_08"), "NPC-to-NPC familiarity persists in saved memory")
	nearby_resident.queue_free()

	_stage("اختبار الطقس وحركة المرور")
	var weather_system := Node.new()
	weather_system.set_script(load("res://scripts/world_systems.gd"))
	root.add_child(weather_system)
	weather_system.call("set_weather", "ممطر")
	_check(str(weather_system.get("weather")) == "ممطر", "weather system accepts supported weather")
	weather_system.call("set_weather", "ثلوج")
	_check(str(weather_system.get("weather")) == "ممطر", "weather system rejects unsupported weather")

	# Autonomous traffic cars follow the correct road axis and stay inside lane bounds.
	var traffic := CharacterBody3D.new()
	traffic.set_script(load("res://scripts/traffic_car.gd"))
	traffic.set("build_visuals", false)
	root.add_child(traffic)
	traffic.call("configure_traffic", true, -1.65, 0.0, 1.0, 4.0)
	traffic.call("_physics_process", 1.0)
	_check(is_equal_approx(float(traffic.global_position.x), 4.0) and is_equal_approx(float(traffic.global_position.z), -1.65), "traffic car advances along the horizontal road lane")
	traffic.call("configure_traffic", false, 1.65, 10.0, -1.0, 3.0)
	traffic.call("_physics_process", 1.0)
	_check(is_equal_approx(float(traffic.global_position.z), 7.0) and is_equal_approx(float(traffic.global_position.x), 1.65), "traffic car follows the vertical lane in reverse direction")
	traffic.call("configure_traffic", true, -1.65, 77.5, 1.0, 4.0)
	traffic.call("_physics_process", 1.0)
	_check(float(traffic.global_position.x) < -70.0, "traffic car wraps safely at the end of the road")
	traffic.queue_free()

	test_completed = true
	_stage("اكتملت جميع الاختبارات")
	print("Gameplay tests: ", total_checks - failures, "/", total_checks, " passed")
	# Release scene resources before shutting down the headless renderer.
	car.queue_free()
	player.queue_free()
	saver.queue_free()
	weather_system.queue_free()
	resident.queue_free()
	nearby_resident.queue_free()
	life.queue_free()
	stamina_player.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures == 0 else 1)
