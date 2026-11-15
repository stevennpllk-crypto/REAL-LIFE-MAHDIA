extends Node
class_name MahdiaLifeManager

signal message_changed(value: String)

const SAVE_KEY := "mahdia_life"
const AUTOSAVE_SECONDS := 10.0
var player: CharacterBody3D
var ai_service: Node
var active_resident: Node3D
var save_manager: Node
var money := 100
var food := 0
var energy := 100.0
var hunger := 100.0
var message := "اقترب من مكان واضغط تفاعل"
var stations: Array[Dictionary] = []
var job_claimed := false
var delivery_state := "not_started"
var delivery_npc: Node3D
var inside_station_kind := ""
var autosave_elapsed := 0.0
var base_run_speed := 4.8
var base_walk_speed := 2.6

func set_ai_service(service: Node) -> void:
	ai_service = service
	if is_instance_valid(ai_service):
		var callback := Callable(self, "_on_npc_ai_reply")
		if not ai_service.is_connected("npc_reply", callback):
			ai_service.connect("npc_reply", callback)
		var status_callback := Callable(self, "_on_ai_connection_status")
		if ai_service.has_signal("connection_status") and not ai_service.is_connected("connection_status", status_callback):
			ai_service.connect("connection_status", status_callback)

func send_player_message(message_text: String) -> void:
	var clean_text := message_text.strip_edges()
	if clean_text.is_empty():
		return
	if not is_instance_valid(active_resident):
		active_resident = _nearest_resident()
	if not is_instance_valid(active_resident):
		_set_message("اقترب من أحد سكان المهدية أولاً.")
		return
	if not is_instance_valid(ai_service) or not ai_service.has_method("request_npc_reply"):
		_set_message(str(active_resident.call("get_dialogue")))
		return
	_set_message("%s يفكر في الرد..." % str(active_resident.get("display_name")))
	ai_service.call("request_npc_reply", active_resident, clean_text)

func _on_ai_connection_status(_ready: bool, status_text: String) -> void:
	_set_message(status_text)

func _on_npc_ai_reply(resident: Node3D, reply: String, success: bool) -> void:
	if not is_instance_valid(resident):
		return
	if success:
		_set_message("%s: %s" % [str(resident.get("display_name")), reply])
	else:
		_set_message("%s: %s" % [str(resident.get("display_name")), str(resident.call("get_dialogue"))])

func setup(target: CharacterBody3D, saver: Node) -> void:
	player = target
	base_run_speed = float(player.get("run_speed"))
	base_walk_speed = float(player.get("walk_speed"))
	save_manager = saver
	var saved: Dictionary = save_manager.load_progress()
	var data: Dictionary = saved.get(SAVE_KEY, {})
	money = maxi(0, int(data.get("money", 100)))
	food = maxi(0, int(data.get("food", 0)))
	energy = clampf(float(data.get("energy", 100.0)), 0.0, 100.0)
	hunger = clampf(float(data.get("hunger", 100.0)), 0.0, 100.0)
	job_claimed = bool(data.get("job_claimed", false))
	delivery_state = str(data.get("delivery_state", "not_started"))
	_create_station("مقهى الميناء", "cafe", Vector3(-12, 0, -5), Color(0.65, 0.28, 0.12))
	_create_station("منزلك", "home", Vector3(15, 0, 8), Color(0.82, 0.76, 0.61))
	_create_station("مكتب العمل", "job", Vector3(22, 0, -12), Color(0.18, 0.42, 0.28))
	_create_station("متجر الحي", "shop", Vector3(-22, 0, 12), Color(0.18, 0.38, 0.68))
	_set_message("مرحباً بك في المهدية! اقترب من مبنى وادخل من بابه للتفاعل.")

func _make_wall(parent: Node3D, size: Vector3, pos: Vector3, tint: Color) -> void:
	var wall := StaticBody3D.new()
	wall.position = pos
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.86
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = material
	wall.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	wall.add_child(collision)
	parent.add_child(wall)

