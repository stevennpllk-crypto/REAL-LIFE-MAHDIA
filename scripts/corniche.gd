extends Node3D
class_name MahdiaCorniche

# The sunny Mahdia corniche that greets the player: whitewashed 3-4 storey
# buildings with blue shutters and balconies, cafe terraces with parasols, a
# corniche road with parked cars, a wide light-stone promenade lined with tall
# palms and lamps, a stone balustrade above rocks and the Mediterranean, small
# boats, a Tunisian flag, and Borj el Kebir on a rocky point to the west.
#
# Geometry is procedural and merged per material (MahdiaMeshBatch), textures
# are CC0 Poly Haven PBR sets downloaded by CI (fallbacks keep it working
# without them).

const MESH_BATCH = preload("res://scripts/mesh_batch.gd")
const SEA_SHADER = preload("res://shaders/sea.gdshader")
const FLAG_SHADER = preload("res://shaders/flag.gdshader")
const FROND_SHADER = preload("res://shaders/palm_frond.gdshader")

const SEA_LEVEL := -0.35
const BUILDING_FRONT_Z := -33.0
const BUILDING_DEPTH := 8.0
const SIDEWALK_EDGE_Z := -37.0
const ROAD_SEA_EDGE_Z := -43.0
const BALUSTRADE_Z := -56.85
const SEAWALL_Z := -57.3
const HEADLAND_MIN := Vector2(-52.0, -82.0)
const HEADLAND_MAX := Vector2(-6.0, -57.3)
const X_EAST := 124.0
const X_WEST := -90.0
const PROMENADE_WEST := -72.0
const FORTRESS_CENTER := Vector3(-29.0, 0.0, -70.0)
# Openings in the balustrade keep the sea reachable for swimming.
const BALUSTRADE_GAPS := [Vector2(83.0, 86.0), Vector2(29.0, 32.0), Vector2(-3.0, 0.5)]

const BLUE := Color(0.06, 0.30, 0.60)
const WHITE_WALL := Color(0.97, 0.96, 0.93)

var world: Node
var tier := 2
var texture_cache: Dictionary = {}
var material_cache: Dictionary = {}
var boats: Array[Node3D] = []
var boat_rest: Array[Transform3D] = []
var clock := 0.0
var sea_material: ShaderMaterial
var sea_instance: MeshInstance3D
var frond_material: ShaderMaterial
var car_mesh_cache: Dictionary = {}
var lamp_glass_material: StandardMaterial3D
# Plan-view rectangles (x, z) for the HUD minimap.
var map_roads: Array[Rect2] = []
var map_walkways: Array[Rect2] = []
var map_land: Array[Rect2] = []

func build(owner_world: Node, quality_tier: int) -> void:
	world = owner_world
	tier = quality_tier
	name = "MahdiaCorniche"
	# Each section is built on its own frame so slow phones keep presenting
	# frames (and the touch HUD stays live) while the district streams in.
	var t0 := Time.get_ticks_msec()
	_build_ground_and_streets()
	_build_sea()
	await get_tree().process_frame
	_build_seawall_and_rocks()
	await get_tree().process_frame
	_build_balustrade()
	await get_tree().process_frame
	_build_headland_and_fortress()
	await get_tree().process_frame
	_build_building_row()
	await get_tree().process_frame
	_build_palms_and_lamps()
	await get_tree().process_frame
	_build_cafes()
	_build_parked_cars()
	_build_flags()
	_build_boats()
	print("MAHDIA_CORNICHE_BUILD_MS=", Time.get_ticks_msec() - t0)

# ---------------------------------------------------------------- materials

func _tex(asset: String, map_name: String) -> Texture2D:
	var key := asset + "_" + map_name
	if texture_cache.has(key):
		return texture_cache[key] as Texture2D
	var result: Texture2D = null
	for ext in ["jpg", "png"]:
		var path := "res://assets/textures/%s_%s_1k.%s" % [asset, map_name, ext]
		if ResourceLoader.exists(path):
			result = load(path) as Texture2D
			if result != null:
				break
	texture_cache[key] = result
	return result

# Triplanar, world-space PBR material: any box or rock gets a correctly scaled
# texture without UV work. tile = metres per texture repeat.
func stone_material(asset: String, tint: Color, tile: float, roughness := 0.9, normal_scale := 0.9) -> StandardMaterial3D:
	var key := "%s|%s|%.2f|%.2f" % [asset, tint.to_html(), tile, roughness]
	if material_cache.has(key):
		return material_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.roughness = roughness
	var diff := _tex(asset, "diff")
	if diff != null:
		m.albedo_texture = diff
		var nor := _tex(asset, "nor_gl")
		if nor != null:
			m.normal_enabled = true
			m.normal_texture = nor
			m.normal_scale = normal_scale
		var rough := _tex(asset, "rough")
		if rough != null:
			m.roughness_texture = rough
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3.ONE / tile
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material_cache[key] = m
	return m

func plain(color: Color, roughness := 0.8, metallic := 0.0, emission := Color.BLACK) -> StandardMaterial3D:
	var key := "plain|%s|%.2f|%.2f|%s" % [color.to_html(), roughness, metallic, emission.to_html()]
	if material_cache.has(key):
		return material_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	if emission != Color.BLACK:
		m.emission_enabled = true
		m.emission = emission
	material_cache[key] = m
	return m

func vcolor_material(roughness := 0.85) -> StandardMaterial3D:
	var key := "vcolor|%.2f" % roughness
	if material_cache.has(key):
		return material_cache[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = roughness
	material_cache[key] = m
	return m

func _static_box(size: Vector3, pos: Vector3, rot_y := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = rot_y
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	return body

func _xf(pos: Vector3, rot_y := 0.0, scale := Vector3.ONE) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, rot_y).scaled(scale), pos)

# ------------------------------------------------------- ground and streets

