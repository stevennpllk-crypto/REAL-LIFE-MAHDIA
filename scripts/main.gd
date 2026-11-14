extends Node3D

const PLAYER_SCRIPT = preload("res://scripts/player.gd")
const NPC_SCRIPT = preload("res://scripts/npc.gd")
var player: CharacterBody3D
var sun: DirectionalLight3D
var day_clock := 9.0
var status_label: Label

func _ready() -> void:
	randomize()
	_build_environment()
	_build_town()
	_spawn_player()
	_spawn_residents()
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
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.12, 0.34, 0.62)
	sky_mat.sky_horizon_color = Color(0.68, 0.79, 0.86)
	sky_mat.ground_bottom_color = Color(0.12, 0.14, 0.17)
	sky_mat.ground_horizon_color = Color(0.48, 0.53, 0.55)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	world_env.environment = env
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
	# A visible blue waterfront marks the coast edge of the prototype map.
	_box(self, Vector3(180, 0.12, 32), Vector3(0, 0.02, -72), Color(0.08, 0.38, 0.62))

func _build_town() -> void:
	# Prototype white-and-sandstone blocks, arranged around a walkable square.
	for i in range(5):
		for j in range(4):
			var x := float(i) * 13.0 - 26.0
			var z := float(j) * 13.0 - 18.0
			if absf(x) < 8.0 and absf(z) < 8.0:
				continue
			var height := randf_range(5.0, 9.0)
			var building := StaticBody3D.new()
			var shade := [Color(0.88,0.83,0.72), Color(0.92,0.89,0.80), Color(0.76,0.70,0.60)][randi_range(0,2)]
			_box(building, Vector3(7.0,height,7.0), Vector3(x,height/2.0,z), shade)
			var col := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(7.0,height,7.0)
			col.shape = shape
			col.position = Vector3(x,height/2.0,z)
			building.add_child(col)
			add_child(building)
	# Landmark: simple lighthouse silhouette by the sea.
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

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 14)
	panel.custom_minimum_size = Vector2(245, 54)
	layer.add_child(panel)
	status_label = Label.new()
	status_label.text = "MAHDIA  •  09:00  •  Prototype"
	panel.add_child(status_label)
	var hint := Label.new()
	hint.text = "WASD / لمس للتحرك  •  اسحب لتدوير الكاميرا"
	hint.position = Vector2(16, 78)
	layer.add_child(hint)
	var run_button := Button.new()
	run_button.text = "جري"
	run_button.position = Vector2(150, -105)
	run_button.anchor_left = 1.0
	run_button.anchor_right = 1.0
	run_button.anchor_top = 1.0
	run_button.anchor_bottom = 1.0
	run_button.custom_minimum_size = Vector2(90, 60)
	layer.add_child(run_button)
	run_button.button_down.connect(func(): player.set_mobile_run(true))
	run_button.button_up.connect(func(): player.set_mobile_run(false))

func _process(delta: float) -> void:
	day_clock = fposmod(day_clock + delta * 0.025, 24.0)
	var daylight := clampf(sin((day_clock - 6.0) / 12.0 * PI), 0.12, 1.0)
	sun.light_energy = daylight
	if is_instance_valid(status_label):
		status_label.text = "MAHDIA  •  %02d:%02d  •  Prototype" % [int(day_clock), int(fposmod(day_clock * 60.0, 60.0))]
