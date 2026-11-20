extends SceneTree

# Loads the real Main scene and verifies that graphics tiers drive the
# resident/traffic object pools, draw distance and occlusion culling.

var failures := 0
var total_checks := 0

func _initialize() -> void:
	call_deferred("_run")
	call_deferred("_timeout")

func _timeout() -> void:
	await create_timer(80.0).timeout
	push_error("Quality/pooling test timed out")
	quit(124)

func _check(condition: bool, label: String) -> void:
	total_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func _set_tier(world: Node, tier: int) -> void:
	while int(world.get("quality_level")) != tier:
		world.call("_cycle_graphics_quality")
		await process_frame
	await process_frame

func _run() -> void:
	var world: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(world)
	var waited := 0
	while not bool(world.get("world_ready")) and waited < 600:
		await process_frame
		waited += 1
	_check(bool(world.get("world_ready")), "main world finished building")
	_check(int(world.get("building_count")) > 0, "buildings were created with occluders")
	_check(world.get_tree().get_nodes_in_group("mahdia_buildings").size() == int(world.get("building_count")), "every building is registered")
	var occluders := 0
	for b in world.get_tree().get_nodes_in_group("mahdia_buildings"):
		for c in b.get_children():
			if c is OccluderInstance3D and (c as OccluderInstance3D).occluder is BoxOccluder3D:
				occluders += 1
	_check(occluders == int(world.get("building_count")), "one box occluder per building")
	_check(bool(ProjectSettings.get_setting("rendering/occlusion_culling/use_occlusion_culling")), "occlusion culling enabled in project settings")

	var budgets_r := [5, 8, 12]
	var budgets_t := [2, 3, 4]
	var far := [160.0, 220.0, 320.0]
	var detail := [30.0, 55.0, 100.0]
	for tier in [0, 1, 2, 0, 2, 0]:
		await _set_tier(world, tier)
		var status: Dictionary = world.call("get_pool_status")
		_check(int(status.residents_active) == budgets_r[tier], "tier %d active residents = %d" % [tier, budgets_r[tier]])
		_check(int(status.traffic_active) == budgets_t[tier], "tier %d active traffic = %d" % [tier, budgets_t[tier]])
		var cam := world.get_viewport().get_camera_3d()
		_check(cam != null and is_equal_approx(cam.far, far[tier]), "tier %d camera draw distance = %d" % [tier, int(far[tier])])
		var details: Array = world.get("building_detail_meshes")
		_check(details.size() > 0 and is_equal_approx((details[0] as GeometryInstance3D).visibility_range_end, detail[tier]), "tier %d facade detail range = %d" % [tier, int(detail[tier])])
		_check(world.get_viewport().use_occlusion_culling, "tier %d viewport occlusion culling on" % tier)

	var final_status: Dictionary = world.call("get_pool_status")
	_check(int(final_status.created) == 16, "pool never created more than 12 residents + 4 cars")
	_check(int(final_status.reused) > 0, "pooled residents/cars were reused, not rebuilt")
	_check(int(final_status.parked) == (12 - 5) + (4 - 2), "extra residents/cars parked on Low tier")

	root.remove_child(world)
	world.free()
	for i in range(3):
		await process_frame
	print("Quality/pooling tests: %d/%d passed" % [total_checks - failures, total_checks])
	quit(1 if failures > 0 else 0)
