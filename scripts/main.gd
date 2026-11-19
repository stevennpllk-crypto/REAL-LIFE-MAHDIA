extends Node3D

const PLAYER_SCRIPT = preload("res://scripts/player.gd")
const NPC_SCRIPT = preload("res://scripts/npc.gd")
const MOBILE_CONTROLS = preload("res://scripts/mobile_controls.gd")
const VEHICLE_SCRIPT = preload("res://scripts/vehicle.gd")
const TRAFFIC_SCRIPT = preload("res://scripts/traffic_car.gd")
const WORLD_SYSTEMS = preload("res://scripts/world_systems.gd")
const NETWORK_SCRIPT = preload("res://scripts/multiplayer_manager.gd")
const SAVE_SCRIPT = preload("res://scripts/save_manager.gd")
const LIFE_SCRIPT = preload("res://scripts/life_manager.gd")
const AI_SERVICE_SCRIPT = preload("res://scripts/ai_service.gd")
const PLANET_NAV_SCRIPT = preload("res://scripts/planet_navigation.gd")
const TERRAIN_STREAMER_SCRIPT = preload("res://scripts/terrain_streamer.gd")

var player: CharacterBody3D
var sun: DirectionalLight3D
var world_environment: Environment
var status_label: Label
var ai_status_label: Label
var hint_label: Label
var vehicle: CharacterBody3D
var world_systems: Node
var network_manager: Node
var save_manager: Node
var life_manager: Node
var ai_service: Node
var chat_input: LineEdit
var ai_endpoint_input: LineEdit
var ai_email_input: LineEdit
var ai_password_input: LineEdit
var ai_token_input: LineEdit
var ai_setup_panel: PanelContainer
var planet_navigation: Node
var terrain_streamer: Node3D
var material_cache: Dictionary = {}
var water_waves: Array[MeshInstance3D] = []
var water_wave_origins: Array[Vector3] = []
var water_clock := 0.0
var water_visual_elapsed := 0.0
var hud_refresh_elapsed := 0.0
var autosave_elapsed := 0.0
var quality_level := 2
var quality_button: Button
var restored_vehicle_position := START_VEHICLE_POSITION
var restore_vehicle_driver := false
var mission_hud_label: Label
var mission_target_marker: Label3D
var mission_last_text := ""
var wallet_label: Label
var level_label: Label
var chat_row: HBoxContainer
var mission_hud_panel: PanelContainer
const START_PLAYER_POSITION := Vector3(68.0, 0.03, -46.0)
const START_PLAYER_ROTATION := PI * 0.5 - 0.25
const START_VEHICLE_POSITION := Vector3(58.0, 0.1, -43.5)
const AUTOSAVE_INTERVAL := 12.0
const WORLD_SAVE_KEY := "mahdia_world"

func _ready() -> void:
	randomize()
	_select_device_profile()
	_build_environment()
	# Bring up a playable camera and HUD before constructing decorative city blocks.
	# This guarantees that even a slow phone can present a real game frame quickly.
	_spawn_player()
	_setup_systems()
	_build_hud()
	print("MAHDIA_PLAYER_READY")
	await get_tree().process_frame
	await _build_town()
	print("MAHDIA_TOWN_READY")
	_spawn_residents()
	_spawn_vehicle()
	_spawn_traffic()
	print("MAHDIA_WORLD_READY")

func _material(color: Color, roughness := 0.88) -> StandardMaterial3D:
	var key := color.to_html() + str(roughness)
	if material_cache.has(key):
		return material_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	# Physically based lighting gives surfaces real form; the low tier disables shadows instead.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material_cache[key] = mat
	return mat

var rounded_mesh_cache: Dictionary = {}
var plaster_texture: ImageTexture
var surface_texture_cache: Dictionary = {}
var pbr_texture_cache: Dictionary = {}

func _rounded_box_mesh(size: Vector3) -> ArrayMesh:
	var key := "%0.3f_%0.3f_%0.3f" % [size.x, size.y, size.z]
	if rounded_mesh_cache.has(key):
		return rounded_mesh_cache[key]
	var half := size * 0.5
	var bevel := minf(minf(size.x, minf(size.y, size.z)) * 0.12, 0.16)
	bevel = maxf(0.002, bevel)
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
	var divisions := 4
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
				var raw := normal * (half.x if absf(normal.x) > 0.5 else half.y if absf(normal.y) > 0.5 else half.z)
				raw += axis_u * lerpf(-hu, hu, float(x) / divisions)
				raw += axis_v * lerpf(-hv, hv, float(y) / divisions)
				var inner := Vector3(
					clampf(raw.x, -half.x + bevel, half.x - bevel),
					clampf(raw.y, -half.y + bevel, half.y - bevel),
					clampf(raw.z, -half.z + bevel, half.z - bevel)
				)
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
				for point in [[p00, 0, 0], [p10, 1, 0], [p11, 1, 1], [p00, 0, 0], [p11, 1, 1], [p01, 0, 1]]:
					surface.set_normal(point[0][1])
					surface.set_uv(Vector2((float(x) + float(point[1])) / divisions, (float(y) + float(point[2])) / divisions))
					surface.add_vertex(point[0][0])
	var mesh := surface.commit()
	rounded_mesh_cache[key] = mesh
	return mesh

func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.mesh = _rounded_box_mesh(size)
	item.position = pos
	item.material_override = _material(color)
	parent.add_child(item)
	return item

func _pbr_texture(asset: String, map_name: String) -> Texture2D:
	var key := asset + "_" + map_name
	if pbr_texture_cache.has(key):
		return pbr_texture_cache[key] as Texture2D
	var extensions := ["jpg", "png"] if map_name == "diff" or map_name == "rough" else ["png", "jpg"]
	for extension in extensions:
		var path := "res://assets/textures/%s_%s_1k.%s" % [asset, map_name, extension]
		if ResourceLoader.exists(path):
			var texture := load(path) as Texture2D
			if texture != null:
				pbr_texture_cache[key] = texture
				return texture
	pbr_texture_cache[key] = null
	return null


func _apply_pbr_maps(material: StandardMaterial3D, asset: String) -> void:
	var normal_map := _pbr_texture(asset, "nor_gl")
	var rough_map := _pbr_texture(asset, "rough")
	if normal_map != null:
		material.normal_enabled = true
		material.normal_texture = normal_map
		material.normal_scale = 0.48
	if rough_map != null:
		material.roughness_texture = rough_map
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _plaster_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	var plaster_map := _pbr_texture("plastered_wall", "diff")
	if plaster_map != null:
		material.albedo_texture = plaster_map
		_apply_pbr_maps(material, "plastered_wall")
	else:
		if plaster_texture == null:
			var image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
			for y in range(128):
				for x in range(128):
					var grain := randf_range(0.91, 1.0)
					var stain := 0.96 + sin(float(x) * 0.11 + sin(float(y) * 0.07)) * 0.025
					var value := clampf(grain * stain, 0.82, 1.0)
					image.set_pixel(x, y, Color(value, value, value, 1.0))
			plaster_texture = ImageTexture.create_from_image(image)
		material.albedo_texture = plaster_texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.roughness = 0.96
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return material

func _plaster_box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.mesh = _rounded_box_mesh(size)
	item.position = pos
	item.material_override = _plaster_material(color)
	parent.add_child(item)
	return item

func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	world_environment = Environment.new()
	world_environment.background_mode = Environment.BG_COLOR
	world_environment.background_color = Color(0.48, 0.69, 0.86)
	# Avoid procedural-sky shader variants on low-limit GLES3/SwiftShader devices.
	world_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_environment.ambient_light_color = Color(0.78, 0.82, 0.90)
	world_environment.ambient_light_energy = 0.72
	world_environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	world_env.environment = world_environment
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_energy = 1.28
	# One directional sun provides real surface shading and shadows.
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 48.0
	sun.shadow_opacity = 0.62
	sun.visible = true
	add_child(sun)
	# Explicitly disable costly environment passes for broad GLES3 compatibility.
	world_environment.glow_enabled = false
	world_environment.ssao_enabled = false
	world_environment.ssil_enabled = false
	world_environment.sdfgi_enabled = false
	world_environment.fog_enabled = false
	world_environment.volumetric_fog_enabled = false

	# Solid land stops at the shoreline; the sea area remains swimmable.
	var ground := StaticBody3D.new()
	_box(ground, Vector3(180, 1, 120), Vector3(0, -0.55, 30), Color(0.72, 0.66, 0.53))
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(180, 1, 120)
	floor_shape.shape = floor_box
	floor_shape.position = Vector3(0, -0.55, 30)
	ground.add_child(floor_shape)
	add_child(ground)
	var shore := StaticBody3D.new()
	_box(shore, Vector3(180, 1, 29), Vector3(0, -0.55, -44.5), Color(0.82, 0.76, 0.64))
	var shore_shape := CollisionShape3D.new()
	var shore_box := BoxShape3D.new()
	shore_box.size = Vector3(180, 1, 29)
	shore_shape.shape = shore_box
	shore_shape.position = Vector3(0, -0.55, -44.5)
	shore.add_child(shore_shape)
	add_child(shore)

	# Mediterranean sea and a pale coastal promenade.
	var sea := _box(self, Vector3(180, 0.16, 38), Vector3(0, -0.02, -78), Color(0.025, 0.29, 0.50))
	var sea_material := _material(Color(0.025, 0.29, 0.50), 0.24)
	sea_material.metallic = 0.12
	sea_material.roughness = 0.24
	sea_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	sea.material_override = sea_material
	_textured_box(self, Vector3(180, 0.18, 5.5), Vector3(0, 0.04, -57), Color(0.88, 0.84, 0.75), "stone", Vector3(1.0, 42.0, 1.0))
	_create_coastal_scenery()
	_create_waterfront_district()
	_create_beach_cafe()

