	player.position = START_PLAYER_POSITION
	player.rotation.y = START_PLAYER_ROTATION
	player.name = "Player"
	add_child(player)

func _spawn_residents() -> void:
	# Keep active simulation population proportional to the selected device tier.
	# Residents beyond this budget are not instantiated, avoiding hidden CPU/RAM cost.
	# Place residents on public sidewalks rather than random points that may
	# intersect buildings or spawn directly inside traffic lanes.
	var personalities := [
		"friendly", "shy", "busy", "curious", "grumpy", "friendly",
		"curious", "busy", "friendly", "shy", "curious", "busy"
	]
	var jobs := [
		"fisher", "shopkeeper", "mechanic", "student", "resident", "cook",
		"driver", "beachgoer", "shopkeeper", "student", "fisher", "mechanic"
	]
	var resident_names := [
		"سامي", "مريم", "أيمن", "ليلى", "منير", "آمنة",
		"يوسف", "سارة", "حاتم", "نجلاء", "وليد", "ريم"
	]
	var sidewalk_positions := [
		Vector3(62.0, 0, -44.0), Vector3(57.0, 0, -50.0),
		Vector3(51.0, 0, -44.2), Vector3(46.0, 0, -50.0),
		Vector3(40.0, 0, -44.0), Vector3(35.0, 0, -50.0),
		Vector3(29.0, 0, -44.2), Vector3(24.0, 0, -50.0),
		Vector3(18.0, 0, -44.0), Vector3(13.0, 0, -50.0),
		Vector3(7.0, 0, -44.2), Vector3(2.0, 0, -50.0)
	]
	var resident_budget: int = sidewalk_positions.size()
	for i in range(mini(sidewalk_positions.size(), resident_budget)):
		var npc := CharacterBody3D.new()
		npc.set_script(NPC_SCRIPT)
		npc.position = sidewalk_positions[i]
		npc.display_name = resident_names[i]
		npc.personality = personalities[i]
		npc.occupation = jobs[i]
		var work_spot: Vector3 = sidewalk_positions[i] + Vector3(0, 0, 5.0 if i % 2 == 0 else -5.0)
		npc.set_ai_context(player, world_systems, work_spot, i, save_manager)
		npc.set_ai_service(ai_service)
		add_child(npc)
	var imported_resident_count := 0
	var beachgoer_count := 0
	var resident_nodes := get_tree().get_nodes_in_group("mahdia_residents")
	for resident in resident_nodes:
		if bool(resident.get("imported_model_loaded")):
			imported_resident_count += 1
		if str(resident.get("occupation")) == "beachgoer":
			beachgoer_count += 1
	print("MAHDIA_IMPORTED_RESIDENTS=", imported_resident_count, "/", resident_nodes.size())
	print("MAHDIA_BEACHGOERS=", beachgoer_count, "/", resident_nodes.size())
	if is_instance_valid(life_manager):
		life_manager.call("resolve_delivery_target")

func _spawn_vehicle() -> void:
	vehicle = CharacterBody3D.new()