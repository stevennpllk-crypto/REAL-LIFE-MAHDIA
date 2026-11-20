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
var mobile_controls: Node
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
var quality_level := 1
var quality_button: Button
var world_ready := false
# Object pools: one slot per resident/traffic car. A node above the active
# tier budget is detached from the tree (no render, physics or script cost)
# and reattached when the budget rises, instead of being freed and rebuilt.
var resident_slots: Dictionary = {}
var traffic_slots: Dictionary = {}
var pool_reuse_count := 0
var pool_create_count := 0
# Draw-distance LOD: small facade details fade out before the building shell.
var building_detail_meshes: Array[GeometryInstance3D] = []
var building_count := 0
const CAMERA_FAR_BY_TIER := [160.0, 220.0, 320.0]
const DETAIL_RANGE_BY_TIER := [30.0, 55.0, 100.0]
const RESIDENT_BUDGETS := [5, 8, 12]
const TRAFFIC_BUDGETS := [2, 3, 4]
var restored_vehicle_position := START_VEHICLE_POSITION
var restore_vehicle_driver := false
var mission_hud_label: Label
var mission_target_marker: Label3D
var mission_last_text := ""
var wallet_label: Label
var level_label: Label
var chat_row: HBoxContainer
var mission_hud_panel: PanelContainer
# Spawn on the corniche promenade, facing west along it toward Borj el Kebir.
const START_PLAYER_POSITION := Vector3(68.0, 0.03, -48.5)
const START_PLAYER_ROTATION := PI * 0.5 - 0.06
# The player's black sedan is parked at the promenade curb, nose toward the spawn.
const START_VEHICLE_POSITION := Vector3(61.5, 0.1, -41.7)
const START_VEHICLE_ROTATION := -PI * 0.5
const CORNICHE_SCRIPT = preload("res://scripts/corniche.gd")
const ICON_BUTTON = preload("res://scripts/hud_icon_button.gd")
const HDRI_PATH := "res://assets/hdri/kloofendal_48d_partly_cloudy_puresky_2k.hdr"
var corniche: Node3D
var minimap_content: Control
var minimap_overlay: Control
var minimap_static_rects: Array = []
var level_bar: ProgressBar
var chat_log_label: RichTextLabel
var chat_log_lines: Array[String] = []
var info_panel: PanelContainer
var info_title: Label
var info_body: RichTextLabel
var settings_panel: PanelContainer
var voice_enabled := false
var voice_button: Button
var tts_voice := ""
var renderer_name := ""
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
	await _build_corniche()
	print("MAHDIA_CORNICHE_READY")
	await _build_town()
	print("MAHDIA_TOWN_READY")
	_spawn_residents()
	_spawn_vehicle()
	_spawn_traffic()
	world_ready = true
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
	renderer_name = str(ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method"))
	if RenderingServer.has_method("get_current_rendering_method"):
		renderer_name = str(RenderingServer.call("get_current_rendering_method"))
	var world_env := WorldEnvironment.new()
	world_environment = Environment.new()
	# Midday Mediterranean sky: CC0 Poly Haven HDRI when downloaded, with a
	# matching procedural sky as fallback. It also lights the scene (ambient +
	# reflections), which is what makes the white facades and the sea read.
	var sky := Sky.new()
	var panorama: Texture2D = null
	if ResourceLoader.exists(HDRI_PATH):
		panorama = load(HDRI_PATH) as Texture2D
	if panorama != null:
		var pano := PanoramaSkyMaterial.new()
		pano.panorama = panorama
		pano.filter = true
		sky.sky_material = pano
	else:
		var procedural := ProceduralSkyMaterial.new()
		procedural.sky_top_color = Color(0.16, 0.42, 0.80)
		procedural.sky_horizon_color = Color(0.68, 0.82, 0.94)
		procedural.ground_horizon_color = Color(0.68, 0.82, 0.94)
		procedural.ground_bottom_color = Color(0.18, 0.32, 0.46)
		procedural.sun_angle_max = 18.0
		sky.sky_material = procedural
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	world_environment.background_mode = Environment.BG_SKY
	world_environment.sky = sky
	world_environment.sky_rotation = Vector3(0, deg_to_rad(40.0), 0)
	world_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	world_environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	world_environment.ambient_light_sky_contribution = 1.0
	world_environment.ambient_light_energy = 1.0
	world_environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	world_environment.tonemap_exposure = 1.0
	world_environment.tonemap_white = 6.0
	# Glow, fog and colour adjustments are supported by the Mobile renderer.
	world_environment.glow_enabled = true
	world_environment.glow_intensity = 0.45
	world_environment.glow_strength = 0.9
	world_environment.glow_bloom = 0.02
	world_environment.glow_hdr_threshold = 1.15
	world_environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	world_environment.fog_enabled = true
	world_environment.fog_light_color = Color(0.70, 0.80, 0.90)
	world_environment.fog_light_energy = 1.0
	world_environment.fog_density = 0.0016
	world_environment.fog_aerial_perspective = 0.35
	world_environment.fog_sky_affect = 0.0
	world_environment.fog_sun_scatter = 0.08
	world_environment.adjustment_enabled = true
	world_environment.adjustment_saturation = 1.12
	world_environment.adjustment_contrast = 1.06
	world_environment.adjustment_brightness = 1.0
	# SSAO/SSIL/SDFGI/SSR exist only in Forward+; the Mobile and Compatibility
	# renderers ignore them, so enable SSAO only where it actually runs.
	world_environment.ssao_enabled = renderer_name == "forward_plus"
	world_environment.ssao_radius = 1.2
	world_environment.ssao_intensity = 1.6
	world_environment.ssil_enabled = false
	world_environment.sdfgi_enabled = false
	world_environment.volumetric_fog_enabled = false
	world_env.environment = world_environment
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50, 135, 0)
	sun.light_energy = 1.75
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.2
	sun.directional_shadow_max_distance = 60.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.shadow_opacity = 0.9
	sun.visible = true
	add_child(sun)

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
	# The shore collider keeps its original extent (to z = -59, where the
	# swimming zone starts); its visual stops at the corniche seawall.
	var shore := StaticBody3D.new()
	_box(shore, Vector3(180, 1, 26.7), Vector3(0, -0.6, -43.65), Color(0.82, 0.76, 0.64))
	var shore_shape := CollisionShape3D.new()
	var shore_box := BoxShape3D.new()
	shore_box.size = Vector3(180, 1, 29)
	shore_shape.shape = shore_box
	shore_shape.position = Vector3(0, -0.55, -44.5)
	shore.add_child(shore_shape)
	add_child(shore)

