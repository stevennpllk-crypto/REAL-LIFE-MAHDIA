extends CharacterBody3D
class_name MahdiaNPC

@export var display_name := "Resident"
@export var walk_speed := 1.2
@export var wander_radius := 7.0
var home_position := Vector3.ZERO
var target_position := Vector3.ZERO
var wait_time := 0.0
var left_arm: Node3D
var right_arm: Node3D
var left_leg: Node3D
var right_leg: Node3D
var clock := 0.0

func _ready() -> void:
	add_to_group("mahdia_residents")
	home_position = global_position
	_choose_target()
	var torso := CapsuleMesh.new()
	torso.radius = 0.29
	torso.height = 0.76
	_part(torso, Vector3(0, 1.12, 0), Color(0.66, 0.39, 0.22))
	var head := SphereMesh.new()
	head.radius = 0.21
	head.height = 0.42
	_part(head, Vector3(0, 1.75, 0), Color(0.67, 0.47, 0.33))
	var hair := SphereMesh.new()
	hair.radius = 0.22
	hair.height = 0.19
	_part(hair, Vector3(0, 1.88, 0), Color(0.12, 0.09, 0.07))
	left_arm = _limb(Vector3(-0.37, 1.25, 0), Color(0.66, 0.39, 0.22), 0.47)
	right_arm = _limb(Vector3(0.37, 1.25, 0), Color(0.66, 0.39, 0.22), 0.47)
	left_leg = _limb(Vector3(-0.16, 0.53, 0), Color(0.13, 0.15, 0.18), 0.62)
	right_leg = _limb(Vector3(0.16, 0.53, 0), Color(0.13, 0.15, 0.18), 0.62)
	var collider := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.75
	collider.shape = shape
	collider.position.y = 0.88
	add_child(collider)

func _part(mesh: Mesh, pos: Vector3, color: Color) -> void:
	var item := MeshInstance3D.new()
	item.mesh = mesh
	item.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	item.material_override = mat
	add_child(item)

func _limb(pos: Vector3, color: Color, length: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	add_child(pivot)
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.11
	mesh.height = length
	var item := MeshInstance3D.new()
	item.mesh = mesh
	item.position.y = -length * 0.35
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	item.material_override = mat
	pivot.add_child(item)
	return pivot

func _choose_target() -> void:
	var angle := randf() * TAU
	var distance := randf_range(2.0, wander_radius)
	target_position = home_position + Vector3(cos(angle) * distance, 0, sin(angle) * distance)
	wait_time = randf_range(1.0, 3.0)

func _physics_process(delta: float) -> void:
	if wait_time > 0.0:
		wait_time -= delta
		_animate(delta, false)
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
	_animate(delta, true)

func _animate(delta: float, moving: bool) -> void:
	if moving:
		clock += delta * 5.0
		var swing := sin(clock) * 0.38
		left_arm.rotation.x = swing
		right_arm.rotation.x = -swing
		left_leg.rotation.x = -swing
		right_leg.rotation.x = swing
	else:
		left_arm.rotation.x = lerpf(left_arm.rotation.x, 0.0, delta * 5.0)
		right_arm.rotation.x = lerpf(right_arm.rotation.x, 0.0, delta * 5.0)
		left_leg.rotation.x = lerpf(left_leg.rotation.x, 0.0, delta * 5.0)
		right_leg.rotation.x = lerpf(right_leg.rotation.x, 0.0, delta * 5.0)
