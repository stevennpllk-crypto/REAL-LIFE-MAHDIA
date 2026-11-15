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
var home_position := Vector3.ZERO
var work_position := Vector3.ZERO
var rest_position := Vector3.ZERO
var target_position := Vector3.ZERO
var wait_time := 0.0
var decision_elapsed := 0.0
var memory_meetings := 0
var last_player_interaction := -1000.0
var mood := 0.5
var ai_state := "wander"
var personal_seed := 0
var turn_bias := 1.0
var left_arm: Node3D
var right_arm: Node3D
var left_leg: Node3D
var right_leg: Node3D
var visual_root: Node3D
var clock := 0.0

func set_ai_context(player_node: CharacterBody3D, clock_node: Node, work_spot: Vector3, identity: int) -> void:
	player = player_node
	world_clock = clock_node
	work_position = work_spot
	personal_seed = identity
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
	var palette := [Color(0.72, 0.25, 0.16), Color(0.12, 0.42, 0.36), Color(0.82, 0.62, 0.18), Color(0.24, 0.34, 0.62), Color(0.62, 0.35, 0.22), Color(0.42, 0.30, 0.58)]
	var shirt: Color = palette[posmod(personal_seed, palette.size())]
	_part(_capsule(0.255, 0.78), Vector3(0, 1.19, 0), shirt)
	_part(_sphere(0.19, 0.40), Vector3(0, 1.84, 0), Color(0.68, 0.47, 0.34))
	_part(_sphere(0.198, 0.17), Vector3(0, 1.97, 0.015), Color(0.09, 0.065, 0.05))
	_part(_sphere(0.022, 0.03), Vector3(-0.068, 1.86, -0.175), Color(0.035, 0.025, 0.02))
	_part(_sphere(0.022, 0.03), Vector3(0.068, 1.86, -0.175), Color(0.035, 0.025, 0.02))
	left_arm = _limb(Vector3(-0.30, 1.43, 0), shirt, 0.62, 0.10)
	right_arm = _limb(Vector3(0.30, 1.43, 0), shirt, 0.62, 0.10)
	left_leg = _limb(Vector3(-0.14, 0.76, 0), Color(0.12, 0.14, 0.18), 0.72, 0.12)
	right_leg = _limb(Vector3(0.14, 0.76, 0), Color(0.12, 0.14, 0.18), 0.72, 0.12)

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

func _part(mesh: Mesh, pos: Vector3, color: Color) -> void:
	var item := MeshInstance3D.new()
	item.mesh = mesh
	item.position = pos
	item.material_override = _mat(color)
	visual_root.add_child(item)

func _limb(pos: Vector3, color: Color, length: float, radius: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	visual_root.add_child(pivot)
	var item := MeshInstance3D.new()
	item.mesh = _capsule(radius, length)
	item.position = Vector3(0, -length * 0.34, 0)
	item.material_override = _mat(color)
	pivot.add_child(item)
	return pivot

func _current_hour() -> float:
	if is_instance_valid(world_clock):
		return float(world_clock.get("hour"))
	return 12.0

func _choose_daily_goal(hour: float) -> void:
	# A lightweight utility AI: every resident follows a personal daily routine.
	if hour >= 7.0 and hour < 12.0:
		ai_state = "commuting" if occupation != "resident" else "socializing"
		target_position = work_position if occupation != "resident" else rest_position
	elif hour >= 12.0 and hour < 14.0:
		ai_state = "resting"
		target_position = rest_position
	elif hour >= 14.0 and hour < 18.0:
		ai_state = "working" if occupation != "resident" else "wandering"
		target_position = work_position if occupation != "resident" else _random_near(home_position)
	else:
		ai_state = "going_home"
		target_position = home_position
	wait_time = randf_range(0.5, 2.0)

func _random_near(center: Vector3) -> Vector3:
	var angle := randf() * TAU
	var distance := randf_range(2.0, wander_radius)
	return center + Vector3(cos(angle) * distance, 0, sin(angle) * distance)

func _choose_target() -> void:
	target_position = _random_near(home_position)
	wait_time = randf_range(1.0, 3.0)
	ai_state = "wander"

func on_player_interacted() -> void:
	memory_meetings += 1
	last_player_interaction = Time.get_ticks_msec() / 1000.0
	mood = clampf(mood + 0.12, 0.0, 1.0)

func get_dialogue() -> String:
	var remembered := "أهلاً، تذكرتك!" if memory_meetings > 1 else "أهلاً بك."
	match personality:
		"shy":
			return remembered + " أنا خجول قليلاً، لكن تفضل."
		"busy":
			return "مرحباً، أنا أعمل الآن. " + remembered
		"curious":
			return remembered + " ما رأيك في أخبار المهدية اليوم؟"
		"grumpy":
			return remembered + " الجو مزدحم اليوم، أليس كذلك؟"
		_:
			return remembered + " يعطيك الصحة!"

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

func _avoid_obstacle(direction: Vector3) -> Vector3:
	if direction.length_squared() < 0.01:
		return direction
	var origin := global_position + Vector3.UP * 0.8
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * 1.6)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return direction
	var side := Vector3(-direction.z, 0, direction.x) * turn_bias
	return (direction + side * 1.8).normalized()

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	decision_elapsed += delta
	if decision_elapsed >= 4.0:
		decision_elapsed = 0.0
		if not _player_decision():
			_choose_daily_goal(_current_hour())
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
		elif ai_state == "commuting":
			ai_state = "working"
			wait_time = randf_range(8.0, 16.0)
		elif ai_state == "going_home":
			ai_state = "resting"
			wait_time = randf_range(5.0, 12.0)
		else:
			_choose_target()
		velocity.x = move_toward(velocity.x, 0.0, walk_speed * delta * 4.0)
		velocity.z = move_toward(velocity.z, 0.0, walk_speed * delta * 4.0)
		move_and_slide()
		_animate(delta, false)
		return
	direction = _avoid_obstacle(direction.normalized())
	var pace := walk_speed * (0.72 if ai_state == "avoiding" else 1.0)
	velocity.x = direction.x * pace
	velocity.z = direction.z * pace
	rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), delta * 4.0)
	move_and_slide()
	_animate(delta, true)

func _animate(delta: float, moving: bool) -> void:
	if moving:
		clock += delta * 5.0
		var swing := sin(clock) * 0.34
		left_arm.rotation.x = swing
		right_arm.rotation.x = -swing
		left_leg.rotation.x = -swing
		right_leg.rotation.x = swing
	else:
		left_arm.rotation.x = lerpf(left_arm.rotation.x, 0.0, delta * 5.0)
		right_arm.rotation.x = lerpf(right_arm.rotation.x, 0.0, delta * 5.0)
		left_leg.rotation.x = lerpf(left_leg.rotation.x, 0.0, delta * 5.0)
		right_leg.rotation.x = lerpf(right_leg.rotation.x, 0.0, delta * 5.0)
