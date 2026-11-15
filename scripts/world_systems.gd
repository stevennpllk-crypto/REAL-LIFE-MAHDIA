extends Node
class_name MahdiaWorldSystems

var hour := 8.0
var weather := "مشمس"
var sun: DirectionalLight3D
var environment: Environment
var status_callback: Callable
var weather_elapsed := 0.0
var next_weather_change := 180.0

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
	if is_instance_valid(sun):
		sun.light_energy = daylight
	if is_instance_valid(environment):
		environment.ambient_light_energy = lerpf(0.25, 1.0, daylight)

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
