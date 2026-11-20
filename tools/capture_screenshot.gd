extends SceneTree

# Renders the real Main scene with a real (non-dummy) renderer and saves a PNG.
# Usage (needs a display, e.g. xvfb-run):
#   godot --path . --rendering-method mobile --script res://tools/capture_screenshot.gd -- out.png [tier] [seconds]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://corniche.png"
	var tier := int(args[1]) if args.size() > 1 else 2
	var seconds := float(args[2]) if args.size() > 2 else 3.0
	# Show the phone touch controls on desktop for an accurate HUD capture.
	root.set_meta("mahdia_force_touch_ui", true)
	var world: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(world)
	var waited := 0
	while not bool(world.get("world_ready")) and waited < 2000:
		await process_frame
		waited += 1
	while int(world.get("quality_level")) != tier:
		world.call("_cycle_graphics_quality")
		await process_frame
	if world.has_method("reset_view_for_capture"):
		world.call("reset_view_for_capture")
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	var err := image.save_png(out)
	print("MAHDIA_SCREENSHOT=", out, " err=", err, " size=", image.get_size(), " tier=", tier)
	quit(0 if err == OK else 1)