func _create_station(title: String, kind: String, at: Vector3, tint: Color) -> void:
	var building := Node3D.new()
	building.name = kind.capitalize() + "Interior"
	building.position = at
	var wall_color := tint
	_make_wall(building, Vector3(4.0, 0.18, 3.0), Vector3(0, -0.12, 0), Color(0.64, 0.59, 0.49))
	_make_wall(building, Vector3(4.0, 2.8, 0.22), Vector3(0, 1.4, -1.5), wall_color)
	_make_wall(building, Vector3(0.22, 2.8, 3.0), Vector3(-2.0, 1.4, 0), wall_color)
	_make_wall(building, Vector3(0.22, 2.8, 3.0), Vector3(2.0, 1.4, 0), wall_color)
	# Two front wall sections leave a real doorway in the middle.
	_make_wall(building, Vector3(1.2, 2.8, 0.22), Vector3(-1.4, 1.4, 1.5), wall_color)
	_make_wall(building, Vector3(1.2, 2.8, 0.22), Vector3(1.4, 1.4, 1.5), wall_color)
	_make_wall(building, Vector3(4.0, 0.18, 3.0), Vector3(0, 2.85, 0), tint.darkened(0.18))
	var sign := Label3D.new()
	sign.text = title
	sign.position = Vector3(0, 3.25, 1.72)
	sign.font_size = 34
	sign.pixel_size = 0.008
	building.add_child(sign)
	get_tree().current_scene.add_child(building)
	stations.append({"title": title, "kind": kind, "position": at, "building": building})

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
	var kind := str(nearest.kind)
	if inside_station_kind != kind:
		player.global_position = nearest.position + Vector3(0, 0, 0.35)
		inside_station_kind = kind
		_set_message("دخلت %s. اضغط تفاعل مرة أخرى لاستخدام المكان، أو اخرج من الباب." % str(nearest.title))
		return
	match kind:
		"cafe":
			if money >= 5:
				money -= 5
				energy = minf(100.0, energy + 20.0)
				_set_message("مقهى الميناء ☕: -5 د.ت، الطاقة +20")
			else:
				_set_message("رصيدك لا يكفي للقهوة. تحتاج 5 د.ت.")
		"home":
			energy = minf(100.0, energy + 45.0)
			if food > 0:
				food -= 1
				hunger = minf(100.0, hunger + 35.0)
				_set_message("تناولت وجبة في منزلك واستعدت طاقتك. الجوع %d%%" % int(hunger))
			else:
				_set_message("استرحت في منزلك واستعدت بعض الطاقة. اشترِ طعاماً لتخفيف الجوع.")
		"job":
			if not job_claimed:
				money += 30
				job_claimed = true
				_set_message("أنهيت عملاً في المهدية وربحت 30 د.ت!")
			else:
				_set_message("أنهيت عمل اليوم بالفعل. عد لاحقاً.")
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
	save_now()

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
	active_resident = resident
	if resident.has_method("on_player_interacted"):
		resident.on_player_interacted()
	var resident_dialogue := str(resident.call("get_dialogue")) if resident.has_method("get_dialogue") else str(resident.get("display_name"))
	if delivery_state == "ready" and food > 0:
		food -= 1
		money += 20
		delivery_state = "completed"
		delivery_npc = null
		_set_message("أحسنت! سلّمت الوجبة وربحت 20 د.ت. شكراً لمساعدتك!")
	elif delivery_state == "accepted":
		_set_message("المواطن ينتظر الوجبة. اشترها من متجر الحي ثم عد إليه.")
	elif delivery_state == "completed":
		_set_message("%s: يعطيك الصحة! ساعدتني كثيراً." % resident_dialogue)
	else:
		delivery_state = "accepted"
		delivery_npc = resident
		_set_message("%s هل يمكنك إحضار وجبة من متجر الحي؟ المكافأة 20 د.ت!" % resident_dialogue)
	save_now()

func _set_message(value: String) -> void:
	message = value
	message_changed.emit(message)
	print(message)

func save_now() -> void:
	if not is_instance_valid(save_manager):
		return
	var all_data: Dictionary = save_manager.load_progress()
	all_data[SAVE_KEY] = {
		"money": money,
		"food": food,
		"energy": energy,
		"hunger": hunger,
		"job_claimed": job_claimed,
		"delivery_state": delivery_state
	}
	var result: Error = save_manager.save_progress(all_data)
	if result != OK:
		push_warning("Could not save life progress: %s" % error_string(result))

func _apply_stamina(delta: float, sprinting: bool) -> void:
	if not is_instance_valid(player):
		return
	if sprinting:
		if energy > 0.0:
			energy = maxf(0.0, energy - delta * 9.0)
	else:
		energy = minf(100.0, energy + delta * 5.0)
	var available_speed := base_run_speed if energy > 0.0 else base_walk_speed
	player.set("run_speed", available_speed)

func _process(delta: float) -> void:
	hunger = maxf(0.0, hunger - delta * 0.025)
	var sprinting := false
	if is_instance_valid(player):
		sprinting = bool(player.get("running")) or Input.is_action_pressed("run")
	_apply_stamina(delta, sprinting)
	if hunger <= 0.0:
		energy = maxf(0.0, energy - delta * 0.01)
	autosave_elapsed += delta
	if autosave_elapsed >= AUTOSAVE_SECONDS:
		autosave_elapsed = 0.0
		save_now()
	if inside_station_kind != "" and is_instance_valid(player):
		var station_position := Vector3.ZERO
		for station in stations:
			if str(station.kind) == inside_station_kind:
				station_position = station.position
				break
		if player.global_position.distance_to(station_position) > 5.2:
			inside_station_kind = ""