func _build_corniche() -> void:
	corniche = Node3D.new()
	corniche.set_script(CORNICHE_SCRIPT)
	add_child(corniche)
	await corniche.call("build", self, clampi(quality_level, 0, 2))
	_create_beach_cafe()
	_collect_minimap_rects()

# Called by the corniche and by _create_building: registers a building for
# occlusion culling, the per-tier facade-detail LOD and the minimap.
func register_building(building: StaticBody3D, size: Vector3) -> void:
	# The first two meshes are the shell and roof slab; everything after
	# them is facade detail that the draw-distance LOD may hide.
	var mesh_index := 0
	for child in building.get_children():
		if child is GeometryInstance3D:
			if mesh_index >= 2:
				var detail := child as GeometryInstance3D
				detail.visibility_range_end = DETAIL_RANGE_BY_TIER[clampi(quality_level, 0, 2)]
				detail.visibility_range_end_margin = 4.0
				detail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				building_detail_meshes.append(detail)
			mesh_index += 1
	# A slightly inset box occluder lets the renderer skip props, cars and
	# residents that are completely hidden behind this building.
	var occluder := OccluderInstance3D.new()
	var box_occluder := BoxOccluder3D.new()
	box_occluder.size = Vector3(maxf(size.x - 0.2, 0.5), maxf(size.y - 0.1, 0.5), maxf(size.z - 0.2, 0.5))
	occluder.occluder = box_occluder
	occluder.position.y = size.y * 0.5
	building.add_child(occluder)
	building.set_meta("footprint", Vector2(size.x, size.z))
	building.add_to_group("mahdia_buildings")
	building_count += 1

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


func _build_town() -> void:
	# Main asphalt streets crossing a compact Mahdia-inspired neighborhood.
	_textured_box(self, Vector3(180, 0.12, 9), Vector3(0, 0.035, 0), Color(0.16, 0.18, 0.19), "asphalt", Vector3(4, 30, 1))
	# The north-south avenue now meets the corniche road instead of the sea.
	_textured_box(self, Vector3(9, 0.12, 128), Vector3(0, 0.04, 26), Color(0.16, 0.18, 0.19), "asphalt", Vector3(22, 4, 1))
	for x in range(-80, 81, 12):
		_box(self, Vector3(5.0, 0.025, 0.16), Vector3(float(x), 0.11, 0), Color(0.92, 0.84, 0.58))
	for z in range(-32, 81, 12):
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
		_textured_box(self, Vector3(1.6, 0.2, 124), Vector3(side * 5.5, 0.08, 29), Color(0.78, 0.75, 0.68), "stone", Vector3(22, 2, 1))

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
			# The seafront row now belongs to the corniche buildings.
			if z < -20.0:
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
	register_building(building, size)
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

const RESIDENT_PERSONALITIES := [
	"friendly", "shy", "busy", "curious", "grumpy", "friendly",
	"curious", "busy", "friendly", "shy", "curious", "busy"
]
const RESIDENT_JOBS := [
	"fisher", "shopkeeper", "mechanic", "student", "resident", "cook",
	"driver", "beachgoer", "shopkeeper", "student", "fisher", "mechanic"
]
const RESIDENT_NAMES := [
	"سامي", "مريم", "أيمن", "ليلى", "منير", "آمنة",
	"يوسف", "سارة", "حاتم", "نجلاء", "وليد", "ريم"
]
# Public sidewalk spots, so residents never spawn inside buildings or lanes.
const SIDEWALK_POSITIONS := [
	Vector3(62.0, 0, -44.0), Vector3(57.0, 0, -50.0),
	Vector3(51.0, 0, -44.2), Vector3(46.0, 0, -50.0),
	Vector3(40.0, 0, -44.0), Vector3(35.0, 0, -50.0),
	Vector3(29.0, 0, -44.2), Vector3(24.0, 0, -50.0),
	Vector3(18.0, 0, -44.0), Vector3(13.0, 0, -50.0),
	Vector3(7.0, 0, -44.2), Vector3(2.0, 0, -50.0)
]
# Four lightweight autonomous vehicles on the two main-road axes; they wrap
# at the road ends, so each pooled car is reused continuously while active.
const TRAFFIC_SPECS := [
	[true, -1.65, -52.0, 1.0, 4.0],
	[true, 1.65, 34.0, -1.0, 3.6],
	[false, -1.65, -40.0, 1.0, 3.8],
	[false, 1.65, 48.0, -1.0, 4.2]
]

func _spawn_residents() -> void:
	# Only residents inside the active tier budget are ever instantiated, so a
	# Low-tier session never pays the RAM cost of the full population.
	_apply_resident_budget()
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

