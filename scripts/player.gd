extends CharacterBody3D
class_name MahdiaPlayer

@export var walk_speed := 2.6
@export var run_speed := 4.8
@export var acceleration := 5.8
@export var deceleration := 9.5
@export var input_deadzone := 0.12
@export var turn_response := 4.8
@export var mobile_camera_sensitivity := 0.00125
@export var jump_velocity := 4.5
@export var mouse_sensitivity := 0.0020
@export var build_visuals := true
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var move_vector := Vector2.ZERO
var running := false
var jump_requested := false
var interact_requested := false
var camera_pivot: Node3D
var camera: Camera3D
var visual_root: Node3D
var imported_player_skeleton: Skeleton3D
var imported_player_bones: Dictionary = {}
var imported_player_loaded := false
var left_arm: Node3D
var right_arm: Node3D
var left_leg: Node3D
var right_leg: Node3D
var left_elbow: Node3D
var right_elbow: Node3D
var left_knee: Node3D
var right_knee: Node3D
var animation_clock := 0.0
var idle_clock := 0.0
var gait_intensity := 0.0
var camera_drag_finger := -1
var is_swimming := false
var crouching := false
var attack_time := 0.0
var attack_cooldown := 0.0
var jump_buffer_time := 0.0
var coyote_time := 0.0
var dodge_requested := false
var dodge_time := 0.0
var dodge_cooldown := 0.0
var dodge_direction := Vector3.ZERO

