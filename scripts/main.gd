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
var autosave_elapsed := 0.0
var quality_level := 0
var quality_button: Button
var restored_vehicle_position := Vector3(5, 0.1, 10)
var restore_vehicle_driver := false
const AUTOSAVE_INTERVAL := 12.0
const WORLD_SAVE_KEY := "mahdia_world"

func _ready() -> void:
	randomize()
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
	# Unshaded keeps low-poly geometry visible on devices with tight shader uniform limits.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material_cache[key] = mat
	return mat

func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	item.mesh = mesh
	item.position = pos
	item.material_override = _material(color)
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
	world_environment.ambient_light_energy = 0.9
	world_env.environment = world_environment
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_energy = 1.1
	# The entire scene uses unshaded, vertex-coloured geometry. A scene light
	# adds no visible quality but can exceed GLES3 uniform limits on mobile GPUs.
	# Keep the time-of-day controller node, but exclude it from rendering.
	sun.shadow_enabled = false
	sun.visible = false
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
	_box(self, Vector3(180, 0.16, 38), Vector3(0, -0.02, -78), Color(0.035, 0.34, 0.56))
	_box(self, Vector3(180, 0.18, 5), Vector3(0, 0.04, -57), Color(0.82, 0.76, 0.64))
	_create_coastal_scenery()

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

func _build_town() -> void:
	# Main asphalt streets crossing a compact Mahdia-inspired neighborhood.
	_box(self, Vector3(180, 0.12, 9), Vector3(0, 0.035, 0), Color(0.16, 0.18, 0.19))
	_box(self, Vector3(9, 0.12, 180), Vector3(0, 0.04, 0), Color(0.16, 0.18, 0.19))
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
		_box(self, Vector3(180, 0.2, 1.6), Vector3(0, 0.08, side * 5.5), Color(0.78, 0.75, 0.68))
		_box(self, Vector3(1.6, 0.2, 180), Vector3(side * 5.5, 0.08, 0), Color(0.78, 0.75, 0.68))

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
	_create_city_details()

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

	_box(building, size, Vector3(0, h * 0.5, 0), wall_color)
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
		var leaf_mesh := BoxMesh.new()
		leaf_mesh.size = Vector3(0.34, 0.12, 2.5)
		leaf.mesh = leaf_mesh
		leaf.position = pos + Vector3(cos(angle) * 0.85, 3.8, sin(angle) * 0.85)
		leaf.rotation.y = -angle
		leaf.rotation.x = -0.22
		leaf.material_override = _material(Color(0.13, 0.38, 0.22))
		add_child(leaf)

func _create_street_lamp(pos: Vector3) -> void:
	_box(self, Vector3(0.12, 3.5, 0.12), pos + Vector3(0, 1.75, 0), Color(0.12, 0.14, 0.16))
	_box(self, Vector3(0.65, 0.12, 0.3), pos + Vector3(0.22, 3.45, 0), Color(0.96, 0.82, 0.52))

func _spawn_player() -> void:
	player = CharacterBody3D.new()
	player.set_script(PLAYER_SCRIPT)
	player.position = Vector3(0, 0.03, 8)
	player.name = "Player"
	add_child(player)

func _spawn_residents() -> void:
	# Place residents on public sidewalks rather than random points that may
	# intersect buildings or spawn directly inside traffic lanes.
	var personalities := [
		"friendly", "shy", "busy", "curious", "grumpy", "friendly",
		"curious", "busy", "friendly", "shy", "curious", "busy"
	]
	var jobs := [
		"fisher", "shopkeeper", "mechanic", "student", "resident", "cook",
		"driver", "resident", "shopkeeper", "student", "fisher", "mechanic"
	]
	var resident_names := [
		"سامي", "مريم", "أيمن", "ليلى", "منير", "آمنة",
		"يوسف", "سارة", "حاتم", "نجلاء", "وليد", "ريم"
	]
	var sidewalk_positions := [
		Vector3(-6.6, 0, -25), Vector3(6.6, 0, -25),
		Vector3(-6.6, 0, -17), Vector3(6.6, 0, -17),
		Vector3(-6.6, 0, -9), Vector3(6.6, 0, -9),
		Vector3(-6.6, 0, 9), Vector3(6.6, 0, 9),
		Vector3(-6.6, 0, 17), Vector3(6.6, 0, 17),
		Vector3(-6.6, 0, 25), Vector3(6.6, 0, 25)
	]
	for i in range(sidewalk_positions.size()):
		var npc := CharacterBody3D.new()
		npc.set_script(NPC_SCRIPT)
		npc.position = sidewalk_positions[i]
		npc.display_name = resident_names[i]
		npc.personality = personalities[i]
		npc.occupation = jobs[i]
		var work_spot: Vector3 = sidewalk_positions[i] + Vector3(0, 0, 5.0 if i % 2 == 0 else -5.0)
		npc.set_ai_context(player, world_systems, work_spot, i, save_manager)
		add_child(npc)

