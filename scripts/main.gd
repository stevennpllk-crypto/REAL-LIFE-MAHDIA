extends Node3D

const PLAYER_SCRIPT = preload("res://scripts/player.gd")
const NPC_SCRIPT = preload("res://scripts/npc.gd")
const MOBILE_CONTROLS = preload("res://scripts/mobile_controls.gd")
const VEHICLE_SCRIPT = preload("res://scripts/vehicle.gd")
const WORLD_SYSTEMS = preload("res://scripts/world_systems.gd")
const NETWORK_SCRIPT = preload("res://scripts/multiplayer_manager.gd")
const SAVE_SCRIPT = preload("res://scripts/save_manager.gd")

var player: CharacterBody3D
var sun: DirectionalLight3D
var world_environment: Environment
var status_label: Label
var vehicle: CharacterBody3D
var world_systems: Node
var network_manager: Node
var save_manager: Node

func _ready() -> void:
	randomize()
	_build_environment()
	_build_town()
	_spawn_player()
	_spawn_residents()
	_spawn_vehicle()
	_setup_systems()
	_build_hud()

func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
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
	world_environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.12, 0.34, 0.62)
	sky_mat.sky_horizon_color = Color(0.68, 0.79, 0.86)
	sky_mat.ground_bottom_color = Color(0.12, 0.14, 0.17)
	sky_mat.ground_horizon_color = Color(0.48, 0.53, 0.55)
	sky.sky_material = sky_mat
	world_environment.sky = sky
	world_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	world_env.environment = world_environment
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_energy = 1.1
	add_child(sun)
	var ground := StaticBody3D.new()
	_box(ground, Vector3(180, 1, 180), Vector3(0, -0.55, 0), Color(0.78, 0.68, 0.48))
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(180, 1, 180)
	floor_shape.shape = floor_box
	floor_shape.position.y = -0.55
	ground.add_child(floor_shape)
	add_child(ground)
	_box(self, Vector3(180, 0.12, 32), Vector3(0, 0.02, -72), Color(0.08, 0.38, 0.62))

func _build_town() -> void:
	for i in range(5):
		for j in range(4):
			var x := float(i) * 13.0 - 26.0
			var z := float(j) * 13.0 - 18.0
			if absf(x) < 8.0 and absf(z) < 8.0:
				continue
			var height := randf_range(5.0, 9.0)
			var building := StaticBody3D.new()
			var shades := [Color(0.88,0.83,0.72), Color(0.92,0.89,0.80), Color(0.76,0.70,0.60)]
			var shade: Color = shades[randi_range(0, 2)]
			_box(building, Vector3(7.0,height,7.0), Vector3(x,height/2.0,z), shade)
			var col := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(7.0,height,7.0)
			col.shape = shape
			col.position = Vector3(x,height/2.0,z)
			building.add_child(col)
			add_child(building)
	var tower := StaticBody3D.new()
	var cyl := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.2
	cylinder.bottom_radius = 1.8
	cylinder.height = 13.0
	cyl.mesh = cylinder
	cyl.position = Vector3(42, 6.5, -48)
	cyl.material_override = _material(Color(0.9,0.86,0.74))
	tower.add_child(cyl)
	add_child(tower)

func _spawn_player() -> void:
	player = CharacterBody3D.new()
	player.set_script(PLAYER_SCRIPT)
	player.position = Vector3(0, 1, 8)
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

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 14)
	panel.custom_minimum_size = Vector2(270, 54)
	layer.add_child(panel)
	status_label = Label.new()
	status_label.text = "MAHDIA • 08:00 • Prototype"
	panel.add_child(status_label)
	var hint := Label.new()
	hint.text = "WASD/عصا اللمس • E ركوب/نزول • Shift جري • Space قفز"
	hint.position = Vector2(16, 78)
	layer.add_child(hint)
	var controls := Node.new()
	controls.set_script(MOBILE_CONTROLS)
	layer.add_child(controls)
	controls.setup(player)

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("interact") and is_instance_valid(vehicle):
		if vehicle.driver == player:
			vehicle.exit_vehicle()
		elif player.global_position.distance_to(vehicle.global_position) < 4.0:
			vehicle.enter_vehicle(player)
	if is_instance_valid(status_label):
		var hour_value: float = world_systems.hour if is_instance_valid(world_systems) else 8.0
		status_label.text = "MAHDIA • %02d:%02d • %s" % [int(hour_value), int(fposmod(hour_value * 60.0, 60.0)), world_systems.weather]
