extends CharacterBody3D
class_name MahdiaNPC

@export var display_name := "Resident"
@export var walk_speed := 1.15
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
	var palette := [Color(0.72, 0.25, 0.16), Color(0.12, 0.42, 0.36), Color(0.82, 0.62, 0.18), Color(0.24, 0.34, 0.62), Color(0.62, 0.35, 0.22)]
	var shirt: Color = palette[randi_range(0, palette.size() - 1)]
	_part(_capsule(0.255, 0.78), Vector3(0, 1.19, 0), shirt)
	_part(_sphere(0.19, 0.40), Vector3(0, 1.84, 0), Color(0.68, 0.47, 0.34))
	_part(_sphere(0.198, 0.17), Vector3(0, 1.97, 0.015), Color(0.09, 0.065, 0.05))
	_part(_sphere(0.022, 0.03), Vector3(-0.068, 1.86, -0.175), Color(0.035, 0.025, 0.02))
	_part(_sphere(0.022, 0.03), Vector3(0.068, 1.86, -0.175), Color(0.035, 0.025, 0.02))
	left_arm = _limb(Vector3(-0.30, 1.43, 0), shirt, 0.62, 0.10)
	right_arm = _limb(Vector3(0.30, 1.43, 0), shirt, 0.62, 0.10)
	left_leg = _limb(Vector3(-0.14, 0.76, 0), Color(0.12, 0.14, 0.18), 0.72, 0.12)
	right_leg = _limb(Vector3(0.14, 0.76, 0), Color(0.12, 0.14, 0.18), 0.72, 0.12)
	var collider := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.29
	shape.height = 1.72
	collider.shape = shape
	collider.position.y = 0.86
	add_child(collider)

func _capsule(radius: float, height: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	return mesh

func _sphere(radius: float, height: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	return mesh

func _part(mesh: Mesh, pos: Vector3, color: Color) -> void:
	var item := MeshInstance3D.new()
	item.mesh = mesh
	item.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.84
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	item.material_override = mat
	add_child(item)

func _limb(pos: Vector3, color: Color, length: float, radius: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	add_child(pivot)
	_part_to(pivot, _capsule(radius, length), Vector3(0, -length * 0.34, 0), color)
	return pivot

func _part_to(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color) -> void:
	var item := MeshInstance3D.new()
	item.mesh = mesh
	item.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	item.material_override = mat
	parent.add_child(item)

func _choose_target() -> void:
	var angle := randf() * TAU
	var distance := randf_range(2.0, wander_radius)
	target_position = home_position + Vector3(cos(angle) * distance, 0, sin(angle) * distance)
	wait_time = randf_range(1.0, 3.0)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	if wait_time > 0.0:
		wait_time -= delta
		velocity.x = move_toward(velocity.x, 0.0, walk_speed * delta * 4.0)
		velocity.z = move_toward(velocity.z, 0.0, walk_speed * delta * 4.0)
		move_and_slide()
		_animate(delta, false)
		return
	var direction := target_position - global_position
	direction.y = 0
	if direction.length() < 0.5:
		_choose_target()
		return
	velocity.x = direction.normalized().x * walk_speed
	velocity.z = direction.normalized().z * walk_speed
	rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), delta * 4.0)
	move_and_slide()
	_animate(delta, true)

func _animate(delta: float, moving: bool) -> void:
	if moving:
		clock += delta * 5.0
		var swing := sin(clock) * 0.34
		left_arm.rotation.x = swing
		right_arm.rotation.x = -swing
		left_leg.rotation.x = -swing
		right_leg.rotation.x = swing
	else:
		left_arm.rotation.x = lerpf(left_arm.rotation.x, 0.0, delta * 5.0)
		right_arm.rotation.x = lerpf(right_arm.rotation.x, 0.0, delta * 5.0)
		left_leg.rotation.x = lerpf(left_leg.rotation.x, 0.0, delta * 5.0)
		right_leg.rotation.x = lerpf(right_leg.rotation.x, 0.0, delta * 5.0)