func _create_coastal_scenery() -> void:
	# A small Mediterranean waterfront set: boats, wave crests, benches and shade.
	for i in range(3):
		var x := -25.0 + float(i) * 23.0
		var z := -76.0 - float(i % 2) * 5.0
		_box(self, Vector3(5.8, 0.42, 2.0), Vector3(x, 0.18, z), Color(0.32, 0.20, 0.13))
		_box(self, Vector3(3.6, 0.12, 1.7), Vector3(x, 0.43, z), Color(0.92, 0.88, 0.77))
		_box(self, Vector3(0.12, 2.1, 0.12), Vector3(x, 1.48, z), Color(0.34, 0.24, 0.15))
		_box(self, Vector3(2.8, 0.08, 1.5), Vector3(x, 2.45, z), Color(0.88, 0.82, 0.68))
	for i in range(10):
		var wave := MeshInstance3D.new()
		var wave_mesh := BoxMesh.new()
		wave_mesh.size = Vector3(randf_range(3.0, 8.0), 0.025, 0.07)
		wave.mesh = wave_mesh
		wave.position = Vector3(randf_range(-82.0, 82.0), 0.075, -62.0 - float(i) * 2.5)
		wave.material_override = _material(Color(0.42, 0.76, 0.82))
		add_child(wave)
		water_waves.append(wave)
		water_wave_origins.append(wave.position)
	for i in range(4):
		var x := -18.0 + float(i) * 12.0
		_box(self, Vector3(2.2, 0.12, 0.55), Vector3(x, 0.72, -54.0), Color(0.40, 0.23, 0.12))
		_box(self, Vector3(2.2, 0.12, 0.12), Vector3(x, 1.18, -54.22), Color(0.40, 0.23, 0.12))
	for i in range(3):
		var x := -13.0 + float(i) * 13.0
		var canopy := _box(self, Vector3(3.2, 0.12, 3.2), Vector3(x, 2.55, -50.5), [Color(0.86, 0.28, 0.18), Color(0.92, 0.84, 0.66), Color(0.16, 0.42, 0.48)][i])
		canopy.rotation.z = 0.08
		for side in [-1.0, 1.0]:
			_box(self, Vector3(0.10, 2.5, 0.10), Vector3(x + side * 1.35, 1.25, -50.5), Color(0.35, 0.26, 0.18))
	for i in range(7):
		_create_palm(Vector3(-42.0 + float(i) * 14.0, 0, -47.0))
	_create_borj_el_kebir_landmark()


func _create_waterfront_district() -> void:
	# Dense whitewashed Mahdia-style facades along the inland side of the promenade.
	# Their street-facing sides look toward the sea-facing walking route.
	var positions := [Vector3(34, 0, -29), Vector3(52, 0, -29), Vector3(70, 0, -29), Vector3(88, 0, -29), Vector3(106, 0, -29)]
	var palettes := [
		Color(0.91, 0.86, 0.76), Color(0.95, 0.91, 0.82),
		Color(0.84, 0.80, 0.71), Color(0.93, 0.88, 0.78),
		Color(0.87, 0.83, 0.75)
	]
	for i in range(positions.size()):
		var dimensions := Vector3(13.0 if i % 2 == 0 else 11.5, 9.0 + float(i % 3), 10.0)
		_create_building(positions[i], dimensions, palettes[i], 210 + i)
		var facade := get_child(get_child_count() - 1) as Node3D
		if is_instance_valid(facade):
			facade.rotation.y = PI
		# Ground-floor cafe/shop awnings, facing the pedestrian promenade.
		var awning_color: Color = [Color(0.76, 0.16, 0.13), Color(0.90, 0.84, 0.69), Color(0.12, 0.36, 0.42)][i % 3]
		_box(self, Vector3(4.4, 0.16, 1.25), positions[i] + Vector3(0, 3.0, 5.35), awning_color)
		_box(self, Vector3(4.4, 0.12, 0.12), positions[i] + Vector3(0, 2.86, 5.96), Color(0.94, 0.90, 0.82))
	# A line of palms and planters gives the promenade the dense coastal rhythm in the reference.
	for i in range(5):
		var x := 30.0 + float(i) * 18.0
		_create_palm(Vector3(x, 0, -40.5))
		_box(self, Vector3(1.8, 0.34, 0.9), Vector3(x + 5.5, 0.22, -42.2), Color(0.53, 0.39, 0.27))
		_box(self, Vector3(1.55, 0.26, 0.72), Vector3(x + 5.5, 0.48, -42.2), Color(0.18, 0.39, 0.22))
	_create_tunisian_flag(Vector3(58.0, 0.0, -39.0))


func _create_tunisian_flag(pos: Vector3) -> void:
	var pole := _box(self, Vector3(0.10, 6.8, 0.10), pos + Vector3(0, 3.4, 0), Color(0.16, 0.18, 0.20))
	var flag := _box(self, Vector3(1.65, 1.05, 0.055), pos + Vector3(0.82, 5.55, 0), Color(0.83, 0.055, 0.09))
	# White disc, red crescent and star are layered on the camera-facing side.
	var disc := MeshInstance3D.new()
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 0.32
	disc_mesh.bottom_radius = 0.32
	disc_mesh.height = 0.035
	disc_mesh.radial_segments = 32
	disc.mesh = disc_mesh
	disc.rotation_degrees.x = 90
	disc.position = pos + Vector3(0.82, 5.55, 0.055)
	disc.material_override = _material(Color(0.96, 0.94, 0.88))
	add_child(disc)
	var crescent := MeshInstance3D.new()
	var crescent_mesh := TorusMesh.new()
	crescent_mesh.inner_radius = 0.12
	crescent_mesh.outer_radius = 0.20
	crescent_mesh.rings = 24
	crescent_mesh.ring_segments = 12
	crescent.mesh = crescent_mesh
	crescent.rotation_degrees.x = 90
	crescent.position = pos + Vector3(0.79, 5.55, 0.083)
	crescent.material_override = _material(Color(0.82, 0.055, 0.09))
	add_child(crescent)
	var star := MeshInstance3D.new()
	var star_mesh := PrismMesh.new()
	star_mesh.size = Vector3(0.19, 0.19, 0.025)
	star.mesh = star_mesh
	star.position = pos + Vector3(1.04, 5.55, 0.09)
	star.material_override = _material(Color(0.82, 0.055, 0.09))
	add_child(star)


func _create_beach_cafe() -> void:
	# A recognizable waterfront cafe with a shaded counter and outdoor seating.
	var sand := Color(0.83, 0.76, 0.63)
	var wood := Color(0.34, 0.22, 0.14)
	var cafe := Node3D.new()
	cafe.name = "BeachCafe"
	cafe.position = Vector3(-63.0, 0.0, -46.5)
	add_child(cafe)
	_box(cafe, Vector3(7.0, 0.22, 4.2), Vector3(0, 0.12, 0), sand)
	_box(cafe, Vector3(6.6, 2.4, 0.18), Vector3(0, 1.32, -1.95), Color(0.91, 0.86, 0.75))
	_box(cafe, Vector3(0.18, 2.4, 3.9), Vector3(-3.25, 1.32, 0), Color(0.91, 0.86, 0.75))
	_box(cafe, Vector3(0.18, 2.4, 3.9), Vector3(3.25, 1.32, 0), Color(0.91, 0.86, 0.75))
	_box(cafe, Vector3(7.5, 0.22, 4.7), Vector3(0, 2.62, 0), Color(0.17, 0.38, 0.43))
	_box(cafe, Vector3(7.7, 0.14, 1.25), Vector3(0, 2.28, 2.05), Color(0.88, 0.28, 0.16))
	_box(cafe, Vector3(4.2, 0.82, 0.72), Vector3(0, 0.62, 1.05), wood)
	_box(cafe, Vector3(4.35, 0.10, 0.82), Vector3(0, 1.08, 1.05), Color(0.79, 0.72, 0.59))
	var sign := Label3D.new()
	sign.text = "مقهى الشاطئ"
	sign.position = Vector3(0, 2.0, 2.42)
	sign.font_size = 36
	sign.pixel_size = 0.008
	cafe.add_child(sign)
	# Three outdoor tables with simple chairs; shared meshes keep this mobile-friendly.
	for i in range(3):
		var x := -5.4 + float(i) * 5.4
		var table := MeshInstance3D.new()
		var table_mesh := CylinderMesh.new()
		table_mesh.top_radius = 0.68
		table_mesh.bottom_radius = 0.68
		table_mesh.height = 0.12
		table.mesh = table_mesh
		table.position = Vector3(x, 0.88, 4.2)
		table.material_override = _material(Color(0.88, 0.84, 0.74))
		cafe.add_child(table)
		_box(cafe, Vector3(0.16, 0.82, 0.16), Vector3(x, 0.42, 4.2), wood)
		for side in [-1.0, 1.0]:
			_box(cafe, Vector3(0.72, 0.12, 0.72), Vector3(x + side * 1.15, 0.48, 4.2), Color(0.22, 0.38, 0.36))
			_box(cafe, Vector3(0.72, 0.82, 0.12), Vector3(x + side * 1.15, 0.88, 4.5), wood)
	# A striped shade sail gives the cafe a distinct beach silhouette.
	_box(cafe, Vector3(4.0, 0.10, 3.0), Vector3(0, 3.15, 4.4), Color(0.91, 0.83, 0.68))
	for x in [-1.9, 1.9]:
		_box(cafe, Vector3(0.12, 3.0, 0.12), Vector3(x, 1.55, 5.7), wood)


