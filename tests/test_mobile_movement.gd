extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run_tests")

func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func _run_tests() -> void:
	var player := CharacterBody3D.new()
	player.set_script(load("res://scripts/player.gd"))
	player.set("build_visuals", false)
	root.add_child(player)
	await process_frame

	player.call("set_mobile_move", Vector2(0.05, 0.0))
	_check(Vector2(player.get("move_vector")).length() == 0.0, "deadzone ignores tiny joystick drift")

	player.call("set_mobile_move", Vector2(0.5, 0.0))
	var half_strength: float = Vector2(player.get("move_vector")).length()
	_check(half_strength > 0.0 and half_strength < 0.5, "partial joystick tilt produces slow movement")

	player.call("set_mobile_move", Vector2(1.0, 0.0))
	var full_strength: float = Vector2(player.get("move_vector")).length()
	_check(is_equal_approx(full_strength, 1.0), "full joystick tilt reaches full input")

	_check(half_strength < full_strength, "movement input scales progressively")
	player.call("set_mobile_move", Vector2(0.0, 1.0))
	var vertical: Vector2 = player.get("move_vector")
	_check(vertical.x == 0.0 and vertical.y > 0.0, "joystick direction is preserved")
	player.global_position = Vector3(0, 0, -65)
	_check(bool(player.call("is_in_water")), "player enters the sea swimming zone")
	player.global_position = Vector3(0, 0, -40)
	_check(not bool(player.call("is_in_water")), "player leaves the swimming zone at the shore")

	player.call("set_mobile_run", true)
	_check(player.get("running") == true, "run button state is accepted")
	player.call("set_mobile_run", false)
	_check(player.get("running") == false, "run button release is accepted")

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

	var weather_system := Node.new()
	weather_system.set_script(load("res://scripts/world_systems.gd"))
	root.add_child(weather_system)
	weather_system.call("set_weather", "ممطر")
	_check(str(weather_system.get("weather")) == "ممطر", "weather system accepts supported weather")
	weather_system.call("set_weather", "ثلوج")
	_check(str(weather_system.get("weather")) == "ممطر", "weather system rejects unsupported weather")

	print("Gameplay tests: ", 18 - failures, "/18 passed")
	# Release scene resources before shutting down the headless renderer.
	car.queue_free()
	player.queue_free()
	saver.queue_free()
	weather_system.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
