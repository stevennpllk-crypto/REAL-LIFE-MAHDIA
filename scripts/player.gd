extends CharacterBody3D
class_name MahdiaPlayer

@export var walk_speed := 2.6
@export var run_speed := 4.8
@export var acceleration := 8.0
@export var deceleration := 13.0
@export var input_deadzone := 0.14
@export var jump_velocity := 4.5
@export var mouse_sensitivity := 0.0020
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
var camera_drag_finger := -1
var is_swimming := false

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
	shape.radius = 0.31
	shape.height = 1.78
	collider.shape = shape
	collider.position.y = 0.89
	add_child(collider)
	camera_pivot = Node3D.new()
	camera_pivot.position.y = 1.48
	add_child(camera_pivot)
	camera = Camera3D.new()
	camera.position = Vector3(0, 1.0, 5.8)
	camera.rotation_degrees.x = 12.0
	camera.current = true
	camera.fov = 68.0
	camera.near = 0.08
	camera_pivot.add_child(camera)
	if not OS.has_feature("mobile"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _mat(color: Color, roughness := 0.82) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
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
	var torso := CapsuleMesh.new()
	torso.radius = 0.265
	torso.height = 0.82
	_part(visual_root, torso, Vector3(0, 1.22, 0), Color(0.055, 0.24, 0.78))
	var neck := CylinderMesh.new()
	neck.top_radius = 0.105
	neck.bottom_radius = 0.12
	neck.height = 0.16
	_part(visual_root, neck, Vector3(0, 1.70, 0), Color(0.65, 0.43, 0.31))
	var head := SphereMesh.new()
	head.radius = 0.205
	head.height = 0.43
	_part(visual_root, head, Vector3(0, 1.88, 0), Color(0.69, 0.48, 0.35))
	var hair := SphereMesh.new()
	hair.radius = 0.211
	hair.height = 0.18
	_part(visual_root, hair, Vector3(0, 2.015, 0.018), Color(0.075, 0.055, 0.045))
	# Eyes and nose face the character's forward direction (-Z).
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.022
	eye_mesh.height = 0.035
	_part(visual_root, eye_mesh, Vector3(-0.073, 1.90, -0.188), Color(0.045, 0.035, 0.03))
	_part(visual_root, eye_mesh, Vector3(0.073, 1.90, -0.188), Color(0.045, 0.035, 0.03))
	var nose := SphereMesh.new()
	nose.radius = 0.035
	nose.height = 0.07
	_part(visual_root, nose, Vector3(0, 1.84, -0.205), Color(0.62, 0.40, 0.29))
	left_arm = _make_limb(Vector3(-0.31, 1.48, 0), Color(0.055, 0.24, 0.78), 0.66, 0.105)
	right_arm = _make_limb(Vector3(0.31, 1.48, 0), Color(0.055, 0.24, 0.78), 0.66, 0.105)
	left_leg = _make_limb(Vector3(-0.145, 0.78, 0), Color(0.10, 0.12, 0.17), 0.76, 0.125)
	right_leg = _make_limb(Vector3(0.145, 0.78, 0), Color(0.10, 0.12, 0.17), 0.76, 0.125)
	_make_shoe(Vector3(-0.145, 0.095, -0.075))
	_make_shoe(Vector3(0.145, 0.095, -0.075))

func _make_limb(pos: Vector3, color: Color, length: float, radius: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	visual_root.add_child(pivot)
	var limb := CapsuleMesh.new()
	limb.radius = radius
	limb.height = length
	_part(pivot, limb, Vector3(0, -length * 0.34, 0), color)
	return pivot

func _make_shoe(pos: Vector3) -> void:
	var shoe := BoxMesh.new()
	shoe.size = Vector3(0.25, 0.14, 0.39)
	_part(visual_root, shoe, pos, Color(0.90, 0.89, 0.83))

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
	camera_pivot.rotate_y(-relative.x * mouse_sensitivity)
	camera.rotate_x(-relative.y * mouse_sensitivity)
	camera.rotation.x = clampf(camera.rotation.x, deg_to_rad(-48), deg_to_rad(22))

func set_mobile_move(value: Vector2) -> void:
	var magnitude := value.length()
	if magnitude < input_deadzone:
		move_vector = Vector2.ZERO
		return
	var strength := clampf((magnitude - input_deadzone) / (1.0 - input_deadzone), 0.0, 1.0)
	# Gentle response near the center gives precise walking; full tilt still reaches full speed.
	strength = pow(strength, 1.55)
	move_vector = value.normalized() * strength

func set_mobile_run(value: bool) -> void:
	running = value

func request_jump() -> void:
	jump_requested = true

func request_interact() -> void:
	interact_requested = true

func _physics_process(delta: float) -> void:
	is_swimming = global_position.z < -59.0 and absf(global_position.x) < 90.0
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
	var speed := (2.8 if (running or Input.is_action_pressed("run")) else 1.8) if is_swimming else (run_speed if (running or Input.is_action_pressed("run")) else walk_speed)
	var target_speed := speed * strength
	var moving := strength > 0.01
	if moving:
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), delta * 6.0)
	var desired_velocity := direction * target_speed
	var rate := acceleration if moving else deceleration
	velocity.x = move_toward(velocity.x, desired_velocity.x, rate * delta)
	velocity.z = move_toward(velocity.z, desired_velocity.z, rate * delta)
	if not is_swimming and (Input.is_action_just_pressed("jump") or jump_requested) and is_on_floor():
		velocity.y = jump_velocity
	jump_requested = false
	move_and_slide()
	_animate_figure(delta, moving and is_on_floor(), speed)

func _animate_figure(delta: float, moving: bool, speed: float) -> void:
	if not is_instance_valid(visual_root):
		return
	if moving:
		animation_clock += delta * (9.0 if speed > walk_speed + 0.2 else 6.0)
		var swing := sin(animation_clock) * 0.42
		left_arm.rotation.x = swing
		right_arm.rotation.x = -swing
		left_leg.rotation.x = -swing * 0.85
		right_leg.rotation.x = swing * 0.85
	else:
		left_arm.rotation.x = lerpf(left_arm.rotation.x, 0.0, delta * 8.0)
		right_arm.rotation.x = lerpf(right_arm.rotation.x, 0.0, delta * 8.0)
		left_leg.rotation.x = lerpf(left_leg.rotation.x, 0.0, delta * 8.0)
		right_leg.rotation.x = lerpf(right_leg.rotation.x, 0.0, delta * 8.0)
