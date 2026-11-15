extends Node3D

const PLAYER_SCRIPT = preload("res://scripts/player.gd")
const NPC_SCRIPT = preload("res://scripts/npc.gd")
const MOBILE_CONTROLS = preload("res://scripts/mobile_controls.gd")
const VEHICLE_SCRIPT = preload("res://scripts/vehicle.gd")
const WORLD_SYSTEMS = preload("res://scripts/world_systems.gd")
const NETWORK_SCRIPT = preload("res://scripts/multiplayer_manager.gd")
const SAVE_SCRIPT = preload("res://scripts/save_manager.gd")
const LIFE_SCRIPT = preload("res://scripts/life_manager.gd")
const PLANET_NAV_SCRIPT = preload("res://scripts/planet_navigation.gd")
const TERRAIN_STREAMER_SCRIPT = preload("res://scripts/terrain_streamer.gd")

var player: CharacterBody3D
var sun: DirectionalLight3D
var world_environment: Environment
var status_label: Label
var hint_label: Label
var vehicle: CharacterBody3D
var world_systems: Node
var network_manager: Node
var save_manager: Node
var life_manager: Node
var planet_navigation: Node
var terrain_streamer: Node3D
var material_cache: Dictionary = {}

func _ready() -> void:
	randomize()
	_build_environment()
	# Bring up a playable camera and HUD before constructing decorative city blocks.
	# This guarantees that even a slow phone can present a real game frame quickly.
	_spawn_player()
	_build_hud()
	print("MAHDIA_PLAYER_READY")
	await get_tree().process_frame
	await _build_town()
	print("MAHDIA_TOWN_READY")
	_spawn_residents()
	_spawn_vehicle()
	_setup_systems()
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
	# Disable real-time shadows on the mobile compatibility renderer.
	# This avoids expensive shadow shader variants on low-memory phones and SwiftShader.
	sun.shadow_enabled = false
	add_child(sun)

	var ground := StaticBody3D.new()
	_box(ground, Vector3(180, 1, 180), Vector3(0, -0.55, 0), Color(0.72, 0.66, 0.53))
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(180, 1, 180)
	floor_shape.shape = floor_box
	floor_shape.position.y = -0.55
	ground.add_child(floor_shape)
	add_child(ground)

	# Mediterranean sea and a pale coastal promenade.
	_box(self, Vector3(180, 0.16, 38), Vector3(0, -0.02, -78), Color(0.035, 0.34, 0.56))
	_box(self, Vector3(180, 0.18, 5), Vector3(0, 0.04, -57), Color(0.82, 0.76, 0.64))

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

func _create_building(origin: Vector3, size: Vector3, wall_color: Color, seed_value: int) -> void:
	# Keep each building intentionally lightweight: one body, one roof, one door,
	# and a small number of windows. The previous facade generated hundreds of
	# tiny mesh nodes and delayed first-frame rendering on mobile GPUs.
	var building := StaticBody3D.new()
	building.position = origin
	var w := size.x
	var h := size.y
	var d := size.z
	_box(building, size, Vector3(0, h * 0.5, 0), wall_color)
	_box(building, Vector3(w + 0.2, 0.22, d + 0.2), Vector3(0, h + 0.11, 0), Color(0.70, 0.66, 0.58))
	_box(building, Vector3(1.05, 2.05, 0.10), Vector3(0, 1.03, d * 0.501), Color(0.25, 0.17, 0.12))
	for col in range(2):
		var wx := (float(col) - 0.5) * w * 0.48
		_box(building, Vector3(1.15, 1.15, 0.08), Vector3(wx, minf(3.45, h * 0.58), d * 0.505), Color(0.12, 0.29, 0.38))
		_box(building, Vector3(1.28, 0.09, 0.12), Vector3(wx, minf(4.05, h * 0.58 + 0.62), d * 0.52), Color(0.92, 0.88, 0.78))
	if seed_value % 3 == 0:
		_box(building, Vector3(w * 0.66, 0.18, 0.9), Vector3(0, 2.42, d * 0.72), Color(0.12, 0.40, 0.36))
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
	for i in range(6):
		var npc := CharacterBody3D.new()
		npc.set_script(NPC_SCRIPT)
		npc.position = Vector3(randf_range(-24,24), 0, randf_range(-20,20))
		npc.display_name = "Resident %02d" % (i + 1)
		add_child(npc)

func _spawn_vehicle() -> void:
	vehicle = CharacterBody3D.new()
	vehicle.set_script(VEHICLE_SCRIPT)
	vehicle.position = Vector3(5, 0.1, 10)
	vehicle.name = "MahdiaCar"
	add_child(vehicle)

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

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 14)
	panel.custom_minimum_size = Vector2(470, 62)
	layer.add_child(panel)
	status_label = Label.new()
	status_label.text = "MAHDIA • 08:00 • Prototype"
	panel.add_child(status_label)
	hint_label = Label.new()
	hint_label.text = "عصا اللمس للحركة • اسحب يمين الشاشة لتحريك الكاميرا • تفاعل • جري • قفز"
	hint_label.position = Vector2(16, 78)
	layer.add_child(hint_label)
	var message_panel := PanelContainer.new()
	message_panel.anchor_left = 0.5
	message_panel.anchor_right = 0.5
	message_panel.anchor_top = 1.0
	message_panel.anchor_bottom = 1.0
	message_panel.offset_left = -250
	message_panel.offset_right = 250
	message_panel.offset_top = -82
	message_panel.offset_bottom = -28
	layer.add_child(message_panel)
	var message_label := Label.new()
	message_label.name = "LifeMessage"
	message_label.text = "مرحباً بك في المهدية! اقترب من شخص أو مبنى للتفاعل."
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_panel.add_child(message_label)
	life_manager.message_changed.connect(func(value: String): message_label.text = value)
	var controls := Node.new()
	controls.set_script(MOBILE_CONTROLS)
	layer.add_child(controls)
	controls.setup(player)

func _process(_delta: float) -> void:
	# _process continues while _ready() yields during town generation.
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
		status_label.text = "%s • %s • %02d:%02d • %s • %d د.ت • طاقة %d%%" % [planet_navigation.get_region_name(), planet_navigation.get_coordinate_text(), int(hour_value), int(fposmod(hour_value * 60.0, 60.0)), world_systems.weather, life_manager.money, int(life_manager.energy)]