func _build_ground_and_streets() -> void:
	var b := MESH_BATCH.new()
	var paving := stone_material("precast_stone_paving", Color(1.35, 1.32, 1.25), 3.4, 0.55, 0.45)
	var sidewalk := stone_material("precast_stone_paving", Color(0.93, 0.89, 0.81), 1.6, 0.85, 0.6)
	var asphalt := stone_material("asphalt_02", Color(0.55, 0.55, 0.56), 5.0, 0.92, 0.5)
	var curb := stone_material("beige_wall_001", Color(0.93, 0.91, 0.86), 1.5, 0.8)
	var land := plain(Color(0.78, 0.73, 0.62), 0.95)
	# Wide distant land so the city never ends in a void past the playable grid.
	b.box("land", land, _xf(Vector3(0, -0.11, 160.0)), Vector3(900.0, 0.1, 434.0), true)
	# Building-side sidewalk / cafe terrace.
	b.box("sidewalk", sidewalk, _xf(Vector3((X_EAST + X_WEST) * 0.5, -0.03, (BUILDING_FRONT_Z + SIDEWALK_EDGE_Z) * 0.5 + 0.5)), Vector3(X_EAST - X_WEST, 0.12, 5.0), true)
	# Corniche road.
	b.box("asphalt", asphalt, _xf(Vector3((X_EAST + X_WEST) * 0.5, -0.045, (SIDEWALK_EDGE_Z + ROAD_SEA_EDGE_Z) * 0.5)), Vector3(X_EAST - X_WEST, 0.1, 6.0), true)
	# Promenade, continuing onto the fortress point.
	var prom_len := X_EAST - PROMENADE_WEST
	b.box("paving", paving, _xf(Vector3((X_EAST + PROMENADE_WEST) * 0.5, -0.03, (ROAD_SEA_EDGE_Z + SEAWALL_Z) * 0.5)), Vector3(prom_len, 0.12, absf(SEAWALL_Z - ROAD_SEA_EDGE_Z)), true)
	# Curbs on both sides of the road.
	for z in [SIDEWALK_EDGE_Z, ROAD_SEA_EDGE_Z]:
		b.box("curb", curb, _xf(Vector3((X_EAST + X_WEST) * 0.5, 0.02, z)), Vector3(X_EAST - X_WEST, 0.16, 0.26), true)
	var paint := plain(Color(0.92, 0.92, 0.88), 0.6)
	# Dashed centre line and parking bay ticks on the sea side.
	var x := X_WEST + 2.0
	while x < X_EAST - 2.0:
		if absf(x) > 6.0:
			b.box("paint", paint, _xf(Vector3(x, 0.007, -39.6)), Vector3(3.0, 0.01, 0.13), true)
		x += 6.0
	x = X_WEST + 4.0
	while x < X_EAST:
		b.box("paint", paint, _xf(Vector3(x, 0.007, -41.6)), Vector3(0.1, 0.01, 2.4), true)
		x += 5.6
	b.box("paint", paint, _xf(Vector3((X_EAST + X_WEST) * 0.5, 0.007, -40.4)), Vector3(X_EAST - X_WEST, 0.01, 0.1), true)
	# Pedestrian crossing from the town avenue onto the promenade.
	for i in range(8):
		b.box("paint", paint, _xf(Vector3(-3.5 + float(i) * 1.0, 0.008, -40.0)), Vector3(0.5, 0.01, 5.6), true)
	# Pale stone banding across the promenade, like the real corniche slabs.
	var band := stone_material("beige_wall_001", Color(0.86, 0.82, 0.74), 1.5, 0.7)
	x = PROMENADE_WEST + 3.0
	while x < X_EAST:
		b.box("band", band, _xf(Vector3(x, 0.034, (ROAD_SEA_EDGE_Z + BALUSTRADE_Z) * 0.5)), Vector3(0.32, 0.01, absf(BALUSTRADE_Z - ROAD_SEA_EDGE_Z) - 0.6), true)
		x += 9.0
	var items := b.commit_instances(self)
	for item in items:
		item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	map_roads.append(Rect2(X_WEST, SIDEWALK_EDGE_Z - 6.0, X_EAST - X_WEST, 6.0))
	map_walkways.append(Rect2(X_WEST, BUILDING_FRONT_Z - 4.0 + 0.0, X_EAST - X_WEST, 4.0))
	map_walkways.append(Rect2(PROMENADE_WEST, SEAWALL_Z, prom_len, absf(SEAWALL_Z - ROAD_SEA_EDGE_Z)))

# ------------------------------------------------------------------- sea

func _build_sea() -> void:
	sea_material = ShaderMaterial.new()
	sea_material.shader = SEA_SHADER
	sea_material.set_shader_parameter("shore_z", SEAWALL_Z)
	sea_material.set_shader_parameter("headland", Vector4(HEADLAND_MIN.x, HEADLAND_MIN.y, HEADLAND_MAX.x, HEADLAND_MAX.y))
	sea_instance = MeshInstance3D.new()
	sea_instance.name = "MediterraneanSea"
	sea_instance.position = Vector3(0, SEA_LEVEL, -57.0 - 300.0)
	sea_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sea_instance.material_override = sea_material
	add_child(sea_instance)
	apply_quality(tier)

func apply_quality(quality_tier: int) -> void:
	tier = quality_tier
	if is_instance_valid(sea_instance):
		var plane := PlaneMesh.new()
		plane.size = Vector2(1000.0, 600.0)
		var subdivisions: Array[int] = [70, 140, 240]
		plane.subdivide_width = subdivisions[tier]
		plane.subdivide_depth = int(subdivisions[tier] * 0.6)
		sea_instance.mesh = plane
	if sea_material != null:
		var octaves: Array[int] = [2, 4, 6]
		sea_material.set_shader_parameter("ripple_octaves", octaves[tier])
	if frond_material != null:
		frond_material.set_shader_parameter("wind_strength", 0.0 if tier == 0 else 0.10)

# ---------------------------------------------------------- seawall, rocks

func _rock_mesh(seed_value: int) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 10
	sphere.rings = 6
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.9
	for i in range(verts.size()):
		var v := verts[i]
		var k := 1.0 + noise.get_noise_3dv(v * 1.3) * 0.38
		v *= k
		v.y *= 0.62
		verts[i] = v
	arrays[Mesh.ARRAY_VERTEX] = verts
	var tmp := ArrayMesh.new()
	tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var st := SurfaceTool.new()
	st.create_from(tmp, 0)
	st.deindex()
	st.generate_normals()
	st.generate_tangents()
	return st.commit()

func _scatter_rocks(points: Array[Transform3D]) -> void:
	var rock_material := stone_material("coast_land_rocks_01", Color(0.92, 0.86, 0.76), 2.2, 0.95, 1.0)
	var variants := 4
	var buckets: Array = []
	for v in range(variants):
		buckets.append([])
	for i in range(points.size()):
		(buckets[i % variants] as Array).append(points[i])
	for v in range(variants):
		var bucket: Array = buckets[v]
		if bucket.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _rock_mesh(31 + v * 17)
		mm.instance_count = bucket.size()
		for i in range(bucket.size()):
			mm.set_instance_transform(i, bucket[i])
		var inst := MultiMeshInstance3D.new()
		inst.name = "CoastRocks_%d" % v
		inst.multimesh = mm
		inst.material_override = rock_material
		add_child(inst)

func _build_seawall_and_rocks() -> void:
	var b := MESH_BATCH.new()
	var wall := stone_material("large_sandstone_blocks_01", Color(0.98, 0.92, 0.80), 3.0, 0.95)
	var coping := stone_material("beige_wall_001", Color(0.96, 0.94, 0.88), 1.4, 0.75)
	var length := X_EAST - HEADLAND_MAX.x
	var cx := (X_EAST + HEADLAND_MAX.x) * 0.5
	b.box("wall", wall, _xf(Vector3(cx, -1.2, SEAWALL_Z + 0.2)), Vector3(length, 2.5, 0.6), true)
	b.box("coping", coping, _xf(Vector3(cx, 0.01, SEAWALL_Z + 0.25)), Vector3(length, 0.14, 0.75), true)
	# West of the fortress point the promenade meets the sea again.
	var west_len := HEADLAND_MIN.x - PROMENADE_WEST
	b.box("wall", wall, _xf(Vector3((HEADLAND_MIN.x + PROMENADE_WEST) * 0.5, -1.2, SEAWALL_Z + 0.2)), Vector3(absf(west_len), 2.5, 0.6), true)
	b.commit_instances(self)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var rocks: Array[Transform3D] = []
	var x := HEADLAND_MAX.x + 1.0
	while x < X_EAST:
		var count := rng.randi_range(1, 3)
		for i in range(count):
			var s := rng.randf_range(0.7, 2.1)
			var pos := Vector3(x + rng.randf_range(-1.5, 1.5), SEA_LEVEL + rng.randf_range(-0.35, 0.25), SEAWALL_Z - rng.randf_range(0.4, 4.5))
			var basis := Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3.RIGHT, rng.randf_range(-0.3, 0.3)).scaled(Vector3(s * rng.randf_range(0.9, 1.5), s, s * rng.randf_range(0.8, 1.2)))
			rocks.append(Transform3D(basis, pos))
		x += rng.randf_range(1.4, 2.6)
	# Rock skirt around the fortress point.
	for i in range(70):
		var a := float(i) / 70.0
		var perimeter := 2.0 * (HEADLAND_MAX.x - HEADLAND_MIN.x) + (HEADLAND_MAX.y - HEADLAND_MIN.y)
		var d := a * perimeter
		var pos := Vector3.ZERO
		var west_side := HEADLAND_MAX.y - HEADLAND_MIN.y
		if d < west_side:
			pos = Vector3(HEADLAND_MAX.x + rng.randf_range(0.5, 2.5), 0, HEADLAND_MAX.y - d)
		elif d < west_side + (HEADLAND_MAX.x - HEADLAND_MIN.x):
			pos = Vector3(HEADLAND_MAX.x - (d - west_side), 0, HEADLAND_MIN.y - rng.randf_range(0.5, 2.5))
		else:
			pos = Vector3(HEADLAND_MIN.x - rng.randf_range(0.5, 2.5), 0, HEADLAND_MIN.y + (d - west_side - (HEADLAND_MAX.x - HEADLAND_MIN.x)))
		pos.y = SEA_LEVEL + rng.randf_range(-0.2, 0.5)
		var s := rng.randf_range(1.2, 2.8)
		rocks.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * 1.3, s * 0.9, s)), pos))
	_scatter_rocks(rocks)