func _create_resident(i: int) -> CharacterBody3D:
	var npc := CharacterBody3D.new()
	npc.set_script(NPC_SCRIPT)
	npc.position = SIDEWALK_POSITIONS[i]
	npc.display_name = RESIDENT_NAMES[i]
	npc.personality = RESIDENT_PERSONALITIES[i]
	npc.occupation = RESIDENT_JOBS[i]
	npc.is_adult = RESIDENT_JOBS[i] == "beachgoer"
	var work_spot: Vector3 = SIDEWALK_POSITIONS[i] + Vector3(0, 0, 5.0 if i % 2 == 0 else -5.0)
	npc.set_ai_context(player, world_systems, work_spot, i, save_manager)
	npc.set_ai_service(ai_service)
	return npc

func _apply_resident_budget() -> void:
	var budget: int = mini(RESIDENT_BUDGETS[clampi(quality_level, 0, 2)], SIDEWALK_POSITIONS.size())
	for i in range(SIDEWALK_POSITIONS.size()):
		var npc: Node3D = resident_slots.get(i)
		if i < budget:
			if npc == null:
				npc = _create_resident(i)
				resident_slots[i] = npc
				pool_create_count += 1
				add_child(npc)
			elif not npc.is_inside_tree():
				# Reuse the parked resident: memory, model and mesh are kept.
				if npc is CharacterBody3D:
					(npc as CharacterBody3D).velocity = Vector3.ZERO
				add_child(npc)
				pool_reuse_count += 1
		elif npc != null and npc.is_inside_tree():
			if npc.has_method("_save_memory"):
				npc.call("_save_memory")
			remove_child(npc)
	if is_instance_valid(life_manager):
		var target = life_manager.get("delivery_npc")
		if target is Node and not (target as Node).is_inside_tree():
			life_manager.set("delivery_npc", null)
		life_manager.call("resolve_delivery_target")

func _apply_traffic_budget() -> void:
	var budget: int = mini(TRAFFIC_BUDGETS[clampi(quality_level, 0, 2)], TRAFFIC_SPECS.size())
	for i in range(TRAFFIC_SPECS.size()):
		var car: Node3D = traffic_slots.get(i)
		if i < budget:
			if car == null:
				var spec: Array = TRAFFIC_SPECS[i]
				car = CharacterBody3D.new()
				car.set_script(TRAFFIC_SCRIPT)
				car.name = "TrafficCar_%02d" % (i + 1)
				car.call("configure_traffic", bool(spec[0]), float(spec[1]), float(spec[2]), float(spec[3]), float(spec[4]))
				traffic_slots[i] = car
				pool_create_count += 1
				add_child(car)
			elif not car.is_inside_tree():
				add_child(car)
				pool_reuse_count += 1
		elif car != null and car.is_inside_tree():
			remove_child(car)

func _exit_tree() -> void:
	# Parked pool members are outside the tree, so free them explicitly.
	for pool in [resident_slots, traffic_slots]:
		for node in pool.values():
			if is_instance_valid(node) and not node.is_inside_tree():
				node.free()
		pool.clear()

func get_pool_status() -> Dictionary:
	var parked := 0
	for pool in [resident_slots, traffic_slots]:
		for node in pool.values():
			if is_instance_valid(node) and not node.is_inside_tree():
				parked += 1
	return {
		"residents_active": get_tree().get_nodes_in_group("mahdia_residents").size(),
		"traffic_active": get_tree().get_nodes_in_group("mahdia_traffic").size(),
		"parked": parked,
		"created": pool_create_count,
		"reused": pool_reuse_count
	}

func _spawn_vehicle() -> void:
	vehicle = CharacterBody3D.new()
	vehicle.set_script(VEHICLE_SCRIPT)
	vehicle.position = restored_vehicle_position
	vehicle.rotation.y = START_VEHICLE_ROTATION
	if is_instance_valid(corniche) and corniche.has_method("car_mesh"):
		vehicle.set("body_mesh_override", corniche.call("car_mesh", Color(0.015, 0.017, 0.02), false, false))
	vehicle.name = "MahdiaCar"
	add_child(vehicle)
	if restore_vehicle_driver:
		vehicle.enter_vehicle(player)

func _spawn_traffic() -> void:
	_apply_traffic_budget()

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
	quality_button = Button.new()
	quality_button.anchor_left = 1.0
	quality_button.anchor_right = 1.0
	quality_button.offset_left = -164
	quality_button.offset_right = -16
	quality_button.offset_top = 14
	quality_button.offset_bottom = 56
	quality_button.custom_minimum_size = Vector2(148, 42)
	quality_button.pressed.connect(_cycle_graphics_quality)
	# Lives inside the settings panel (gear icon); see _build_reference_hud.
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
		# Game messages now flow into the reference-style chat log.
		message_panel.visible = false
		if not technical_status:
			_push_chat_log(value)
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

	mobile_controls = Node.new()
	mobile_controls.set_script(MOBILE_CONTROLS)
	layer.add_child(mobile_controls)
	mobile_controls.setup(player)




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
		distance_text = " · %.0f م" % player.global_position.distance_to(target_position)
	var display := "%s%s" % [objective, distance_text]
	if is_instance_valid(mission_hud_panel):
		mission_hud_panel.tooltip_text = title
	if display != mission_last_text:
		mission_hud_label.text = display
		mission_last_text = display
	if is_instance_valid(mission_target_marker) and mission_target_marker.is_inside_tree():
		mission_target_marker.visible = has_target
		if has_target:
			mission_target_marker.global_position = target_position + Vector3(0, 3.1, 0)

func _hud_panel_style(radius := 10, alpha := 0.55) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.07, alpha)
	style.set_corner_radius_all(radius)
	style.set_border_width_all(1)
	style.border_color = Color(1, 1, 1, 0.18)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style

