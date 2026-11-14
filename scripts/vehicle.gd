extends CharacterBody3D
class_name MahdiaVehicle

@export var acceleration := 10.0
@export var max_speed := 18.0
@export var turn_speed := 1.8
var driver: CharacterBody3D
var speed := 0.0

func _ready() -> void:
	var body := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.0, 0.8, 3.8)
	body.mesh = mesh
	body.position.y = 0.75
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.32, 0.68)
	body.material_override = mat
	add_child(body)
	var cabin := MeshInstance3D.new()
	var cabin_mesh := BoxMesh.new()
	cabin_mesh.size = Vector3(1.65, 0.65, 1.7)
	cabin.mesh = cabin_mesh
	cabin.position = Vector3(0, 1.42, -0.15)
	cabin.material_override = mat
	add_child(cabin)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0, 1.5, 3.8)
	collision.shape = shape
	collision.position.y = 0.75
	add_child(collision)

func _physics_process(delta: float) -> void:
	if driver == null:
		return
	var throttle := Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	var steering := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	# Reuse the on-screen joystick while the player is driving.
	if driver != null and "move_vector" in driver:
		var touch_input: Vector2 = driver.get("move_vector")
		if touch_input.length() > 0.05:
			throttle = -touch_input.y
			steering = touch_input.x
	speed = move_toward(speed, throttle * max_speed, acceleration * delta)
	rotation.y -= steering * turn_speed * delta * clampf(absf(speed) / 5.0, 0.0, 1.0)
	velocity = -global_transform.basis.z * speed
	velocity.y -= 9.8 * delta
	move_and_slide()
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
