extends Node
class_name PlanetNavigation

# Geospatial coordinate foundation for a future streamed Earth world.
# Local X = east, local -Z = north. This does not generate terrain by itself.

const EARTH_RADIUS_M := 6378137.0
const START_LATITUDE := 35.5047
const START_LONGITUDE := 11.0622
const ORIGIN_RESET_DISTANCE_M := 500.0

var latitude: float = START_LATITUDE
var longitude: float = START_LONGITUDE
var origin_latitude: float = START_LATITUDE
var origin_longitude: float = START_LONGITUDE
var origin_world_position := Vector3.ZERO
var initialized := false

func attach_player(player: Node3D) -> void:
	if not is_instance_valid(player):
		return
	origin_world_position = player.global_position
	initialized = true

func update_from_player(world_position: Vector3) -> void:
	if not initialized:
		origin_world_position = world_position
		initialized = true
		return
	var offset := world_position - origin_world_position
	var north_m := -offset.z
	var east_m := offset.x
	var latitude_rad := deg_to_rad(origin_latitude)
	latitude = clampf(origin_latitude + rad_to_deg(north_m / EARTH_RADIUS_M), -89.9999, 89.9999)
	var longitude_scale := maxf(0.000001, cos(latitude_rad))
	longitude = wrapf(origin_longitude + rad_to_deg(east_m / (EARTH_RADIUS_M * longitude_scale)), -180.0, 180.0)
	if Vector2(east_m, north_m).length() >= ORIGIN_RESET_DISTANCE_M:
		origin_latitude = latitude
		origin_longitude = longitude
		origin_world_position = world_position

func set_coordinates(target_latitude: float, target_longitude: float, player: Node3D) -> bool:
	if not is_instance_valid(player) or target_latitude < -90.0 or target_latitude > 90.0:
		return false
	var target_lon := wrapf(target_longitude, -180.0, 180.0)
	var mean_latitude := deg_to_rad((origin_latitude + target_latitude) * 0.5)
	var north_m := deg_to_rad(target_latitude - origin_latitude) * EARTH_RADIUS_M
	var east_m := deg_to_rad(wrapf(target_lon - origin_longitude, -180.0, 180.0)) * EARTH_RADIUS_M * cos(mean_latitude)
	player.global_position = origin_world_position + Vector3(east_m, 0.0, -north_m)
	latitude = target_latitude
	longitude = target_lon
	origin_latitude = latitude
	origin_longitude = longitude
	origin_world_position = player.global_position
	return true

func get_coordinate_text() -> String:
	var ns := "N" if latitude >= 0.0 else "S"
	var ew := "E" if longitude >= 0.0 else "W"
	return "%0.4f°%s %0.4f°%s" % [absf(latitude), ns, absf(longitude), ew]

func get_region_name() -> String:
	if latitude > 33.0 and latitude < 38.0 and longitude > 7.0 and longitude < 12.5:
		return "تونس"
	return "العالم"