func _create_borj_el_kebir_landmark() -> void:
	var stone := Color(0.69, 0.62, 0.49)
	var pale := Color(0.82, 0.75, 0.62)
	var fortress_material := StandardMaterial3D.new()
	fortress_material.albedo_color = stone
	var fortress_diffuse := _pbr_texture("cobblestone_pavement", "diff")
	if fortress_diffuse != null:
		fortress_material.albedo_texture = fortress_diffuse
		_apply_pbr_maps(fortress_material, "cobblestone_pavement")
	fortress_material.uv1_scale = Vector3(3.0, 1.0, 1.0)
	fortress_material.roughness = 0.94
	var main_wall := _box(self, Vector3(19.0, 7.0, 1.25), Vector3(37.0, 3.5, -51.0), stone)
	main_wall.material_override = fortress_material
	var west_wall := _box(self, Vector3(1.25, 7.0, 10.0), Vector3(28.2, 3.5, -56.0), stone)
	west_wall.material_override = fortress_material
	var east_wall := _box(self, Vector3(1.25, 7.0, 10.0), Vector3(45.8, 3.5, -56.0), stone)
	east_wall.material_override = fortress_material
	_box(self, Vector3(3.0, 3.8, 0.12), Vector3(37.0, 1.9, -50.32), Color(0.12, 0.11, 0.10))
	_box(self, Vector3(4.2, 0.55, 0.42), Vector3(37.0, 4.0, -50.15), pale)
	# Carved horizontal masonry courses and parapet teeth give the fortress a stone silhouette.
	for course in range(7):
		var y := 0.72 + float(course) * 0.88
		for block in range(19):
			var bx := 28.0 + float(block) * 1.0
			if bx > 46.0:
				continue
			if course > 1 and course < 5 and absf(bx - 37.0) < 2.2:
				continue
			_box(self, Vector3(0.82, 0.055, 0.045), Vector3(bx, y, -50.34), Color(0.77, 0.70, 0.57))
	for crenel in range(11):
		var cx := 28.8 + float(crenel) * 1.64
		_box(self, Vector3(0.78, 0.62, 1.32), Vector3(cx, 7.28, -51.0), pale)
	for x in [28.5, 45.5]:
		var tower := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 1.55
		mesh.bottom_radius = 2.0
		mesh.height = 10.0 if x < 30.0 else 13.0
		mesh.radial_segments = 16
		tower.mesh = mesh
		tower.position = Vector3(x, mesh.height * 0.5, -54.0)
		tower.material_override = fortress_material
		add_child(tower)
		for j in range(12):
			var a := TAU * float(j) / 12.0
			_box(self, Vector3(0.34, 0.72, 0.34), Vector3(x + cos(a) * 1.62, mesh.height + 0.36, -54.0 + sin(a) * 1.62), pale)
		for slit in range(4):
			_box(self, Vector3(0.16, 1.05, 0.10), Vector3(x + cos(float(slit) * TAU / 4.0) * 1.72, mesh.height * 0.62, -54.0 + sin(float(slit) * TAU / 4.0) * 1.72), Color(0.20, 0.17, 0.13))
	_box(self, Vector3(0.10, 10.0, 0.10), Vector3(25.0, 5.0, -49.5), Color(0.30, 0.27, 0.22))
	_box(self, Vector3(2.6, 1.55, 0.08), Vector3(26.25, 8.45, -49.5), Color(0.82, 0.08, 0.12))
	_box(self, Vector3(180.0, 0.78, 0.42), Vector3(0, 0.55, -55.2), pale)
	for i in range(31):
		var x := -88.0 + float(i) * 5.85
		_box(self, Vector3(0.18, 0.95, 0.24), Vector3(x, 0.98, -55.2), stone)
	_box(self, Vector3(180.0, 0.16, 0.56), Vector3(0, 1.48, -55.2), pale)


func _build_town() -> void:
	# Main asphalt streets crossing a compact Mahdia-inspired neighborhood.
	_textured_box(self, Vector3(180, 0.12, 9), Vector3(0, 0.035, 0), Color(0.16, 0.18, 0.19), "asphalt", Vector3(4, 30, 1))
	_textured_box(self, Vector3(9, 0.12, 180), Vector3(0, 0.04, 0), Color(0.16, 0.18, 0.19), "asphalt", Vector3(30, 4, 1))
	for x in range(-80, 81, 12):
		_box(self, Vector3(5.0, 0.025, 0.16), Vector3(float(x), 0.11, 0), Color(0.92, 0.84, 0.58))
	for z in range(-80, 81, 12):
		_box(self, Vector3(0.16, 0.025, 5.0), Vector3(0, 0.12, float(z)), Color(0.92, 0.84, 0.58))
	# Pedestrian crossings and raised curbs.
	for i in range(7):
		_box(self, Vector3(0.72, 0.035, 0.16), Vector3(-4.0 + float(i) * 1.3, 0.13, -5.1), Color(0.94, 0.92, 0.84))
		_box(self, Vector3(0.72, 0.035, 0.16), Vector3(-4.0 + float(i) * 1.3, 0.13, 5.1), Color(0.94, 0.92, 0.84))
	_box(self, Vector3(180, 0.28, 0.22), Vector3(0, 0.17, -4.55), Color(0.91, 0.88, 0.78))
	_box(self, Vector3(180, 0.28, 0.22), Vector3(0, 0.17, 4.55), Color(0.91, 0.88, 0.78))
	for bay in range(5):
		var bx := -31.0 + float(bay) * 7.0
		_box(self, Vector3(0.10, 0.025, 4.0), Vector3(bx, 0.13, 8.2), Color(0.86, 0.87, 0.82))

	# Sidewalk strips.
	for side in [-1.0, 1.0]:
		_textured_box(self, Vector3(180, 0.2, 1.6), Vector3(0, 0.08, side * 5.5), Color(0.78, 0.75, 0.68), "stone", Vector3(2, 30, 1))
		_textured_box(self, Vector3(1.6, 0.2, 180), Vector3(side * 5.5, 0.08, 0), Color(0.78, 0.75, 0.68), "stone", Vector3(30, 2, 1))

	var palette := [
		Color(0.88, 0.82, 0.70), Color(0.94, 0.89, 0.78),
		Color(0.78, 0.72, 0.62), Color(0.84, 0.86, 0.83),
		Color(0.91, 0.84, 0.75)
	]
	for i in range(5):
		for j in range(4):
			var x := float(i) * 17.0 - 34.0
			var z := float(j) * 18.0 - 27.0
			if absf(x) < 9.0 or absf(z) < 9.0:
				continue
			var height := randf_range(5.5, 9.0)
			var width := randf_range(7.0, 9.0)
			var depth := randf_range(7.0, 9.0)
			_create_building(Vector3(x, 0, z), Vector3(width, height, depth), palette[randi_range(0, palette.size()-1)], i * 11 + j)
			# Spread expensive node creation over frames to keep the renderer responsive.
			if (i * 5 + j) % 3 == 0:
				await get_tree().process_frame

	_create_palm(Vector3(-10, 0, -10))
	_create_palm(Vector3(10, 0, -10))
	_create_palm(Vector3(-10, 0, 10))
	_create_palm(Vector3(10, 0, 10))
	_create_street_lamp(Vector3(-6.5, 0, -8))
	_create_street_lamp(Vector3(6.5, 0, 8))
	_create_street_lamp(Vector3(-8, 0, 6.5))
	_create_street_lamp(Vector3(8, 0, -6.5))
	_create_outer_district()
	# One unified world-detail set for every device profile.
	_create_city_details()


func _create_outer_district() -> void:
	# Expand the playable city beyond the starter crossroads into three connected
	# residential/commercial blocks. Geometry is shared and scaled for mobile.
	var asphalt := Color(0.14, 0.16, 0.17)
	var curb := Color(0.78, 0.75, 0.68)
	var lane := Color(0.88, 0.82, 0.67)
	# Two east-west streets and two north-south streets create a readable grid.
	for z in [30.0, 58.0]:
		_textured_box(self, Vector3(180, 0.12, 7.0), Vector3(0, 0.035, z), asphalt, "asphalt", Vector3(4, 30, 1))
		_box(self, Vector3(180, 0.22, 0.18), Vector3(0, 0.16, z - 3.7), curb)
		_box(self, Vector3(180, 0.22, 0.18), Vector3(0, 0.16, z + 3.7), curb)
		for x in range(-84, 85, 12):
			_box(self, Vector3(4.0, 0.025, 0.13), Vector3(float(x), 0.11, z), lane)
	for x in [-52.0, 52.0]:
		_textured_box(self, Vector3(7.0, 0.12, 112.0), Vector3(x, 0.035, 34.0), asphalt, "asphalt", Vector3(1, 30, 4))
		_box(self, Vector3(0.18, 0.22, 112.0), Vector3(x - 3.7, 0.16, 34.0), curb)
		_box(self, Vector3(0.18, 0.22, 112.0), Vector3(x + 3.7, 0.16, 34.0), curb)
	# More homes and small shops; the population/building budget follows device tier.
	var palette := [Color(0.91, 0.85, 0.74), Color(0.83, 0.79, 0.69), Color(0.94, 0.89, 0.79), Color(0.77, 0.76, 0.70)]
	var lots := [
		Vector3(-72, 0, -20), Vector3(-72, 0, 5), Vector3(-72, 0, 35), Vector3(-72, 0, 68),
		Vector3(-32, 0, 43), Vector3(-10, 0, 43), Vector3(12, 0, 43), Vector3(32, 0, 43),
		Vector3(72, 0, -20), Vector3(72, 0, 5), Vector3(72, 0, 35), Vector3(72, 0, 68),
		Vector3(-32, 0, 78), Vector3(-10, 0, 78), Vector3(12, 0, 78), Vector3(32, 0, 78)
	]
	var count: int = lots.size()
	for i in range(mini(count, lots.size())):
		var height := randf_range(5.8, 10.5)
		var dimensions := Vector3(randf_range(7.0, 9.5), height, randf_range(7.0, 9.5))
		_create_building(lots[i], dimensions, palette[i % palette.size()], 70 + i)
		if i % 3 == 2:
			await get_tree().process_frame
	# A small public square with benches, planted trees and a tiled centre.
	_textured_box(self, Vector3(18, 0.16, 15), Vector3(0, 0.10, 72), Color(0.70, 0.68, 0.59), "stone", Vector3(4, 4, 1))
	for x in [-6.0, 6.0]:
		for z in [67.0, 77.0]:
			_create_palm(Vector3(x, 0, z))
	for x in [-4.5, 4.5]:
		_box(self, Vector3(3.0, 0.14, 0.55), Vector3(x, 0.65, 72), Color(0.40, 0.25, 0.15))
	# Market awnings add a recognisable coastal-town street frontage.
	for i in range(4):
		var x := -24.0 + float(i) * 16.0
		_box(self, Vector3(5.5, 0.14, 2.0), Vector3(x, 2.75, 35.0), [Color(0.78, 0.23, 0.16), Color(0.88, 0.81, 0.65), Color(0.16, 0.39, 0.42), Color(0.79, 0.65, 0.28)][i])
		_box(self, Vector3(0.12, 2.6, 0.12), Vector3(x - 2.35, 1.3, 35.0), Color(0.34, 0.25, 0.18))
		_box(self, Vector3(0.12, 2.6, 0.12), Vector3(x + 2.35, 1.3, 35.0), Color(0.34, 0.25, 0.18))
	# Street furniture and lighting make the new blocks navigable at night.
	for x in range(-80, 81, 20):
		_create_street_lamp(Vector3(float(x), 0, 25.0))
		_create_street_lamp(Vector3(float(x), 0, 63.0))

