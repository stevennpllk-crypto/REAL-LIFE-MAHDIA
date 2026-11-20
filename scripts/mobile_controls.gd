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

const ICON_BUTTON = preload("res://scripts/hud_icon_button.gd")

func setup(player: CharacterBody3D) -> void:
	target = player
	var platform := OS.get_name()
	var forced := is_inside_tree() and get_tree().root.has_meta("mahdia_force_touch_ui")
	if not forced and not OS.has_feature("mobile") and platform != "Android" and platform != "iOS":
		return

	var root := Control.new()
	root.name = "TouchControls"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Reference layout: joystick bottom-left above the chat log.
	stick_base = Control.new()
	stick_base.name = "MovementJoystick"
	stick_base.anchor_left = 0.0
	stick_base.anchor_right = 0.0
	stick_base.anchor_top = 1.0
	stick_base.anchor_bottom = 1.0
	stick_base.offset_left = 34.0
	stick_base.offset_top = -232.0
	stick_base.offset_right = 172.0
	stick_base.offset_bottom = -94.0
	stick_base.mouse_filter = Control.MOUSE_FILTER_STOP
	stick_base.draw.connect(_draw_stick)
	stick_base.gui_input.connect(_on_stick_input)
	root.add_child(stick_base)

	# Action cluster bottom-right, matching the reference image:
	# run (top right), punch (left), crouch (bottom left), jump (bottom right).
	run_button = _make_button(root, "run", Vector2(-71, -201), 80.0)
	attack_button = _make_button(root, "punch", Vector2(-208, -147), 80.0)
	crouch_button = _make_button(root, "crouch", Vector2(-181, -59), 66.0)
	jump_button = _make_button(root, "jump", Vector2(-71, -80), 74.0)
	interact_button = _make_button(root, "hand", Vector2(-208, -250), 62.0)
	dodge_button = _make_button(root, "bolt", Vector2(-300, -64), 56.0)

	run_button.button_down.connect(func(): target.set_mobile_run(true))
	run_button.button_up.connect(func(): target.set_mobile_run(false))
	jump_button.pressed.connect(func(): target.request_jump())
	interact_button.pressed.connect(func(): target.request_interact())
	attack_button.pressed.connect(func(): target.request_attack())
	crouch_button.pressed.connect(func():
		target.toggle_crouch()
		crouch_button.set("toggled_on", bool(target.get("crouching")))
		crouch_button.queue_redraw()
	)
	dodge_button.pressed.connect(func(): target.request_dodge())

# center is measured from the bottom-right corner of the screen.
func _make_button(parent: Control, icon: String, center: Vector2, diameter: float) -> Button:
	var button: Button = ICON_BUTTON.new()
	button.call("setup", icon, diameter)
	button.name = "Action_" + icon
	button.anchor_left = 1.0
	button.anchor_right = 1.0
	button.anchor_top = 1.0
	button.anchor_bottom = 1.0
	button.offset_left = center.x - diameter * 0.5
	button.offset_right = center.x + diameter * 0.5
	button.offset_top = center.y - diameter * 0.5
	button.offset_bottom = center.y + diameter * 0.5
	parent.add_child(button)
	return button

func _draw_stick() -> void:
	var center := stick_base.size * 0.5
	var outer := stick_max_radius + 18.0
	stick_base.draw_circle(center, outer, Color(0.03, 0.05, 0.08, 0.30))
	stick_base.draw_arc(center, outer, 0.0, TAU, 64, Color(1, 1, 1, 0.50), 2.0, true)
	stick_base.draw_arc(center, outer - 9.0, 0.0, TAU, 64, Color(1, 1, 1, 0.16), 1.0, true)
	# Direction ticks on the ring.
	for i in range(4):
		var a := TAU * float(i) / 4.0
		var d := Vector2(cos(a), sin(a))
		var p := Vector2(-d.y, d.x)
		var tip := center + d * (outer - 4.0)
		stick_base.draw_colored_polygon(PackedVector2Array([tip, tip - d * 7.0 + p * 5.0, tip - d * 7.0 - p * 5.0]), Color(1, 1, 1, 0.55))
	var knob := center + stick_value * stick_max_radius
	stick_base.draw_circle(knob + Vector2(0, 2), 25.0, Color(0, 0, 0, 0.22))
	stick_base.draw_circle(knob, 24.0, Color(0.86, 0.88, 0.90, 0.95))
	stick_base.draw_circle(knob - Vector2(4, 5), 15.0, Color(1, 1, 1, 0.55))
	stick_base.draw_arc(knob, 24.0, 0.0, TAU, 40, Color(0.55, 0.58, 0.62, 0.9), 1.5, true)

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


func reset_input_state() -> void:
	# Invalidate any finger still holding the joystick when changing control modes.
	# Its later drag/release events must not leak movement into the next mode.
	stick_touch = -1
	stick_value = Vector2.ZERO
	if is_instance_valid(target):
		target.set_mobile_move(Vector2.ZERO)
		target.set_mobile_run(false)
	if is_instance_valid(stick_base):
		stick_base.queue_redraw()
