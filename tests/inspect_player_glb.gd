extends SceneTree

const MODEL_PATH := "res://assets/characters/male-adult-01.glb"

func _initialize() -> void:
	call_deferred("_inspect_player_asset")

func _inspect_player_asset() -> void:
	if not ResourceLoader.exists(MODEL_PATH):
		push_error("PLAYER_ASSET_DIAGNOSTIC missing_model=" + MODEL_PATH)
		quit(1)
		return

	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		push_error("PLAYER_ASSET_DIAGNOSTIC failed_to_load_scene")
		quit(1)
		return

	var model := packed.instantiate()
	root.add_child(model)
	await process_frame

	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	print("PLAYER_ASSET_DIAGNOSTIC model=", MODEL_PATH,
		" skeletons=", skeletons.size(), " meshes=", meshes.size())

	if skeletons.is_empty() or meshes.is_empty():
		push_error("PLAYER_ASSET_DIAGNOSTIC missing_skeleton_or_mesh")
		quit(1)
		return

	var skeleton := skeletons[0] as Skeleton3D
	var head_index := -1
	var pelvis_index := -1
	for i in range(skeleton.get_bone_count()):
		var bone_name := skeleton.get_bone_name(i).to_lower().replace("_", "").replace(" ", "")
		if bone_name.ends_with("head"):
			head_index = i
		elif bone_name.contains("hips") or bone_name.contains("pelvis"):
			pelvis_index = i

	print("PLAYER_ASSET_DIAGNOSTIC bone_count=", skeleton.get_bone_count(),
		" head_index=", head_index, " pelvis_index=", pelvis_index)
	var head_world := Vector3.ZERO
	var pelvis_world := Vector3.ZERO
	if head_index >= 0:
		var head_rest := skeleton.get_bone_global_rest(head_index)
		head_world = skeleton.to_global(head_rest.origin)
		print("PLAYER_ASSET_HEAD local_rest=", skeleton.get_bone_rest(head_index),
			" skeleton_rest=", head_rest, " world_position=", head_world)
	if pelvis_index >= 0:
		var pelvis_rest := skeleton.get_bone_global_rest(pelvis_index)
		pelvis_world = skeleton.to_global(pelvis_rest.origin)
		print("PLAYER_ASSET_PELVIS local_rest=", skeleton.get_bone_rest(pelvis_index),
			" skeleton_rest=", pelvis_rest, " world_position=", pelvis_world)
	if head_index >= 0 and pelvis_index >= 0:
		var vertical_delta := head_world.y - pelvis_world.y
		var orientation := "UPRIGHT" if vertical_delta > 0.05 else "INVERTED" if vertical_delta < -0.05 else "UNVERIFIED"
		print("PLAYER_ASSET_ORIENTATION=", orientation,
			" head_world_y=", snappedf(head_world.y, 0.001),
			" pelvis_world_y=", snappedf(pelvis_world.y, 0.001),
			" vertical_delta=", snappedf(vertical_delta, 0.001))

	for node in meshes:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		print("PLAYER_ASSET_MESH name=", mesh_instance.name,
			" local_aabb=", mesh_instance.get_aabb(),
			" global_transform=", mesh_instance.global_transform)

	print("PLAYER_ASSET_DIAGNOSTIC_COMPLETE")
	quit(0)