# --------------------------------------------------------------- balustrade

func _in_gap(x: float) -> bool:
	for gap in BALUSTRADE_GAPS:
		var g: Vector2 = gap
		if x > g.x and x < g.y:
			return true
	return false

func _build_balustrade() -> void:
	var stone := stone_material("beige_wall_001", Color(0.97, 0.95, 0.89), 1.2, 0.78, 0.6)
	var baluster_profile := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.075, 0.0), Vector2(0.075, 0.06), Vector2(0.055, 0.09),
		Vector2(0.085, 0.24), Vector2(0.085, 0.34), Vector2(0.04, 0.50), Vector2(0.035, 0.56),
		Vector2(0.06, 0.60), Vector2(0.06, 0.65), Vector2(0.0, 0.65)
	])
	var segments := 6 if tier == 0 else 8
	var chunk_len := 16.0
	var start := HEADLAND_MAX.x + 0.6
	var chunk_start := start
	while chunk_start < X_EAST:
		var chunk_end := minf(chunk_start + chunk_len, X_EAST)
		var b := MESH_BATCH.new()
		var run_start := -1.0
		var x := chunk_start
		while x <= chunk_end:
			var gap := _in_gap(x)
			if not gap and run_start < 0.0:
				run_start = x
			if (gap or x + 0.3 > chunk_end) and run_start >= 0.0:
				var run_end := x
				var run_len := run_end - run_start
				if run_len > 0.2:
					var mid := (run_start + run_end) * 0.5
					b.box("stone", stone, _xf(Vector3(mid, 0.15, BALUSTRADE_Z)), Vector3(run_len, 0.26, 0.42), true)
					b.box("stone", stone, _xf(Vector3(mid, 1.0, BALUSTRADE_Z)), Vector3(run_len, 0.12, 0.42))
					b.box("stone", stone, _xf(Vector3(mid, 0.93, BALUSTRADE_Z)), Vector3(run_len, 0.05, 0.34))
				run_start = -1.0
			if not gap:
				b.lathe("stone", stone, _xf(Vector3(x, 0.28, BALUSTRADE_Z)), baluster_profile, segments)
			x += 0.3
		# Square pillars every 4.2 m.
		var px := ceilf(chunk_start / 4.2) * 4.2
		while px < chunk_end:
			if not _in_gap(px) and not _in_gap(px - 0.4) and not _in_gap(px + 0.4):
				b.box("stone", stone, _xf(Vector3(px, 0.55, BALUSTRADE_Z)), Vector3(0.48, 1.1, 0.5), true)
				b.box("stone", stone, _xf(Vector3(px, 1.15, BALUSTRADE_Z)), Vector3(0.58, 0.1, 0.6))
			px += 4.2
		var items := b.commit_instances(self)
		for item in items:
			item.visibility_range_end = 140.0
			item.visibility_range_end_margin = 10.0
		chunk_start = chunk_end
	# Collision between the openings so the promenade edge is a real barrier.
	var edges: Array[float] = [start]
	for gap in BALUSTRADE_GAPS:
		var g: Vector2 = gap
		edges.append(g.x)
		edges.append(g.y)
	edges.append(X_EAST)
	edges.sort()
	for i in range(0, edges.size() - 1, 2):
		var a := edges[i]
		var c := edges[i + 1]
		if c - a > 0.3:
			_static_box(Vector3(c - a, 1.2, 0.45), Vector3((a + c) * 0.5, 0.6, BALUSTRADE_Z))

# ----------------------------------------------------- headland + fortress

func _build_headland_and_fortress() -> void:
	var size := Vector3(HEADLAND_MAX.x - HEADLAND_MIN.x, 1.2, HEADLAND_MAX.y - HEADLAND_MIN.y)
	var centre := Vector3((HEADLAND_MAX.x + HEADLAND_MIN.x) * 0.5, -0.62, (HEADLAND_MAX.y + HEADLAND_MIN.y) * 0.5)
	var ground := stone_material("coast_land_rocks_01", Color(0.95, 0.88, 0.74), 3.0, 0.95)
	var b := MESH_BATCH.new()
	b.box("ground", ground, _xf(centre), size)
	var paving := stone_material("precast_stone_paving", Color(0.96, 0.92, 0.83), 2.4, 0.75)
	b.box("approach", paving, _xf(Vector3(HEADLAND_MAX.x - 4.0, -0.025, centre.z + 4.0)), Vector3(8.0, 0.1, size.z - 10.0), true)
	b.commit_instances(self)
	_static_box(size, centre)
	map_land.append(Rect2(HEADLAND_MIN.x, HEADLAND_MIN.y, size.x, size.z))
	_build_fortress()

func _merlons(b, mat: Material, from: Vector3, to: Vector3, top_y: float, thickness: float) -> void:
	var dir := to - from
	var length := dir.length()
	var unit := dir / length
	var angle := atan2(unit.x, unit.z)
	var count := int(length / 1.5)
	for i in range(count):
		var t := (float(i) + 0.5) / float(count)
		var p := from + dir * t
		b.box("stone", mat, Transform3D(Basis(Vector3.UP, angle), Vector3(p.x, top_y + 0.45, p.z)), Vector3(thickness, 0.9, 0.85))

