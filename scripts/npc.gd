extends CharacterBody3D
class_name MahdiaNPC

@export var display_name := "Resident"
@export var walk_speed := 1.15
@export var wander_radius := 7.0
@export var personality := "friendly"
@export var occupation := "resident"
@export var build_visuals := true

var player: CharacterBody3D
var world_clock: Node
var memory_manager: Node
var memory_id := ""
var home_position := Vector3.ZERO
var work_position := Vector3.ZERO
var rest_position := Vector3.ZERO
var target_position := Vector3.ZERO
var wait_time := 0.0
var decision_elapsed := 0.0
var player_scan_elapsed := 0.0
var goal_refresh_elapsed := 0.0
var memory_meetings := 0
var last_player_interaction := -1000.0
var mood := 0.5
var trust := 0.0
var hunger := 0.18
var energy := 0.82
var social_need := 0.45
var curiosity := 0.55
var decision_reason := "أبحث عن شيء أفعله"
var need_update_elapsed := 0.0
var social_scan_elapsed := 0.0
var resident_relationships: Dictionary = {}
# Prevent two nearby residents from rapidly maxing out familiarity every scan.
var social_encounter_cooldowns: Dictionary = {}
var ai_state := "wander"
var personal_seed := 0
var turn_bias := 1.0
var obstacle_check_elapsed := 0.0
var obstacle_steering := Vector3.ZERO
var crowd_check_elapsed := 0.0
var crowd_steering := Vector3.ZERO
var left_arm: Node3D
var right_arm: Node3D
var left_leg: Node3D
var right_leg: Node3D
var visual_root: Node3D
var head_visual: Node3D
var body_visual: Node3D
var eye_left: MeshInstance3D
var eye_right: MeshInstance3D
var blink_timer := 2.5
var idle_phase := 0.0
var clock := 0.0
# Cognitive simulation: persistent episodic memories, learned preferences and self-review.
var long_term_memories: Array[Dictionary] = []
var learned_preferences: Dictionary = {}
var stress := 0.0
var confidence := 0.5
var current_goal := "استكشاف الحي"
var reflection_elapsed := 0.0
var memory_save_elapsed := 0.0
var memory_dirty := false
var autonomy_cycles := 0
var last_experience_tag := ""
var last_experience_time := -1000.0

func set_ai_context(player_node: CharacterBody3D, clock_node: Node, work_spot: Vector3, identity: int, saver: Node = null) -> void:
	player = player_node
	world_clock = clock_node
	memory_manager = saver
	memory_id = "resident_%02d" % identity
	_load_memory()
	work_position = work_spot
	personal_seed = identity
	# Stagger periodic disk writes so residents never save on the same frame.
	memory_save_elapsed = float(posmod(identity, 8)) * 5.0
	rest_position = work_spot + Vector3(3.0, 0, 2.5)
	turn_bias = -1.0 if identity % 2 == 0 else 1.0

func _ready() -> void:
	add_to_group("mahdia_residents")
	home_position = global_position
	if work_position == Vector3.ZERO:
		work_position = home_position + Vector3(5, 0, 0)
	rest_position = home_position + Vector3(-3, 0, 3)
	_choose_target()
	if build_visuals:
		_build_character()
	var collider := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.29
	shape.height = 1.72
	collider.shape = shape
	collider.position.y = 0.86
	add_child(collider)
	_choose_daily_goal(_current_hour())

func _mat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.86
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

