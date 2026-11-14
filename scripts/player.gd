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

func _ready() -> void:
	_add_action("move_forward", KEY_W)
	_add_action("move_back", KEY_S)
	_add_action("move_left", KEY_A)
	_add_action("move_right", KEY_D)
	_add_action("run", KEY_SHIFT)
	_add_action("jump", KEY_SPACE)
	_add_action("interact", KEY_E)
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.38
	capsule.height = 1.75
	var body_mesh := MeshInstance3D.new()
	body_mesh.mesh = capsule
	body_mesh.position.y = 0.9
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.16, 0.32, 0.62)
	body_mesh.material_override = material
	add_child(body_mesh)
	var collider := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.38
	shape.height = 1.75
	collider.shape = shape
	collider.position.y = 0.9
	add_child(collider)
	camera_pivot = Node3D.new()
	camera_pivot.position.y = 1.55
	add_child(camera_pivot)
	camera = Camera3D.new()
	camera.position = Vector3(0, 1.0, 4.8)
	camera.rotation_degrees.x = -12
	camera.current = true
	camera_pivot.add_child(camera)
	if not OS.has_feature("mobile"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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
	if direction.length() > 0.05:
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
