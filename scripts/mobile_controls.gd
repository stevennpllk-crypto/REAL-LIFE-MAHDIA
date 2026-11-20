extends Node
class_name MahdiaMobileControls

# Touch controls are created explicitly for Android/iOS.  The previous layout
# relied on a Control with a zero size, which made the joystick invisible.
var target: CharacterBody3D
var stick_touch := -1
var stick_value := Vector2.ZERO
var stick_base: Control
var run_button: Button
var jump_button: Button
var interact_button: Button
var attack_button: Button
var crouch_button: Button
var dodge_button: Button
var stick_max_radius := 46.0

func setup(player: CharacterBody3D) -> void:
	target = player
	var platform := OS.get_name()
	if not OS.has_feature("mobile") and platform != "Android" and platform != "iOS":
		return

	var root := Control.new()
	root.name = "TouchControls"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(root)

	stick_base = Control.new()
	stick_base.name = "MovementJoystick"
	stick_base.anchor_left = 0.0
	stick_base.anchor_right = 0.0
	stick_base.anchor_top = 1.0
	stick_base.anchor_bottom = 1.0
	stick_base.offset_left = 20.0
	stick_base.offset_top = -158.0
	stick_base.offset_right = 158.0
	stick_base.offset_bottom = -20.0
	stick_base.mouse_filter = Control.MOUSE_FILTER_STOP
	stick_base.draw.connect(_draw_stick)
	stick_base.gui_input.connect(_on_stick_input)
	root.add_child(stick_base)

	run_button = _make_button(root, "🏃", Vector2(-90, -258))
	jump_button = _make_button(root, "⬆", Vector2(-90, -80))
	interact_button = _make_button(root, "💬", Vector2(-90, -350))
	attack_button = _make_button(root, "👊", Vector2(-178, -166))
	crouch_button = _make_button(root, "🧎", Vector2(-178, -80))
	dodge_button = _make_button(root, "⚡", Vector2(-178, -258))

	run_button.button_down.connect(func(): target.set_mobile_run(true))
	run_button.button_up.connect(func(): target.set_mobile_run(false))
	jump_button.pressed.connect(func(): target.request_jump())
	interact_button.pressed.connect(func(): target.request_interact())
	attack_button.pressed.connect(func(): target.request_attack())
	crouch_button.pressed.connect(func(): target.toggle_crouch())
	dodge_button.pressed.connect(func(): target.request_dodge())

func _make_button(parent: Control, caption: String, offset: Vector2) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(72, 72)
	button.add_theme_font_size_override("font_size", 25)
	button.anchor_left = 1.0
	button.anchor_right = 1.0
	button.anchor_top = 1.0
	button.anchor_bottom = 1.0
	button.offset_left = offset.x
	button.offset_right = offset.x + 72.0
	button.offset_top = offset.y
	button.offset_bottom = offset.y + 72.0
	button.focus_mode = Control.FOCUS_NONE
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.035, 0.055, 0.075, 0.72)
	normal.set_corner_radius_all(36)
	normal.set_border_width_all(1)
	normal.border_color = Color(0.84, 0.89, 0.92, 0.60)
	button.add_theme_stylebox_override("normal", normal)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.22, 0.29, 0.33, 0.92)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_font_size_override("font_size", 24)
	parent.add_child(button)
	return button

func _draw_stick() -> void:
	var center := stick_base.size * 0.5
	stick_base.draw_circle(center, stick_max_radius + 8.0, Color(0.04, 0.07, 0.12, 0.38))
	stick_base.draw_arc(center, stick_max_radius + 8.0, 0.0, TAU, 48, Color(0.82, 0.88, 0.98, 0.72), 3.0)
	stick_base.draw_circle(center + stick_value * stick_max_radius, 21.0, Color(0.78, 0.87, 1.0, 0.92))

func _on_stick_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and stick_touch == -1:
			stick_touch = event.index
			_update_stick(_screen_to_stick_local(event.position))
		elif not event.pressed and event.index == stick_touch:
			stick_touch = -1
			stick_value = Vector2.ZERO
			target.set_mobile_move(Vector2.ZERO)
			stick_base.queue_redraw()
	elif event is InputEventScreenDrag and event.index == stick_touch:
		_update_stick(_screen_to_stick_local(event.position))

func _screen_to_stick_local(screen_position: Vector2) -> Vector2:
	# Screen-touch events use viewport coordinates, unlike Control-local GUI
	# coordinates. Convert before comparing against the joystick's local center.
	return stick_base.get_global_transform_with_canvas().affine_inverse() * screen_position

func _update_stick(local_position: Vector2) -> void:
	var center := stick_base.size * 0.5
	stick_value = ((local_position - center) / stick_max_radius).limit_length(1.0)
	target.set_mobile_move(stick_value)
	stick_base.queue_redraw()