func _build_fortress() -> void:
	var stone := stone_material("large_sandstone_blocks_01", Color(1.0, 0.94, 0.80), 4.0, 0.95, 1.0)
	var dark := plain(Color(0.10, 0.08, 0.06), 0.95)
	var b := MESH_BATCH.new()
	var c := FORTRESS_CENTER
	var half := Vector2(17.0, 10.0)
	var wall_h := 10.0
	var t := 1.8
	# Curtain walls with a slight batter (base course wider).
	var walls := [
		[Vector3(c.x, 0, c.z - half.y), Vector3(half.x * 2.0, wall_h, t)],
		[Vector3(c.x, 0, c.z + half.y), Vector3(half.x * 2.0, wall_h, t)],
		[Vector3(c.x - half.x, 0, c.z), Vector3(t, wall_h, half.y * 2.0)],
		[Vector3(c.x + half.x, 0, c.z), Vector3(t, wall_h, half.y * 2.0)]
	]
	for w in walls:
		var p: Vector3 = w[0]
		var s: Vector3 = w[1]
		b.box("stone", stone, _xf(Vector3(p.x, s.y * 0.5, p.z)), s, true)
		b.box("stone", stone, _xf(Vector3(p.x, 0.6, p.z)), s + Vector3(0.5, -s.y + 1.2, 0.5) * Vector3(1, 1, 1), true)
		_static_box(s, Vector3(p.x, s.y * 0.5, p.z))
	# Crenellations along the outer face of every wall.
	_merlons(b, stone, Vector3(c.x - half.x, 0, c.z - half.y), Vector3(c.x + half.x, 0, c.z - half.y), wall_h, t)
	_merlons(b, stone, Vector3(c.x - half.x, 0, c.z + half.y), Vector3(c.x + half.x, 0, c.z + half.y), wall_h, t)
	_merlons(b, stone, Vector3(c.x - half.x, 0, c.z - half.y), Vector3(c.x - half.x, 0, c.z + half.y), wall_h, t)
	_merlons(b, stone, Vector3(c.x + half.x, 0, c.z - half.y), Vector3(c.x + half.x, 0, c.z + half.y), wall_h, t)
	# Square corner bastions.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := Vector3(c.x + sx * half.x, 0, c.z + sz * half.y)
			var bh := 13.0
			b.box("stone", stone, _xf(Vector3(p.x, bh * 0.5, p.z)), Vector3(5.2, bh, 5.2), true)
			b.box("stone", stone, _xf(Vector3(p.x, bh - 0.2, p.z)), Vector3(5.6, 0.35, 5.6))
			for k in range(4):
				var off := (float(k) - 1.5) * 1.35
				for edge in [-1.0, 1.0]:
					b.box("stone", stone, _xf(Vector3(p.x + off, bh + 0.45, p.z + edge * 2.6)), Vector3(0.8, 0.9, 0.5))
					b.box("stone", stone, _xf(Vector3(p.x + edge * 2.6, bh + 0.45, p.z + off)), Vector3(0.5, 0.9, 0.8))
			_static_box(Vector3(5.2, bh, 5.2), Vector3(p.x, bh * 0.5, p.z))
			# Arrow slits facing outward.
			b.box("dark", dark, _xf(Vector3(p.x + sx * 2.62, 6.0, p.z)), Vector3(0.06, 1.2, 0.22))
			b.box("dark", dark, _xf(Vector3(p.x, 6.0, p.z + sz * 2.62)), Vector3(0.22, 1.2, 0.06))
	# The tall square keep on the promenade side, the fortress's landmark.
	var keep := Vector3(c.x + half.x - 7.0, 0, c.z + half.y - 3.0)
	var keep_h := 25.0
	b.box("stone", stone, _xf(Vector3(keep.x, keep_h * 0.5, keep.z)), Vector3(6.4, keep_h, 6.4), true)
	b.box("stone", stone, _xf(Vector3(keep.x, keep_h - 0.25, keep.z)), Vector3(7.0, 0.5, 7.0))
	b.box("stone", stone, _xf(Vector3(keep.x, 15.0, keep.z)), Vector3(6.7, 0.3, 6.7))
	for k in range(5):
		var off := (float(k) - 2.0) * 1.4
		for edge in [-1.0, 1.0]:
			b.box("stone", stone, _xf(Vector3(keep.x + off, keep_h + 0.5, keep.z + edge * 3.25)), Vector3(0.85, 1.0, 0.5))
			b.box("stone", stone, _xf(Vector3(keep.x + edge * 3.25, keep_h + 0.5, keep.z + off)), Vector3(0.5, 1.0, 0.85))
	for level in [9.0, 18.5]:
		for side in [-1.0, 1.0]:
			b.box("dark", dark, _xf(Vector3(keep.x + side * 3.22, level, keep.z)), Vector3(0.06, 1.6, 0.35))
			b.box("dark", dark, _xf(Vector3(keep.x, level, keep.z + side * 3.22)), Vector3(0.35, 1.6, 0.06))
	_static_box(Vector3(6.4, keep_h, 6.4), Vector3(keep.x, keep_h * 0.5, keep.z))
	# Gate in the east wall (facing the promenade), with an arched dark opening.
	var gate := Vector3(c.x + half.x + t * 0.5 + 0.02, 0, c.z + 1.5)
	var arch := PackedVector2Array()
	arch.append(Vector2(-1.3, 0.0))
	arch.append(Vector2(1.3, 0.0))
	for i in range(9):
		var a := float(i) / 8.0 * PI
		arch.append(Vector2(cos(a) * 1.3, 3.0 + sin(a) * 1.3))
	b.extrude_profile("dark", dark, Transform3D(Basis.IDENTITY, gate), arch, 0.08)
	b.box("stone", stone, _xf(Vector3(gate.x + 0.25, 2.3, gate.z - 1.75)), Vector3(0.6, 4.6, 0.6), true)
	b.box("stone", stone, _xf(Vector3(gate.x + 0.25, 2.3, gate.z + 1.75)), Vector3(0.6, 4.6, 0.6), true)
	b.box("stone", stone, _xf(Vector3(gate.x + 0.25, 4.8, gate.z)), Vector3(0.6, 0.5, 4.1))
	# Courtyard floor so the inside reads as solid from the keep top view.
	b.box("stone", stone, _xf(Vector3(c.x, 0.03, c.z)), Vector3(half.x * 2.0, 0.08, half.y * 2.0), true)
	b.commit_instances(self)
	var flag_pos := Vector3(keep.x, keep_h, keep.z)
	_create_flag(flag_pos, 6.0, Vector2(2.6, 1.7))

# ------------------------------------------------------------- buildings

func _build_building_row() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2611
	var x := X_EAST - 2.0
	var index := 0
	while x > X_WEST + 8.0:
		var width := rng.randf_range(10.5, 15.5)
		var centre := x - width * 0.5
		if absf(centre) < 7.0 + width * 0.5:
			# Leave the junction with the town avenue (x = 0) open.
			x = -7.5
			continue
		var floors := 4 if rng.randf() < 0.45 else 3
		_create_corniche_building(centre, width - 0.3, floors, index, rng)
		x -= width
		index += 1

