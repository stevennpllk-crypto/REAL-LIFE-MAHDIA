extends Node
class_name MahdiaLifeManager

const SAVE_KEY := "mahdia_life"

var player: CharacterBody3D
var save_manager: Node
var money := 100
var food := 0
var energy := 100.0
var message := "اقترب من مكان واضغط E للتفاعل"
var stations: Array[Dictionary] = []
var job_claimed := false
var hud_label: Label3D

func setup(target: CharacterBody3D, saver: Node) -> void:
	player = target
	save_manager = saver
	var saved: Dictionary = save_manager.load_progress()
	var data: Dictionary = saved.get(SAVE_KEY, {})
	money = int(data.get("money", 100))
	food = int(data.get("food", 0))
	energy = float(data.get("energy", 100.0))
	job_claimed = bool(data.get("job_claimed", false))
	_create_station("مقهى الميناء", "cafe", Vector3(-12, 0, -5), Color(0.65, 0.28, 0.12))
	_create_station("منزلك", "home", Vector3(15, 0, 8), Color(0.82, 0.76, 0.61))
	_create_station("مكتب العمل", "job", Vector3(22, 0, -12), Color(0.18, 0.42, 0.28))
	_create_station("متجر الحي", "shop", Vector3(-22, 0, 12), Color(0.18, 0.38, 0.68))

func _create_station(title: String, kind: String, at: Vector3, tint: Color) -> void:
	var body := StaticBody3D.new()
	body.name = kind.capitalize() + "Station"
	body.position = at
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(4.0, 2.8, 3.0)
	mesh.mesh = box
	mesh.position.y = 1.4
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.82
	mesh.material_override = material
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var collision := BoxShape3D.new()
	collision.size = Vector3(4.0, 2.8, 3.0)
	shape.shape = collision
	shape.position.y = 1.4
	body.add_child(shape)
	var sign := Label3D.new()
	sign.text = title
	sign.position = Vector3(0, 3.2, 0)
	sign.font_size = 36
	sign.pixel_size = 0.008
	body.add_child(sign)
	get_tree().current_scene.add_child(body)
	stations.append({"title": title, "kind": kind, "position": at})

func try_interact() -> void:
	if not is_instance_valid(player):
		return
	var nearest: Dictionary = {}
	var nearest_distance := 4.5
	for station in stations:
		var distance: float = player.global_position.distance_to(station.position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = station
	if nearest.is_empty():
		message = "لا يوجد مكان قريب للتفاعل"
		return
	match str(nearest.kind):
		"cafe":
			if money >= 5:
				money -= 5
				energy = minf(100.0, energy + 20.0)
				message = "استمتعت بقهوة الميناء: -5 د.ت، طاقة +20"
			else:
				message = "رصيدك لا يكفي للقهوة"
		"home":
			energy = 100.0
			message = "استرحت في منزلك واستعدت كامل الطاقة"
		"job":
			if not job_claimed:
				money += 30
				job_claimed = true
				message = "أنهيت عملاً بسيطاً وربحت 30 د.ت"
			else:
				message = "أنهيت عمل اليوم بالفعل"
		"shop":
			if money >= 10:
				money -= 10
				food += 1
				message = "اشتريت وجبة. الطعام: %d" % food
			else:
				message = "تحتاج إلى 10 د.ت لشراء وجبة"
	_save()
	print(message)

func _save() -> void:
	if is_instance_valid(save_manager):
		var all_data: Dictionary = save_manager.load_progress()
		all_data[SAVE_KEY] = {"money": money, "food": food, "energy": energy, "job_claimed": job_claimed}
		save_manager.save_progress(all_data)
