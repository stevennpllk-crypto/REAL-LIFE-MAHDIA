extends Node
class_name MahdiaLifeManager

signal message_changed(value: String)

const SAVE_KEY := "mahdia_life"
var player: CharacterBody3D
var save_manager: Node
var money := 100
var food := 0
var energy := 100.0
var message := "اقترب من مكان واضغط تفاعل"
var stations: Array[Dictionary] = []
var job_claimed := false
var delivery_state := "not_started"
var delivery_npc: Node3D

func setup(target: CharacterBody3D, saver: Node) -> void:
	player = target
	save_manager = saver
	var saved: Dictionary = save_manager.load_progress()
	var data: Dictionary = saved.get(SAVE_KEY, {})
	money = int(data.get("money", 100))
	food = int(data.get("food", 0))
	energy = float(data.get("energy", 100.0))
	job_claimed = bool(data.get("job_claimed", false))
	delivery_state = str(data.get("delivery_state", "not_started"))
	_create_station("مقهى الميناء", "cafe", Vector3(-12, 0, -5), Color(0.65, 0.28, 0.12))
	_create_station("منزلك", "home", Vector3(15, 0, 8), Color(0.82, 0.76, 0.61))
	_create_station("مكتب العمل", "job", Vector3(22, 0, -12), Color(0.18, 0.42, 0.28))
	_create_station("متجر الحي", "shop", Vector3(-22, 0, 12), Color(0.18, 0.38, 0.68))
	_set_message("مرحباً بك في المهدية! تحدث مع السكان واكتشف مهامهم.")

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
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
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
	var resident := _nearest_resident()
	var nearest: Dictionary = {}
	var nearest_distance := 4.5
	for station in stations:
		var distance: float = player.global_position.distance_to(station.position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = station
	if is_instance_valid(resident) and player.global_position.distance_to(resident.global_position) <= nearest_distance:
		_interact_resident(resident)
		return
	if nearest.is_empty():
		_set_message("لا يوجد شخص أو مكان قريب. اقترب أكثر.")
		return
	match str(nearest.kind):
		"cafe":
			if money >= 5:
				money -= 5
				energy = minf(100.0, energy + 20.0)
				_set_message("قهوة الميناء ☕: -5 د.ت، الطاقة +20")
			else:
				_set_message("رصيدك لا يكفي للقهوة. تحتاج 5 د.ت.")
		"home":
			energy = 100.0
			_set_message("استرحت في منزلك واستعدت كامل الطاقة.")
		"job":
			if not job_claimed:
				money += 30
				job_claimed = true
				_set_message("أنهيت عملاً في المهدية وربحت 30 د.ت!")
			else:
				_set_message("أنهيت عمل اليوم بالفعل. عد غداً.")
		"shop":
			if money >= 10:
				money -= 10
				food += 1
				if delivery_state == "accepted":
					delivery_state = "ready"
					_set_message("اشتريت الوجبة المطلوبة! عد إلى المواطن الذي طلبها.")
				else:
					_set_message("اشتريت وجبة. الطعام في حقيبتك: %d" % food)
			else:
				_set_message("تحتاج إلى 10 د.ت لشراء وجبة.")
	_save()

func _nearest_resident() -> Node3D:
	var nearest: Node3D
	var best := 4.5
	for candidate in get_tree().get_nodes_in_group("mahdia_residents"):
		if not is_instance_valid(candidate):
			continue
		var distance: float = player.global_position.distance_to(candidate.global_position)
		if distance < best:
			best = distance
			nearest = candidate
	return nearest

func _interact_resident(resident: Node3D) -> void:
	if delivery_state == "ready" and food > 0:
		food -= 1
		money += 20
		delivery_state = "completed"
		delivery_npc = null
		_set_message("أحسنت! سلّمت الوجبة وربحت 20 د.ت. شكراً لمساعدتك!")
	elif delivery_state == "accepted":
		_set_message("المواطن ينتظر الوجبة. اشترها من متجر الحي ثم عد إليه.")
	elif delivery_state == "ready":
		_set_message("عد إلى المتجر واشتر وجبة أخرى؛ يبدو أنك لا تحملها.")
	elif delivery_state == "completed":
		_set_message("%s: يعطيك الصحة! ساعدتني كثيراً." % str(resident.get("display_name")))
	else:
		delivery_state = "accepted"
		delivery_npc = resident
		_set_message("%s: هل يمكنك إحضار وجبة من متجر الحي؟ المكافأة 20 د.ت!" % str(resident.get("display_name")))
	_save()

func _set_message(value: String) -> void:
	message = value
	message_changed.emit(message)
	print(message)

func _save() -> void:
	if is_instance_valid(save_manager):
		var all_data: Dictionary = save_manager.load_progress()
		all_data[SAVE_KEY] = {
			"money": money,
			"food": food,
			"energy": energy,
			"job_claimed": job_claimed,
			"delivery_state": delivery_state
		}
		save_manager.save_progress(all_data)
