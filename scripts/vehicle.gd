extends CharacterBody3D
class_name MahdiaVehicle

@export var acceleration := 9.0
@export var max_speed := 9.0
@export var reverse_speed := 4.0
@export var build_visuals := true
@export var turn_speed := 1.45
var driver: CharacterBody3D
var speed := 0.0
var steering_input := 0.0
var wheels: Array[MeshInstance3D] = []
var rounded_mesh_cache: Dictionary = {}

func _rounded_mesh(size: Vector3) -> ArrayMesh:
	var key := "%.2f_%.2f_%.2f" % [size.x, size.y, size.z]
	if rounded_mesh_cache.has(key):
		return rounded_mesh_cache[key]
	var half := size * 0.5
	var bevel := maxf(0.001, minf(minf(size.x, minf(size.y, size.z)) * 0.12, 0.14))
	var faces := [
		[Vector3.RIGHT, Vector3.UP, Vector3.BACK],
		[Vector3.LEFT, Vector3.UP, Vector3.FORWARD],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT],
		[Vector3.DOWN, Vector3.BACK, Vector3.LEFT],
		[Vector3.FORWARD, Vector3.RIGHT, Vector3.UP],
		[Vector3.BACK, Vector3.LEFT, Vector3.UP]
	]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var divisions := 3
	for face in faces:
		var normal: Vector3 = face[0]
		var axis_u: Vector3 = face[1]
		var axis_v: Vector3 = face[2]
		var hu := half.y if absf(axis_u.y) > 0.5 else half.x if absf(axis_u.x) > 0.5 else half.z
		var hv := half.y if absf(axis_v.y) > 0.5 else half.x if absf(axis_v.x) > 0.5 else half.z
		var grid: Array = []
		for y in range(divisions + 1):
			var line: Array = []
			for x in range(divisions + 1):
				var extent := half.x if absf(normal.x) > 0.5 else half.y if absf(normal.y) > 0.5 else half.z
				var raw := normal * extent + axis_u * lerpf(-hu, hu, float(x) / divisions) + axis_v * lerpf(-hv, hv, float(y) / divisions)
				var inner := Vector3(clampf(raw.x, -half.x + bevel, half.x - bevel), clampf(raw.y, -half.y + bevel, half.y - bevel), clampf(raw.z, -half.z + bevel, half.z - bevel))
				var delta := raw - inner
				var vertex_normal := delta.normalized() if delta.length_squared() > 0.00001 else normal
				line.append([inner + vertex_normal * bevel, vertex_normal])
			grid.append(line)
		for y in range(divisions):
			for x in range(divisions):
				var p00: Array = grid[y][x]
				var p10: Array = grid[y][x + 1]
				var p11: Array = grid[y + 1][x + 1]
				var p01: Array = grid[y + 1][x]
				for point in [p00, p10, p11, p00, p11, p01]:
					surface.set_normal(point[1])
					surface.add_vertex(point[0])
	var mesh := surface.commit()
	rounded_mesh_cache[key] = mesh
	return mesh

func _ready() -> void:
	if build_visuals:
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
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return material

func _box(size: Vector3, pos: Vector3, color: Color, metallic := 0.0) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.mesh = _rounded_mesh(size)
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
	# Front fascia: grille, bumper inserts and readable headlamp shapes.
	_box(Vector3(0.78, 0.20, 0.07), Vector3(0, 0.66, -1.88), Color(0.10, 0.12, 0.13), 0.25)
	_box(Vector3(0.44, 0.055, 0.075), Vector3(0, 0.69, -1.925), Color(0.34, 0.38, 0.39), 0.45)
	_box(Vector3(0.38, 0.13, 0.055), Vector3(0, 0.39, -1.91), Color(0.88, 0.88, 0.78))
	# Rear plate and trim.
	_box(Vector3(0.62, 0.18, 0.045), Vector3(0, 0.63, 1.88), Color(0.82, 0.84, 0.78))
	_box(Vector3(1.72, 0.10, 0.10), Vector3(0, 0.36, 1.89), Color(0.18, 0.19, 0.20), 0.35)
	# Mirrors, door handles and subtle lower side skirts.
	for side in [-1.0, 1.0]:
		_box(Vector3(0.22, 0.12, 0.18), Vector3(side * 0.91, 1.43, -0.63), Color(0.10, 0.13, 0.15), 0.3)
		_box(Vector3(0.055, 0.045, 0.12), Vector3(side * 0.972, 1.16, -0.10), Color(0.82, 0.78, 0.66), 0.35)
		_box(Vector3(0.10, 0.12, 2.65), Vector3(side * 0.965, 0.42, 0.0), Color(0.20, 0.21, 0.22), 0.25)
	# A visible cabin through the windows: dashboard, seats and steering wheel.
	_box(Vector3(1.34, 0.16, 0.38), Vector3(0, 1.05, -0.86), Color(0.075, 0.085, 0.09))
	for z in [-0.30, 0.43]:
		_box(Vector3(0.48, 0.48, 0.42), Vector3(-0.40, 1.02, z), Color(0.12, 0.14, 0.15))
		_box(Vector3(0.48, 0.48, 0.42), Vector3(0.40, 1.02, z), Color(0.12, 0.14, 0.15))
	_box(Vector3(0.10, 0.10, 0.38), Vector3(0, 1.20, -0.72), Color(0.08, 0.09, 0.10))

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
	var target_speed := throttle * (max_speed if throttle >= 0.0 else reverse_speed)
	speed = move_toward(speed, target_speed, acceleration * delta)
	steering_input = move_toward(steering_input, steering, delta * 5.0)
	var steering_factor := clampf(absf(speed) / 2.0, 0.0, 1.0)
	rotation.y -= steering_input * turn_speed * delta * steering_factor * (1.0 if speed >= 0.0 else -1.0)
	velocity.x = -global_transform.basis.z.x * speed
	velocity.z = -global_transform.basis.z.z * speed
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = -0.1
	move_and_slide()
	if get_slide_collision_count() > 0:
		speed *= 0.82
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
	driver.velocity = Vector3.ZERO
	driver.set_physics_process(true)
	driver = null
	speed = 0.0
	steering_input = 0.0