func _icon_button(layer: Node, icon: String, diameter: float, anchor_right: bool, pos: Vector2, callback: Callable) -> Button:
	var button: Button = ICON_BUTTON.new()
	button.call("setup", icon, diameter)
	button.name = "Hud_" + icon
	if anchor_right:
		button.anchor_left = 1.0
		button.anchor_right = 1.0
		button.offset_left = pos.x - diameter
		button.offset_right = pos.x
	else:
		button.offset_left = pos.x
		button.offset_right = pos.x + diameter
	button.offset_top = pos.y
	button.offset_bottom = pos.y + diameter
	if callback.is_valid():
		button.pressed.connect(callback)
	layer.add_child(button)
	return button

func _build_reference_hud(layer: CanvasLayer) -> void:
	# --- Round minimap (top-left): live plan of the real world around the
	# player, rotated with the camera. Children are clipped to the circle.
	var minimap_frame := Control.new()
	minimap_frame.name = "Minimap"
	minimap_frame.position = Vector2(14, 10)
	minimap_frame.size = Vector2(136, 136)
	minimap_frame.custom_minimum_size = Vector2(136, 136)
	minimap_frame.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	minimap_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_frame.draw.connect(func(): minimap_frame.draw_circle(Vector2(68, 68), 66.0, Color(0.52, 0.62, 0.46, 1.0)))
	layer.add_child(minimap_frame)
	minimap_content = Control.new()
	minimap_content.size = Vector2(136, 136)
	minimap_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_content.draw.connect(_draw_minimap)
	minimap_frame.add_child(minimap_content)
	minimap_overlay = Control.new()
	minimap_overlay.position = minimap_frame.position
	minimap_overlay.size = Vector2(136, 136)
	minimap_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_overlay.draw.connect(func():
		var c := Vector2(68, 68)
		minimap_overlay.draw_arc(c, 66.0, 0.0, TAU, 72, Color(1, 1, 1, 0.92), 3.0, true)
		minimap_overlay.draw_arc(c, 69.0, 0.0, TAU, 72, Color(0, 0, 0, 0.35), 2.0, true)
		minimap_overlay.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -9), c + Vector2(6.5, 7), c + Vector2(0, 3.5), c + Vector2(-6.5, 7)]), Color.WHITE)
		minimap_overlay.draw_polyline(PackedVector2Array([c + Vector2(0, -9), c + Vector2(6.5, 7), c + Vector2(0, 3.5), c + Vector2(-6.5, 7), c + Vector2(0, -9)]), Color(0, 0, 0, 0.6), 1.2, true)
	)
	layer.add_child(minimap_overlay)
	var location := HBoxContainer.new()
	location.position = Vector2(22, 150)
	location.add_theme_constant_override("separation", 4)
	layer.add_child(location)
	var pin := Control.new()
	pin.custom_minimum_size = Vector2(18, 22)
	pin.draw.connect(func(): ICON_BUTTON.draw_icon_shape(pin, "pin", Vector2(9, 11), 8.0, Color(1.0, 0.80, 0.18)))
	location.add_child(pin)
	var location_label := Label.new()
	location_label.text = "المهدية"
	location_label.add_theme_font_size_override("font_size", 15)
	location_label.add_theme_color_override("font_color", Color.WHITE)
	location_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	location_label.add_theme_constant_override("outline_size", 4)
	location.add_child(location_label)

	# Home (back to the corniche spawn) and wardrobe buttons beside the map.
	_icon_button(layer, "home", 42.0, false, Vector2(158, 14), _return_to_start_view)
	_icon_button(layer, "shirt", 42.0, false, Vector2(158, 64), _cycle_player_outfit)

	# --- Mission panel (top centre).
	mission_hud_panel = PanelContainer.new()
	mission_hud_panel.anchor_left = 0.5
	mission_hud_panel.anchor_right = 0.5
	mission_hud_panel.offset_left = -170
	mission_hud_panel.offset_right = 170
	mission_hud_panel.offset_top = 10
	mission_hud_panel.offset_bottom = 70
	mission_hud_panel.add_theme_stylebox_override("panel", _hud_panel_style(8, 0.58))
	mission_hud_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(mission_hud_panel)
	var mission_col := VBoxContainer.new()
	mission_col.add_theme_constant_override("separation", 0)
	mission_hud_panel.add_child(mission_col)
	var mission_head := HBoxContainer.new()
	mission_head.alignment = BoxContainer.ALIGNMENT_END
	mission_col.add_child(mission_head)
	var mission_title := Label.new()
	mission_title.name = "MissionTitle"
	mission_title.text = "المهمة الحالية:"
	mission_title.add_theme_font_size_override("font_size", 14)
	mission_title.add_theme_color_override("font_color", Color(1, 1, 1))
	mission_head.add_child(mission_title)
	var diamond := Control.new()
	diamond.custom_minimum_size = Vector2(16, 18)
	diamond.draw.connect(func(): ICON_BUTTON.draw_icon_shape(diamond, "diamond", Vector2(8, 9), 6.5, Color(1.0, 0.70, 0.12)))
	mission_head.add_child(diamond)
	mission_hud_label = Label.new()
	mission_hud_label.text = "تحدث مع أحد سكان المهدية لبدء مغامرتك"
	mission_hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mission_hud_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mission_hud_label.add_theme_font_size_override("font_size", 13)
	mission_hud_label.add_theme_color_override("font_color", Color(0.92, 0.94, 0.96))
	mission_col.add_child(mission_hud_label)

	# --- Wallet pill with cash icon and "+" (top right).
	var wallet := PanelContainer.new()
	wallet.anchor_left = 1.0
	wallet.anchor_right = 1.0
	wallet.offset_left = -300
	wallet.offset_right = -96
	wallet.offset_top = 14
	wallet.offset_bottom = 50
	var wallet_style := _hud_panel_style(18, 0.55)
	wallet_style.content_margin_top = 2
	wallet_style.content_margin_bottom = 2
	wallet_style.content_margin_right = 4
	wallet.add_theme_stylebox_override("panel", wallet_style)
	layer.add_child(wallet)
	var wallet_row := HBoxContainer.new()
	wallet_row.add_theme_constant_override("separation", 6)
	wallet.add_child(wallet_row)
	var cash := Control.new()
	cash.custom_minimum_size = Vector2(30, 30)
	cash.draw.connect(func(): ICON_BUTTON.draw_icon_shape(cash, "cash", Vector2(15, 16), 12.0, Color.WHITE))
	wallet_row.add_child(cash)
	wallet_label = Label.new()
	wallet_label.text = "12,560 د.ت"
	wallet_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wallet_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wallet_label.add_theme_font_size_override("font_size", 16)
	wallet_row.add_child(wallet_label)
	var plus: Button = ICON_BUTTON.new()
	plus.call("setup", "plus", 28.0)
	plus.set("accent", Color(1, 1, 1, 0.18))
	plus.pressed.connect(_show_earn_money)
	wallet_row.add_child(plus)

	# --- Level label + green XP bar under the wallet.
	level_label = Label.new()
	level_label.text = "Lv. 1"
	level_label.anchor_left = 1.0
	level_label.anchor_right = 1.0
	level_label.offset_left = -296
	level_label.offset_right = -200
	level_label.offset_top = 52
	level_label.offset_bottom = 70
	level_label.add_theme_font_size_override("font_size", 13)
	level_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	level_label.add_theme_constant_override("outline_size", 4)
	layer.add_child(level_label)
	level_bar = ProgressBar.new()
	level_bar.anchor_left = 1.0
	level_bar.anchor_right = 1.0
	level_bar.offset_left = -296
	level_bar.offset_right = -110
	level_bar.offset_top = 72
	level_bar.offset_bottom = 80
	level_bar.show_percentage = false
	level_bar.max_value = 1.0
	level_bar.step = 0.001
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0, 0, 0, 0.45)
	bar_bg.set_corner_radius_all(4)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.30, 0.85, 0.45)
	bar_fill.set_corner_radius_all(4)
	level_bar.add_theme_stylebox_override("background", bar_bg)
	level_bar.add_theme_stylebox_override("fill", bar_fill)
	layer.add_child(level_bar)

	# --- Avatar, then trophy / settings / friends row, chat and mic buttons.
	var avatar := _icon_button(layer, "profile", 64.0, true, Vector2(-14, 8), _show_profile_panel)
	avatar.set("accent", Color(0.16, 0.22, 0.30, 0.92))
	avatar.set("ring", Color(1, 1, 1, 0.9))
	_icon_button(layer, "friends", 40.0, true, Vector2(-14, 88), _show_friends_panel)
	_icon_button(layer, "gear", 40.0, true, Vector2(-62, 88), _toggle_settings_panel)
	_icon_button(layer, "trophy", 40.0, true, Vector2(-110, 88), _show_progress_panel)
	_icon_button(layer, "chat", 46.0, true, Vector2(-20, 248), _toggle_chat_panel)
	voice_button = _icon_button(layer, "mic", 46.0, true, Vector2(-20, 304), _toggle_voice)

	# --- Chat log (bottom-left): the latest real game / resident messages.
	var log_panel := PanelContainer.new()
	log_panel.anchor_top = 1.0
	log_panel.anchor_bottom = 1.0
	log_panel.offset_left = 10
	log_panel.offset_right = 380
	log_panel.offset_top = -84
	log_panel.offset_bottom = -8
	log_panel.add_theme_stylebox_override("panel", _hud_panel_style(6, 0.42))
	log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(log_panel)
	chat_log_label = RichTextLabel.new()
	chat_log_label.bbcode_enabled = true
	chat_log_label.fit_content = true
	chat_log_label.scroll_active = false
	chat_log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chat_log_label.add_theme_font_size_override("normal_font_size", 12)
	chat_log_label.add_theme_font_size_override("bold_font_size", 12)
	log_panel.add_child(chat_log_label)
	_push_chat_log("مرحباً بك في كورنيش المهدية! اقترب من أحد السكان للتحدث.")

	# --- Generic info panel used by trophy / profile / friends / "+" buttons.
	info_panel = PanelContainer.new()
	info_panel.anchor_left = 0.5
	info_panel.anchor_right = 0.5
	info_panel.anchor_top = 0.5
	info_panel.anchor_bottom = 0.5
	info_panel.offset_left = -220
	info_panel.offset_right = 220
	info_panel.offset_top = -150
	info_panel.offset_bottom = 150
	info_panel.add_theme_stylebox_override("panel", _hud_panel_style(12, 0.86))
	info_panel.visible = false
	layer.add_child(info_panel)
	var info_col := VBoxContainer.new()
	info_panel.add_child(info_col)
	var info_head := HBoxContainer.new()
	info_col.add_child(info_head)
	var close_info: Button = ICON_BUTTON.new()
	close_info.call("setup", "close", 34.0)
	close_info.pressed.connect(func(): info_panel.visible = false)
	info_head.add_child(close_info)
	info_title = Label.new()
	info_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info_title.add_theme_font_size_override("font_size", 18)
	info_head.add_child(info_title)
	info_body = RichTextLabel.new()
	info_body.bbcode_enabled = true
	info_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_body.add_theme_font_size_override("normal_font_size", 15)
	info_col.add_child(info_body)

	# --- Settings panel (gear): graphics quality and AI setup.
	settings_panel = PanelContainer.new()
	settings_panel.anchor_left = 0.5
	settings_panel.anchor_right = 0.5
	settings_panel.anchor_top = 0.5
	settings_panel.anchor_bottom = 0.5
	settings_panel.offset_left = -200
	settings_panel.offset_right = 200
	settings_panel.offset_top = -120
	settings_panel.offset_bottom = 120
	settings_panel.add_theme_stylebox_override("panel", _hud_panel_style(12, 0.86))
	settings_panel.visible = false
	layer.add_child(settings_panel)
	var settings_col := VBoxContainer.new()
	settings_col.add_theme_constant_override("separation", 10)
	settings_panel.add_child(settings_col)
	var settings_title := Label.new()
	settings_title.text = "الإعدادات"
	settings_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_title.add_theme_font_size_override("font_size", 18)
	settings_col.add_child(settings_title)
	quality_button.custom_minimum_size = Vector2(0, 46)
	settings_col.add_child(quality_button)
	var ai_button := Button.new()
	ai_button.text = "إعداد الذكاء الاصطناعي للسكان"
	ai_button.custom_minimum_size = Vector2(0, 42)
	ai_button.pressed.connect(func():
		settings_panel.visible = false
		_toggle_ai_setup()
	)
	settings_col.add_child(ai_button)
	var close_settings := Button.new()
	close_settings.text = "إغلاق"
	close_settings.custom_minimum_size = Vector2(0, 40)
	close_settings.pressed.connect(func(): settings_panel.visible = false)
	settings_col.add_child(close_settings)

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