func _create_building(origin: Vector3, size: Vector3, wall_color: Color, seed_value: int) -> void:
	# Mediterranean/Mahdia-inspired low-rise architecture. Keep geometry static
	# and deliberately bounded so the richer street remains usable on 3 GB phones.
	var building := StaticBody3D.new()
	building.position = origin
	var w := size.x
	var h := size.y
	var d := size.z
	var window_y := minf(3.45, h * 0.58)
	var window_color := Color(0.10, 0.23, 0.30)
	var trim_color := Color(0.91, 0.87, 0.77)
	var frame_color := Color(0.29, 0.23, 0.18)

	_plaster_box(building, size, Vector3(0, h * 0.5, 0), wall_color)
	_box(building, Vector3(w + 0.32, 0.24, d + 0.32), Vector3(0, h + 0.12, 0), Color(0.70, 0.66, 0.58))
	# Roof parapet gives flat Tunisian rooftops a recognisable silhouette.
	for side in [-1.0, 1.0]:
		_box(building, Vector3(w + 0.12, 0.42, 0.12), Vector3(0, h + 0.40, side * (d * 0.5)), trim_color)
		_box(building, Vector3(0.12, 0.42, d + 0.12), Vector3(side * (w * 0.5), h + 0.40, 0), trim_color)

	# Ground-floor entrance, raised step and occasional shopfront.
	_box(building, Vector3(1.05, 2.05, 0.10), Vector3(0, 1.03, d * 0.501), Color(0.25, 0.17, 0.12))
	_box(building, Vector3(1.42, 0.16, 0.72), Vector3(0, 0.10, d * 0.69), Color(0.66, 0.59, 0.48))
	if seed_value % 3 == 0:
		_box(building, Vector3(w * 0.62, 1.55, 0.07), Vector3(0, 1.38, d * 0.505), Color(0.12, 0.24, 0.27))
		_box(building, Vector3(w * 0.68, 0.16, 0.92), Vector3(0, 2.25, d * 0.72), [Color(0.76, 0.22, 0.16), Color(0.88, 0.78, 0.58), Color(0.16, 0.40, 0.43)][posmod(seed_value, 3)])
	else:
		_box(building, Vector3(1.15, 1.15, 0.08), Vector3(0, window_y, d * 0.505), window_color)

	# Repeated upper-floor windows with stone sills and simple wooden frames.
	var window_count := 2 if w < 8.2 else 3
	for floor_index in range(1, 3):
		var y := minf(float(floor_index) * 2.65 + 0.9, h - 1.15)
		for col in range(window_count):
			var wx := (float(col) - float(window_count - 1) * 0.5) * (w * 0.72 / float(window_count))
			_box(building, Vector3(1.08, 1.12, 0.075), Vector3(wx, y, d * 0.505), window_color)
			_box(building, Vector3(1.20, 0.10, 0.13), Vector3(wx, y + 0.62, d * 0.53), trim_color)
			_box(building, Vector3(1.24, 0.12, 0.20), Vector3(wx, y - 0.62, d * 0.56), Color(0.68, 0.61, 0.49))
			_box(building, Vector3(0.09, 1.16, 0.11), Vector3(wx - 0.57, y, d * 0.54), frame_color)
			_box(building, Vector3(0.09, 1.16, 0.11), Vector3(wx + 0.57, y, d * 0.54), frame_color)
			if (seed_value + floor_index + col) % 3 == 0:
				# Small projecting balcony and rail.
				_box(building, Vector3(1.38, 0.12, 0.66), Vector3(wx, y - 0.58, d * 0.78), Color(0.67, 0.62, 0.53))
				_box(building, Vector3(1.30, 0.10, 0.08), Vector3(wx, y - 0.08, d * 0.98), Color(0.24, 0.27, 0.27))
				for rail_x in [-0.58, -0.20, 0.20, 0.58]:
					_box(building, Vector3(0.055, 0.48, 0.055), Vector3(wx + rail_x, y - 0.32, d * 0.98), Color(0.24, 0.27, 0.27))

	# A few side windows and wall-mounted air-conditioning units.
	for side in [-1.0, 1.0]:
		for floor_index in range(2):
			var side_y := 2.0 + float(floor_index) * 2.6
			_box(building, Vector3(0.075, 0.92, 1.0), Vector3(side * (w * 0.505), side_y, -d * 0.12), window_color)
		if (seed_value + int(side)) % 2 == 0:
			_box(building, Vector3(0.42, 0.34, 0.42), Vector3(side * (w * 0.505), 2.65, d * 0.12), Color(0.78, 0.79, 0.75))
			_box(building, Vector3(0.28, 0.10, 0.08), Vector3(side * (w * 0.53), 2.65, d * 0.12), Color(0.35, 0.38, 0.38))

	# Rooftop water tank and a small service shed on selected buildings.
	if seed_value % 2 == 0:
		var tank := MeshInstance3D.new()
		var tank_mesh := CylinderMesh.new()
		tank_mesh.top_radius = 0.48
		tank_mesh.bottom_radius = 0.48
		tank_mesh.height = 0.95
		tank.mesh = tank_mesh
		tank.position = Vector3(w * 0.25, h + 0.78, -d * 0.20)
		tank.material_override = _material(Color(0.78, 0.82, 0.80))
		building.add_child(tank)
		_box(building, Vector3(1.8, 1.25, 1.6), Vector3(-w * 0.22, h + 0.75, -d * 0.18), Color(0.82, 0.78, 0.68))

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position.y = h * 0.5
	building.add_child(collision)
	add_child(building)

func _create_palm(pos: Vector3) -> void:
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.16
	trunk_mesh.bottom_radius = 0.24
	trunk_mesh.height = 3.8
	trunk.mesh = trunk_mesh
	trunk.position = pos + Vector3(0, 1.9, 0)
	trunk.material_override = _material(Color(0.42, 0.29, 0.17))
	add_child(trunk)
	for i in range(7):
		var angle := TAU * float(i) / 7.0
		var leaf := MeshInstance3D.new()
		var leaf_mesh := CapsuleMesh.new()
		leaf_mesh.radius = 0.105
		leaf_mesh.height = 2.75
		leaf.mesh = leaf_mesh
		leaf.position = pos + Vector3(cos(angle) * 0.85, 3.8, sin(angle) * 0.85)
		leaf.rotation.x = PI * 0.5
		leaf.rotation.y = -angle
		leaf.rotation.z = -0.22
		leaf.material_override = _material(Color(0.13, 0.38, 0.22))
		add_child(leaf)

func _create_street_lamp(pos: Vector3) -> void:
	_box(self, Vector3(0.12, 3.5, 0.12), pos + Vector3(0, 1.75, 0), Color(0.12, 0.14, 0.16))
	_box(self, Vector3(0.65, 0.12, 0.3), pos + Vector3(0.22, 3.45, 0), Color(0.96, 0.82, 0.52))

func _spawn_player() -> void:
	player = CharacterBody3D.new()
	player.set_script(PLAYER_SCRIPT)
	player.position = START_PLAYER_POSITION
	player.rotation.y = START_PLAYER_ROTATION
	player.name = "Player"
	add_child(player)