func _create_corniche_building(cx: float, width: float, floors: int, seed_value: int, rng: RandomNumberGenerator) -> void:
	var ground_h := 4.2
	var floor_h := 3.25
	var height := ground_h + floor_h * float(floors - 1) + 0.7
	var building := StaticBody3D.new()
	building.name = "CornicheBuilding_%02d" % seed_value
	building.position = Vector3(cx, 0, BUILDING_FRONT_Z + BUILDING_DEPTH * 0.5)
	var front := -BUILDING_DEPTH * 0.5
	var tints := [WHITE_WALL, Color(0.98, 0.95, 0.88), Color(0.95, 0.94, 0.92), Color(0.99, 0.97, 0.94), Color(0.96, 0.90, 0.80)]
	var tint: Color = tints[seed_value % tints.size()]
	var plaster := stone_material("plastered_wall", tint, 3.5, 0.95, 0.35)
	# Mesh 0: shell, mesh 1: roof slab. Everything after them is facade detail.
	var shell := MeshInstance3D.new()
	var shell_mesh := BoxMesh.new()
	shell_mesh.size = Vector3(width, height, BUILDING_DEPTH)
	shell.mesh = shell_mesh
	shell.position.y = height * 0.5
	shell.material_override = plaster
	building.add_child(shell)
	var roof := MeshInstance3D.new()
	var roof_mesh := BoxMesh.new()
	roof_mesh.size = Vector3(width + 0.2, 0.25, BUILDING_DEPTH + 0.2)
	roof.mesh = roof_mesh
	roof.position.y = height + 0.1
	roof.material_override = plain(tint.darkened(0.12), 0.9)
	building.add_child(roof)

	var b := MESH_BATCH.new()
	var glass := plain(Color(0.07, 0.10, 0.13), 0.12, 0.2)
	var shutter := plain(BLUE if seed_value % 5 != 3 else Color(0.10, 0.42, 0.55), 0.55)
	var trim := plain(tint.lightened(0.3), 0.7)
	var iron := plain(Color(0.07, 0.08, 0.09), 0.5, 0.6)
	var door := plain(Color(0.30, 0.19, 0.11), 0.7)
	var awning_colors := [Color(0.12, 0.30, 0.55), Color(0.78, 0.16, 0.13), Color(0.94, 0.90, 0.80), Color(0.10, 0.42, 0.36)]
	var awning := plain(awning_colors[seed_value % awning_colors.size()], 0.85)
	var fz := front - 0.01
	# Cornice bands between storeys and a parapet with a top moulding.
	for f in range(floors):
		var y := ground_h + floor_h * float(f) - 0.15
		b.box("trim", trim, _xf(Vector3(0, y, fz - 0.08)), Vector3(width, 0.18, 0.2))
	b.box("trim", trim, _xf(Vector3(0, height - 0.1, fz - 0.12)), Vector3(width + 0.1, 0.25, 0.3))
	b.box("trim", trim, _xf(Vector3(0, height + 0.45, front + 0.1)), Vector3(width, 0.7, 0.2), true)
	# Upper floors: tall windows with blue shutters, many with iron balconies.
	var cols := maxi(3, int(width / 3.1))
	var spacing := width / float(cols)
	for f in range(1, floors):
		var base_y := ground_h + floor_h * float(f - 1)
		var balcony_floor := (f + seed_value) % 2 == 1 or floors == 3
		var continuous := balcony_floor and seed_value % 3 == 0
		for col in range(cols):
			var wx := -width * 0.5 + spacing * (float(col) + 0.5)
			var wy := base_y + 1.45
			b.box("glass", glass, _xf(Vector3(wx, wy, fz + 0.02)), Vector3(1.0, 1.9, 0.06))
			b.box("trim", trim, _xf(Vector3(wx, wy + 1.02, fz - 0.06)), Vector3(1.3, 0.14, 0.14))
			b.box("trim", trim, _xf(Vector3(wx, wy - 0.98, fz - 0.07)), Vector3(1.25, 0.08, 0.18))
			var closed := rng.randf() < 0.22
			for side in [-1.0, 1.0]:
				var open_x: float = wx + side * 0.78
				if closed:
					b.box("shutter", shutter, _xf(Vector3(wx + side * 0.255, wy, fz - 0.05)), Vector3(0.5, 1.9, 0.05))
				else:
					b.box("shutter", shutter, _xf(Vector3(open_x, wy, fz - 0.05)), Vector3(0.52, 1.95, 0.05))
				# Louvre lines catch the light.
				var lx: float = wx + side * 0.255 if closed else open_x
				for slat in range(6):
					b.box("trim_dark", plain(BLUE.darkened(0.35), 0.6), _xf(Vector3(lx, wy - 0.75 + float(slat) * 0.3, fz - 0.085)), Vector3(0.44, 0.03, 0.02))
			if balcony_floor and not continuous:
				var bw := 1.7
				b.box("trim", trim, _xf(Vector3(wx, base_y + 0.42, fz - 0.45)), Vector3(bw, 0.12, 0.9))
				b.box("iron", iron, _xf(Vector3(wx, base_y + 1.42, fz - 0.88)), Vector3(bw, 0.05, 0.05))
				for r in range(9):
					var rx := wx - bw * 0.5 + bw * float(r) / 8.0
					b.box("iron", iron, _xf(Vector3(rx, base_y + 0.95, fz - 0.88)), Vector3(0.025, 0.95, 0.025))
				for side in [-1.0, 1.0]:
					b.box("iron", iron, _xf(Vector3(wx + side * bw * 0.5, base_y + 0.95, fz - 0.47)), Vector3(0.025, 0.95, 0.85))
		if continuous:
			b.box("trim", trim, _xf(Vector3(0, base_y + 0.42, fz - 0.5)), Vector3(width - 0.4, 0.12, 1.0))
			b.box("iron", iron, _xf(Vector3(0, base_y + 1.42, fz - 0.98)), Vector3(width - 0.4, 0.05, 0.05))
			var rails := int((width - 0.4) / 0.22)
			for r in range(rails + 1):
				var rx := -(width - 0.4) * 0.5 + (width - 0.4) * float(r) / float(rails)
				b.box("iron", iron, _xf(Vector3(rx, base_y + 0.95, fz - 0.98)), Vector3(0.025, 0.95, 0.025))
	# Ground floor: shopfront glazing, a door, and an awning over the terrace.
	var shop_w := width - 1.6
	b.box("glass", glass, _xf(Vector3(-0.6, 1.75, fz + 0.02)), Vector3(shop_w - 1.6, 2.6, 0.06))
	var mullions := int(shop_w / 1.8)
	for m in range(mullions + 1):
		var mx := -0.6 - (shop_w - 1.6) * 0.5 + (shop_w - 1.6) * float(m) / float(maxi(mullions, 1))
		b.box("trim", trim, _xf(Vector3(mx, 1.75, fz - 0.03)), Vector3(0.1, 2.7, 0.08))
	b.box("door", door, _xf(Vector3(width * 0.5 - 1.3, 1.25, fz + 0.01)), Vector3(1.1, 2.5, 0.08))
	b.box("trim", trim, _xf(Vector3(width * 0.5 - 1.3, 2.6, fz - 0.05)), Vector3(1.4, 0.16, 0.16))
	# Sloped canvas awning.
	var awn_depth := 2.3
	var awn_basis := Basis(Vector3.RIGHT, deg_to_rad(-16.0))
	b.box("awning", awning, Transform3D(awn_basis, Vector3(-0.6, 3.45, fz - awn_depth * 0.5)), Vector3(shop_w - 1.2, 0.05, awn_depth))
	b.box("awning", awning, _xf(Vector3(-0.6, 3.05, fz - awn_depth + 0.05)), Vector3(shop_w - 1.2, 0.35, 0.03))
	# Rooftop clutter: water tank, satellite dish, AC units on the facade.
	if seed_value % 2 == 0:
		b.lathe("trim", trim, _xf(Vector3(width * 0.25, height + 0.2, 1.0)), PackedVector2Array([Vector2(0, 0), Vector2(0.55, 0), Vector2(0.55, 1.1), Vector2(0, 1.1)]), 10)
	if seed_value % 3 == 1:
		b.box("trim", trim, _xf(Vector3(-width * 0.3, height + 0.6, 0.0), 0.0), Vector3(2.2, 1.4, 2.0), true)
	for ac in range(floors - 1):
		if (ac + seed_value) % 3 == 0:
			b.box("trim", plain(Color(0.86, 0.87, 0.85), 0.6), _xf(Vector3(-width * 0.5 + 0.9, ground_h + floor_h * float(ac) + 0.6, fz - 0.25)), Vector3(0.8, 0.55, 0.45))
	var details := b.commit_instances(building)
	for item in details:
		item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, height, BUILDING_DEPTH)
	collision.shape = shape
	collision.position.y = height * 0.5
	building.add_child(collision)
	if world != null and world.has_method("register_building"):
		world.call("register_building", building, Vector3(width, height, BUILDING_DEPTH))
	add_child(building)

# ------------------------------------------------------------ palms, lamps