# ------------------------------------------------------------- minimap

func _collect_minimap_rects() -> void:
	minimap_static_rects.clear()
	var land := Color(0.60, 0.70, 0.52)
	var road := Color(0.36, 0.38, 0.40)
	var walk := Color(0.86, 0.82, 0.72)
	var roof := Color(0.93, 0.90, 0.84)
	if is_instance_valid(corniche):
		for r in corniche.get("map_land"):
			minimap_static_rects.append([r, Color(0.74, 0.68, 0.52)])
		for r in corniche.get("map_walkways"):
			minimap_static_rects.append([r, walk])
		for r in corniche.get("map_roads"):
			minimap_static_rects.append([r, road])
	# Town streets built by _build_town / _create_outer_district.
	for r in [Rect2(-90, -4.5, 180, 9), Rect2(-4.5, -38, 9, 128), Rect2(-90, 26.5, 180, 7), Rect2(-90, 54.5, 180, 7), Rect2(-55.5, -22, 7, 112), Rect2(48.5, -22, 7, 112)]:
		minimap_static_rects.append([r, road])
	for building in get_tree().get_nodes_in_group("mahdia_buildings"):
		if building is Node3D and building.has_meta("footprint"):
			var fp: Vector2 = building.get_meta("footprint")
			var pos: Vector3 = (building as Node3D).global_position
			minimap_static_rects.append([Rect2(pos.x - fp.x * 0.5, pos.z - fp.y * 0.5, fp.x, fp.y), roof])
	minimap_static_rects.push_front([Rect2(-95, -57.3, 190, 150), land])

