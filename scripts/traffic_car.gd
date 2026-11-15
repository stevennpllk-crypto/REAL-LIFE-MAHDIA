extends CharacterBody3D
class_name MahdiaTrafficCar

@export var cruise_speed := 4.2
@export var lane_offset := -1.65
@export var horizontal := true
@export var direction := 1.0
@export var build_visuals := true

const ROAD_LIMIT := 78.0
var lane_progress := 0.0
var body_mesh: MeshInstance3D

func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	if build_visuals:
		_build_visuals()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.55, 1.1, 3.0)
	collider.shape = shape
	collider.position.y = 0.62
	add_child(collider)
	_update_transform()

func _physics_process(delta: float) -> void:
	lane_progress += cruise_speed * direction * delta
	if lane_progress > ROAD_LIMIT:
		lane_progress = -ROAD_LIMIT
	elif lane_progress < -ROAD_LIMIT:
		lane_progress = ROAD_LIMIT
	_update_transform()

func _update_transform() -> void:
	if horizontal:
		global_position = Vector3(lane_progress, 0.05, lane_offset)
		rotation.y = -PI * 0.5 if direction > 0.0 else PI * 0.5
	else:
		global_position = Vector3(lane_offset, 0.05, lane_progress)
		rotation.y = PI if direction > 0.0 else 0.0

func _build_visuals() -> void:
	var paint_colors := [
		Color(0.12, 0.34, 0.58),
		Color(0.78, 0.72, 0.56),
		Color(0.18, 0.42, 0.32),
		Color(0.62, 0.20, 0.14)
	]
	var paint := StandardMaterial3D.new()
	paint.albedo_color = paint_colors[posmod(get_instance_id(), paint_colors.size())]
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.10, 0.20, 0.25)
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	body_mesh = _add_ellipsoid(Vector3(1.72, 0.62, 3.20), Vector3(0, 0.66, 0), paint)
	_add_ellipsoid(Vector3(1.34, 0.68, 1.72), Vector3(0, 1.08, -0.12), glass)
	_add_ellipsoid(Vector3(1.52, 0.25, 0.82), Vector3(0, 0.82, -1.18), paint)
	_add_ellipsoid(Vector3(1.52, 0.22, 0.62), Vector3(0, 0.82, 1.28), paint)
	var lamp_material := StandardMaterial3D.new()
	lamp_material.albedo_color = Color(1.0, 0.88, 0.58)
	lamp_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var tail_material := StandardMaterial3D.new()
	tail_material.albedo_color = Color(0.72, 0.08, 0.045)
	tail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for side in [-1.0, 1.0]:
		_add_ellipsoid(Vector3(0.22, 0.13, 0.10), Vector3(side * 0.58, 0.72, -1.57), lamp_material)
		_add_ellipsoid(Vector3(0.20, 0.12, 0.10), Vector3(side * 0.58, 0.72, 1.57), tail_material)
	for side in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			var wheel := MeshInstance3D.new()
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.28
			mesh.bottom_radius = 0.28
			mesh.height = 0.16
			wheel.mesh = mesh
			wheel.position = Vector3(side * 0.82, 0.35, z)
			wheel.rotation_degrees.z = 90
			var rubber := StandardMaterial3D.new()
			rubber.albedo_color = Color(0.035, 0.04, 0.045)
			rubber.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			wheel.material_override = rubber
			add_child(wheel)

func _add_ellipsoid(size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 16
	mesh.rings = 8
	item.mesh = mesh
	item.scale = size
	item.position = pos
	item.material_override = material
	add_child(item)
	return item

func configure_traffic(axis_is_horizontal: bool, lane: float, start_progress: float, travel_direction: float, speed_value: float) -> void:
	horizontal = axis_is_horizontal
	lane_offset = lane
	lane_progress = start_progress
	direction = 1.0 if travel_direction >= 0.0 else -1.0
	cruise_speed = maxf(1.0, speed_value)
	_update_transform()
