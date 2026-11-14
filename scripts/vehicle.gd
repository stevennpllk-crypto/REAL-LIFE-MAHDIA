extends CharacterBody3D
class_name MahdiaVehicle

@export var acceleration := 9.0
@export var max_speed := 15.0
@export var turn_speed := 1.45
var driver: CharacterBody3D
var speed := 0.0
var wheels: Array[MeshInstance3D] = []

func _ready() -> void:
	_build_car()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0, 1.45, 3.8)
	collision.shape = shape
	collision.position.y = 0.72
	add_child(collision)

func _mat(color: Color, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.38
	return material

func _box(size: Vector3, pos: Vector3, color: Color, metallic := 0.0) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	item.mesh = mesh
	item.position = pos
	item.material_override = _mat(color, metallic)
	add_child(item)
	return item

func _build_car() -> void:
	var paint := Color(0.72, 0.12, 0.08)
	var glass := _mat(Color(0.10, 0.22, 0.29), 0.25)
	_box(Vector3(1.92, 0.58, 3.65), Vector3(0, 0.66, 0), paint, 0.35)
	_box(Vector3(1.58, 0.78, 1.85), Vector3(0, 1.27, -0.18), Color(0.78, 0.16, 0.10), 0.3)
	_box(Vector3(1.48, 0.55, 0.06), Vector3(0, 1.34, -1.12), Color(0.11, 0.23, 0.29))
	_box(Vector3(1.48, 0.52, 0.06), Vector3(0, 1.34, 0.76), Color(0.11, 0.23, 0.29))
	_box(Vector3(0.06, 0.52, 0.78), Vector3(-0.79, 1.34, -0.18), Color(0.12, 0.25, 0.31))
	_box(Vector3(0.06, 0.52, 0.78), Vector3(0.79, 1.34, -0.18), Color(0.12, 0.25, 0.31))
	_box(Vector3(2.0, 0.16, 0.18), Vector3(0, 0.48, -1.83), Color(0.22, 0.23, 0.24), 0.5)
	_box(Vector3(2.0, 0.16, 0.18), Vector3(0, 0.48, 1.83), Color(0.22, 0.23, 0.24), 0.5)
	for side in [-1.0, 1.0]:
		_box(Vector3(0.32, 0.18, 0.42), Vector3(side * 0.66, 0.91, -1.78), Color(0.96, 0.88, 0.63), 0.2)
		_box(Vector3(0.32, 0.18, 0.42), Vector3(side * 0.66, 0.91, 1.78), Color(0.72, 0.025, 0.018))
		_box(Vector3(0.10, 0.10, 0.22), Vector3(side * 1.0, 1.03, -0.15), Color(0.88, 0.88, 0.82))
		for z in [-1.22, 1.22]:
			var wheel := MeshInstance3D.new()
			var wheel_mesh := CylinderMesh.new()
			wheel_mesh.top_radius = 0.39
			wheel_mesh.bottom_radius = 0.39
			wheel_mesh.height = 0.22
			wheel.mesh = wheel_mesh
			wheel.position = Vector3(side * 0.98, 0.42, z)
			wheel.rotation_degrees.z = 90
			wheel.material_override = _mat(Color(0.045, 0.05, 0.055))
			add_child(wheel)
			wheels.append(wheel)
			var hub := MeshInstance3D.new()
			var hub_mesh := CylinderMesh.new()
			hub_mesh.top_radius = 0.17
			hub_mesh.bottom_radius = 0.17
			hub_mesh.height = 0.235
			hub.mesh = hub_mesh
			hub.position = wheel.position
			hub.rotation_degrees.z = 90
			hub.material_override = _mat(Color(0.58, 0.60, 0.62), 0.8)
			add_child(hub)

func _physics_process(delta: float) -> void:
	if driver == null:
		return
	var throttle := Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	var steering := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var touch_value: Variant = driver.get("move_vector")
	if touch_value is Vector2 and touch_value.length() > 0.05:
		var touch_input: Vector2 = touch_value
		throttle = -touch_input.y
		steering = touch_input.x
	speed = move_toward(speed, throttle * max_speed, acceleration * delta)
	rotation.y -= steering * turn_speed * delta * clampf(absf(speed) / 4.0, 0.0, 1.0)
	velocity = -global_transform.basis.z * speed
	velocity.y -= 9.8 * delta
	move_and_slide()
	for wheel in wheels:
		wheel.rotate_object_local(Vector3(0, 0, 1), speed * delta / 0.39)
	driver.global_position = global_position + Vector3(0, 1.8, 0)
	if Input.is_action_just_pressed("interact"):
		exit_vehicle()

func enter_vehicle(player: CharacterBody3D) -> void:
	if driver != null:
		return
	driver = player
	driver.visible = false
	driver.set_physics_process(false)

func exit_vehicle() -> void:
	if driver == null:
		return
	driver.visible = true
	driver.global_position = global_position + global_transform.basis.x * 2.0 + Vector3.UP
	driver.set_physics_process(true)
	driver = null
	speed = 0.0