func _build_character() -> void:
	visual_root = Node3D.new()
	visual_root.name = "ResidentVisual"
	add_child(visual_root)
	var palette := [Color(0.72, 0.25, 0.16), Color(0.12, 0.42, 0.36), Color(0.82, 0.62, 0.18), Color(0.24, 0.34, 0.62), Color(0.62, 0.35, 0.22), Color(0.42, 0.30, 0.58), Color(0.78, 0.72, 0.58), Color(0.12, 0.22, 0.28)]
	var skin_palette := [Color(0.48, 0.30, 0.21), Color(0.60, 0.39, 0.28), Color(0.69, 0.48, 0.35), Color(0.76, 0.56, 0.42), Color(0.55, 0.35, 0.25)]
	var hair_palette := [Color(0.045, 0.035, 0.03), Color(0.13, 0.075, 0.045), Color(0.22, 0.15, 0.09), Color(0.34, 0.25, 0.16)]
	var shirt: Color = palette[posmod(personal_seed, palette.size())]
	var skin: Color = skin_palette[posmod(personal_seed * 3 + 1, skin_palette.size())]
	var hair: Color = hair_palette[posmod(personal_seed * 5 + 2, hair_palette.size())]
	var height_variation := 0.94 + float(posmod(personal_seed * 7, 13)) * 0.01
	visual_root.scale = Vector3(1.0, height_variation, 1.0)
	# Tailored torso: a tapered body, collar, waist and subtle clothing panels.
	var torso := CylinderMesh.new()
	torso.top_radius = 0.19
	torso.bottom_radius = 0.275
	torso.height = 0.78
	torso.radial_segments = 12
	body_visual = _part(torso, Vector3(0, 1.18, 0), shirt)
	_part(_torus(0.105, 0.025), Vector3(0, 1.56, -0.005), shirt.darkened(0.18))
	_part(_capsule(0.045, 0.16), Vector3(0, 1.49, -0.19), shirt.lightened(0.16))
	head_visual = get_node_or_null("ResidentVisual/HeadPivot") as Node3D
	if not is_instance_valid(head_visual):
		head_visual = Node3D.new()
		head_visual.name = "HeadPivot"
		head_visual.position = Vector3(0, 1.84, 0)
		visual_root.add_child(head_visual)
		var head := MeshInstance3D.new()
		head.mesh = _sphere(0.19, 0.40)
		head.material_override = _mat(skin)
		head_visual.add_child(head)
	# Hair cap, side locks, ears, nose, brows and eyes give faces readable depth.
	var cap := _head_part(_sphere(0.195, 0.22), Vector3(0, 0.145, 0.015), hair)
	cap.scale = Vector3(1.0, 0.62, 1.0)
	_head_part(_sphere(0.055, 0.16), Vector3(-0.174, 0, 0), hair)
	_head_part(_sphere(0.055, 0.16), Vector3(0.174, 0, 0), hair)
	_head_part(_sphere(0.035, 0.055), Vector3(-0.184, -0.02, 0), skin)
	_head_part(_sphere(0.035, 0.055), Vector3(0.184, -0.02, 0), skin)
	eye_left = _head_part(_sphere(0.022, 0.03), Vector3(-0.068, 0.02, -0.175), Color(0.035, 0.025, 0.02))
	eye_right = _head_part(_sphere(0.022, 0.03), Vector3(0.068, 0.02, -0.175), Color(0.035, 0.025, 0.02))
	_head_part(_sphere(0.026, 0.045), Vector3(0, -0.02, -0.187), skin.lightened(0.04))
	_head_part(_capsule(0.014, 0.075), Vector3(-0.068, 0.065, -0.174), hair)
	_head_part(_capsule(0.014, 0.075), Vector3(0.068, 0.065, -0.174), hair)
	_build_occupation_details()
	left_arm = _limb(Vector3(-0.30, 1.43, 0), shirt, 0.62, 0.10)
	right_arm = _limb(Vector3(0.30, 1.43, 0), shirt, 0.62, 0.10)
	left_leg = _limb(Vector3(-0.14, 0.76, 0), Color(0.12, 0.14, 0.18), 0.72, 0.12)
	right_leg = _limb(Vector3(0.14, 0.76, 0), Color(0.12, 0.14, 0.18), 0.72, 0.12)

func _torus(inner_radius: float, outer_radius: float) -> TorusMesh:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner_radius
	mesh.outer_radius = outer_radius
	mesh.rings = 12
	mesh.ring_segments = 6
	return mesh

func _build_occupation_details() -> void:
	# Distinct, inexpensive silhouettes make residents identifiable at a glance.
	var details := Node3D.new()
	details.name = "OccupationDetails"
	visual_root.add_child(details)
	match occupation:
		"fisher":
			_detail_cylinder(details, 0.19, 0.12, Vector3(0, 2.08, 0), Color(0.12, 0.30, 0.42))
			_detail_box(details, Vector3(0.42, 0.07, 0.32), Vector3(0, 2.04, -0.02), Color(0.12, 0.30, 0.42))
			_detail_box(details, Vector3(0.40, 0.48, 0.06), Vector3(0, 1.18, 0.25), Color(0.42, 0.28, 0.16))
		"shopkeeper":
			_detail_box(details, Vector3(0.43, 0.60, 0.055), Vector3(0, 1.17, -0.245), Color(0.16, 0.31, 0.27))
			_detail_box(details, Vector3(0.08, 0.42, 0.06), Vector3(-0.17, 1.52, -0.245), Color(0.16, 0.31, 0.27))
		"mechanic":
			_detail_box(details, Vector3(0.55, 0.14, 0.32), Vector3(0, 0.91, 0), Color(0.20, 0.19, 0.16))
			_detail_box(details, Vector3(0.18, 0.16, 0.08), Vector3(0.17, 0.91, -0.20), Color(0.78, 0.55, 0.16))
		"student":
			_detail_box(details, Vector3(0.42, 0.56, 0.22), Vector3(0, 1.25, 0.25), Color(0.18, 0.24, 0.34))
			_detail_box(details, Vector3(0.08, 0.42, 0.08), Vector3(-0.22, 1.31, 0.05), Color(0.18, 0.24, 0.34))
		"cook":
			_detail_cylinder(details, 0.17, 0.22, Vector3(0, 2.12, 0), Color(0.93, 0.91, 0.84))
			_detail_box(details, Vector3(0.44, 0.62, 0.055), Vector3(0, 1.17, -0.245), Color(0.88, 0.84, 0.72))
		"driver":
			_detail_box(details, Vector3(0.38, 0.10, 0.32), Vector3(0, 2.05, 0), Color(0.16, 0.20, 0.25))
			_detail_box(details, Vector3(0.44, 0.06, 0.26), Vector3(0, 1.99, -0.06), Color(0.16, 0.20, 0.25))
		_:
			_detail_box(details, Vector3(0.42, 0.12, 0.30), Vector3(0, 1.66, 0), Color(0.78, 0.68, 0.48))

