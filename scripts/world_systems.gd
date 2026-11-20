extends Node
class_name MahdiaWorldSystems

var hour := 13.0
var weather := "مشمس"
var sun: DirectionalLight3D
var environment: Environment
var status_callback: Callable
var weather_elapsed := 0.0
var next_weather_change := 180.0
const SUN_STRENGTH := 1.75
var base_fog_density := 0.0016

func configure(light: DirectionalLight3D, env: Environment) -> void:
	sun = light
	environment = env

func _process(delta: float) -> void:
	hour = fposmod(hour + delta * 0.018, 24.0)
	weather_elapsed += delta
	if weather_elapsed >= next_weather_change:
		weather_elapsed = 0.0
		next_weather_change = randf_range(180.0, 360.0)
		var choices := ["مشمس", "مشمس", "غائم", "ممطر"]
		set_weather(choices[randi_range(0, choices.size() - 1)])
	var daylight := clampf(sin((hour - 6.0) / 12.0 * PI), 0.08, 1.0)
	var sky := _sky_color_for_hour(hour)
	var weather_light := 1.0
	if weather == "غائم":
		weather_light = 0.78
	elif weather == "ممطر":
		weather_light = 0.58
	if is_instance_valid(sun):
		# Mediterranean sun: highest around 13:00, coming from behind the
		# player's spawn view over the sea so facades, people and Borj el
		# Kebir are front-lit like the reference image. The quality tier
		# controls shadows.
		var sun_elevation := clampf(daylight, 0.0, 1.0)
		sun.rotation_degrees = Vector3(
			lerpf(-6.0, -52.0, sun_elevation),
			135.0 + (hour - 13.0) * 15.0,
			0.0
		)
		var warm_light := 1.0 - clampf(absf(hour - 13.0) / 6.5, 0.0, 1.0)
		sun.light_color = Color(1.0, 0.74, 0.55).lerp(Color(1.0, 0.95, 0.88), warm_light)
		sun.light_energy = daylight * weather_light * SUN_STRENGTH
	if is_instance_valid(environment):
		var weather_tint := Color(0.78, 0.84, 0.92) if weather == "غائم" else Color(0.68, 0.75, 0.86) if weather == "ممطر" else Color.WHITE
		# Colour-mode fallback (only used when no sky is configured).
		environment.background_color = sky * weather_tint
		environment.ambient_light_color = Color(0.34, 0.39, 0.52).lerp(Color(0.82, 0.86, 0.92), daylight) * weather_tint
		environment.ambient_light_energy = lerpf(0.12, 1.0, daylight) * weather_light
		# HDRI / procedural sky: dim it at night and under cloud.
		environment.background_energy_multiplier = lerpf(0.035, 1.0, daylight) * weather_light
		if environment.fog_enabled:
			var haze := 0.0 if weather == "مشمس" else (0.004 if weather == "غائم" else 0.009)
			environment.fog_density = base_fog_density + haze
			environment.fog_light_color = Color(0.70, 0.80, 0.90).lerp(Color(0.10, 0.12, 0.18), 1.0 - daylight) * weather_tint

func get_daylight() -> float:
	return clampf(sin((hour - 6.0) / 12.0 * PI), 0.0, 1.0)

func _sky_color_for_hour(value: float) -> Color:
	var night := Color(0.035, 0.065, 0.13)
	var dawn := Color(0.92, 0.48, 0.32)
	var day := Color(0.48, 0.69, 0.86)
	var sunset := Color(0.88, 0.38, 0.25)
	if value < 5.0 or value >= 20.0:
		return night
	if value < 7.5:
		return night.lerp(dawn, clampf((value - 5.0) / 2.5, 0.0, 1.0))
	if value < 9.0:
		return dawn.lerp(day, clampf((value - 7.5) / 1.5, 0.0, 1.0))
	if value < 16.5:
		return day
	if value < 19.0:
		return day.lerp(sunset, clampf((value - 16.5) / 2.5, 0.0, 1.0))
	return sunset.lerp(night, clampf((value - 19.0) / 1.0, 0.0, 1.0))

func set_weather(value: String) -> void:
	if value not in ["مشمس", "غائم", "ممطر"]:
		return
	weather = value
	if is_instance_valid(environment):
		match weather:
			"مشمس":
				environment.tonemap_exposure = 1.0
			"غائم":
				environment.tonemap_exposure = 0.88
			"ممطر":
				environment.tonemap_exposure = 0.78
				if is_instance_valid(sun):
					sun.light_energy = minf(sun.light_energy, 0.55)