func _spawn_vehicle() -> void:
	vehicle = CharacterBody3D.new()
	vehicle.set_script(VEHICLE_SCRIPT)
	vehicle.position = restored_vehicle_position
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
	for i in range(traffic_specs.size()):
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
	panel.position = Vector2(16, 14)
	panel.custom_minimum_size = Vector2(470, 62)
	layer.add_child(panel)
	status_label = Label.new()
	status_label.text = "MAHDIA • 08:00 • Prototype"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(status_label)
	quality_button = Button.new()
	quality_button.text = "الرسوم: منخفضة"
	quality_button.anchor_left = 1.0
	quality_button.anchor_right = 1.0
	quality_button.offset_left = -170.0
	quality_button.offset_right = -16.0
	quality_button.offset_top = 14.0
	quality_button.offset_bottom = 62.0
	quality_button.focus_mode = Control.FOCUS_NONE
	quality_button.pressed.connect(_cycle_graphics_quality)
	layer.add_child(quality_button)
	_apply_graphics_quality()
	hint_label = Label.new()
	hint_label.text = "عصا اللمس للحركة • اسحب يمين الشاشة لتحريك الكاميرا • تفاعل • جري • قفز"
	hint_label.position = Vector2(16, 78)
	layer.add_child(hint_label)
	var message_panel := PanelContainer.new()
	# Keep the message strip in the central safe zone: mobile action buttons
	# occupy the lower-right corner and the movement stick occupies lower-left.
	message_panel.anchor_left = 0.28
	message_panel.anchor_right = 0.72
	message_panel.anchor_top = 1.0
	message_panel.anchor_bottom = 1.0
	message_panel.offset_left = 0
	message_panel.offset_right = 0
	message_panel.offset_top = -112
	message_panel.offset_bottom = -72
	layer.add_child(message_panel)
	var message_label := Label.new()
	message_label.name = "LifeMessage"
	message_label.text = "مرحباً بك في المهدية! اقترب من شخص أو مبنى للتفاعل."
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_panel.add_child(message_label)
	life_manager.message_changed.connect(func(value: String): message_label.text = value)

	# Lightweight chat input for the currently selected resident.
	var chat_row := HBoxContainer.new()
	# A compact center-bottom composer avoids covering the joystick and
	# the three touch action buttons on 16:9 phones.
	chat_row.anchor_left = 0.28
	chat_row.anchor_right = 0.72
	chat_row.anchor_top = 1.0
	chat_row.anchor_bottom = 1.0
	chat_row.offset_top = -64
	chat_row.offset_bottom = -18
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

	var ai_config_button := Button.new()
	ai_config_button.text = "إعداد الذكاء"
	ai_config_button.anchor_left = 1.0
	ai_config_button.anchor_right = 1.0
	ai_config_button.offset_left = -170
	ai_config_button.offset_right = -16
	ai_config_button.offset_top = 72
	ai_config_button.offset_bottom = 116
	ai_config_button.pressed.connect(_toggle_ai_setup)
	layer.add_child(ai_config_button)

	# Expose real backend/model readiness instead of silently losing service signals.
	ai_status_label = Label.new()
	ai_status_label.text = "JASSIM AI: جارٍ فحص الخادم..."
	ai_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ai_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ai_status_label.anchor_left = 1.0
	ai_status_label.anchor_right = 1.0
	ai_status_label.offset_left = -340
	ai_status_label.offset_right = -16
	ai_status_label.offset_top = 122
	ai_status_label.offset_bottom = 166
	layer.add_child(ai_status_label)

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

	var controls := Node.new()
	controls.set_script(MOBILE_CONTROLS)
	layer.add_child(controls)
	controls.setup(player)


func _on_ai_connection_status(ready: bool, message: String) -> void:
	if not is_instance_valid(ai_status_label):
		return
	ai_status_label.text = ("● " if ready else "○ ") + "JASSIM AI: " + message
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
	# _process continues while _ready() yields during town generation.
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
	if is_instance_valid(planet_navigation) and is_instance_valid(player):
		planet_navigation.update_from_player(player.global_position)
	if is_instance_valid(status_label):
		var hour_value: float = world_systems.hour if is_instance_valid(world_systems) else 8.0
		status_label.text = "%s • %s • %02d:%02d • %s • %d د.ت • طاقة %d%% • جوع %d%%" % [planet_navigation.get_region_name(), planet_navigation.get_coordinate_text(), int(hour_value), int(fposmod(hour_value * 60.0, 60.0)), world_systems.weather, life_manager.money, int(life_manager.energy), int(life_manager.hunger)]


func _restore_world_progress() -> void:
	if not is_instance_valid(save_manager) or not is_instance_valid(player):
		return
	var data: Dictionary = save_manager.load_progress()
	var world: Dictionary = data.get(WORLD_SAVE_KEY, {})
	if world.has("player_position") and world.player_position is Array and world.player_position.size() == 3:
		var p: Array = world.player_position
		player.global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	if world.has("player_rotation_y"):
		player.rotation.y = float(world.player_rotation_y)
	if world.has("vehicle_position") and world.vehicle_position is Array and world.vehicle_position.size() == 3:
		var car: Array = world.vehicle_position
		restored_vehicle_position = Vector3(float(car[0]), float(car[1]), float(car[2]))
	restore_vehicle_driver = bool(world.get("was_driving", false))
	quality_level = clampi(int(world.get("graphics_quality", 0)), 0, 2)
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

func _cycle_graphics_quality() -> void:
	quality_level = (quality_level + 1) % 3
	_apply_graphics_quality()
	_save_world_progress()

func _apply_graphics_quality() -> void:
	var labels := ["منخفضة", "متوسطة", "عالية"]
	if is_instance_valid(quality_button):
		quality_button.text = "الرسوم: " + labels[quality_level]
	Engine.max_fps = [30, 45, 60][quality_level]
	if is_instance_valid(sun):
		# All quality tiers remain on the GLES3-safe unlit path.
		sun.shadow_enabled = false
		sun.visible = false
	if is_instance_valid(world_environment):
		world_environment.ambient_light_energy = [0.58, 0.78, 0.95][quality_level]


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