func _frond(b, material: Material, origin: Vector3, yaw: float, pitch: float, length: float, color_base: Color, rng: RandomNumberGenerator) -> void:
	var dir := Vector3(cos(yaw), 0, sin(yaw))
	var side := Vector3(-dir.z, 0, dir.x)
	var steps := 14
	var prev := origin
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		# Rises with the pitch, then droops under its own weight.
		var p := origin + dir * (length * t * cos(pitch * 0.6)) + Vector3.UP * (length * (sin(pitch) * t - 0.75 * t * t))
		var leaf_len := length * 0.36 * (1.0 - 0.75 * t) + 0.12
		var tangent := (p - prev).normalized()
		var droop := Vector3.DOWN * leaf_len * (0.25 + 0.45 * t)
		var col := color_base.lerp(Color(0.55, 0.58, 0.22), t * 0.35 * rng.randf())
		for s in [-1.0, 1.0]:
			var tip: Vector3 = p + side * s * leaf_len * 0.9 + droop + tangent * leaf_len * 0.35
			var base_a := prev
			var base_b := p
			var normal := (base_b - base_a).cross(tip - base_a).normalized()
			if normal.y < 0.0:
				normal = -normal
			var uv_a := Vector2(float(i - 1) / float(steps), 0.0)
			var uv_b := Vector2(t, 0.0)
			var uv_t := Vector2(minf(t + 0.08, 1.0), 1.0)
			b.tri("frond", material, [base_a, base_b, tip], [normal, normal, normal], [uv_a, uv_b, uv_t], col)
		prev = p

func _palm_mesh(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + variant * 37
	var height: float = [9.5, 11.0, 8.2][variant % 3]
	var lean: float = [0.45, -0.7, 0.9][variant % 3]
	var b := MESH_BATCH.new()
	var bark := stone_material("coast_land_rocks_01", Color(0.62, 0.52, 0.40), 0.9, 0.95, 1.2)
	var points: Array[Vector3] = []
	var radii: Array[float] = []
	var rings := 40
	for i in range(rings + 1):
		var t := float(i) / float(rings)
		points.append(Vector3(lean * t * t, height * t, lean * 0.3 * t * t))
		var r := lerpf(0.3, 0.2, t) + (0.02 if i % 2 == 0 else -0.01)
		if t < 0.06:
			r += (0.06 - t) * 2.5
		radii.append(r)
	b.tube("bark", bark, points, radii, 10)
	var crown := points[points.size() - 1]
	# Leaf-base "boot" and date clusters under the crown.
	b.lathe("bark", bark, Transform3D(Basis.IDENTITY, crown - Vector3(0, 0.55, 0)), PackedVector2Array([Vector2(0.18, 0), Vector2(0.38, 0.3), Vector2(0.36, 0.7), Vector2(0.12, 0.95)]), 10)
	var dates := plain(Color(0.58, 0.36, 0.12), 0.7)
	for k in range(3):
		var a := TAU * float(k) / 3.0 + 0.4
		b.lathe("dates", dates, Transform3D(Basis.IDENTITY, crown + Vector3(cos(a) * 0.38, -0.85, sin(a) * 0.38)), PackedVector2Array([Vector2(0, 0), Vector2(0.16, 0.12), Vector2(0.18, 0.4), Vector2(0, 0.6)]), 6)
	if frond_material == null:
		frond_material = ShaderMaterial.new()
		frond_material.shader = FROND_SHADER
	var count := 18
	for k in range(count):
		var yaw := TAU * float(k) / float(count) + rng.randf_range(-0.15, 0.15)
		var young := k % 3 == 0
		var pitch := rng.randf_range(0.9, 1.2) if young else rng.randf_range(0.15, 0.55)
		var length := rng.randf_range(3.2, 4.4)
		var col := Color(0.16, 0.36, 0.12).lerp(Color(0.30, 0.44, 0.16), rng.randf())
		_frond(b, frond_material, crown + Vector3(0, 0.1, 0), yaw, pitch, length, col, rng)
	return b.commit_mesh(true)

func _build_palms_and_lamps() -> void:
	var palm_meshes: Array[ArrayMesh] = []
	for v in range(3):
		palm_meshes.append(_palm_mesh(v))
	var spots: Array[Vector3] = []
	var x := X_EAST - 4.0
	while x > PROMENADE_WEST + 2.0:
		spots.append(Vector3(x, 0, ROAD_SEA_EDGE_Z - 1.1))
		x -= 10.5
	# A few palms on the fortress point and the building-side terrace.
	spots.append(Vector3(-10.0, 0, -62.0))
	spots.append(Vector3(-9.0, 0, -76.0))
	spots.append(Vector3(46.0, 0, -35.5))
	spots.append(Vector3(97.0, 0, -35.5))
	var i := 0
	for spot in spots:
		var palm := MeshInstance3D.new()
		palm.name = "Palm_%02d" % i
		palm.mesh = palm_meshes[i % palm_meshes.size()]
		palm.position = spot
		palm.rotation.y = float(i) * 1.7
		var s := 0.9 + 0.2 * float((i * 7) % 5) / 4.0
		palm.scale = Vector3(s, s, s)
		add_child(palm)
		# Planter ring around the trunk on the promenade.
		i += 1
	# Lamp posts between the palms, merged into a single mesh set.
	var b := MESH_BATCH.new()
	var metal := plain(Color(0.05, 0.06, 0.06), 0.45, 0.7)
	lamp_glass_material = plain(Color(0.95, 0.92, 0.82), 0.2, 0.0, Color(0.0, 0.0, 0.0))
	lamp_glass_material.emission_enabled = true
	lamp_glass_material.emission = Color(1.0, 0.82, 0.55)
	lamp_glass_material.emission_energy_multiplier = 0.0
	var planter := stone_material("beige_wall_001", Color(0.93, 0.90, 0.84), 1.2, 0.8)
	x = X_EAST - 9.25
	while x > PROMENADE_WEST + 2.0:
		var base := Vector3(x, 0, ROAD_SEA_EDGE_Z - 1.1)
		b.lathe("metal", metal, _xf(base), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.22, 0.0), Vector2(0.2, 0.25), Vector2(0.11, 0.45), Vector2(0.11, 0.9), Vector2(0.075, 1.0), Vector2(0.06, 4.6), Vector2(0.09, 4.7), Vector2(0.0, 4.75)]), 10)
		for side in [-1.0, 1.0]:
			var arm: Array[Vector3] = [base + Vector3(0, 4.3, 0), base + Vector3(side * 0.45, 4.62, 0), base + Vector3(side * 0.85, 4.55, 0)]
			var arm_radii: Array[float] = [0.03, 0.03, 0.03]
			b.tube("metal", metal, arm, arm_radii, 6)
			b.lathe("metal", metal, _xf(base + Vector3(side * 0.85, 4.12, 0)), PackedVector2Array([Vector2(0.0, 0.42), Vector2(0.19, 0.42), Vector2(0.0, 0.6)]), 8)
			b.lathe("glass", lamp_glass_material, _xf(base + Vector3(side * 0.85, 4.0, 0)), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.08, 0.0), Vector2(0.16, 0.38), Vector2(0.0, 0.42)]), 8)
		x -= 10.5
	# Planters at every palm.
	for spot in spots:
		if spot.z > ROAD_SEA_EDGE_Z - 2.0 and spot.z < ROAD_SEA_EDGE_Z:
			b.box("planter", planter, _xf(spot + Vector3(0, 0.14, 0)), Vector3(1.5, 0.3, 1.5), true)
	var items := b.commit_instances(self)
	for item in items:
		item.visibility_range_end = 150.0

# Lamps glow from dusk to dawn (driven by MahdiaWorldSystems' hour).
func set_night_factor(value: float) -> void:
	if lamp_glass_material != null:
		lamp_glass_material.emission_energy_multiplier = value * 4.0

