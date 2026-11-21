extends Node3D
class_name MahdiaLargeWorldExpansion

# Adds three connected, explorable districts around the original playable town.
# Geometry is generated locally: no network access, paid assets, or fake file padding.
# Mobile uses a strict object budget; desktop can build the full district set.

const MOBILE_BUILDING_BUDGET := 60
const DESKTOP_BUILDING_BUDGET := 75
const LOT_SPACING := 24.0

var _materials: Dictionary = {}
var _built_buildings := 0

func build_world() -> void:
	print("MAHDIA_EXPANSION_BEGIN")
	_build_district("OldTown", Vector2(-145.0, 112.0), Color(0.91, 0.85, 0.74), 0)
	_build_district("HarborQuarter", Vector2(145.0, -118.0), Color(0.86, 0.82, 0.73), 1)
	_build_district("NewResidential", Vector2(145.0, 142.0), Color(0.93, 0.89, 0.80), 2)
	_build_public_spaces()
	print("MAHDIA_EXPANSION_READY buildings=", _built_buildings, " districts=3")

func _budget() -> int:
	return MOBILE_BUILDING_BUDGET if OS.has_feature("mobile") else DESKTOP_BUILDING_BUDGET

func _material(color: Color, surface: String = "plastered_wall") -> StandardMaterial3D:
	var key := color.to_html() + "_" + surface
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.94
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var diff_path := "res://assets/textures/%s_diff_1k.jpg" % surface
	var normal_path := "res://assets/textures/%s_nor_gl_1k.png" % surface
	var rough_path := "res://assets/textures/%s_rough_1k.jpg" % surface
	if ResourceLoader.exists(diff_path):
		material.albedo_texture = load(diff_path) as Texture2D
	if ResourceLoader.exists(normal_path):
		material.normal_enabled = true
		material.normal_texture = load(normal_path) as Texture2D
		material.normal_scale = 0.42
	if ResourceLoader.exists(rough_path):
		material.roughness_texture = load(rough_path) as Texture2D
	_materials[key] = material
	return material

func _box(parent: Node3D, size: Vector3, at: Vector3, color: Color, collision := false, surface: String = "plastered_wall") -> Node3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.position = at
	mesh_instance.material_override = _material(color, surface)
	parent.add_child(mesh_instance)
	if collision:
		var body := StaticBody3D.new()
		body.position = at
		var shape_node := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		shape_node.shape = shape
		body.add_child(shape_node)
		parent.add_child(body)
	return mesh_instance

func _build_district(district_name: String, center: Vector2, wall_color: Color, style: int) -> void:
	var district := Node3D.new()
	district.name = district_name
	district.position = Vector3(center.x, 0.0, center.y)
	add_child(district)
	# Four streets and sidewalks form a walkable 5x5 block grid.
	for lane in range(6):
		var offset := (float(lane) - 2.5) * LOT_SPACING
		_box(district, Vector3(7.0, 0.12, 144.0), Vector3(offset, 0.02, 0.0), Color(0.17, 0.18, 0.18), false, "cobblestone_pavement")
		_box(district, Vector3(144.0, 0.12, 7.0), Vector3(0.0, 0.025, offset), Color(0.17, 0.18, 0.18))
		_box(district, Vector3(0.22, 0.16, 144.0), Vector3(offset - 3.65, 0.08, 0.0), Color(0.74, 0.71, 0.64), false, "cobblestone_pavement")
		_box(district, Vector3(144.0, 0.16, 0.22), Vector3(0.0, 0.08, offset - 3.65), Color(0.74, 0.71, 0.64))
	var palette := [wall_color, wall_color.darkened(0.06), wall_color.lightened(0.035), Color(0.78, 0.77, 0.71)]
	for z_index in range(5):
		for x_index in range(5):
			if _built_buildings >= _budget():
				return
			var lot_x := (float(x_index) - 2.0) * LOT_SPACING + 12.0
			var lot_z := (float(z_index) - 2.0) * LOT_SPACING + 12.0
			var lot := Node3D.new()
			lot.name = "Building_%02d_%02d" % [x_index, z_index]
			lot.position = Vector3(lot_x, 0.0, lot_z)
			district.add_child(lot)
			var height := 5.5 + float((x_index * 7 + z_index * 3 + style) % 5) * 1.15
			var width := 8.5 + float((x_index + style) % 3)
			var depth := 8.0 + float((z_index + style) % 3)
			var facade: Color = palette[(x_index + z_index + style) % palette.size()]
			_box(lot, Vector3(width, height, depth), Vector3(0, height * 0.5, 0), facade, true, "plastered_wall")
			_box(lot, Vector3(width + 0.35, 0.22, depth + 0.35), Vector3(0, height + 0.11, 0), Color(0.67, 0.63, 0.56))
			# Recessed-looking windows, entrance and parapet; all share cached materials.
			var glass := Color(0.12, 0.25, 0.31)
			for floor_index in range(maxi(1, int(height / 3.0))):
				var window_y := 1.9 + float(floor_index) * 2.5
				if window_y > height - 0.8:
					continue
				for side in [-1.0, 1.0]:
					_box(lot, Vector3(1.25, 1.25, 0.10), Vector3(side * width * 0.25, window_y, depth * 0.505), glass)
					_box(lot, Vector3(1.38, 0.10, 0.14), Vector3(side * width * 0.25, window_y - 0.69, depth * 0.52), Color(0.83, 0.79, 0.70))
			_box(lot, Vector3(1.15, 2.0, 0.12), Vector3(0, 1.0, depth * 0.51), Color(0.25, 0.18, 0.13))
			if style == 1 and (x_index + z_index) % 2 == 0:
				_box(lot, Vector3(width * 0.72, 0.18, 1.6), Vector3(0, 2.8, depth * 0.62), Color(0.78, 0.27, 0.17))
			_built_buildings += 1
			if _built_buildings % 6 == 0:
				await get_tree().process_frame

func _build_public_spaces() -> void:
	# A central square, small harbour apron and waterfront promenade landmarks.
	var square := Node3D.new()
	square.name = "ExpandedCentralSquare"
	square.position = Vector3(-145.0, 0.0, 112.0)
	add_child(square)
	_box(square, Vector3(34.0, 0.18, 28.0), Vector3.ZERO, Color(0.70, 0.67, 0.58))
	for x in [-12.0, 12.0]:
		for z in [-9.0, 9.0]:
			_box(square, Vector3(1.1, 0.35, 1.1), Vector3(x, 0.27, z), Color(0.48, 0.34, 0.22))
			_box(square, Vector3(0.28, 4.2, 0.28), Vector3(x, 2.4, z), Color(0.36, 0.29, 0.21))
	var harbor := Node3D.new()
	harbor.name = "HarborExtension"
	harbor.position = Vector3(145.0, 0.0, -118.0)
	add_child(harbor)
	_box(harbor, Vector3(54.0, 0.5, 14.0), Vector3(0, 0.0, -82.0), Color(0.63, 0.59, 0.50))
	for boat_index in range(4):
		var boat_x := -19.0 + float(boat_index) * 12.0
		_box(harbor, Vector3(6.0, 0.48, 2.2), Vector3(boat_x, 0.45, -90.0), Color(0.30, 0.22, 0.16))
		_box(harbor, Vector3(3.7, 0.10, 1.7), Vector3(boat_x, 0.75, -90.0), Color(0.88, 0.85, 0.75))
	print("MAHDIA_PUBLIC_SPACES_READY")