func _spawn_residents() -> void:
	# Keep active simulation population proportional to the selected device tier.
	# Residents beyond this budget are not instantiated, avoiding hidden CPU/RAM cost.
	# Place residents on public sidewalks rather than random points that may
	# intersect buildings or spawn directly inside traffic lanes.
	var personalities := [
		"friendly", "shy", "busy", "curious", "grumpy", "friendly",
		"curious", "busy", "friendly", "shy", "curious", "busy"
	]
	var jobs := [
		"fisher", "shopkeeper", "mechanic", "student", "resident", "cook",
		"driver", "beachgoer", "shopkeeper", "student", "fisher", "mechanic"
	]
	var resident_names := [
		"سامي", "مريم", "أيمن", "ليلى", "منير", "آمنة",
		"يوسف", "سارة", "حاتم", "نجلاء", "وليد", "ريم"
	]
	var sidewalk_positions := [
		Vector3(62.0, 0, -44.0), Vector3(57.0, 0, -50.0),
		Vector3(51.0, 0, -44.2), Vector3(46.0, 0, -50.0),
		Vector3(40.0, 0, -44.0), Vector3(35.0, 0, -50.0),
		Vector3(29.0, 0, -44.2), Vector3(24.0, 0, -50.0),
		Vector3(18.0, 0, -44.0), Vector3(13.0, 0, -50.0),
		Vector3(7.0, 0, -44.2), Vector3(2.0, 0, -50.0)
	]
	var resident_budget: int = sidewalk_positions.size()
	for i in range(mini(sidewalk_positions.size(), resident_budget)):
		var npc := CharacterBody3D.new()
		npc.set_script(NPC_SCRIPT)
		npc.position = sidewalk_positions[i]
		npc.display_name = resident_names[i]
		npc.personality = personalities[i]
		npc.occupation = jobs[i]
		npc.is_adult = jobs[i] == "beachgoer"
		var work_spot: Vector3 = sidewalk_positions[i] + Vector3(0, 0, 5.0 if i % 2 == 0 else -5.0)
		npc.set_ai_context(player, world_systems, work_spot, i, save_manager)
		npc.set_ai_service(ai_service)
		add_child(npc)
	var imported_resident_count := 0
	var beachgoer_count := 0
	var resident_nodes := get_tree().get_nodes_in_group("mahdia_residents")
	for resident in resident_nodes:
		if bool(resident.get("imported_model_loaded")):
			imported_resident_count += 1
		if str(resident.get("occupation")) == "beachgoer":
			beachgoer_count += 1
	print("MAHDIA_IMPORTED_RESIDENTS=", imported_resident_count, "/", resident_nodes.size())
	print("MAHDIA_BEACHGOERS=", beachgoer_count, "/", resident_nodes.size())
	if is_instance_valid(life_manager):
		life_manager.call("resolve_delivery_target")

func _spawn_vehicle() -> void:
	vehicle = CharacterBody3D.new()
	vehicle.set_script(VEHICLE_SCRIPT)
	vehicle.position = restored_vehicle_position
	vehicle.rotation.y = START_PLAYER_ROTATION
	vehicle.name = "MahdiaCar"
	add_child(vehicle)
	if restore_vehicle_driver:
		vehicle.enter_vehicle(player)

func _spawn_traffic() -> void:
	# Four lightweight autonomous vehicles use the two existing main-road axes.
	# They stay inside the asphalt lanes and wrap at the distant road ends.
	var traffic_specs := [
		[true, -1.65, -52.0, 1.0, 4.0],
		[true, 1.65, 34.0, -1.0, 3.6],
		[false, -1.65, -40.0, 1.0, 3.8],
		[false, 1.65, 48.0, -1.0, 4.2]
	]
	var traffic_budget: int = traffic_specs.size()
	for i in range(mini(traffic_specs.size(), traffic_budget)):
		var spec: Array = traffic_specs[i]
		var car := CharacterBody3D.new()
		car.set_script(TRAFFIC_SCRIPT)
		car.name = "TrafficCar_%02d" % (i + 1)
		car.call("configure_traffic", bool(spec[0]), float(spec[1]), float(spec[2]), float(spec[3]), float(spec[4]))
		add_child(car)

func _setup_systems() -> void:
	world_systems = Node.new()
	world_systems.set_script(WORLD_SYSTEMS)
	world_systems.configure(sun, world_environment)
	add_child(world_systems)
	network_manager = Node.new()
	network_manager.set_script(NETWORK_SCRIPT)
	add_child(network_manager)
	save_manager = Node.new()
	save_manager.set_script(SAVE_SCRIPT)
	add_child(save_manager)
	planet_navigation = Node.new()
	planet_navigation.set_script(PLANET_NAV_SCRIPT)
	add_child(planet_navigation)
	planet_navigation.attach_player(player)
	terrain_streamer = Node3D.new()
	terrain_streamer.set_script(TERRAIN_STREAMER_SCRIPT)
	add_child(terrain_streamer)
	terrain_streamer.configure(player, planet_navigation)
	life_manager = Node.new()
	life_manager.set_script(LIFE_SCRIPT)
	add_child(life_manager)
	life_manager.setup(player, save_manager)
	ai_service = Node.new()
	ai_service.name = "MahdiaAIService"
	ai_service.set_script(AI_SERVICE_SCRIPT)
	add_child(ai_service)
	ai_service.connection_status.connect(_on_ai_connection_status)
	ai_service.auth_completed.connect(_on_ai_auth_completed)
	life_manager.set_ai_service(ai_service)
	_restore_world_progress()
	_apply_graphics_quality()

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(172, 14)
	panel.custom_minimum_size = Vector2(300, 54)
	panel.visible = false
	layer.add_child(panel)
	status_label = Label.new()
	status_label.text = "MAHDIA • 08:00 • Prototype"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(status_label)
	_apply_graphics_quality()
	hint_label = Label.new()
	hint_label.text = "الحركة: العصا اليسرى • الكاميرا: اسحب يمين الشاشة"
	hint_label.position = Vector2(172, 72)
	hint_label.custom_minimum_size = Vector2(390, 34)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.add_theme_font_size_override("font_size", 15)
	hint_label.visible = false
	layer.add_child(hint_label)
	var message_panel := PanelContainer.new()
	# Keep the message strip in the central safe zone: mobile action buttons
	# occupy the lower-right corner and the movement stick occupies lower-left.
	message_panel.anchor_left = 0.02
	message_panel.anchor_right = 0.34
	message_panel.anchor_top = 1.0
	message_panel.anchor_bottom = 1.0
	message_panel.offset_left = 0
	message_panel.offset_right = 0
	message_panel.offset_top = -274
	message_panel.offset_bottom = -208
	message_panel.custom_minimum_size = Vector2(250, 62)
	layer.add_child(message_panel)
	var message_label := Label.new()
	message_label.name = "LifeMessage"
	message_label.text = "مرحباً بك في المهدية! اقترب من شخص أو مبنى للتفاعل."
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.add_theme_font_size_override("font_size", 13)
	message_panel.add_child(message_label)
	message_panel.visible = false
	life_manager.message_changed.connect(func(value: String):
		message_label.text = value
		var technical_status := value.contains("JASSIM AI") or value.contains("خادم") or value.contains("جارٍ الفحص")
		message_panel.visible = not technical_status
	)

	# Lightweight chat input for the currently selected resident.
	chat_row = HBoxContainer.new()
	# Keep the resident chat in the central lower safe zone. The old
	# bottom-left placement overlapped the movement joystick on phones.
	chat_row.anchor_left = 0.18
	chat_row.anchor_right = 0.82
	chat_row.anchor_top = 1.0
	chat_row.anchor_bottom = 1.0
	chat_row.offset_top = -202
	chat_row.offset_bottom = -150
	chat_row.visible = false
	layer.add_child(chat_row)
	chat_input = LineEdit.new()
	chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_input.placeholder_text = "اكتب للمواطن القريب..."
	chat_input.max_length = 1200
	chat_input.text_submitted.connect(_on_chat_submitted)
	chat_row.add_child(chat_input)
	var send_button := Button.new()
	send_button.text = "إرسال"
	send_button.pressed.connect(_on_chat_send_pressed)
	chat_row.add_child(send_button)

	# Compact connection row: keep backend diagnostics out of the playable view.
	var ai_row_panel := PanelContainer.new()
	ai_row_panel.anchor_left = 1.0
	ai_row_panel.anchor_right = 1.0
	ai_row_panel.offset_left = -286
	ai_row_panel.offset_right = -16
	ai_row_panel.offset_top = 86
	ai_row_panel.offset_bottom = 124
	ai_row_panel.visible = false
	layer.add_child(ai_row_panel)
	var ai_row := HBoxContainer.new()
	ai_row_panel.add_child(ai_row)
	ai_status_label = Label.new()
	ai_status_label.text = "○ JASSIM AI: جارٍ الفحص"
	ai_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ai_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ai_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ai_status_label.clip_text = true
	ai_status_label.add_theme_font_size_override("font_size", 13)
	ai_row.add_child(ai_status_label)
	var ai_config_button := Button.new()
	ai_config_button.text = "⚙"
	ai_config_button.custom_minimum_size = Vector2(40, 34)
	ai_config_button.tooltip_text = "إعداد الذكاء الاصطناعي"
	ai_config_button.pressed.connect(_toggle_ai_setup)
	ai_row.add_child(ai_config_button)

	ai_setup_panel = PanelContainer.new()
	ai_setup_panel.anchor_left = 0.5
	ai_setup_panel.anchor_right = 0.5
	ai_setup_panel.anchor_top = 0.5
	ai_setup_panel.anchor_bottom = 0.5
	ai_setup_panel.offset_left = -230
	ai_setup_panel.offset_right = 230
	ai_setup_panel.offset_top = -205
	ai_setup_panel.offset_bottom = 205
	ai_setup_panel.visible = false
	layer.add_child(ai_setup_panel)
	var setup_col := VBoxContainer.new()
	ai_setup_panel.add_child(setup_col)
	var setup_title := Label.new()
	setup_title.text = "ربط سكان المهدية بالذكاء الاصطناعي المجاني"
	setup_col.add_child(setup_title)
	ai_endpoint_input = LineEdit.new()
	ai_endpoint_input.placeholder_text = "عنوان خادم JASSIM"
	ai_endpoint_input.text = str(ai_service.get("default_endpoint"))
	setup_col.add_child(ai_endpoint_input)
	ai_email_input = LineEdit.new()
	ai_email_input.placeholder_text = "البريد الإلكتروني لحساب JASSIM"
	ai_email_input.max_length = 254
	ai_email_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	setup_col.add_child(ai_email_input)
	ai_password_input = LineEdit.new()
	ai_password_input.placeholder_text = "كلمة المرور (10 أحرف على الأقل)"
	ai_password_input.max_length = 256
	ai_password_input.secret = true
	setup_col.add_child(ai_password_input)
	var auth_buttons := HBoxContainer.new()
	var login_button := Button.new()
	login_button.text = "تسجيل الدخول"
	login_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	login_button.pressed.connect(func(): _login_ai_account(false))
	auth_buttons.add_child(login_button)
	var register_button := Button.new()
	register_button.text = "إنشاء حساب مجاني"
	register_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	register_button.pressed.connect(func(): _login_ai_account(true))
	auth_buttons.add_child(register_button)
	setup_col.add_child(auth_buttons)
	var token_note := Label.new()
	token_note.text = "أو أدخل رمز جلسة موجوداً:"
	setup_col.add_child(token_note)
	ai_token_input = LineEdit.new()
	ai_token_input.placeholder_text = "رمز جلسة JASSIM (اختياري)"
	ai_token_input.secret = true
	setup_col.add_child(ai_token_input)
	var setup_note := Label.new()
	setup_note.text = "المحادثات العادية تبقى خاصة؛ شخصيات اللعبة فقط تستخدم مزود الذكاء المجاني. لا تضع رمز الإدارة العام هنا."
	setup_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	setup_col.add_child(setup_note)
	var save_ai_button := Button.new()
	save_ai_button.text = "حفظ رمز الجلسة"
	save_ai_button.pressed.connect(_save_ai_settings)
	setup_col.add_child(save_ai_button)
	var close_ai_button := Button.new()
	close_ai_button.text = "إغلاق"
	close_ai_button.pressed.connect(func(): ai_setup_panel.visible = false)
	setup_col.add_child(close_ai_button)

	_build_reference_hud(layer)

	var controls := Node.new()
	controls.set_script(MOBILE_CONTROLS)
	layer.add_child(controls)
	controls.setup(player)