# ------------------------------------------------------------------ cafes

func _build_cafes() -> void:
	var b := MESH_BATCH.new()
	var cloth_colors := [Color(0.97, 0.96, 0.92), Color(0.95, 0.93, 0.86), Color(0.85, 0.15, 0.12), Color(0.12, 0.32, 0.58)]
	var pole := plain(Color(0.30, 0.22, 0.15), 0.7)
	var table := plain(Color(0.92, 0.92, 0.90), 0.5, 0.3)
	var chair := plain(Color(0.20, 0.17, 0.14), 0.6)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var x := X_EAST - 8.0
	var group := 0
	while x > X_WEST + 6.0:
		if absf(x) < 9.0:
			x -= 9.0
			continue
		if group % 2 == 0:
			var cloth := plain(cloth_colors[(group / 2) % cloth_colors.size()], 0.9)
			for k in range(2):
				var p := Vector3(x - float(k) * 3.2, 0, -35.3)
				b.lathe("pole", pole, _xf(p), PackedVector2Array([Vector2(0, 0), Vector2(0.035, 0), Vector2(0.035, 2.5), Vector2(0, 2.55)]), 6)
				b.lathe("cloth_%d" % ((group / 2) % cloth_colors.size()), cloth, _xf(p), PackedVector2Array([Vector2(0, 2.62), Vector2(1.45, 2.12), Vector2(1.45, 2.02), Vector2(1.38, 2.05)]), 8)
				b.lathe("table", table, _xf(p), PackedVector2Array([Vector2(0, 0), Vector2(0.2, 0), Vector2(0.03, 0.06), Vector2(0.03, 0.72), Vector2(0.38, 0.72), Vector2(0.38, 0.76), Vector2(0, 0.76)]), 10)
				for c in range(3):
					var a := TAU * float(c) / 3.0 + rng.randf()
					var cp := p + Vector3(cos(a) * 0.75, 0, sin(a) * 0.75)
					b.box("chair", chair, _xf(cp + Vector3(0, 0.45, 0), -a), Vector3(0.42, 0.05, 0.42))
					b.box("chair", chair, _xf(cp + Vector3(cos(a) * 0.2, 0.7, sin(a) * 0.2), -a + PI * 0.5), Vector3(0.42, 0.5, 0.04))
					for lx in [-0.18, 0.18]:
						for lz in [-0.18, 0.18]:
							b.box("chair", chair, _xf(cp + Vector3(lx, 0.22, lz)), Vector3(0.03, 0.45, 0.03), true)
		x -= 13.0
		group += 1
	var items := b.commit_instances(self)
	for item in items:
		item.visibility_range_end = 90.0
		item.visibility_range_end_margin = 8.0

# ----------------------------------------------------------- parked cars

func car_mesh(paint_color: Color, taxi := false, with_wheels := true) -> ArrayMesh:
	var key := paint_color.to_html() + str(taxi) + str(with_wheels)
	if car_mesh_cache.has(key):
		return car_mesh_cache[key]
	var b := MESH_BATCH.new()
	var paint := plain(paint_color, 0.22, 0.55)
	var glass := plain(Color(0.03, 0.04, 0.05), 0.05, 0.3)
	var rubber := plain(Color(0.03, 0.03, 0.03), 0.9)
	var chrome := plain(Color(0.75, 0.76, 0.78), 0.18, 1.0)
	var lamp := plain(Color(0.95, 0.95, 0.9), 0.1, 0.0, Color(0.15, 0.15, 0.12))
	var tail := plain(Color(0.55, 0.02, 0.02), 0.2, 0.0, Color(0.25, 0.0, 0.0))
	# Side profile (z = length axis, front at -Z; y = height).
	var lower := PackedVector2Array([
		Vector2(-2.42, 0.30), Vector2(-2.47, 0.50), Vector2(-2.40, 0.72), Vector2(-1.95, 0.84),
		Vector2(-1.00, 0.95), Vector2(1.55, 0.97), Vector2(2.25, 0.90), Vector2(2.42, 0.70),
		Vector2(2.40, 0.32), Vector2(1.95, 0.26), Vector2(-1.9, 0.26)
	])
	b.extrude_profile("paint", paint, Transform3D.IDENTITY, lower, 1.84)
	var cabin := PackedVector2Array([
		Vector2(-1.00, 0.94), Vector2(-0.25, 1.40), Vector2(0.85, 1.42), Vector2(1.62, 0.97)
	])
	b.extrude_profile("glass", glass, Transform3D.IDENTITY, cabin, 1.56)
	b.box("paint", paint, _xf(Vector3(0, 1.425, 0.3)), Vector3(1.5, 0.05, 1.05))
	b.box("paint", paint, _xf(Vector3(0.79, 1.18, 0.05)), Vector3(0.04, 0.46, 0.12))
	b.box("paint", paint, _xf(Vector3(-0.79, 1.18, 0.05)), Vector3(0.04, 0.46, 0.12))
	# Grille, lamps and bumpers.
	b.box("glass", glass, _xf(Vector3(0, 0.62, -2.46)), Vector3(0.9, 0.22, 0.04))
	b.box("chrome", chrome, _xf(Vector3(0, 0.62, -2.475)), Vector3(0.95, 0.03, 0.03))
	b.box("chrome", chrome, _xf(Vector3(0, 0.36, -2.44)), Vector3(1.7, 0.06, 0.06))
	for side in [-1.0, 1.0]:
		b.box("lamp", lamp, _xf(Vector3(side * 0.68, 0.72, -2.38)), Vector3(0.42, 0.12, 0.12))
		b.box("tail", tail, _xf(Vector3(side * 0.66, 0.78, 2.37)), Vector3(0.45, 0.13, 0.08))
		b.box("paint", paint, _xf(Vector3(side * 0.98, 1.0, -0.85)), Vector3(0.14, 0.09, 0.2))
		b.box("chrome", chrome, _xf(Vector3(side * 0.925, 0.82, 0.1)), Vector3(0.02, 0.025, 0.25))
		for wz in ([-1.5, 1.45] if with_wheels else []):
			var wheel_xf := Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(side * 0.83, 0.34, wz))
			b.lathe("rubber", rubber, wheel_xf, PackedVector2Array([Vector2(0.0, -0.12), Vector2(0.27, -0.12), Vector2(0.34, -0.08), Vector2(0.34, 0.08), Vector2(0.27, 0.12), Vector2(0.0, 0.12)]), 14)
			var rim_xf := Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(side * 0.88, 0.34, wz))
			b.lathe("chrome", chrome, rim_xf, PackedVector2Array([Vector2(0.0, -0.085), Vector2(0.22, -0.085), Vector2(0.22, 0.085), Vector2(0.0, 0.085)]), 10)
	if taxi:
		var sign := plain(Color(0.95, 0.95, 0.9), 0.4, 0.0, Color(0.2, 0.2, 0.15))
		b.box("sign", sign, _xf(Vector3(0, 1.53, 0.3)), Vector3(0.7, 0.17, 0.25))
	var mesh := b.commit_mesh(true)
	car_mesh_cache[key] = mesh
	return mesh

