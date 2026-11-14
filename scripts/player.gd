extends CharacterBody3D
class_name MahdiaPlayer

@export var walk_speed := 4.2
@export var run_speed := 7.0
@export var jump_velocity := 4.5
@export var mouse_sensitivity := 0.0025
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var move_vector := Vector2.ZERO
var running := false
var jump_requested := false
var interact_requested := false
var camera_pivot: Node3D
var camera: Camera3D
var visual_root: Node3D
var left_arm: Node3D
var right_arm: Node3D
var left_leg: Node3D
var right_leg: Node3D
var animation_clock := 0.0

func _ready() -> void:
	_add_action("move_forward", KEY_W)
	_add_action("move_back", KEY_S)
	_add_action("move_left", KEY_A)
	_add_action("move_right", KEY_D)
	_add_action("run", KEY_SHIFT)
	_add_action("jump", KEY_SPACE)
	_add_action("interact", KEY_E)
	_build_human_figure()
	var collider := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.34
	shape.height = 1.78
	collider.shape = shape
	collider.position.y = 0.9
	add_child(collider)
	camera_pivot = Node3D.new()
	camera_pivot.position.y = 1.52
	add_child(camera_pivot)
	camera = Camera3D.new()
	camera.position = Vector3(0, 1.0, 5.4)
	camera.rotation_degrees.x = -10
	camera.current = true
	camera.fov = 72.0
	camera_pivot.add_child(camera)
	if not OS.has_feature("mobile"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.82
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
	# Casual Tunisian street outfit: shirt, trousers, skin and sneakers.
	var torso := CapsuleMesh.new()
	torso.radius = 0.31
	torso.height = 0.78
	_part(visual_root, torso, Vector3(0, 1.15, 0), Color(0.12, 0.32, 0.68))
	var head := SphereMesh.new()
	head.radius = 0.22
	head.height = 0.44
	_part(visual_root, head, Vector3(0, 1.78, 0), Color(0.68, 0.48, 0.34))
	var hair := SphereMesh.new()
	hair.radius = 0.225
	hair.height = 0.22
	_part(visual_root, hair, Vector3(0, 1.91, -0.015), Color(0.10, 0.075, 0.055))
	left_arm = _make_limb(Vector3(-0.39, 1.28, 0), Color(0.12, 0.32, 0.68), 0.48)
	right_arm = _make_limb(Vector3(0.39, 1.28, 0), Color(0.12, 0.32, 0.68), 0.48)
	left_leg = _make_limb(Vector3(-0.17, 0.55, 0), Color(0.10, 0.12, 0.17), 0.62)
	right_leg = _make_limb(Vector3(0.17, 0.55, 0), Color(0.10, 0.12, 0.17), 0.62)
	_box_shoe(Vector3(-0.17, 0.12, -0.08))
	_box_shoe(Vector3(0.17, 0.12, -0.08)

func _make_limb(pos: Vector3, color: Color, length: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	visual_root.add_child(pivot)
	var limb := CapsuleMesh.new()
	limb.radius = 0.105 if length < 0.55 else 0.13
	limb.height = length
	_part(pivot, limb, Vector3(0, -length * 0.35, 0), color)
	return pivot

func _box_shoe(pos: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.25, 0.13, 0.42)
	_part(visual_root, mesh, pos, Color(0.92, 0.91, 0.86))

func _add_action(action: String, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_pivot.rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clampf(camera.rotation.x, deg_to_rad(-55), deg_to_rad(25))
	if event is InputEventScreenDrag:
		# The joystick owns the left-bottom area; the rest of the screen controls the view.
		if event.position.x > get_viewport().get_visible_rect().size.x * 0.42:
			camera_pivot.rotate_y(-event.relative.x * mouse_sensitivity * 1.8)
			camera.rotate_x(-event.relative.y * mouse_sensitivity * 1.8)
			camera.rotation.x = clampf(camera.rotation.x, deg_to_rad(-55), deg_to_rad(25))
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func set_mobile_move(value: Vector2) -> void:
	move_vector = value.limit_length(1.0)

func set_mobile_run(value: bool) -> void:
	running = value

func request_jump() -> void:
	jump_requested = true

func request_interact() -> void:
	interact_requested = true

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if move_vector.length() > 0.05:
		input_dir = move_vector
	var direction := (camera_pivot.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	direction.y = 0
	var speed := run_speed if (running or Input.is_action_pressed("run")) else walk_speed
	var moving := direction.length() > 0.05
	if moving:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), delta * 10.0)
	else:
		velocity.x = move_toward(velocity.x, 0.0, walk_speed * 5.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, walk_speed * 5.0 * delta)
	if (Input.is_action_just_pressed("jump") or jump_requested) and is_on_floor():
		velocity.y = jump_velocity
	jump_requested = false
	move_and_slide()
	_animate_figure(delta, moving and is_on_floor(), speed)

func _animate_figure(delta: float, moving: bool, speed: float) -> void:
	if not is_instance_valid(visual_root):
		return
	if moving:
		animation_clock += delta * (9.0 if speed > walk_speed + 0.2 else 6.0)
		var swing := sin(animation_clock) * 0.48
		left_arm.rotation.x = swing
		right_arm.rotation.x = -swing
		left_leg.rotation.x = -swing * 0.8
		right_leg.rotation.x = swing * 0.8
	else:
		left_arm.rotation.x = lerpf(left_arm.rotation.x, 0.0, delta * 8.0)
		right_arm.rotation.x = lerpf(right_arm.rotation.x, 0.0, delta * 8.0)
		left_leg.rotation.x = lerpf(left_leg.rotation.x, 0.0, delta * 8.0)
		right_leg.rotation.x = lerpf(right_leg.rotation.x, 0.0, delta * 8.0)