func _ready() -> void:
	_add_action("move_forward", KEY_W)
	_add_action("move_back", KEY_S)
	_add_action("move_left", KEY_A)
	_add_action("move_right", KEY_D)
	_add_action("run", KEY_SHIFT)
	_add_action("jump", KEY_SPACE)
	_add_action("interact", KEY_E)
	if build_visuals:
		if not _build_imported_player_character():
			_build_human_figure()
	var collider := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.31
	shape.height = 1.78
	collider.shape = shape
	collider.position.y = 0.89
	add_child(collider)
	camera_pivot = Node3D.new()
	camera_pivot.position.y = 1.43
	add_child(camera_pivot)
	camera = Camera3D.new()
	# Reference-image framing: a close, centered third-person follow camera.
	# The slightly narrower lens keeps the player prominent without extreme
	# perspective distortion on a tall mobile display.
	camera.position = Vector3(0.10, 0.30, 1.55)
	camera.rotation_degrees.x = -8.5
	camera.current = true
	camera.fov = 51.0
	camera.near = 0.08
	camera_pivot.add_child(camera)
	if not OS.has_feature("mobile"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build_imported_player_character() -> bool:
	var model_path := "res://assets/characters/male-adult-01.glb"
	if not ResourceLoader.exists(model_path):
		return false
	var packed_model := ResourceLoader.load(model_path) as PackedScene
	if packed_model == null:
		push_warning("Could not load imported player character")
		return false
	visual_root = Node3D.new()
	visual_root.name = "ImportedPlayerVisual"
	add_child(visual_root)
	var model_instance := packed_model.instantiate()
	model_instance.name = "ImportedPlayerHuman"
	visual_root.add_child(model_instance)
	# The supplied Biped GLB uses +Z as its visual forward direction, while
	# CharacterBody3D and the follow camera use -Z. Turn the mesh only, not the
	# controller, so the initial camera sees the player's back and movement stays correct.
	model_instance.rotation.y = PI
	_fit_imported_player_model(model_instance)
	visual_root.scale = Vector3.ONE
	var skeleton_nodes := model_instance.find_children("*", "Skeleton3D", true, false)
	if not skeleton_nodes.is_empty():
		imported_player_skeleton = skeleton_nodes[0] as Skeleton3D
		_cache_imported_player_bones()
		_log_imported_player_orientation()
	imported_player_loaded = true
	var rig_names: Array[String] = []
	if is_instance_valid(imported_player_skeleton):
		for bone_index in range(imported_player_skeleton.get_bone_count()):
			rig_names.append(imported_player_skeleton.get_bone_name(bone_index))
	print("MAHDIA_PLAYER_IMPORTED=1 mapped_bones=", imported_player_bones.size(), " bone_names=", rig_names)
	return true


func _log_imported_player_orientation() -> void:
	if not is_instance_valid(imported_player_skeleton):
		print("MAHDIA_PLAYER_ORIENTATION=UNVERIFIED reason=no_skeleton")
		return
	var head_index := -1
	var hips_index := -1
	for bone_index in range(imported_player_skeleton.get_bone_count()):
		var bone_name := imported_player_skeleton.get_bone_name(bone_index).to_lower().replace("mixamorig:", "").replace("_", "").replace(" ", "")
		if bone_name.ends_with("head"):
			head_index = bone_index
		elif bone_name.contains("hips") or bone_name.contains("pelvis"):
			hips_index = bone_index
	if head_index < 0 or hips_index < 0:
		print("MAHDIA_PLAYER_ORIENTATION=UNVERIFIED head_bone=", head_index, " hips_bone=", hips_index)
		return
	var head_y := imported_player_skeleton.get_bone_global_rest(head_index).origin.y
	var hips_y := imported_player_skeleton.get_bone_global_rest(hips_index).origin.y
	var orientation := "UPRIGHT" if head_y > hips_y + 0.05 else "INVERTED"
	print("MAHDIA_PLAYER_ORIENTATION=", orientation, " head_y=", snappedf(head_y, 0.001), " hips_y=", snappedf(hips_y, 0.001))


func _fit_imported_player_model(model_instance: Node3D) -> void:
	# Imported character GLBs can use different authoring origins and scales.
	# Fit their complete visible mesh bounds to the existing 1.78 m capsule,
	# then put the bottom of the feet exactly on the world floor.
	var mesh_nodes := model_instance.find_children("*", "MeshInstance3D", true, false)
	var model_bounds := AABB()
	var has_bounds := false
	var inverse_root := model_instance.global_transform.affine_inverse()
	for node in mesh_nodes:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var local_bounds := mesh_instance.get_aabb()
		if local_bounds.size.length_squared() < 0.0001:
			continue
		var relative_transform := inverse_root * mesh_instance.global_transform
		for corner_index in range(8):
			var corner := local_bounds.position + Vector3(
				local_bounds.size.x if (corner_index & 1) != 0 else 0.0,
				local_bounds.size.y if (corner_index & 2) != 0 else 0.0,
				local_bounds.size.z if (corner_index & 4) != 0 else 0.0
			)
			var point_in_model := relative_transform * corner
			if not has_bounds:
				model_bounds = AABB(point_in_model, Vector3.ZERO)
				has_bounds = true
			else:
				model_bounds = model_bounds.expand(point_in_model)
	if not has_bounds or model_bounds.size.y < 0.1:
		push_warning("Imported player model has no usable mesh bounds; using source scale")
		return
	var fit_scale := 1.78 / model_bounds.size.y
	model_instance.scale = model_instance.scale * fit_scale
	model_instance.position.y -= model_bounds.position.y * fit_scale
	print("MAHDIA_PLAYER_FIT height=", model_bounds.size.y, " scale=", fit_scale, " offset_y=", model_instance.position.y)


func _cache_imported_player_bones() -> void:
	imported_player_bones.clear()
	if not is_instance_valid(imported_player_skeleton):
		return
	var skeleton := imported_player_skeleton
	for bone_index in range(skeleton.get_bone_count()):
		var bone_name := skeleton.get_bone_name(bone_index).to_lower().replace("mixamorig:", "").replace("_", "").replace(" ", "")
		# Support both Mixamo-style names and the Bip01 naming used by the shipped GLBs.
		if bone_name.contains("lupperarm") or bone_name.ends_with("leftarm") and not bone_name.contains("fore"):
			imported_player_bones["left_arm"] = bone_index
		elif bone_name.contains("rupperarm") or bone_name.ends_with("rightarm") and not bone_name.contains("fore"):
			imported_player_bones["right_arm"] = bone_index
		elif bone_name.contains("lforearm") or bone_name.ends_with("leftforearm"):
			imported_player_bones["left_forearm"] = bone_index
		elif bone_name.contains("rforearm") or bone_name.ends_with("rightforearm"):
			imported_player_bones["right_forearm"] = bone_index
		elif bone_name.contains("lthigh") or bone_name.ends_with("leftupleg"):
			imported_player_bones["left_leg"] = bone_index
		elif bone_name.contains("rthigh") or bone_name.ends_with("rightupleg"):
			imported_player_bones["right_leg"] = bone_index
		elif bone_name.contains("lcalf") or bone_name.ends_with("leftleg"):
			imported_player_bones["left_knee"] = bone_index
		elif bone_name.contains("rcalf") or bone_name.ends_with("rightleg"):
			imported_player_bones["right_knee"] = bone_index
		elif bone_name.contains("lclavicle"):
			imported_player_bones["left_clavicle"] = bone_index
		elif bone_name.contains("rclavicle"):
			imported_player_bones["right_clavicle"] = bone_index
		elif bone_name.contains("lhand") or bone_name.ends_with("lefthand"):
			imported_player_bones["left_hand"] = bone_index
		elif bone_name.contains("rhand") or bone_name.ends_with("righthand"):
			imported_player_bones["right_hand"] = bone_index
		elif bone_name.contains("lfoot") or bone_name.ends_with("leftfoot"):
			imported_player_bones["left_foot"] = bone_index
		elif bone_name.contains("rfoot") or bone_name.ends_with("rightfoot"):
			imported_player_bones["right_foot"] = bone_index
		elif bone_name.ends_with("spine1") or bone_name.ends_with("spine2"):
			if not imported_player_bones.has("spine"):
				imported_player_bones["spine"] = bone_index
		elif bone_name.ends_with("neck"):
			imported_player_bones["neck"] = bone_index
		elif bone_name.ends_with("head"):
			imported_player_bones["head"] = bone_index


func _pose_imported_player_bone(key: String, angle: float) -> void:
	if not is_instance_valid(imported_player_skeleton) or not imported_player_bones.has(key):
		return
	var bone_index := int(imported_player_bones[key])
	var inverse_rest := imported_player_skeleton.get_bone_global_rest(bone_index).basis.inverse()
	var pose_rotation := Quaternion.IDENTITY
	if key == "left_arm" or key == "right_arm":
		# The imported Bip01 rig starts in a T-pose. Rotate each shoulder down
		# around the body's forward axis, then add gait swing around body-up.
		var drop_axis := (inverse_rest * Vector3.BACK).normalized()
		var swing_axis := (inverse_rest * Vector3.UP).normalized()
		# Bip01's local shoulder roll is opposite to the imported Mixamo axis.
		# Negative left / positive right lowers the arms beside the torso.
		# The cached Bip01 rest basis is mirrored across the shoulders. The
		# previous signs lifted both forearms toward the head on Android; reverse
		# the roll so the T-pose settles beside the torso.
		var drop_angle := 1.20 if key == "left_arm" else -1.20
		pose_rotation = Quaternion(drop_axis, drop_angle) * Quaternion(swing_axis, angle)
	elif key == "head" or key == "neck":
		var head_axis := (inverse_rest * Vector3.UP).normalized()
		pose_rotation = Quaternion(head_axis, angle)
	elif key == "spine":
		var spine_axis := (inverse_rest * Vector3.FORWARD).normalized()
		pose_rotation = Quaternion(spine_axis, angle)
	elif key.ends_with("clavicle"):
		var clavicle_axis := (inverse_rest * Vector3.BACK).normalized()
		pose_rotation = Quaternion(clavicle_axis, angle)
	else:
		# Limbs hinge around their local lateral axis.
		var limb_axis := (inverse_rest * Vector3.RIGHT).normalized()
		pose_rotation = Quaternion(limb_axis, angle)
	imported_player_skeleton.set_bone_pose_rotation(bone_index, pose_rotation)


func _mat(color: Color, roughness := 0.82) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return m

func _part(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.mesh = mesh
	item.position = pos
	item.material_override = _mat(color)
	parent.add_child(item)
	return item

func _build_human_figure() -> void:
	visual_root = Node3D.new()
	visual_root.name = "HumanCharacterVisual"
	add_child(visual_root)
	# Proportioned low-poly human silhouette with separate clothing pieces.
	var torso := CylinderMesh.new()
	torso.top_radius = 0.205
	torso.bottom_radius = 0.285
	torso.height = 0.82
	torso.radial_segments = 16
	_part(visual_root, torso, Vector3(0, 1.22, 0), Color(0.035, 0.045, 0.065))
	# Add a fitted collar, front zip, cuffs and subtle fabric panels.
	var collar := TorusMesh.new()
	collar.inner_radius = 0.09
	collar.outer_radius = 0.12
	collar.rings = 16
	collar.ring_segments = 8
	_part(visual_root, collar, Vector3(0, 1.59, -0.012), Color(0.10, 0.12, 0.15))
	var zip := BoxMesh.new()
	zip.size = Vector3(0.012, 0.34, 0.012)
	_part(visual_root, zip, Vector3(0, 1.23, -0.252), Color(0.32, 0.34, 0.37))
	var shirt_panel := BoxMesh.new()
	shirt_panel.size = Vector3(0.12, 0.15, 0.014)
	_part(visual_root, shirt_panel, Vector3(-0.14, 1.30, -0.246), Color(0.07, 0.085, 0.11))
	var shirt_panel_right := BoxMesh.new()
	shirt_panel_right.size = Vector3(0.12, 0.15, 0.014)
	_part(visual_root, shirt_panel_right, Vector3(0.14, 1.30, -0.246), Color(0.07, 0.085, 0.11))
	var neck := CylinderMesh.new()
	neck.top_radius = 0.105
	neck.bottom_radius = 0.12
	neck.height = 0.16
	_part(visual_root, neck, Vector3(0, 1.70, 0), Color(0.65, 0.43, 0.31))
	var head := SphereMesh.new()
	head.radius = 0.205
	head.height = 0.43
	_part(visual_root, head, Vector3(0, 1.88, 0), Color(0.69, 0.48, 0.35))
	var neck_shadow := SphereMesh.new()
	neck_shadow.radius = 0.11
	neck_shadow.height = 0.16
	_part(visual_root, neck_shadow, Vector3(0, 1.70, -0.005), Color(0.62, 0.40, 0.29))
	var hair := SphereMesh.new()
	hair.radius = 0.211
	hair.height = 0.18
	var hair_cap := _part(visual_root, hair, Vector3(0, 2.015, 0.018), Color(0.075, 0.055, 0.045))
	hair_cap.scale = Vector3(1.0, 0.62, 1.0)
	var ear := SphereMesh.new()
	ear.radius = 0.052
	ear.height = 0.13
	_part(visual_root, ear, Vector3(-0.195, 1.87, 0), Color(0.69, 0.48, 0.35))
	_part(visual_root, ear, Vector3(0.195, 1.87, 0), Color(0.69, 0.48, 0.35))
	var brow := CapsuleMesh.new()
	brow.radius = 0.012
	brow.height = 0.075
	var left_brow := _part(visual_root, brow, Vector3(-0.073, 1.94, -0.183), Color(0.075, 0.055, 0.045))
	var right_brow := _part(visual_root, brow, Vector3(0.073, 1.94, -0.183), Color(0.075, 0.055, 0.045))
	left_brow.rotation.z = -0.12
	right_brow.rotation.z = 0.12
	# Eyes and nose face the character's forward direction (-Z).
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.022
	eye_mesh.height = 0.035
	_part(visual_root, eye_mesh, Vector3(-0.073, 1.90, -0.188), Color(0.045, 0.035, 0.03))
	_part(visual_root, eye_mesh, Vector3(0.073, 1.90, -0.188), Color(0.045, 0.035, 0.03))
	var eye_white := SphereMesh.new()
	eye_white.radius = 0.027
	eye_white.height = 0.038
	_part(visual_root, eye_white, Vector3(-0.073, 1.90, -0.181), Color(0.92, 0.88, 0.80))
	_part(visual_root, eye_white, Vector3(0.073, 1.90, -0.181), Color(0.92, 0.88, 0.80))
	var iris := SphereMesh.new()
	iris.radius = 0.013
	iris.height = 0.022
	_part(visual_root, iris, Vector3(-0.073, 1.90, -0.205), Color(0.18, 0.11, 0.07))
	_part(visual_root, iris, Vector3(0.073, 1.90, -0.205), Color(0.18, 0.11, 0.07))
	var nose := SphereMesh.new()
	nose.radius = 0.035
	nose.height = 0.07
	_part(visual_root, nose, Vector3(0, 1.84, -0.205), Color(0.62, 0.40, 0.29))
	var mouth := CapsuleMesh.new()
	mouth.radius = 0.008
	mouth.height = 0.05
	var mouth_item := _part(visual_root, mouth, Vector3(0, 1.78, -0.194), Color(0.25, 0.09, 0.075))
	mouth_item.rotation.z = PI * 0.5
	left_arm = _make_limb(Vector3(-0.31, 1.48, 0), Color(0.055, 0.24, 0.78), 0.66, 0.105)
	right_arm = _make_limb(Vector3(0.31, 1.48, 0), Color(0.055, 0.24, 0.78), 0.66, 0.105)
	left_leg = _make_limb(Vector3(-0.145, 0.78, 0), Color(0.10, 0.12, 0.17), 0.76, 0.125)
	right_leg = _make_limb(Vector3(0.145, 0.78, 0), Color(0.10, 0.12, 0.17), 0.76, 0.125)
	_make_shoe(Vector3(-0.145, 0.095, -0.075))
	_make_shoe(Vector3(0.145, 0.095, -0.075))
	# Visible hands and a wrist watch break the mannequin silhouette.
	var hand_mesh := SphereMesh.new()
	hand_mesh.radius = 0.065
	hand_mesh.height = 0.12
	_part(visual_root, hand_mesh, Vector3(-0.31, 1.00, -0.01), Color(0.69, 0.48, 0.35))
	_part(visual_root, hand_mesh, Vector3(0.31, 1.00, -0.01), Color(0.69, 0.48, 0.35))
	var watch := TorusMesh.new()
	watch.inner_radius = 0.075
	watch.outer_radius = 0.09
	_part(visual_root, watch, Vector3(-0.31, 1.14, 0), Color(0.58, 0.54, 0.42))

func _make_limb(pos: Vector3, color: Color, length: float, radius: float) -> Node3D:
	# Separate upper/lower segments let elbows and knees bend naturally.
	var pivot := Node3D.new()
	pivot.position = pos
	visual_root.add_child(pivot)
	var is_arm := length < 0.7
	var upper_length := length * (0.54 if is_arm else 0.52)
	var lower_length := length - upper_length
	var upper := CapsuleMesh.new()
	upper.radius = radius
	upper.height = upper_length
	_part(pivot, upper, Vector3(0, -upper_length * 0.48, 0), color)
	var joint := Node3D.new()
	joint.position = Vector3(0, -upper_length * 0.92, 0)
	pivot.add_child(joint)
	var joint_mesh := SphereMesh.new()
	joint_mesh.radius = radius * 0.94
	joint_mesh.height = radius * 1.9
	_part(joint, joint_mesh, Vector3.ZERO, color.darkened(0.025))
	var lower := CapsuleMesh.new()
	lower.radius = radius * (0.82 if is_arm else 0.88)
	lower.height = lower_length
	_part(joint, lower, Vector3(0, -lower_length * 0.48, 0), color)
	if is_arm:
		var hand := SphereMesh.new()
		hand.radius = 0.065
		hand.height = 0.12
		_part(joint, hand, Vector3(0, -lower_length * 0.91, -0.01), Color(0.69, 0.48, 0.35))
		if pos.x < 0.0:
			left_elbow = joint
		else:
			right_elbow = joint
	else:
		var shoe := CapsuleMesh.new()
		shoe.radius = 0.105
		shoe.height = 0.25
		var shoe_item := _part(joint, shoe, Vector3(0, -lower_length * 0.93, -0.045), Color(0.045, 0.05, 0.06))
		shoe_item.rotation.x = PI * 0.5
		if pos.x < 0.0:
			left_knee = joint
		else:
			right_knee = joint
	return pivot

func _make_shoe(pos: Vector3) -> void:
	var shoe := CapsuleMesh.new()
	shoe.radius = 0.105
	shoe.height = 0.36
	var item := _part(visual_root, shoe, pos, Color(0.12, 0.13, 0.15))
	item.rotation.x = PI * 0.5
	item.scale = Vector3(1.0, 0.75, 1.0)

func _add_action(action: String, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_rotate_camera(event.relative)
	elif event is InputEventScreenTouch:
		if event.pressed and event.position.x > get_viewport().get_visible_rect().size.x * 0.42 and camera_drag_finger == -1:
			camera_drag_finger = event.index
		elif not event.pressed and event.index == camera_drag_finger:
			camera_drag_finger = -1
	elif event is InputEventScreenDrag and event.index == camera_drag_finger:
		_rotate_camera(event.relative * 0.72)
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _rotate_camera(relative: Vector2) -> void:
	var sensitivity := mobile_camera_sensitivity if OS.has_feature("mobile") or OS.get_name() == "Android" or OS.get_name() == "iOS" else mouse_sensitivity
	camera_pivot.rotate_y(-relative.x * sensitivity)
	camera.rotate_x(-relative.y * sensitivity)
	camera.rotation.x = clampf(camera.rotation.x, deg_to_rad(-48), deg_to_rad(22))

func set_mobile_move(value: Vector2) -> void:
	var magnitude := value.length()
	if magnitude < input_deadzone:
		move_vector = Vector2.ZERO
		return
	var strength := clampf((magnitude - input_deadzone) / (1.0 - input_deadzone), 0.0, 1.0)
	# Smooth analog response: a gentle centre for careful steps and a predictable full-tilt limit.
	strength = smoothstep(0.0, 1.0, strength)
	strength = pow(strength, 1.18)
	move_vector = value.normalized() * strength

func set_mobile_run(value: bool) -> void:
	running = value

func request_jump() -> void:
	jump_requested = true

func request_interact() -> void:
	interact_requested = true

func request_attack() -> void:
	if attack_cooldown > 0.0 or is_swimming or crouching:
		return
	attack_time = 0.42
	attack_cooldown = 0.58


func request_dodge() -> void:
	if dodge_cooldown <= 0.0 and not is_swimming and not crouching:
		dodge_requested = true


func toggle_crouch() -> void:
	crouching = not crouching
	if crouching:
		running = false

func is_in_water() -> bool:
	return global_position.z < -59.0 and absf(global_position.x) < 90.0

func _physics_process(delta: float) -> void:
	is_swimming = is_in_water()
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	dodge_cooldown = maxf(0.0, dodge_cooldown - delta)
	jump_buffer_time = maxf(0.0, jump_buffer_time - delta)
	if is_on_floor():
		coyote_time = 0.12
	else:
		coyote_time = maxf(0.0, coyote_time - delta)
	if Input.is_action_just_pressed("jump") or jump_requested:
		jump_buffer_time = 0.16
	jump_requested = false
	if is_swimming:
		var swim_level := -1.25
		if Input.is_action_just_pressed("jump") or jump_requested:
			velocity.y = 2.8
		else:
			var vertical_target := clampf((swim_level - global_position.y) * 2.0, -1.4, 1.4)
			velocity.y = move_toward(velocity.y, vertical_target, delta * 3.0)
	elif not is_on_floor():
		velocity.y -= gravity * delta
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if move_vector.length() > 0.001:
		input_dir = move_vector
	var strength := clampf(input_dir.length(), 0.0, 1.0)
	var basis := camera_pivot.global_transform.basis
	var forward := -basis.z
	var right := basis.x
	forward.y = 0.0
	right.y = 0.0
	forward = forward.normalized()
	right = right.normalized()
	var direction := (right * input_dir.x - forward * input_dir.y)
	direction.y = 0.0
	direction = direction.normalized()
	var wants_to_run := (running or Input.is_action_pressed("run")) and strength > 0.08 and not crouching
	var speed := (2.8 if wants_to_run else 1.8) if is_swimming else (run_speed if wants_to_run else walk_speed)
	if crouching:
		speed *= 0.48
	attack_time = maxf(0.0, attack_time - delta)
	var target_speed := speed * strength
	var moving := strength > 0.01
	if moving:
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), 1.0 - exp(-turn_response * delta))
	var desired_velocity := direction * target_speed
	var rate := acceleration if moving else deceleration
	# Brake harder when reversing direction to avoid the skating / instant-snap feel.
	if moving and Vector2(velocity.x, velocity.z).dot(Vector2(desired_velocity.x, desired_velocity.z)) < -0.05:
		rate *= 1.65
	velocity.x = move_toward(velocity.x, desired_velocity.x, rate * delta)
	velocity.z = move_toward(velocity.z, desired_velocity.z, rate * delta)
	if not is_swimming and jump_buffer_time > 0.0 and coyote_time > 0.0:
		velocity.y = jump_velocity
		jump_buffer_time = 0.0
		coyote_time = 0.0
	if dodge_requested:
		dodge_requested = false
		if strength > 0.08 and dodge_cooldown <= 0.0 and not is_swimming and not crouching:
			dodge_direction = direction if moving else -global_transform.basis.z
			dodge_direction.y = 0.0
			dodge_direction = dodge_direction.normalized()
			dodge_time = 0.24
			dodge_cooldown = 1.25
	if dodge_time > 0.0:
		dodge_time = maxf(0.0, dodge_time - delta)
		var dodge_speed := 5.8 * clampf(dodge_time / 0.24, 0.72, 1.0)
		velocity.x = dodge_direction.x * dodge_speed
		velocity.z = dodge_direction.z * dodge_speed
	move_and_slide()
	_animate_figure(delta, moving and is_on_floor(), speed)

func _animate_imported_player(delta: float, moving: bool, speed: float) -> void:
	if attack_time > 0.0:
		_pose_imported_player_bone("right_arm", 0.28)
		_pose_imported_player_bone("left_arm", -0.08)
		_pose_imported_player_bone("right_forearm", -0.72)
		_pose_imported_player_bone("left_forearm", -0.12)
	elif moving:
		animation_clock += delta * (10.0 if running or Input.is_action_pressed("run") else 6.2)
		gait_intensity = move_toward(gait_intensity, 1.0, delta * 3.5)
		var actual_speed := Vector2(velocity.x, velocity.z).length()
		var gait_scale := clampf(actual_speed / maxf(speed, 0.1), 0.35, 1.0)
		var swing := sin(animation_clock) * 0.46 * gait_intensity * gait_scale
		var torso_sway := sin(animation_clock * 0.5) * 0.035
		_pose_imported_player_bone("spine", -0.025 + torso_sway + (0.035 if running else 0.0))
		_pose_imported_player_bone("left_clavicle", torso_sway)
		_pose_imported_player_bone("right_clavicle", -torso_sway)
		_pose_imported_player_bone("neck", -0.018 if running else 0.0)
		_pose_imported_player_bone("left_arm", swing + torso_sway)
		_pose_imported_player_bone("right_arm", -swing - torso_sway)
		_pose_imported_player_bone("left_forearm", -0.10 - maxf(0.0, swing) * 0.18)
		_pose_imported_player_bone("right_forearm", -0.10 - maxf(0.0, -swing) * 0.18)
		_pose_imported_player_bone("left_hand", sin(animation_clock + 0.4) * 0.07)
		_pose_imported_player_bone("right_hand", -sin(animation_clock + 0.4) * 0.07)
		_pose_imported_player_bone("left_leg", -swing * (1.0 if not is_swimming else 0.28))
		_pose_imported_player_bone("right_leg", swing * (1.0 if not is_swimming else 0.28))
		_pose_imported_player_bone("left_knee", maxf(0.0, swing) * 0.42)
		_pose_imported_player_bone("right_knee", maxf(0.0, -swing) * 0.42)
		_pose_imported_player_bone("left_foot", -maxf(0.0, swing) * 0.18)
		_pose_imported_player_bone("right_foot", -maxf(0.0, -swing) * 0.18)
	else:
		gait_intensity = move_toward(gait_intensity, 0.0, delta * 5.0)
		idle_clock += delta
		var breath := sin(idle_clock * 1.35) * 0.018
		var relaxed_sway := sin(idle_clock * 0.52) * 0.012
		_pose_imported_player_bone("spine", breath)
		_pose_imported_player_bone("left_clavicle", relaxed_sway)
		_pose_imported_player_bone("right_clavicle", -relaxed_sway)
		_pose_imported_player_bone("neck", sin(idle_clock * 0.7) * 0.012)
		_pose_imported_player_bone("left_arm", breath)
		_pose_imported_player_bone("right_arm", breath)
		_pose_imported_player_bone("left_forearm", -0.04)
		_pose_imported_player_bone("right_forearm", -0.04)
		_pose_imported_player_bone("left_hand", sin(idle_clock) * 0.015)
		_pose_imported_player_bone("right_hand", -sin(idle_clock) * 0.015)
		_pose_imported_player_bone("left_leg", 0.0)
		_pose_imported_player_bone("right_leg", 0.0)
		_pose_imported_player_bone("left_knee", 0.0)
		_pose_imported_player_bone("right_knee", 0.0)
		_pose_imported_player_bone("left_foot", 0.0)
		_pose_imported_player_bone("right_foot", 0.0)
		_pose_imported_player_bone("head", sin(idle_clock * 0.7) * 0.018)
	var run_lean := -0.055 if running else -0.018
	var swim_lean := 0.20 if is_swimming else 0.0
	var crouch_lean := 0.13 if crouching else 0.0
	visual_root.rotation.x = lerpf(visual_root.rotation.x, run_lean + swim_lean + crouch_lean, delta * 5.0)
	visual_root.scale.y = lerpf(visual_root.scale.y, 0.84 if crouching else 1.0, delta * 6.0)
	visual_root.position.y = lerpf(visual_root.position.y, 0.0 if moving else sin(idle_clock * 1.35) * 0.006, delta * 6.0)


func _animate_figure(delta: float, moving: bool, speed: float) -> void:
	if not is_instance_valid(visual_root):
		return
	if imported_player_loaded:
		_animate_imported_player(delta, moving, speed)
		return
	if attack_time > 0.0:
		right_arm.rotation.x = lerpf(right_arm.rotation.x, -1.45, delta * 16.0)
		left_arm.rotation.x = lerpf(left_arm.rotation.x, -0.22, delta * 10.0)
		return
	if moving:
		animation_clock += delta * (10.0 if running or Input.is_action_pressed("run") else 6.2)
		gait_intensity = move_toward(gait_intensity, 1.0, delta * 3.5)
		var actual_speed := Vector2(velocity.x, velocity.z).length()
		var gait_scale := clampf(actual_speed / maxf(speed, 0.1), 0.35, 1.0)
		var swing := sin(animation_clock) * 0.42 * gait_intensity * gait_scale
		left_arm.rotation.x = swing
		right_arm.rotation.x = -swing
		left_leg.rotation.x = -swing * (0.92 if not is_swimming else 0.35)
		right_leg.rotation.x = swing * (0.92 if not is_swimming else 0.35)
		if is_instance_valid(visual_root):
			var run_lean := -0.055 if running else -0.018
			var swim_lean := 0.20 if is_swimming else 0.0
			var crouch_lean := 0.13 if crouching else 0.0
			visual_root.rotation.x = lerpf(visual_root.rotation.x, run_lean + swim_lean + crouch_lean, delta * 5.0)
			visual_root.scale.y = lerpf(visual_root.scale.y, 0.84 if crouching else 1.0, delta * 6.0)
		if is_instance_valid(left_elbow): left_elbow.rotation.x = -0.10 - maxf(0.0, swing) * 0.18
		if is_instance_valid(right_elbow): right_elbow.rotation.x = -0.10 + minf(0.0, swing) * 0.18
		if is_instance_valid(left_knee): left_knee.rotation.x = maxf(0.0, swing) * 0.38
		if is_instance_valid(right_knee): right_knee.rotation.x = maxf(0.0, -swing) * 0.38
	else:
		gait_intensity = move_toward(gait_intensity, 0.0, delta * 5.0)
		idle_clock += delta
		var breath := sin(idle_clock * 1.35) * 0.018
		left_arm.rotation.x = lerpf(left_arm.rotation.x, breath, delta * 5.0)
		right_arm.rotation.x = lerpf(right_arm.rotation.x, breath, delta * 5.0)
		left_leg.rotation.x = lerpf(left_leg.rotation.x, 0.0, delta * 8.0)
		right_leg.rotation.x = lerpf(right_leg.rotation.x, 0.0, delta * 8.0)
		if is_instance_valid(left_elbow): left_elbow.rotation.x = lerpf(left_elbow.rotation.x, -0.08, delta * 4.0)
		if is_instance_valid(right_elbow): right_elbow.rotation.x = lerpf(right_elbow.rotation.x, -0.08, delta * 4.0)
		if is_instance_valid(left_knee): left_knee.rotation.x = lerpf(left_knee.rotation.x, 0.0, delta * 8.0)
		if is_instance_valid(right_knee): right_knee.rotation.x = lerpf(right_knee.rotation.x, 0.0, delta * 8.0)
		visual_root.rotation.x = lerpf(visual_root.rotation.x, 0.0, delta * 4.0)
		visual_root.scale.y = lerpf(visual_root.scale.y, 1.0, delta * 5.0)
	visual_root.position.y = lerpf(visual_root.position.y, 0.0 if moving else sin(idle_clock * 1.35) * 0.006, delta * 6.0)
