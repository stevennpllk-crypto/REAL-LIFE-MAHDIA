extends CharacterBody3D
class_name MahdiaNPC

@export var display_name := "Resident"
@export var walk_speed := 1.2
@export var wander_radius := 7.0
var home_position := Vector3.ZERO
var target_position := Vector3.ZERO
var wait_time := 0.0

func _ready() -> void:
	add_to_group("mahdia_residents")
	home_position = global_position
	_choose_target()
	var mesh_instance := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.32
	mesh.height = 1.65
	mesh_instance.mesh = mesh
	mesh_instance.position.y = 0.85
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.42, 0.28)
	mesh_instance.material_override = mat
	add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.32
	shape.height = 1.65
	collision.shape = shape
	collision.position.y = 0.85
	add_child(collision)

func _choose_target() -> void:
	var angle := randf() * TAU
	var distance := randf_range(2.0, wander_radius)
	target_position = home_position + Vector3(cos(angle) * distance, 0, sin(angle) * distance)
	wait_time = randf_range(1.0, 3.0)

func _physics_process(delta: float) -> void:
	if wait_time > 0.0:
		wait_time -= delta
		return
	var direction := target_position - global_position
	direction.y = 0
	if direction.length() < 0.5:
		_choose_target()
		return
	velocity.x = direction.normalized().x * walk_speed
	velocity.z = direction.normalized().z * walk_speed
	rotation.y = atan2(-direction.x, -direction.z)
	move_and_slide()