func _update_mission_hud() -> void:
	if not is_instance_valid(mission_hud_label) or not is_instance_valid(life_manager) or not is_instance_valid(player) or not player.is_inside_tree():
		return
	var state := str(life_manager.get("delivery_state"))
	var job_claimed := bool(life_manager.get("job_claimed"))
	var title := "مهمة: بداية حياة جديدة في المهدية"
	var objective := "تحدث مع أحد السكان لبدء مهمتك الأولى"
	var target_position := Vector3.ZERO
	var has_target := false
	match state:
		"accepted":
			title = "مهمة 1/3: خدمة أهل المهدية"
			objective = "اشترِ وجبة من متجر الحي (10 د.ت)"
			for station in life_manager.get("stations"):
				if str(station.get("kind")) == "shop":
					target_position = station.get("position")
					has_target = true
		"ready":
			title = "مهمة 2/3: توصيل الطلب"
			objective = "عد إلى المواطن الذي طلب الوجبة وسلّمها"
			var recipient = life_manager.get("delivery_npc")
			if is_instance_valid(recipient) and recipient.is_inside_tree() and not recipient.is_queued_for_deletion():
				target_position = recipient.global_position
				has_target = true
		"completed":
			if not job_claimed:
				title = "مهمة 3/3: أول وظيفة"
				objective = "اذهب إلى مكتب العمل واحصل على أجرك (30 د.ت)"
				for station in life_manager.get("stations"):
					if str(station.get("kind")) == "job":
						target_position = station.get("position")
						has_target = true
			else:
				title = "اكتملت مهام البداية!"
				objective = "أصبحت تعرف المدينة. استكشف المهدية بحرية."
		_:
			var residents := get_tree().get_nodes_in_group("mahdia_residents")
			var nearest: Node3D
			var nearest_distance := INF
			for resident in residents:
				if is_instance_valid(resident) and resident.is_inside_tree() and not resident.is_queued_for_deletion():
					var distance := player.global_position.distance_to(resident.global_position)
					if distance < nearest_distance:
						nearest_distance = distance
						nearest = resident
			if is_instance_valid(nearest) and nearest.is_inside_tree() and not nearest.is_queued_for_deletion():
				target_position = nearest.global_position
				has_target = true
	var distance_text := ""
	if has_target:
		distance_text = "\nالمسافة: %.0f م" % player.global_position.distance_to(target_position)
	var display := "◆ %s\n%s%s" % [title, objective, distance_text]
	if display != mission_last_text:
		mission_hud_label.text = display
		mission_last_text = display
	if is_instance_valid(mission_target_marker) and mission_target_marker.is_inside_tree():
		mission_target_marker.visible = has_target
		if has_target:
			mission_target_marker.global_position = target_position + Vector3(0, 3.1, 0)

func _build_reference_hud(layer: CanvasLayer) -> void:
	# Circular navigation map: fixed to the upper-left safe area.
	var minimap := Control.new()
	minimap.position = Vector2(18, 14)
	minimap.custom_minimum_size = Vector2(124, 124)
	minimap.draw.connect(func():
		var center := Vector2(62, 62)
		minimap.draw_circle(center, 59.0, Color(0.025, 0.055, 0.07, 0.84))
		minimap.draw_arc(center, 58.0, 0.0, TAU, 72, Color(0.88, 0.91, 0.88, 0.92), 3.0)
		for road in range(-2, 3):
			var offset := float(road) * 22.0
			minimap.draw_line(Vector2(8, 62 + offset), Vector2(116, 62 + offset), Color(0.60, 0.68, 0.65, 0.54), 3.0)
			minimap.draw_line(Vector2(62 + offset, 8), Vector2(62 + offset, 116), Color(0.60, 0.68, 0.65, 0.54), 3.0)
		minimap.draw_line(Vector2(10, 88), Vector2(114, 88), Color(0.18, 0.48, 0.64, 0.78), 5.0)
		minimap.draw_circle(center, 5.0, Color(1.0, 0.82, 0.18))
		minimap.draw_colored_polygon(PackedVector2Array([Vector2(62, 27), Vector2(54, 47), Vector2(70, 47)]), Color.WHITE)
	)
	layer.add_child(minimap)
	var location := Label.new()
	location.text = "📍 المهدية"
	location.position = Vector2(22, 136)
	location.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
	location.add_theme_font_size_override("font_size", 15)
	layer.add_child(location)

	# A one-tap return-to-waterfront icon sits beside the minimap.
	var home_button := Button.new()
	home_button.text = "⌂"
	home_button.position = Vector2(148, 18)
	home_button.custom_minimum_size = Vector2(44, 44)
	home_button.add_theme_font_size_override("font_size", 27)
	home_button.focus_mode = Control.FOCUS_NONE
	_style_round_hud_button(home_button)
	home_button.pressed.connect(_return_to_start_view)
	layer.add_child(home_button)

	mission_hud_panel = PanelContainer.new()
	mission_hud_panel.anchor_left = 0.5
	mission_hud_panel.anchor_right = 0.5
	mission_hud_panel.offset_left = -148
	mission_hud_panel.offset_right = 148
	mission_hud_panel.offset_top = 12
	mission_hud_panel.offset_bottom = 78
	layer.add_child(mission_hud_panel)
	mission_hud_label = Label.new()
	mission_hud_label.text = "◆ المهمة الحالية\nتحدث مع أحد سكان المهدية لبدء مغامرتك"
	mission_hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mission_hud_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mission_hud_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mission_hud_label.add_theme_font_size_override("font_size", 14)
	mission_hud_panel.add_child(mission_hud_label)

	# Real wallet amount is read from the saved life simulation, not a fake HUD value.
	var wallet := PanelContainer.new()
	wallet.anchor_left = 1.0
	wallet.anchor_right = 1.0
	wallet.offset_left = -258
	wallet.offset_right = -82
	wallet.offset_top = 12
	wallet.offset_bottom = 52
	layer.add_child(wallet)
	wallet_label = Label.new()
	wallet_label.text = "💵 12,560 د.ت  ＋"
	wallet_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wallet_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wallet_label.add_theme_font_size_override("font_size", 15)
	wallet.add_child(wallet_label)

	level_label = Label.new()
	level_label.text = "Lv. 8   •   المهدية"
	level_label.anchor_left = 1.0
	level_label.anchor_right = 1.0
	level_label.offset_left = -252
	level_label.offset_right = -86
	level_label.offset_top = 56
	level_label.offset_bottom = 80
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.add_theme_font_size_override("font_size", 13)
	layer.add_child(level_label)

	var profile := _make_hud_icon(layer, "👤", 12.0, 12.0, Callable())
	profile.custom_minimum_size = Vector2(58, 58)
	profile.offset_left = -70.0
	profile.offset_right = -12.0
	profile.offset_bottom = 70.0

	_make_hud_icon(layer, "🏆", 12.0, 88.0, Callable(self, "_toggle_mission_panel"))
	_make_hud_icon(layer, "⚙", 64.0, 88.0, Callable(self, "_toggle_ai_setup"))
	_make_hud_icon(layer, "👥", 116.0, 88.0, Callable(self, "_show_resident_count"))
	_make_hud_icon(layer, "💬", 12.0, 198.0, Callable(self, "_toggle_chat_panel"))

	mission_target_marker = Label3D.new()
	mission_target_marker.name = "MissionWorldMarker"
	mission_target_marker.text = "▼\nالهدف"
	mission_target_marker.font_size = 48
	mission_target_marker.pixel_size = 0.006
	mission_target_marker.modulate = Color(1.0, 0.78, 0.12)
	mission_target_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mission_target_marker.no_depth_test = true
	mission_target_marker.visible = false
	add_child(mission_target_marker)


func _style_round_hud_button(button: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.035, 0.055, 0.075, 0.78)
	normal.set_corner_radius_all(22)
	normal.set_border_width_all(1)
	normal.border_color = Color(0.82, 0.88, 0.88, 0.78)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.11, 0.17, 0.20, 0.92)
	button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.18, 0.25, 0.27, 0.96)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.focus_mode = Control.FOCUS_NONE


