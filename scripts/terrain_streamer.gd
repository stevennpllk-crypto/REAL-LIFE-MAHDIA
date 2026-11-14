extends Node3D
class_name EarthTerrainStreamer

# Loads locally cached grayscale DEM tiles.
# Expected path: res://world/heightmaps/{zoom}/{x}/{y}.png
# Missing tiles are skipped; no fabricated elevation is presented as real terrain.

@export_range(8, 15, 1) var zoom_level := 13
@export_range(16, 128, 1) var grid_segments := 32
@export_range(1, 2, 1) var tile_radius := 1
@export var elevation_scale := 9000.0
@export var refresh_interval := 1.0

var target: Node3D
var navigation: Node
var last_center := Vector2i(-999999, -999999)
var refresh_clock := 0.0
var loaded_tiles: Array[Node3D] = []
var missing_tile_count := 0
var loaded_tile_count := 0

func configure(player: Node3D, planet_navigation: Node) -> void:
	target = player
	navigation = planet_navigation
	_refresh_tiles()

func _process(delta: float) -> void:
	refresh_clock += delta
	if refresh_clock < refresh_interval:
		return
	refresh_clock = 0.0
	if not is_instance_valid(target) or not is_instance_valid(navigation):
		return
	var center := _coordinate_to_tile(navigation.latitude, navigation.longitude)
	if center != last_center:
		_refresh_tiles()

func _coordinate_to_tile(lat: float, lon: float) -> Vector2i:
	var count := 1 << zoom_level
	var safe_lat := clampf(lat, -85.05112878, 85.05112878)
	var lat_rad := deg_to_rad(safe_lat)
	var x := int(floor((wrapf(lon, -180.0, 180.0) + 180.0) / 360.0 * count))
	var y_float := (1.0 - asinh(tan(lat_rad)) / PI) * 0.5 * count
	return Vector2i(posmod(x, count), clampi(int(floor(y_float)), 0, count - 1))

func _refresh_tiles() -> void:
	if not is_instance_valid(target) or not is_instance_valid(navigation):
		return
	last_center = _coordinate_to_tile(navigation.latitude, navigation.longitude)
	for old_tile in loaded_tiles:
		if is_instance_valid(old_tile):
			old_tile.queue_free()
	loaded_tiles.clear()
	loaded_tile_count = 0
	missing_tile_count = 0
	var count := 1 << zoom_level
	var latitude_scale := cos(deg_to_rad(navigation.latitude))
	var tile_world_size := TAU * 6378137.0 * latitude_scale / float(count)
	for dy in range(-tile_radius, tile_radius + 1):
		for dx in range(-tile_radius, tile_radius + 1):
			var tile_x := posmod(last_center.x + dx, count)
			var tile_y := last_center.y + dy
			if tile_y < 0 or tile_y >= count:
				continue
			var path := "res://world/heightmaps/%d/%d/%d.png" % [zoom_level, tile_x, tile_y]
			if not ResourceLoader.exists(path):
				missing_tile_count += 1
				continue
			var image := Image.load_from_file(ProjectSettings.globalize_path(path))
			if image == null or image.is_empty():
				missing_tile_count += 1
				continue
			var tile := _build_tile(image, tile_world_size)
			if tile == null:
				missing_tile_count += 1
				continue
			tile.position = target.global_position + Vector3((float(dx) - 0.5) * tile_world_size, 0.0, (float(dy) - 0.5) * tile_world_size)
			add_child(tile)
			loaded_tiles.append(tile)
			loaded_tile_count += 1

func _build_tile(image: Image, world_size: float) -> Node3D:
	var width := image.get_width()
	var height := image.get_height()
	if width < 2 or height < 2:
		return null
	var segments := mini(grid_segments, mini(width - 1, height - 1))
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for z in range(segments + 1):
		for x in range(segments + 1):
			var px := int(round(float(x) / segments * (width - 1)))
			var py := int(round(float(z) / segments * (height - 1)))
			var elevation := image.get_pixel(px, py).r * elevation_scale
			vertices.append(Vector3(float(x) / segments * world_size, elevation, float(z) / segments * world_size))
			uvs.append(Vector2(float(x) / segments, float(z) / segments))
	for z in range(segments):
		for x in range(segments):
			var a := z * (segments + 1) + x
			var b := a + 1
			var c := a + segments + 1
			var d := c + 1
			indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _terrain_material())
	var root := StaticBody3D.new()
	var surface := MeshInstance3D.new()
	surface.mesh = mesh
	root.add_child(surface)
	var collision := CollisionShape3D.new()
	collision.shape = mesh.create_trimesh_shape()
	root.add_child(collision)
	return root

func _terrain_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.42, 0.48, 0.30)
	material.roughness = 1.0
	return material

func get_stream_status() -> String:
	return "DEM %d / %d" % [loaded_tile_count, loaded_tile_count + missing_tile_count]