func _detail_box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var item := MeshInstance3D.new()
	item.mesh = mesh
	item.position = pos
	item.material_override = _mat(color)
	parent.add_child(item)

func _detail_cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.92
	mesh.bottom_radius = radius
	mesh.height = height
	var item := MeshInstance3D.new()
	item.mesh = mesh
	item.position = pos
	item.material_override = _mat(color)
	parent.add_child(item)

func _capsule(radius: float, height: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	return mesh

func _sphere(radius: float, height: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	return mesh

func _head_part(mesh: Mesh, pos: Vector3, color: Color) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.mesh = mesh
	item.position = pos
	item.material_override = _mat(color)
	head_visual.add_child(item)
	return item

func _part(mesh: Mesh, pos: Vector3, color: Color) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.mesh = mesh
	item.position = pos
	item.material_override = _mat(color)
	visual_root.add_child(item)
	return item

func _limb(pos: Vector3, color: Color, length: float, radius: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	visual_root.add_child(pivot)
	var item := MeshInstance3D.new()
	item.mesh = _capsule(radius, length)
	item.position = Vector3(0, -length * 0.34, 0)
	item.material_override = _mat(color)
	pivot.add_child(item)
	var extremity := MeshInstance3D.new()
	if length < 0.7:
		extremity.mesh = _sphere(0.075, 0.14)
		extremity.position = Vector3(0, -length * 0.72, -0.005)
		extremity.material_override = _mat(Color(0.60, 0.39, 0.28))
	else:
		extremity.mesh = _capsule(0.105, 0.30)
		extremity.position = Vector3(0, -length * 0.76, -0.035)
		extremity.rotation.x = deg_to_rad(90.0)
		extremity.material_override = _mat(Color(0.045, 0.05, 0.06))
	pivot.add_child(extremity)
	return pivot

func _current_hour() -> float:
	if is_instance_valid(world_clock):
		return float(world_clock.get("hour"))
	return 12.0

func _choose_daily_goal(hour: float) -> void:
	# Utility-based autonomous decision: needs compete with routine and personality.
	# Residents follow staggered daily rhythms instead of all choosing randomly.
	# Night sleep and evening return-home priorities are deliberately stronger.
	var is_night := hour >= 22.0 or hour < 6.0
	var is_evening := hour >= 18.0 and hour < 22.0
	var is_work_hours := hour >= 7.0 and hour < 17.0
	var personal_schedule_offset := float(posmod(personal_seed, 5)) * 0.035
	var rest_score := (1.0 - energy) * 1.25
	if is_night:
		rest_score = maxf(rest_score, 1.45 + (1.0 - energy) * 0.35 + personal_schedule_offset)
	var social_score := social_need * (1.2 if personality in ["friendly", "curious"] else 0.8)
	var explore_score := curiosity * (1.25 if personality == "curious" else 0.75)
	var food_score := hunger * 1.45
	var work_score := 0.78 + personal_schedule_offset if occupation != "resident" and is_work_hours else 0.12
	var home_score := (0.92 + personal_schedule_offset if is_evening else 0.48 if is_night else 0.08)
	# Past outcomes influence future choices; residents gradually develop individual habits.
	food_score *= 1.0 + float(learned_preferences.get("food", 0.0))
	rest_score *= 1.0 + float(learned_preferences.get("rest", 0.0))
	social_score *= 1.0 + float(learned_preferences.get("social", 0.0))
	explore_score *= 1.0 + float(learned_preferences.get("explore", 0.0))
	work_score *= 1.0 + float(learned_preferences.get("work", 0.0))
	var best_score := maxf(food_score, maxf(rest_score, maxf(social_score, maxf(explore_score, maxf(work_score, home_score)))))
	if best_score == food_score:
		current_goal = "الطعام"
		var food_station := _nearest_food_station()
		if is_instance_valid(food_station):
			ai_state = "seeking_food"
			# Approach the public entrance, not the building's centre.
			target_position = food_station.global_position + Vector3(0, 0, 2.7)
			decision_reason = "أتجه إلى مقهى الحي لأتناول الطعام"
		else:
			ai_state = "wandering"
			target_position = _random_near(home_position)
			decision_reason = "أبحث عن مكان يقدم الطعام"
	elif best_score == rest_score:
		current_goal = "الراحة"
		ai_state = "resting"
		target_position = rest_position
		decision_reason = "أحتاج إلى الراحة"
	elif best_score == social_score:
		current_goal = "التواصل"
		ai_state = "socializing"
		var known_resident := _nearest_resident(10.0)
		if is_instance_valid(known_resident):
			target_position = known_resident.global_position + Vector3(1.2, 0, 0.8)
		else:
			target_position = rest_position + _random_near(Vector3.ZERO) * 0.35
		decision_reason = "أبحث عن رفقة وحديث"
	elif best_score == work_score:
		current_goal = "العمل"
		ai_state = "commuting"
		target_position = work_position
		decision_reason = "حان وقت العمل"
	elif best_score == home_score:
		current_goal = "العودة إلى المنزل"
		ai_state = "going_home"
		target_position = home_position
		decision_reason = "أريد العودة إلى المنزل"
	else:
		current_goal = "استكشاف الحي"
		ai_state = "wandering"
		target_position = _random_near(home_position)
		decision_reason = "أستكشف الحي"
	wait_time = randf_range(0.5, 2.0)


func _record_experience(tag: String, detail: String, emotional_weight: float) -> void:
	var now := Time.get_unix_time_from_system()
	if tag == last_experience_tag and now - last_experience_time < 45.0:
		return
	last_experience_tag = tag
	last_experience_time = now
	memory_dirty = true
	long_term_memories.append({
		"tag": tag,
		"detail": detail,
		"weight": clampf(emotional_weight, -1.0, 1.0),
		"hour": _current_hour(),
		"time": now
	})
	while long_term_memories.size() > 16:
		long_term_memories.pop_front()

func _reflect_on_experiences() -> void:
	# Periodic reflection turns repeated experiences into persistent preferences.
	if long_term_memories.is_empty():
		return
	var recent_count := mini(8, long_term_memories.size())
	var total_weight := 0.0
	var counts: Dictionary = {}
	for i in range(long_term_memories.size() - recent_count, long_term_memories.size()):
		var memory: Dictionary = long_term_memories[i]
		total_weight += float(memory.get("weight", 0.0))
		var tag := str(memory.get("tag", ""))
		if not tag.is_empty():
			counts[tag] = int(counts.get(tag, 0)) + 1
	mood = clampf(mood + total_weight * 0.025, 0.0, 1.0)
	for tag in counts:
		var preference := clampf(float(learned_preferences.get(tag, 0.0)), -0.25, 0.35)
		learned_preferences[tag] = clampf(preference + minf(float(counts[tag]) * 0.008, 0.025), -0.25, 0.35)
	confidence = clampf(confidence + 0.004, 0.0, 1.0)
	memory_dirty = true
	autonomy_cycles += 1
	if counts.has("social") and int(counts["social"]) >= 2:
		decision_reason = "أتذكر أن لقاء الجيران يجعل يومي أفضل"
	elif counts.has("explore") and int(counts["explore"]) >= 2:
		decision_reason = "أحب اكتشاف أماكن جديدة في الحي"
	elif stress > 0.7:
		decision_reason = "أشعر بالضغط وأحتاج إلى تغيير روتيني"

func _nearest_food_station() -> Node3D:
	var nearest: Node3D
	var best_distance := INF
	for station in get_tree().get_nodes_in_group("resident_food_stations"):
		if not is_instance_valid(station) or station.is_queued_for_deletion():
			continue
		var distance := global_position.distance_to(station.global_position)
		if distance < best_distance:
			best_distance = distance
			nearest = station as Node3D
	return nearest

func _nearest_resident(max_distance: float) -> MahdiaNPC:
	var nearest: MahdiaNPC
	var best_distance := max_distance
	for candidate in get_tree().get_nodes_in_group("mahdia_residents"):
		if candidate == self or not is_instance_valid(candidate) or candidate.is_queued_for_deletion():
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance < best_distance:
			best_distance = distance
			nearest = candidate as MahdiaNPC
	return nearest

func _update_social_awareness() -> void:
	var other := _nearest_resident(7.0)
	if not is_instance_valid(other):
		return
	var other_id := str(other.get("memory_id"))
	if other_id.is_empty():
		other_id = str(other.get("display_name"))
	if other_id.is_empty():
		return
	var familiarity := clampf(float(resident_relationships.get(other_id, 0.0)), 0.0, 1.0)
	var distance := global_position.distance_to(other.global_position)
	if distance <= 2.4:
		var now_msec := Time.get_ticks_msec()
		var last_encounter := int(social_encounter_cooldowns.get(other_id, -20000))
		# A pair can deepen its relationship at most once every 20 seconds.
		if now_msec - last_encounter >= 20000:
			social_encounter_cooldowns[other_id] = now_msec
			# Store the encounter on both sides: relationships are reciprocal.
			var other_cooldowns: Dictionary = other.get("social_encounter_cooldowns")
			other_cooldowns[memory_id] = now_msec
			other.set("social_encounter_cooldowns", other_cooldowns)
			_record_experience("social", "قضيت وقتاً مع %s" % str(other.get("display_name")), 0.04)
			familiarity = clampf(familiarity + 0.004, 0.0, 1.0)
			resident_relationships[other_id] = familiarity
			var other_relationships: Dictionary = other.get("resident_relationships").duplicate(true)
			var my_id := memory_id if not memory_id.is_empty() else str(display_name)
			var reverse_familiarity := clampf(float(other_relationships.get(my_id, 0.0)) + 0.004, 0.0, 1.0)
			other_relationships[my_id] = reverse_familiarity
			other.set("resident_relationships", other_relationships)
			memory_dirty = true
			if ai_state == "socializing" or social_need > 0.72:
				social_need = clampf(social_need - 0.035, 0.0, 1.0)
				other.set("social_need", clampf(float(other.get("social_need")) - 0.02, 0.0, 1.0))
				other.set("memory_dirty", true)
				decision_reason = "أتحدث مع %s وأتعرف إليه أكثر" % str(other.get("display_name"))
				if ai_state != "working" and ai_state != "resting":
					ai_state = "socializing"
					wait_time = maxf(wait_time, 1.0)

func _update_needs(delta: float) -> void:
	# Emotional state is simulated as a changing internal variable, not a claim of sentience.
	stress = clampf(stress + (0.00008 if hunger > 0.75 or energy < 0.2 else -0.00004) * delta, 0.0, 1.0)
	hunger = clampf(hunger + delta * 0.00032, 0.0, 1.0)
	energy = clampf(energy - delta * (0.00020 if ai_state != "resting" else -0.00085), 0.0, 1.0)
	social_need = clampf(social_need + delta * 0.00024, 0.0, 1.0)
	curiosity = clampf(curiosity + delta * 0.00012, 0.0, 1.0)
	if ai_state == "resting":
		energy = clampf(energy + delta * 0.0010, 0.0, 1.0)
		social_need = clampf(social_need - delta * 0.00012, 0.0, 1.0)
	elif ai_state == "socializing":
		social_need = clampf(social_need - delta * 0.0009, 0.0, 1.0)
	elif ai_state == "working":
		curiosity = clampf(curiosity - delta * 0.00015, 0.0, 1.0)

func _random_near(center: Vector3) -> Vector3:
	var angle := randf() * TAU
	var distance := randf_range(2.0, wander_radius)
	return center + Vector3(cos(angle) * distance, 0, sin(angle) * distance)

func _choose_target() -> void:
	target_position = _random_near(home_position)
	wait_time = randf_range(1.0, 3.0)
	ai_state = "wander"

func on_player_interacted() -> void:
	_record_experience("player", "التقيت باللاعب وتحدثت معه", 0.10)
	memory_meetings += 1
	last_player_interaction = Time.get_ticks_msec() / 1000.0
	mood = clampf(mood + 0.12, 0.0, 1.0)
	trust = clampf(trust + (0.10 if personality != "shy" else 0.045), 0.0, 1.0)
	social_need = clampf(social_need - 0.28, 0.0, 1.0)
	curiosity = clampf(curiosity + 0.08, 0.0, 1.0)
	decision_reason = "تحدثت مع اللاعب وأتذكر اللقاء"
	memory_dirty = true
	_save_memory()

func _load_memory() -> void:
	if not is_instance_valid(memory_manager) or memory_id.is_empty():
		return
	var all_data: Dictionary = memory_manager.load_progress()
	var memories: Dictionary = all_data.get("mahdia_npc_memory", {})
	var memory: Dictionary = memories.get(memory_id, {})
	memory_meetings = maxi(0, int(memory.get("meetings", 0)))
	long_term_memories.clear()
	for entry in memory.get("episodic_memories", []):
		if entry is Dictionary:
			long_term_memories.append(entry.duplicate(true))
	learned_preferences = memory.get("preferences", {}).duplicate(true)
	stress = clampf(float(memory.get("stress", 0.0)), 0.0, 1.0)
	current_goal = str(memory.get("current_goal", "استكشاف الحي"))
	confidence = clampf(float(memory.get("confidence", 0.5)), 0.0, 1.0)
	mood = clampf(float(memory.get("mood", 0.5)), 0.0, 1.0)
	trust = clampf(float(memory.get("trust", 0.0)), 0.0, 1.0)
	hunger = clampf(float(memory.get("hunger", 0.18)), 0.0, 1.0)
	energy = clampf(float(memory.get("energy", 0.82)), 0.0, 1.0)
	social_need = clampf(float(memory.get("social_need", 0.45)), 0.0, 1.0)
	curiosity = clampf(float(memory.get("curiosity", 0.55)), 0.0, 1.0)
	resident_relationships = memory.get("relationships", {}).duplicate(true)

func _save_memory() -> void:
	if not is_instance_valid(memory_manager) or memory_id.is_empty():
		return
	var all_data: Dictionary = memory_manager.load_progress()
	var memories: Dictionary = all_data.get("mahdia_npc_memory", {})
	memories[memory_id] = {"meetings": memory_meetings, "mood": mood, "trust": trust, "hunger": hunger, "energy": energy, "social_need": social_need, "curiosity": curiosity, "relationships": resident_relationships, "episodic_memories": long_term_memories, "preferences": learned_preferences, "stress": stress, "confidence": confidence, "current_goal": current_goal}
	all_data["mahdia_npc_memory"] = memories
	var result: Error = memory_manager.save_progress(all_data)
	if result == OK:
		memory_dirty = false
	else:
		push_warning("Could not save resident memory: %s" % error_string(result))

func get_ai_context() -> Dictionary:
	return {
		"id": memory_id,
		"name": display_name,
		"personality": personality,
		"occupation": occupation,
		"mood": mood,
		"trust": trust,
		"hunger": hunger,
		"energy": energy,
		"social_need": social_need,
		"curiosity": curiosity,
		"relationships": resident_relationships.duplicate(true),
		"meetings": memory_meetings,
		"memories": long_term_memories.duplicate(true),
		"stress": stress,
		"confidence": confidence,
		"goal": current_goal,
		"reason": decision_reason
	}

func get_dialogue() -> String:
	var remembered := "أهلاً، تذكرتك!" if memory_meetings > 1 else "أهلاً بك."
	if trust >= 0.55:
		remembered = "سعيد برؤيتك مجدداً، أصبحتَ مألوفاً لدي."
	var hour := _current_hour()
	var greeting := "صباح الخير" if hour >= 5.0 and hour < 12.0 else "مساء الخير" if hour >= 17.0 else "أهلاً بك"
	if energy < 0.2:
		return greeting + "، " + remembered + " أشعر بالتعب وأحتاج إلى الراحة."
	if hunger > 0.78:
		return greeting + "، " + remembered + " أشعر بالجوع، سأبحث عن طعام."
	if stress > 0.72:
		return remembered + " يومي مزدحم قليلاً، أحتاج إلى استراحة."
	if ai_state == "working" or ai_state == "commuting":
		return greeting + "، أنا في طريقي إلى عملي كـ%s." % occupation
	if ai_state == "socializing" and memory_meetings > 0:
		return remembered + " كنت أتحدث مع الجيران. كيف حالك؟"
	match personality:
		"shy":
			return greeting + ". " + remembered + " أنا خجول قليلاً، لكن تفضل."
		"busy":
			return greeting + "، أنا مشغول قليلاً بعملي، لكن يسعدني لقاؤك."
		"curious":
			return remembered + " هل سمعت آخر أخبار المهدية؟ أحب معرفة ما يحدث حولي."
		"grumpy":
			return remembered + " الشوارع مزدحمة اليوم، أتمنى أن يهدأ الجو قليلاً."
		_:
			return greeting + "! " + remembered + " يعطيك الصحة!"

func _player_decision() -> bool:
	if not is_instance_valid(player) or player.is_queued_for_deletion():
		return false
	var distance := global_position.distance_to(player.global_position)
	if distance > 8.0:
		return false
	match personality:
		"shy":
			if distance < 4.0:
				ai_state = "avoiding"
				target_position = global_position + (global_position - player.global_position).normalized() * 5.0
				return true
		"busy":
			if distance < 2.8:
				ai_state = "acknowledging"
				target_position = global_position
				return true
		_:
			if distance < 5.5:
				ai_state = "greeting"
				target_position = player.global_position + (global_position - player.global_position).normalized() * 1.7
				return true
	return false

func _avoid_obstacle(direction: Vector3, delta: float) -> Vector3:
	if direction.length_squared() < 0.01:
		return direction
	# Eight residents do not need eight raycasts every rendered frame.
	# Reuse the last steering result and refresh it four times per second.
	obstacle_check_elapsed += delta
	if obstacle_check_elapsed < 0.25:
		return obstacle_steering if obstacle_steering.length_squared() > 0.01 else direction
	obstacle_check_elapsed = 0.0
	var origin := global_position + Vector3.UP * 0.8
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * 1.6)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		obstacle_steering = direction
		return direction
	var side := Vector3(-direction.z, 0, direction.x) * turn_bias
	obstacle_steering = (direction + side * 1.8).normalized()
	return obstacle_steering

func _avoid_resident_crowding(direction: Vector3) -> Vector3:
	if direction.length_squared() < 0.01:
		return direction
	# A short staggered scan keeps pedestrians from clipping through one another
	# without adding physics bodies, navigation meshes, or per-frame raycasts.
	crowd_check_elapsed += get_physics_process_delta_time()
	if crowd_check_elapsed < 0.30:
		return direction
	crowd_check_elapsed = 0.0
	var separation := Vector3.ZERO
	var nearby_count := 0
	for resident in get_tree().get_nodes_in_group("mahdia_residents"):
		if resident == self or not is_instance_valid(resident):
			continue
		var offset := global_position - resident.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance > 0.05 and distance < 1.55:
			var strength := (1.55 - distance) / 1.55
			separation += offset.normalized() * strength
			nearby_count += 1
	if nearby_count == 0 or separation.length_squared() < 0.001:
		crowd_steering = direction.normalized()
		return direction
	crowd_steering = (direction.normalized() + separation.normalized() * 0.95).normalized()
	return crowd_steering

func _update_autonomous_decisions(delta: float) -> void:
	# Keep player reactions responsive while allowing residents enough time to
	# actually reach destinations before selecting a new daily goal.
	player_scan_elapsed += delta
	if player_scan_elapsed >= 0.75:
		player_scan_elapsed = 0.0
		_player_decision()
	goal_refresh_elapsed += delta
	if goal_refresh_elapsed >= 30.0:
		goal_refresh_elapsed = 0.0
		var player_nearby := is_instance_valid(player) and not player.is_queued_for_deletion() and global_position.distance_to(player.global_position) <= 8.0
		if not player_nearby:
			_choose_daily_goal(_current_hour())

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	need_update_elapsed += delta
	if need_update_elapsed >= 1.0:
		_update_needs(need_update_elapsed)
		need_update_elapsed = 0.0
	social_scan_elapsed += delta
	if social_scan_elapsed >= 2.0:
		social_scan_elapsed = 0.0
		_update_social_awareness()
	reflection_elapsed += delta
	memory_save_elapsed += delta
	if reflection_elapsed >= 15.0:
		reflection_elapsed = 0.0
		_reflect_on_experiences()
	if memory_save_elapsed >= 45.0:
		memory_save_elapsed = 0.0
		if memory_dirty:
			_save_memory()
	_update_autonomous_decisions(delta)
	if wait_time > 0.0:
		wait_time -= delta
		velocity.x = move_toward(velocity.x, 0.0, walk_speed * delta * 4.0)
		velocity.z = move_toward(velocity.z, 0.0, walk_speed * delta * 4.0)
		move_and_slide()
		_animate(delta, false)
		return
	var direction := target_position - global_position
	direction.y = 0
	if direction.length() < 0.65:
		if ai_state == "greeting" or ai_state == "acknowledging":
			ai_state = "socializing"
			wait_time = randf_range(2.0, 5.0)
		elif ai_state == "seeking_food":
			ai_state = "eating"
			decision_reason = "وصلت إلى مكان الطعام وأتناول وجبتي"
			wait_time = randf_range(5.0, 9.0)
		elif ai_state == "eating":
			_record_experience("food", "تناولت الطعام وشعرت بتحسن", 0.08)
			hunger = maxf(0.08, hunger - 0.68)
			decision_reason = "أنهيت وجبتي وأشعر بتحسن"
			_choose_daily_goal(_current_hour())
		elif ai_state == "commuting":
			_record_experience("work", "وصلت إلى عملي", 0.025)
			ai_state = "working"
			wait_time = randf_range(8.0, 16.0)
		elif ai_state == "going_home":
			ai_state = "resting"
			wait_time = randf_range(5.0, 12.0)
		else:
			if ai_state == "wandering":
				_record_experience("explore", "استكشفت جزءاً جديداً من الحي", 0.035)
			_choose_target()
		velocity.x = move_toward(velocity.x, 0.0, walk_speed * delta * 4.0)
		velocity.z = move_toward(velocity.z, 0.0, walk_speed * delta * 4.0)
		move_and_slide()
		_animate(delta, false)
		return
	direction = _avoid_obstacle(direction.normalized(), delta)
	direction = _avoid_resident_crowding(direction)
	var pace := walk_speed * (0.72 if ai_state == "avoiding" else 1.0)
	# Residents accelerate and brake like people instead of snapping to a fixed velocity.
	velocity.x = move_toward(velocity.x, direction.x * pace, delta * 3.2)
	velocity.z = move_toward(velocity.z, direction.z * pace, delta * 3.2)
	rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), 1.0 - exp(-4.2 * delta))
	move_and_slide()
	_animate(delta, true, pace)