func _make_hud_icon(layer: CanvasLayer, caption: String, right_offset: float, top_offset: float, callback: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.anchor_left = 1.0
	button.anchor_right = 1.0
	button.anchor_top = 0.0
	button.anchor_bottom = 0.0
	button.offset_left = -right_offset - 44.0
	button.offset_right = -right_offset
	button.offset_top = top_offset
	button.offset_bottom = top_offset + 44.0
	button.custom_minimum_size = Vector2(44, 44)
	button.add_theme_font_size_override("font_size", 21)
	_style_round_hud_button(button)
	if callback.is_valid():
		button.pressed.connect(callback)
	layer.add_child(button)
	return button


func _return_to_start_view() -> void:
	if not is_instance_valid(player):
		return
	if is_instance_valid(vehicle) and vehicle.driver == player:
		vehicle.exit_vehicle()
	player.global_position = START_PLAYER_POSITION
	player.rotation.y = START_PLAYER_ROTATION
	player.velocity = Vector3.ZERO


func _toggle_mission_panel() -> void:
	if is_instance_valid(mission_hud_panel):
		mission_hud_panel.visible = not mission_hud_panel.visible


func _toggle_chat_panel() -> void:
	if is_instance_valid(chat_row):
		chat_row.visible = not chat_row.visible
		if chat_row.visible and is_instance_valid(chat_input):
			chat_input.grab_focus()


func _show_resident_count() -> void:
	if is_instance_valid(life_manager):
		var count := get_tree().get_nodes_in_group("mahdia_residents").size()
		life_manager.call("_set_message", "سكان المهدية الموجودون الآن: %d" % count)


func _on_ai_connection_status(ready: bool, message: String) -> void:
	if not is_instance_valid(ai_status_label):
		return
	var compact_status := "JASSIM AI: متصل" if ready else "JASSIM AI: غير متصل"
	if not ready and (message.contains("فحص") or message.contains("جارٍ")):
		compact_status = "JASSIM AI: جارٍ الفحص"
	ai_status_label.text = ("● " if ready else "○ ") + compact_status
	# Preserve the complete diagnostic without drawing a long line across the world.
	ai_status_label.tooltip_text = message
	ai_status_label.add_theme_color_override("font_color", Color(0.35, 0.92, 0.55) if ready else Color(1.0, 0.72, 0.38))

func _on_chat_submitted(value: String) -> void:
	_send_chat_message(value)

func _on_chat_send_pressed() -> void:
	_send_chat_message(chat_input.text if is_instance_valid(chat_input) else "")

func _send_chat_message(value: String) -> void:
	if value.strip_edges().is_empty() or not is_instance_valid(life_manager):
		return
	life_manager.send_player_message(value)
	chat_input.clear()
	chat_input.release_focus()

func _toggle_ai_setup() -> void:
	if is_instance_valid(ai_setup_panel):
		ai_setup_panel.visible = not ai_setup_panel.visible

func _login_ai_account(create_account: bool) -> void:
	if not is_instance_valid(ai_service):
		return
	var new_endpoint := ai_endpoint_input.text.strip_edges()
	if not new_endpoint.begins_with("https://") or new_endpoint.ends_with("/api/chat"):
		_on_ai_auth_completed(false, "عنوان الخادم غير صالح؛ استخدم رابط HTTPS الأساسي")
		return
	ai_service.set("endpoint", new_endpoint.trim_suffix("/"))
	ai_service.authenticate_account(ai_email_input.text, ai_password_input.text, create_account)

func _on_ai_auth_completed(success: bool, message: String) -> void:
	_on_ai_connection_status(success, message)
	if success:
		ai_password_input.clear()
		ai_token_input.clear()
		ai_setup_panel.visible = false

func _save_ai_settings() -> void:
	if not is_instance_valid(ai_service):
		return
	var endpoint := ai_endpoint_input.text.strip_edges()
	var token := ai_token_input.text.strip_edges()
	var ok: bool = ai_service.configure(endpoint, token)
	if ok:
		ai_token_input.clear()
		ai_setup_panel.visible = false
		print("MAHDIA_AI_SETTINGS_SAVED")
	else:
		print("MAHDIA_AI_SETTINGS_INVALID")

func _process(delta: float) -> void:
	# Keep visual water animation smooth enough while avoiding per-frame work.
	water_clock += delta
	water_visual_elapsed += delta
	if water_visual_elapsed >= 0.05:
		water_visual_elapsed = 0.0
		for wave_index in range(water_waves.size()):
			var wave := water_waves[wave_index]
			if is_instance_valid(wave):
				var origin := water_wave_origins[wave_index]
				var phase := water_clock * 0.72 + float(wave_index) * 1.37
				wave.position.x = origin.x + fposmod(water_clock * 0.42 + float(wave_index) * 2.1, 8.0) - 4.0
				wave.position.y = origin.y + sin(phase) * 0.035
				wave.position.z = origin.z + sin(phase * 0.83) * 0.18
				wave.rotation.y = sin(phase * 0.6) * 0.025
				wave.scale.x = 0.78 + (0.22 * (0.5 + 0.5 * sin(phase)))
	autosave_elapsed += delta
	if autosave_elapsed >= AUTOSAVE_INTERVAL:
		autosave_elapsed = 0.0
		_save_world_progress()
	if not is_instance_valid(player):
		return
	var interact_pressed := InputMap.has_action("interact") and Input.is_action_just_pressed("interact")
	if (interact_pressed or player.interact_requested) and is_instance_valid(vehicle):
		if vehicle.driver == player:
			vehicle.exit_vehicle()
		elif player.global_position.distance_to(vehicle.global_position) < 4.0:
			vehicle.enter_vehicle(player)
		elif is_instance_valid(life_manager):
			life_manager.try_interact()
		player.interact_requested = false
	hud_refresh_elapsed += delta
	if hud_refresh_elapsed >= 0.20:
		hud_refresh_elapsed = 0.0
		if is_instance_valid(planet_navigation) and is_instance_valid(player):
			planet_navigation.update_from_player(player.global_position)
		_update_mission_hud()
		if is_instance_valid(wallet_label) and is_instance_valid(life_manager):
			wallet_label.text = "💵 %d د.ت  ＋" % int(life_manager.money)
		if is_instance_valid(status_label):
			var hour_value: float = world_systems.hour if is_instance_valid(world_systems) else 8.0
			status_label.text = "%s • %s • %02d:%02d • %s • %d د.ت • طاقة %d%% • جوع %d%%" % [planet_navigation.get_region_name(), planet_navigation.get_coordinate_text(), int(hour_value), int(fposmod(hour_value * 60.0, 60.0)), world_systems.weather, life_manager.money, int(life_manager.energy), int(life_manager.hunger)]


func _restore_world_progress() -> void:
	if not is_instance_valid(save_manager) or not is_instance_valid(player):
		return
	var data: Dictionary = save_manager.load_progress()
	var world: Dictionary = data.get(WORLD_SAVE_KEY, {})
	var migrate_legacy_start := false
	if world.has("player_position") and world.player_position is Array and world.player_position.size() == 3:
		var p: Array = world.player_position
		var saved_position := Vector3(float(p[0]), float(p[1]), float(p[2]))
		# Older builds started at the inland crossroads. Move only that old
		# default spawn; leave all genuine saved exploration positions untouched.
		migrate_legacy_start = saved_position.distance_to(Vector3(0, 0.03, 8)) < 14.0
		player.global_position = START_PLAYER_POSITION if migrate_legacy_start else saved_position
	if migrate_legacy_start:
		player.rotation.y = START_PLAYER_ROTATION
	elif world.has("player_rotation_y"):
		player.rotation.y = float(world.player_rotation_y)
	if world.has("vehicle_position") and world.vehicle_position is Array and world.vehicle_position.size() == 3:
		var car: Array = world.vehicle_position
		restored_vehicle_position = START_VEHICLE_POSITION if migrate_legacy_start else Vector3(float(car[0]), float(car[1]), float(car[2]))
	restore_vehicle_driver = bool(world.get("was_driving", false))
	quality_level = 2
	print("MAHDIA_WORLD_PROGRESS_RESTORED")

func _save_world_progress() -> void:
	if not is_instance_valid(save_manager) or not is_instance_valid(player):
		return
	var data: Dictionary = save_manager.load_progress()
	var car_position := restored_vehicle_position
	var was_driving := false
	if is_instance_valid(vehicle):
		car_position = vehicle.global_position
		was_driving = vehicle.driver == player
	data[WORLD_SAVE_KEY] = {
		"player_position": [player.global_position.x, player.global_position.y, player.global_position.z],
		"player_rotation_y": player.rotation.y,
		"vehicle_position": [car_position.x, car_position.y, car_position.z],
		"was_driving": was_driving,
		"graphics_quality": quality_level
	}
	var result: Error = save_manager.save_progress(data)
	if result != OK:
		push_warning("Could not save Mahdia world progress: %s" % error_string(result))

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		_save_world_progress()

func _select_device_profile() -> void:
	# The world uses one shared visual and simulation configuration everywhere.
	quality_level = 2

func _apply_graphics_quality() -> void:
	Engine.max_fps = 60
	Engine.physics_ticks_per_second = 60
	get_viewport().scaling_3d_scale = 1.0
	if is_instance_valid(sun):
		sun.visible = true
		sun.shadow_enabled = true
	if is_instance_valid(world_environment):
		world_environment.ambient_light_energy = 0.94


func _surface_texture(kind: String) -> ImageTexture:
	if surface_texture_cache.has(kind):
		return surface_texture_cache[kind]
	var image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 74123 if kind == "asphalt" else 91827
	for y in range(128):
		for x in range(128):
			var grain := rng.randf_range(0.84, 1.0) if kind == "asphalt" else rng.randf_range(0.91, 1.0)
			var broad := 0.97 + sin(float(x) * 0.09 + sin(float(y) * 0.055)) * (0.035 if kind == "asphalt" else 0.018)
			var value := clampf(grain * broad, 0.72, 1.0)
			image.set_pixel(x, y, Color(value, value, value, 1.0))
	var texture := ImageTexture.create_from_image(image)
	surface_texture_cache[kind] = texture
	return texture

func _textured_box(parent: Node3D, size: Vector3, pos: Vector3, tint: Color, texture_kind: String, uv_scale: Vector3) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.mesh = _rounded_box_mesh(size)
	item.position = pos
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	var asset := "cobblestone_pavement" if texture_kind == "stone" else ""
	var diffuse := _pbr_texture(asset, "diff") if not asset.is_empty() else null
	if diffuse != null:
		material.albedo_texture = diffuse
		_apply_pbr_maps(material, asset)
	else:
		material.albedo_texture = _surface_texture(texture_kind)
	material.uv1_scale = uv_scale
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.roughness = 0.96
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	item.material_override = material
	parent.add_child(item)
	return item

func _create_mobile_city_details() -> void:
	# A compact visual baseline for entry-level phones: a few high-value props,
	# shared cached meshes/materials, and no extra collision or lighting nodes.
	for x in [-38.0, 38.0]:
		_box(self, Vector3(0.12, 3.0, 0.12), Vector3(x, 1.5, 6.2), Color(0.16, 0.18, 0.19))
		_box(self, Vector3(0.52, 0.72, 0.30), Vector3(x, 3.25, 6.2), Color(0.12, 0.14, 0.15))
		_box(self, Vector3(0.16, 0.16, 0.08), Vector3(x, 3.42, 6.02), Color(0.76, 0.18, 0.13))
		_box(self, Vector3(0.16, 0.16, 0.08), Vector3(x, 3.18, 6.02), Color(0.18, 0.58, 0.30))
	# Simple curbside bins and planted tubs give the promenade and sidewalks scale.
	for i in range(4):
		var x := -27.0 + float(i) * 18.0
		_box(self, Vector3(0.58, 0.78, 0.58), Vector3(x, 0.42, -52.0), Color(0.16, 0.31, 0.32))
		_box(self, Vector3(1.05, 0.30, 0.72), Vector3(x + 7.0, 0.20, 5.55), Color(0.48, 0.36, 0.25))
		_box(self, Vector3(0.86, 0.18, 0.54), Vector3(x + 7.0, 0.43, 5.55), Color(0.20, 0.39, 0.23))


func _create_realistic_street_layer() -> void:
	# Fine pavement joints break up the huge flat sidewalk slabs.
	for side in [-1.0, 1.0]:
		for step in range(-14, 15):
			var x := float(step) * 6.0
			_box(self, Vector3(0.035, 0.012, 1.48), Vector3(x, 0.185, side * 5.5), Color(0.62, 0.59, 0.53))
			var z := float(step) * 6.0
			_box(self, Vector3(1.48, 0.012, 0.035), Vector3(side * 5.5, 0.185, z), Color(0.62, 0.59, 0.53))
	# Drain grates and manhole covers add believable street-scale details.
	for x in [-42.0, -18.0, 18.0, 42.0]:
		_box(self, Vector3(0.72, 0.035, 0.24), Vector3(x, 0.115, 4.35), Color(0.19, 0.21, 0.21))
		for slot in range(5):
			_box(self, Vector3(0.045, 0.012, 0.20), Vector3(x - 0.28 + float(slot) * 0.14, 0.139, 4.35), Color(0.48, 0.50, 0.49))
	for pos in [Vector3(-4.25, 0.13, -22.0), Vector3(4.25, 0.13, 26.0), Vector3(-22.0, 0.13, 4.25)]:
		var cover := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.34
		disc.bottom_radius = 0.34
		disc.height = 0.035
		disc.radial_segments = 16
		cover.mesh = disc
		cover.position = pos
		cover.material_override = _material(Color(0.32, 0.34, 0.34))
		add_child(cover)
	# Street-name signs around the central junction.
	for sign_data in [[Vector3(-7.4, 2.75, -7.4), "نهج البحر"], [Vector3(7.4, 2.75, 7.4), "المهدية"]]:
		var sign_pos: Vector3 = sign_data[0]
		_box(self, Vector3(1.85, 0.55, 0.10), sign_pos, Color(0.12, 0.34, 0.30))
		var sign_text := Label3D.new()
		sign_text.text = str(sign_data[1])
		sign_text.position = sign_pos + Vector3(0, 0, -0.065)
		sign_text.font_size = 30
		sign_text.pixel_size = 0.006
		sign_text.modulate = Color(0.96, 0.94, 0.84)
		add_child(sign_text)
	# Utility poles and subtly sagging overhead cables; no physics or dynamic lights.
	var cable_material := StandardMaterial3D.new()
	cable_material.albedo_color = Color(0.12, 0.13, 0.14)
	cable_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	for pole_index in range(4):
		var px := -45.0 + float(pole_index) * 30.0
		var pole := MeshInstance3D.new()
		var pole_mesh := CylinderMesh.new()
		pole_mesh.top_radius = 0.10
		pole_mesh.bottom_radius = 0.15
		pole_mesh.height = 6.5
		pole.mesh = pole_mesh
		pole.position = Vector3(px, 3.25, 17.0)
		pole.material_override = _material(Color(0.43, 0.37, 0.29))
		add_child(pole)
		_box(self, Vector3(1.1, 0.10, 0.10), Vector3(px, 6.15, 17.0), Color(0.30, 0.28, 0.24))
	for cable_index in range(3):
		var cable := ImmediateMesh.new()
		cable.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, cable_material)
		for segment in range(17):
			var t := float(segment) / 16.0
			var x := lerpf(-45.0, 45.0, t)
			var sag := sin(t * PI) * 0.52
			cable.surface_add_vertex(Vector3(x, 6.25 - sag - float(cable_index) * 0.20, 17.0 + float(cable_index - 1) * 0.16))
		cable.surface_end()
		var cable_instance := MeshInstance3D.new()
		cable_instance.mesh = cable
		add_child(cable_instance)

