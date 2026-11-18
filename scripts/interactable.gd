extends StaticBody3D
class_name MahdiaInteractable

@export var title := "مكان"
@export_multiline var description := "يمكنك التفاعل مع هذا المكان."
signal interacted(message: String)

func _ready() -> void:
	add_to_group("interactables")

func interact() -> String:
	interacted.emit(description)
	return "%s: %s" % [title, description]