func _build_parked_cars() -> void:
	# Parked along the promenade side of the corniche road. The black sedan
	# right next to the spawn is the player's drivable car (vehicle.gd).
	var specs := [
		[Vector3(74.5, 0, -41.7), Color(0.92, 0.92, 0.90), false],
		[Vector3(46.0, 0, -41.7), Color(0.95, 0.72, 0.05), true],
		[Vector3(39.5, 0, -41.7), Color(0.70, 0.71, 0.72), false],
		[Vector3(22.5, 0, -41.7), Color(0.95, 0.72, 0.05), true],
		[Vector3(14.0, 0, -41.7), Color(0.55, 0.07, 0.06), false],
		[Vector3(-16.0, 0, -41.7), Color(0.92, 0.92, 0.90), false],
		[Vector3(-30.0, 0, -38.3), Color(0.10, 0.20, 0.38), false],
		[Vector3(88.0, 0, -38.3), Color(0.95, 0.72, 0.05), true],
		[Vector3(100.0, 0, -41.7), Color(0.18, 0.19, 0.20), false]
	]
	for spec in specs:
		var pos: Vector3 = spec[0]
		var car := MeshInstance3D.new()
		car.mesh = car_mesh(spec[1], spec[2])
		car.position = pos + Vector3(0, 0.02, 0)
		car.rotation.y = -PI * 0.5 if pos.z < -40.0 else PI * 0.5
		car.visibility_range_end = 170.0
		add_child(car)
		_static_box(Vector3(1.85, 1.4, 4.8), pos + Vector3(0, 0.7, 0), car.rotation.y)

# ----------------------------------------------------------------- flags

func tunisian_flag_texture() -> ImageTexture:
	var w := 192
	var h := 128
	var image := Image.create(w, h, true, Image.FORMAT_RGBA8)
	var red := Color(0.906, 0.0, 0.075)
	var white := Color(1, 1, 1)
	var c := Vector2(w * 0.5, h * 0.5)
	var R := h * 0.25
	var star: PackedVector2Array = []
	var star_c := c + Vector2(R * 0.22, 0)
	for i in range(10):
		var a := -PI * 0.5 + PI * float(i) / 5.0 + PI
		var rr := R * 0.36 if i % 2 == 0 else R * 0.145
		star.append(star_c + Vector2(cos(a), sin(a)) * rr)
	for y in range(h):
		for x in range(w):
			var p := Vector2(x + 0.5, y + 0.5)
			var col := red
			if p.distance_to(c) <= R:
				col = white
				var in_outer := p.distance_to(c + Vector2(-R * 0.08, 0)) <= R * 0.75
				var in_inner := p.distance_to(c + Vector2(R * 0.12, 0)) <= R * 0.6
				if in_outer and not in_inner:
					col = red
				if Geometry2D.is_point_in_polygon(p, star):
					col = red
			image.set_pixel(x, y, col)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

var _flag_texture: ImageTexture

func _create_flag(pole_base: Vector3, pole_height: float, flag_size: Vector2) -> void:
	if _flag_texture == null:
		_flag_texture = tunisian_flag_texture()
	var b := MESH_BATCH.new()
	var metal := plain(Color(0.85, 0.86, 0.86), 0.3, 0.8)
	b.lathe("pole", metal, _xf(pole_base), PackedVector2Array([Vector2(0, 0), Vector2(0.09, 0), Vector2(0.05, 0.3), Vector2(0.04, pole_height), Vector2(0.08, pole_height + 0.05), Vector2(0, pole_height + 0.15)]), 8)
	b.commit_instances(self)
	var material := ShaderMaterial.new()
	material.shader = FLAG_SHADER
	material.set_shader_parameter("flag_texture", _flag_texture)
	var plane := PlaneMesh.new()
	plane.size = flag_size
	plane.orientation = PlaneMesh.FACE_Z
	plane.subdivide_width = 14
	plane.subdivide_depth = 8
	var flag := MeshInstance3D.new()
	flag.name = "TunisianFlag"
	flag.mesh = plane
	flag.material_override = material
	flag.position = pole_base + Vector3(flag_size.x * 0.5 + 0.05, pole_height - flag_size.y * 0.5 - 0.1, 0)
	add_child(flag)

func _build_flags() -> void:
	_create_flag(Vector3(53.0, 0, ROAD_SEA_EDGE_Z - 1.1), 9.0, Vector2(2.4, 1.6))

# ----------------------------------------------------------------- boats

func _boat(pos: Vector3, yaw: float, hull_color: Color, sail: bool) -> void:
	var b := MESH_BATCH.new()
	var white := plain(Color(0.95, 0.95, 0.93), 0.5)
	var stripe := plain(hull_color, 0.5)
	var wood := plain(Color(0.45, 0.30, 0.18), 0.8)
	# Hull: extruded side profile, narrowed by a scaled transform toward the keel.
	b.extrude_profile("hull", white, Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 1.0, 1.0)), Vector3(0, -0.25, 0)), PackedVector2Array([Vector2(-2.3, 0.0), Vector2(1.6, 0.0), Vector2(2.5, 0.75), Vector2(-2.4, 0.75)]), 1.6)
	b.box("stripe", stripe, _xf(Vector3(0, 0.36, 0.1)), Vector3(1.64, 0.14, 4.3))
	b.box("wood", wood, _xf(Vector3(0, 0.52, -0.3)), Vector3(1.4, 0.06, 2.6))
	b.box("hull", white, _xf(Vector3(0, 0.85, -0.8)), Vector3(1.0, 0.6, 1.1))
	if sail:
		b.lathe("wood", wood, _xf(Vector3(0, 0.5, 0.3)), PackedVector2Array([Vector2(0, 0), Vector2(0.05, 0), Vector2(0.035, 6.5), Vector2(0, 6.55)]), 6)
		var cloth := plain(Color(0.97, 0.96, 0.93), 0.9)
		var n := Vector3(1, 0, 0)
		b.tri("sail", cloth, [Vector3(0.0, 1.2, 0.3), Vector3(0.0, 6.9, 0.25), Vector3(0.0, 1.2, -2.0)], [n, n, n], [Vector2(0, 0), Vector2(0, 1), Vector2(1, 0)])
		b.tri("sail", cloth, [Vector3(0.0, 1.2, 0.3), Vector3(0.0, 1.2, -2.0), Vector3(0.0, 6.9, 0.25)], [-n, -n, -n], [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)])
	var boat := Node3D.new()
	boat.name = "Boat"
	boat.position = pos
	boat.rotation.y = yaw
	add_child(boat)
	for item in b.commit_instances(boat):
		item.visibility_range_end = 260.0
	boats.append(boat)
	boat_rest.append(boat.transform)

func _build_boats() -> void:
	_boat(Vector3(58.0, SEA_LEVEL, -68.0), 0.6, BLUE, false)
	_boat(Vector3(40.0, SEA_LEVEL, -75.0), 2.2, Color(0.80, 0.18, 0.12), false)
	_boat(Vector3(70.0, SEA_LEVEL, -84.0), -0.4, Color(0.12, 0.45, 0.40), false)
	_boat(Vector3(8.0, SEA_LEVEL, -96.0), 1.2, BLUE, true)
	_boat(Vector3(-2.0, SEA_LEVEL, -130.0), 0.3, Color(0.10, 0.10, 0.10), true)

func _process(delta: float) -> void:
	clock += delta
	for i in range(boats.size()):
		var boat := boats[i]
		if not is_instance_valid(boat):
			continue
		var rest := boat_rest[i]
		var phase := clock * 1.1 + float(i) * 1.9
		boat.position = rest.origin + Vector3(0, sin(phase) * 0.09, 0)
		boat.rotation = Vector3(sin(phase * 0.8) * 0.035, rest.basis.get_euler().y, cos(phase * 0.9) * 0.05)

# Rough "is this water" test used by the player and the minimap.
static func is_headland(p: Vector3) -> bool:
	return p.x > HEADLAND_MIN.x and p.x < HEADLAND_MAX.x and p.z > HEADLAND_MIN.y and p.z < HEADLAND_MAX.y