func _create_city_details() -> void:
	# Street-level details add scale and recognizable Mediterranean town character
	# without textures, real-time lights, or costly physics bodies.
	# Two compact bus shelters along the main avenue.
	for i in range(2):
		var x := -29.0 + float(i) * 58.0
		var z := 13.0
		_box(self, Vector3(4.2, 0.12, 1.65), Vector3(x, 2.15, z), Color(0.80, 0.83, 0.80))
		for side in [-1.0, 1.0]:
			_box(self, Vector3(0.12, 2.1, 0.12), Vector3(x + side * 1.95, 1.05, z), Color(0.22, 0.31, 0.32))
		_box(self, Vector3(3.7, 0.10, 0.48), Vector3(x, 0.62, z + 0.35), Color(0.35, 0.25, 0.17))
		_box(self, Vector3(0.85, 1.05, 0.08), Vector3(x - 1.35, 1.42, z - 0.78), Color(0.12, 0.34, 0.42))
		_box(self, Vector3(0.92, 0.12, 0.12), Vector3(x - 1.35, 2.02, z - 0.70), Color(0.92, 0.84, 0.64))

	# Low-cost traffic signals at the central crossing.
	for corner in [Vector3(-6.2, 0, -6.2), Vector3(6.2, 0, 6.2)]:
		_box(self, Vector3(0.12, 3.2, 0.12), corner + Vector3(0, 1.6, 0), Color(0.15, 0.17, 0.18))
		_box(self, Vector3(0.48, 0.92, 0.30), corner + Vector3(0, 3.55, 0), Color(0.12, 0.13, 0.14))
		_box(self, Vector3(0.19, 0.19, 0.08), corner + Vector3(0, 3.82, -0.17), Color(0.72, 0.16, 0.12))
		_box(self, Vector3(0.19, 0.19, 0.08), corner + Vector3(0, 3.55, -0.17), Color(0.88, 0.66, 0.16))
		_box(self, Vector3(0.19, 0.19, 0.08), corner + Vector3(0, 3.28, -0.17), Color(0.16, 0.58, 0.28))

	# Planters, rubbish bins and short protective bollards on the promenade.
	for i in range(6):
		var x := -30.0 + float(i) * 12.0
		_box(self, Vector3(1.35, 0.42, 0.72), Vector3(x, 0.28, -52.2), Color(0.58, 0.43, 0.30))
		_box(self, Vector3(1.12, 0.22, 0.54), Vector3(x, 0.58, -52.2), Color(0.20, 0.40, 0.24))
		if i % 2 == 0:
			_box(self, Vector3(0.48, 0.85, 0.48), Vector3(x + 2.4, 0.53, -51.8), Color(0.16, 0.30, 0.31))
	for i in range(12):
		var x := -33.0 + float(i) * 6.0
		_box(self, Vector3(0.22, 0.72, 0.22), Vector3(x, 0.42, -55.8), Color(0.78, 0.76, 0.68))

	# Small storefront awnings make the ground-level blocks read as lived-in shops.
	for i in range(5):
		var x := -30.0 + float(i) * 15.0
		var awning_color: Color = [Color(0.76, 0.22, 0.16), Color(0.88, 0.78, 0.58), Color(0.16, 0.40, 0.43)][i % 3]
		_box(self, Vector3(3.2, 0.14, 1.05), Vector3(x, 3.0, 10.8), awning_color)
		_box(self, Vector3(3.2, 0.12, 0.12), Vector3(x, 2.88, 11.28), Color(0.94, 0.88, 0.74))

	_create_realistic_street_layer()
