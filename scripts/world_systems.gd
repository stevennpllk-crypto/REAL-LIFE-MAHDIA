extends Node
class_name MahdiaWorldSystems

var hour := 8.0
var weather := "مشمس"
var sun: DirectionalLight3D
var environment: Environment
var status_callback: Callable

func configure(light: DirectionalLight3D, env: Environment) -> void:
	sun = light
	environment = env

func _process(delta: float) -> void:
	hour = fposmod(hour + delta * 0.018, 24.0)
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
		environment.tonemap_exposure = 1.0 if weather == "مشمس" else 0.82