func _draw_minimap() -> void:
	if not is_instance_valid(minimap_content) or not is_instance_valid(player):
		return
	var cam := get_viewport().get_camera_3d()
	var forward := Vector3(0, 0, -1)
	if cam != null:
		forward = -cam.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3(0, 0, -1)
	forward = forward.normalized()
	var right := Vector3(-forward.z, 0, forward.x)
	var origin := player.global_position
	var map_scale := 1.05  # pixels per metre
	var centre := Vector2(68, 68)
	var to_map := func(x: float, z: float) -> Vector2:
		var rel := Vector3(x - origin.x, 0, z - origin.z)
		return centre + Vector2(rel.dot(right), -rel.dot(forward)) * map_scale
	# Sea background, then land/streets/buildings as rotated quads.
	minimap_content.draw_rect(Rect2(Vector2.ZERO, minimap_content.size), Color(0.20, 0.50, 0.72))
	var view_radius := 70.0 / map_scale + 4.0
	for entry in minimap_static_rects:
		var r: Rect2 = entry[0]
		var col: Color = entry[1]
		var nearest := Vector2(clampf(origin.x, r.position.x, r.end.x), clampf(origin.z, r.position.y, r.end.y))
		if nearest.distance_to(Vector2(origin.x, origin.z)) > view_radius:
			continue
		var quad := PackedVector2Array([
			to_map.call(r.position.x, r.position.y), to_map.call(r.end.x, r.position.y),
			to_map.call(r.end.x, r.end.y), to_map.call(r.position.x, r.end.y)
		])
		minimap_content.draw_colored_polygon(quad, col)
	for resident in get_tree().get_nodes_in_group("mahdia_residents"):
		if resident is Node3D and resident.is_inside_tree():
			var rp: Vector3 = (resident as Node3D).global_position
			minimap_content.draw_circle(to_map.call(rp.x, rp.z), 2.6, Color(1.0, 0.85, 0.25))
	if is_instance_valid(vehicle):
		minimap_content.draw_circle(to_map.call(vehicle.global_position.x, vehicle.global_position.z), 3.6, Color(0.2, 0.55, 1.0))
	if is_instance_valid(mission_target_marker) and mission_target_marker.visible:
		var mp: Vector3 = mission_target_marker.global_position
		var m: Vector2 = to_map.call(mp.x, mp.z)
		m = centre + (m - centre).limit_length(60.0)
		minimap_content.draw_circle(m, 5.0, Color(1.0, 0.35, 0.2))
		minimap_content.draw_arc(m, 5.0, 0.0, TAU, 16, Color.WHITE, 1.5, true)

# ------------------------------------------------------- HUD button actions

