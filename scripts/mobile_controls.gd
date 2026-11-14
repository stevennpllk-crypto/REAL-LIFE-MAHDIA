extends CanvasLayer
class_name MahdiaMobileControls

var target: CharacterBody3D
var stick_center := Vector2(112, 0)
var stick_touch := -1
var stick_value := Vector2.ZERO
var stick_base: Control
var run_button: Button
var jump_button: Button

func setup(player: CharacterBody3D) -> void:
	target = player
	if not OS.has_feature("mobile"):
		return
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(root)
	stick_base = Control.new()
	stick_base.position = Vector2(24, -184)
	stick_base.anchor_top = 1.0
	stick_base.anchor_bottom = 1.0
	stick_base.custom_minimum_size = Vector2(176, 160)
	stick_base.mouse_filter = Control.MOUSE_FILTER_STOP
	stick_base.draw.connect(_draw_stick)
	stick_base.gui_input.connect(_on_stick_input)
	root.add_child(stick_base)
	run_button = _make_button(root, "جري", Vector2(-190, -150))
	jump_button = _make_button(root, "قفز", Vector2(-100, -150))
	run_button.button_down.connect(func(): target.set_mobile_run(true))
	run_button.button_up.connect(func(): target.set_mobile_run(false))
	jump_button.pressed.connect(func(): target.request_jump())

func _make_button(parent: Control, caption: String, offset: Vector2) -> Button:
	var button := Button.new()
	button.text = caption
	button.anchor_left = 1.0
	button.anchor_right = 1.0
	button.anchor_top = 1.0
	button.anchor_bottom = 1.0
	button.offset_left = offset.x
	button.offset_right = offset.x + 82
	button.offset_top = offset.y
	button.offset_bottom = offset.y + 66
	parent.add_child(button)
	return button

func _draw_stick() -> void:
	stick_base.draw_circle(Vector2(88, 80), 68, Color(0.05, 0.08, 0.12, 0.35))
	stick_base.draw_circle(Vector2(88, 80) + stick_value * 42.0, 27, Color(0.8, 0.88, 1.0, 0.72))

func _on_stick_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and stick_touch == -1:
			stick_touch = event.index
			_update_stick(event.position)
		elif not event.pressed and event.index == stick_touch:
			stick_touch = -1
			stick_value = Vector2.ZERO
			target.set_mobile_move(Vector2.ZERO)
			stick_base.queue_redraw()
	elif event is InputEventScreenDrag and event.index == stick_touch:
		_update_stick(event.position)

func _update_stick(local_position: Vector2) -> void:
	stick_value = ((local_position - Vector2(88, 80)) / 54.0).limit_length(1.0)
	target.set_mobile_move(stick_value)
	stick_base.queue_redraw()