func _animate(delta: float, moving: bool, pace: float = 0.0) -> void:
	if not is_instance_valid(left_arm) or not is_instance_valid(right_arm) or not is_instance_valid(left_leg) or not is_instance_valid(right_leg):
		return
	if moving:
		clock += delta * (4.8 + pace * 1.35)
		var swing := sin(clock) * 0.31
		left_arm.rotation.x = swing
		right_arm.rotation.x = -swing
		left_leg.rotation.x = -swing
		right_leg.rotation.x = swing
	else:
		idle_phase += delta
		var conversational := ai_state == "socializing" or ai_state == "greeting" or ai_state == "acknowledging"
		var gesture := sin(idle_phase * 2.1 + float(personal_seed)) * (0.18 if conversational else 0.025)
		left_arm.rotation.x = lerpf(left_arm.rotation.x, gesture, delta * (3.4 if conversational else 2.8))
		right_arm.rotation.x = lerpf(right_arm.rotation.x, -gesture * 0.7, delta * (3.0 if conversational else 2.8))
		left_arm.rotation.z = lerpf(left_arm.rotation.z, -0.10 if conversational else 0.0, delta * 2.5)
		right_arm.rotation.z = lerpf(right_arm.rotation.z, 0.10 if conversational else 0.0, delta * 2.5)
		left_leg.rotation.x = lerpf(left_leg.rotation.x, 0.0, delta * 5.0)
		right_leg.rotation.x = lerpf(right_leg.rotation.x, 0.0, delta * 5.0)
	if is_instance_valid(head_visual):
		var look_target := Vector3.ZERO
		if is_instance_valid(player) and global_position.distance_to(player.global_position) < 6.0:
			var toward_player := (player.global_position - global_position).normalized()
			look_target.y = clampf(atan2(-toward_player.x, -toward_player.z) - rotation.y, -0.42, 0.42)
		elif ai_state == "socializing":
			var conversation_partner := _nearest_resident(5.5)
			if is_instance_valid(conversation_partner):
				var toward_partner := (conversation_partner.global_position - global_position).normalized()
				look_target.y = clampf(atan2(-toward_partner.x, -toward_partner.z) - rotation.y, -0.48, 0.48)
			else:
				look_target.y = sin(idle_phase * 0.34 + float(personal_seed)) * 0.10
		else:
			look_target.y = sin(idle_phase * 0.34 + float(personal_seed)) * 0.10
		head_visual.rotation.y = lerp_angle(head_visual.rotation.y, look_target.y, 1.0 - exp(-2.2 * delta))
		head_visual.rotation.x = lerpf(head_visual.rotation.x, sin(idle_phase * 0.55) * 0.025, delta * 2.0)
	if is_instance_valid(visual_root):
		var bob := (absf(sin(clock)) * 0.025) if moving else sin(idle_phase * 1.35 + float(personal_seed)) * 0.008
		visual_root.position.y = lerpf(visual_root.position.y, bob, delta * 5.0)
		var lean := 0.035 if ai_state == "socializing" or ai_state == "greeting" else -0.025 if ai_state == "resting" else 0.0
		visual_root.rotation.x = lerpf(visual_root.rotation.x, lean + (sin(clock) * 0.018 if moving else 0.0), delta * 3.0)
	# Residents blink at slightly different natural intervals rather than staring continuously.
	blink_timer -= delta
	if blink_timer <= 0.0:
		blink_timer = randf_range(2.1, 5.2)
		if is_instance_valid(eye_left) and is_instance_valid(eye_right):
			eye_left.scale.y = 0.12
			eye_right.scale.y = 0.12
	else:
		if is_instance_valid(eye_left): eye_left.scale.y = move_toward(eye_left.scale.y, 1.0, delta * 12.0)
		if is_instance_valid(eye_right): eye_right.scale.y = move_toward(eye_right.scale.y, 1.0, delta * 12.0)