func _push_chat_log(value: String) -> void:
	if not is_instance_valid(chat_log_label) or value.strip_edges().is_empty():
		return
	var line := value.strip_edges().replace("[", "(").replace("]", ")")
	var colon := line.find(":")
	if colon > 0 and colon < 24:
		var palette := ["#5ec8ff", "#ffd75e", "#ff7aa8", "#8cf08c"]
		var who := line.substr(0, colon)
		var col: String = palette[absi(who.hash()) % palette.size()]
		line = "[color=%s][b]%s[/b][/color]:%s" % [col, who, line.substr(colon + 1)]
	else:
		line = "[color=#ffe08a][b]المهدية[/b][/color]: " + line
	chat_log_lines.append(line)
	while chat_log_lines.size() > 3:
		chat_log_lines.pop_front()
	chat_log_label.text = "\n".join(chat_log_lines)
	if voice_enabled:
		_speak(value)

func _show_info_panel(title: String, body: String) -> void:
	if not is_instance_valid(info_panel):
		return
	if is_instance_valid(settings_panel):
		settings_panel.visible = false
	if info_panel.visible and info_title.text == title:
		info_panel.visible = false
		return
	info_title.text = title
	info_body.text = body
	info_panel.visible = true

func _cycle_player_outfit() -> void:
	if is_instance_valid(player) and player.has_method("cycle_outfit"):
		var index: int = player.call("cycle_outfit")
		var names := ["أسود كلاسيكي", "أبيض صيفي", "أزرق المهدية", "أحمر رياضي"]
		_push_chat_log("الملابس: %s" % names[index % names.size()])
		_save_world_progress()

func _show_earn_money() -> void:
	var money_value := int(life_manager.get("money")) if is_instance_valid(life_manager) else 0
	_show_info_panel("المحفظة", "الرصيد: [b]%s د.ت[/b]\n\nطرق كسب المال:\n• أكمل مهمة التوصيل لأحد السكان: +20 د.ت\n• اعمل في مكتب العمل: +30 د.ت\n\nلا توجد مشتريات حقيقية داخل اللعبة." % _format_thousands(money_value))

func _show_profile_panel() -> void:
	if not is_instance_valid(life_manager):
		return
	var lvl: int = life_manager.call("get_level")
	_show_info_panel("ملفك الشخصي", "المستوى: [b]%d[/b]  (خبرة %d)\nالمال: %s د.ت\nالطاقة: %d%%\nالشبع: %d%%\nوجبات في الحقيبة: %d" % [lvl, int(life_manager.get("xp")), _format_thousands(int(life_manager.get("money"))), int(life_manager.get("energy")), int(life_manager.get("hunger")), int(life_manager.get("food"))])

func _show_progress_panel() -> void:
	if not is_instance_valid(life_manager):
		return
	var state := str(life_manager.get("delivery_state"))
	var steps := [
		["تحدث مع أحد السكان واقبل طلبه", state != "not_started"],
		["اشترِ الوجبة من متجر الحي", state == "ready" or state == "completed"],
		["سلّم الوجبة إلى صاحبها", state == "completed"],
		["احصل على أجرك من مكتب العمل", bool(life_manager.get("job_claimed"))]
	]
	var lines: Array[String] = []
	for step in steps:
		lines.append(("[color=#8cf08c]✔[/color] " if bool(step[1]) else "○ ") + str(step[0]))
	_show_info_panel("مهام البداية", "\n".join(lines))

func _show_friends_panel() -> void:
	var lines: Array[String] = []
	if is_instance_valid(player):
		var residents := get_tree().get_nodes_in_group("mahdia_residents")
		residents.sort_custom(func(a, b): return (a as Node3D).global_position.distance_to(player.global_position) < (b as Node3D).global_position.distance_to(player.global_position))
		for resident in residents:
			if not (resident is Node3D) or not resident.is_inside_tree():
				continue
			var d := (resident as Node3D).global_position.distance_to(player.global_position)
			lines.append("%s — %s · %d م · ثقة %d%%" % [str(resident.get("display_name")), str(resident.get("occupation")), int(d), int(float(resident.get("trust")) * 100.0)])
			if lines.size() >= 8:
				break
	_show_info_panel("سكان قريبون", "\n".join(lines) if not lines.is_empty() else "لا يوجد سكان قريبون.")

func _toggle_settings_panel() -> void:
	if not is_instance_valid(settings_panel):
		return
	if is_instance_valid(info_panel):
		info_panel.visible = false
	settings_panel.visible = not settings_panel.visible

# Mic button: reads resident replies and game messages aloud with the
# device's text-to-speech voice (Arabic when the phone has one).
func _toggle_voice() -> void:
	if not voice_enabled:
		var voices := DisplayServer.tts_get_voices_for_language("ar")
		if voices.is_empty():
			var all_voices := DisplayServer.tts_get_voices()
			if not all_voices.is_empty():
				voices = PackedStringArray([str((all_voices[0] as Dictionary).get("id", ""))])
		if voices.is_empty() or str(voices[0]).is_empty():
			_push_chat_log("القراءة الصوتية غير متوفرة على هذا الجهاز.")
			return
		tts_voice = voices[0]
	voice_enabled = not voice_enabled
	if is_instance_valid(voice_button):
		voice_button.set("toggled_on", voice_enabled)
		voice_button.queue_redraw()
	var note := "القراءة الصوتية للردود: مفعّلة" if voice_enabled else "القراءة الصوتية للردود: متوقفة"
	_push_chat_log(note)
	if not voice_enabled:
		DisplayServer.tts_stop()

func _speak(value: String) -> void:
	if tts_voice.is_empty():
		return
	DisplayServer.tts_stop()
	DisplayServer.tts_speak(value, tts_voice)

func _format_thousands(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if value < 0 else "") + out

func reset_view_for_capture() -> void:
	_return_to_start_view()
	if is_instance_valid(world_systems):
		world_systems.set("hour", 13.0)
		world_systems.call("set_weather", "مشمس")
	var pivot = player.get("camera_pivot")
	if pivot is Node3D:
		(pivot as Node3D).rotation = Vector3.ZERO


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
	if is_instance_valid(minimap_content):
		minimap_content.queue_redraw()
	var interact_pressed := InputMap.has_action("interact") and Input.is_action_just_pressed("interact")
	if (interact_pressed or player.interact_requested) and is_instance_valid(vehicle):
		if vehicle.driver == player:
			vehicle.exit_vehicle()
			if is_instance_valid(mobile_controls):
				mobile_controls.reset_input_state()
		elif player.global_position.distance_to(vehicle.global_position) < 4.0:
			if is_instance_valid(mobile_controls):
				mobile_controls.reset_input_state()
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
			wallet_label.text = "%s د.ت" % _format_thousands(int(life_manager.money))
			if is_instance_valid(level_label):
				level_label.text = "Lv. %d" % int(life_manager.call("get_level"))
			if is_instance_valid(level_bar):
				level_bar.value = float(life_manager.call("get_level_progress"))
		if is_instance_valid(corniche) and is_instance_valid(world_systems):
			corniche.call("set_night_factor", 1.0 - clampf(float(world_systems.call("get_daylight")) * 3.0, 0.0, 1.0))
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
	quality_level = clampi(int(world.get("graphics_quality", quality_level)), 0, 2)
	if player.has_method("set_outfit"):
		player.call("set_outfit", int(world.get("outfit", 0)))
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
		"graphics_quality": quality_level,
		"outfit": int(player.get("outfit_index"))
	}
	var result: Error = save_manager.save_progress(data)
	if result != OK:
		push_warning("Could not save Mahdia world progress: %s" % error_string(result))

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		_save_world_progress()

func _select_device_profile() -> void:
	# Start mobile devices at Medium; desktop builds start at High.
	quality_level = 1 if OS.has_feature("mobile") else 2

func _cycle_graphics_quality() -> void:
	quality_level = (quality_level + 1) % 3
	_apply_graphics_quality()
	if world_ready:
		_rebuild_population_for_quality()
	_save_world_progress()

func _rebuild_population_for_quality() -> void:
	# Pooled: park or reattach existing nodes instead of freeing and rebuilding.
	_apply_resident_budget()
	_apply_traffic_budget()
	print("MAHDIA_POOL=", get_pool_status())

func _apply_draw_distance(tier: int) -> void:
	# Camera far plane is the hard draw distance; facade details use a shorter
	# visibility range so distant buildings render as a few large boxes only.
	var far: float = CAMERA_FAR_BY_TIER[tier]
	var detail_range: float = DETAIL_RANGE_BY_TIER[tier]
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		cam.far = far
	for detail in building_detail_meshes:
		if is_instance_valid(detail):
			detail.visibility_range_end = detail_range
			detail.visibility_range_end_margin = 4.0
	# Occlusion culling hides objects fully behind building occluders.
	get_viewport().use_occlusion_culling = true

func _apply_graphics_quality() -> void:
	# Low stays playable on 3 GB phones; High is the full visual target.
	var fps_caps := [30, 45, 60]
	var render_scales := [0.70, 0.82, 1.0]
	var shadow_distances := [0.0, 40.0, 70.0]
	var tier := clampi(quality_level, 0, 2)
	Engine.max_fps = fps_caps[tier]
	# Keep physics deterministic across visual tiers.
	Engine.physics_ticks_per_second = 60
	var viewport := get_viewport()
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = render_scales[tier]
	viewport.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][tier]
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if tier == 0 else Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.mesh_lod_threshold = [4.0, 2.0, 1.0][tier]
	RenderingServer.directional_shadow_atlas_set_size([1024, 2048, 4096][tier], true)
	RenderingServer.directional_soft_shadow_filter_set_quality([RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][tier])
	if is_instance_valid(sun):
		sun.visible = true
		sun.shadow_enabled = tier > 0
		sun.directional_shadow_max_distance = shadow_distances[tier] if tier > 0 else 30.0
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if tier == 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	if is_instance_valid(world_environment):
		world_environment.glow_enabled = tier > 0
		world_environment.adjustment_enabled = tier > 0
		world_environment.ssao_enabled = tier == 2 and renderer_name == "forward_plus"
		if world_environment.sky != null:
			world_environment.sky.radiance_size = [Sky.RADIANCE_SIZE_32, Sky.RADIANCE_SIZE_64, Sky.RADIANCE_SIZE_128][tier]
	if is_instance_valid(corniche) and corniche.has_method("apply_quality"):
		corniche.call("apply_quality", tier)
	_apply_draw_distance(tier)
	if is_instance_valid(quality_button):
		var labels := ["منخفضة · 30 FPS", "متوسطة · 45 FPS", "عالية · 60 FPS"]
		quality_button.text = "الجودة: " + labels[tier]
		quality_button.tooltip_text = "اضغط لتغيير جودة الرسومات وعدد السكان والسيارات"


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


	# Small storefront awnings make the ground-level blocks read as lived-in shops.
	for i in range(5):
		var x := -30.0 + float(i) * 15.0
		var awning_color: Color = [Color(0.76, 0.22, 0.16), Color(0.88, 0.78, 0.58), Color(0.16, 0.40, 0.43)][i % 3]
		_box(self, Vector3(3.2, 0.14, 1.05), Vector3(x, 3.0, 10.8), awning_color)
		_box(self, Vector3(3.2, 0.12, 0.12), Vector3(x, 2.88, 11.28), Color(0.94, 0.88, 0.74))

	_create_realistic_street_layer()
