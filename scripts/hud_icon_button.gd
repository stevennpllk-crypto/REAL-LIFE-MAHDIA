extends Button
class_name MahdiaIconButton

# Round HUD button with a vector-drawn icon. Icons are drawn with canvas
# primitives instead of emoji glyphs, so they look identical on every phone
# (emoji fonts differ by vendor and are missing on some Android builds).

var icon_name := ""
var icon_color := Color(1, 1, 1, 0.96)
var accent := Color(0.035, 0.055, 0.075, 0.62)
var ring := Color(1, 1, 1, 0.55)
var toggled_on := false

func setup(name_value: String, diameter: float) -> Button:
	icon_name = name_value
	text = ""
	custom_minimum_size = Vector2(diameter, diameter)
	focus_mode = Control.FOCUS_NONE
	flat = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)
	return self

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	var bg := accent
	if is_pressed() or toggled_on:
		bg = Color(0.20, 0.42, 0.62, 0.85)
	draw_circle(c, r - 1.0, bg)
	draw_arc(c, r - 1.5, 0.0, TAU, 48, ring, 1.6, true)
	draw_icon_shape(self, icon_name, c, r * 0.62, icon_color)

# Shared drawing routine (also used by plain Controls such as the minimap
# location pin and the money pill). s is the half-size of the icon.
static func draw_icon_shape(ci: CanvasItem, kind: String, c: Vector2, s: float, col: Color) -> void:
	var k := s / 10.0
	var w := maxf(1.5, 2.1 * k)
	var dark := Color(0.05, 0.07, 0.09, 0.95)
	match kind:
		"home":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-9, -1) * k, c + Vector2(0, -9.5) * k, c + Vector2(9, -1) * k, c + Vector2(7, -1) * k, c + Vector2(7, 8.5) * k, c + Vector2(-7, 8.5) * k, c + Vector2(-7, -1) * k]), col)
			ci.draw_rect(Rect2(c + Vector2(-2.2, 2.5) * k, Vector2(4.4, 6.0) * k), dark)
		"shirt":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-3.5, -8) * k, c + Vector2(-9.5, -5) * k, c + Vector2(-11, 0) * k, c + Vector2(-6.5, 1.2) * k, c + Vector2(-6, 9) * k, c + Vector2(6, 9) * k, c + Vector2(6.5, 1.2) * k, c + Vector2(11, 0) * k, c + Vector2(9.5, -5) * k, c + Vector2(3.5, -8) * k, c + Vector2(0, -5.5) * k]), col)
		"trophy":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-6.5, -8.5) * k, c + Vector2(6.5, -8.5) * k, c + Vector2(5.5, -2) * k, c + Vector2(2, 2) * k, c + Vector2(-2, 2) * k, c + Vector2(-5.5, -2) * k]), col)
			ci.draw_rect(Rect2(c + Vector2(-1.4, 2) * k, Vector2(2.8, 4) * k), col)
			ci.draw_rect(Rect2(c + Vector2(-5.5, 6) * k, Vector2(11, 2.6) * k), col)
			ci.draw_arc(c + Vector2(-6.5, -4.5) * k, 3.2 * k, PI * 0.5, PI * 1.5, 10, col, w, true)
			ci.draw_arc(c + Vector2(6.5, -4.5) * k, 3.2 * k, -PI * 0.5, PI * 0.5, 10, col, w, true)
		"gear":
			for i in range(8):
				var a := TAU * float(i) / 8.0
				var d := Vector2(cos(a), sin(a))
				var p := Vector2(-d.y, d.x)
				ci.draw_colored_polygon(PackedVector2Array([c + (d * 6.0 - p * 1.8) * k, c + (d * 9.5 - p * 1.5) * k, c + (d * 9.5 + p * 1.5) * k, c + (d * 6.0 + p * 1.8) * k]), col)
			ci.draw_circle(c, 7.0 * k, col)
			ci.draw_circle(c, 3.0 * k, dark)
		"friends":
			ci.draw_circle(c + Vector2(4.5, -4) * k, 3.2 * k, col.darkened(0.15))
			ci.draw_colored_polygon(_half_disc(c + Vector2(4.5, 7) * k, 6.0 * k), col.darkened(0.15))
			ci.draw_circle(c + Vector2(-3, -3) * k, 3.8 * k, col)
			ci.draw_colored_polygon(_half_disc(c + Vector2(-3, 9) * k, 7.0 * k), col)
		"profile":
			ci.draw_circle(c + Vector2(0, -3) * k, 4.6 * k, col)
			ci.draw_colored_polygon(_half_disc(c + Vector2(0, 10) * k, 8.5 * k), col)
		"chat":
			var body := Rect2(c + Vector2(-9, -7) * k, Vector2(18, 12) * k)
			ci.draw_rect(Rect2(body.position + Vector2(2.5 * k, 0), body.size - Vector2(5.0 * k, 0)), col)
			ci.draw_rect(Rect2(body.position + Vector2(0, 2.5 * k), body.size - Vector2(0, 5.0 * k)), col)
			for corner in [Vector2(-6.5, -4.5), Vector2(6.5, -4.5), Vector2(-6.5, 2.5), Vector2(6.5, 2.5)]:
				ci.draw_circle(c + (corner as Vector2) * k, 2.5 * k, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-5, 4) * k, c + Vector2(-1, 4) * k, c + Vector2(-6, 9.5) * k]), col)
			for i in range(3):
				ci.draw_circle(c + Vector2(-4.5 + float(i) * 4.5, -1) * k, 1.3 * k, dark)
		"mic":
			ci.draw_rect(Rect2(c + Vector2(-3, -6) * k, Vector2(6, 8) * k), col)
			ci.draw_circle(c + Vector2(0, -6) * k, 3.0 * k, col)
			ci.draw_circle(c + Vector2(0, 2) * k, 3.0 * k, col)
			ci.draw_arc(c + Vector2(0, 1) * k, 6.2 * k, 0.0, PI, 14, col, w, true)
			ci.draw_line(c + Vector2(0, 7.2) * k, c + Vector2(0, 9.5) * k, col, w, true)
			ci.draw_line(c + Vector2(-3.5, 9.5) * k, c + Vector2(3.5, 9.5) * k, col, w, true)
		"punch":
			ci.draw_rect(Rect2(c + Vector2(-7, -5) * k, Vector2(13, 11) * k), col)
			for i in range(4):
				ci.draw_circle(c + Vector2(-5.5 + float(i) * 3.4, -5.0) * k, 1.9 * k, col)
				ci.draw_line(c + Vector2(-3.8 + float(i) * 3.4, -5.5) * k, c + Vector2(-3.8 + float(i) * 3.4, -1.0) * k, dark, maxf(1.0, k), true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-7, 0) * k, c + Vector2(-10, 3) * k, c + Vector2(-8, 7) * k, c + Vector2(-3, 6) * k]), col)
			ci.draw_line(c + Vector2(-6, 2) * k, c + Vector2(2, 2) * k, dark, maxf(1.0, k), true)
			ci.draw_rect(Rect2(c + Vector2(-5, 6) * k, Vector2(9, 3.5) * k), col.darkened(0.2))
		"crouch":
			ci.draw_circle(c + Vector2(2.5, -7) * k, 2.6 * k, col)
			ci.draw_polyline(PackedVector2Array([c + Vector2(1.5, -4) * k, c + Vector2(-2, 1.5) * k, c + Vector2(3.5, 3) * k, c + Vector2(3, 9) * k]), col, w * 1.3, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-2, 1.5) * k, c + Vector2(-6, 5) * k, c + Vector2(-2.5, 9) * k]), col, w * 1.3, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(0.5, -2.5) * k, c + Vector2(5, 0) * k]), col, w, true)
		"run":
			ci.draw_circle(c + Vector2(4, -8) * k, 2.6 * k, col)
			ci.draw_line(c + Vector2(2.5, -4.5) * k, c + Vector2(-1.5, 2.5) * k, col, w * 1.3, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-5, -2.5) * k, c + Vector2(-1, -4.5) * k, c + Vector2(2.5, -4.5) * k, c + Vector2(5, -1) * k, c + Vector2(8.5, -1.5) * k]), col, w, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-1.5, 2.5) * k, c + Vector2(3, 5) * k, c + Vector2(2, 9.5) * k]), col, w * 1.2, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-1.5, 2.5) * k, c + Vector2(-5, 5.5) * k, c + Vector2(-9, 4.5) * k]), col, w * 1.2, true)
		"jump":
			ci.draw_circle(c + Vector2(0, -7.5) * k, 2.6 * k, col)
			ci.draw_line(c + Vector2(0, -4.5) * k, c + Vector2(0, 2) * k, col, w * 1.3, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-6, -8) * k, c + Vector2(-3, -3) * k, c + Vector2(0, -3.5) * k, c + Vector2(3, -3) * k, c + Vector2(6, -8) * k]), col, w, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(0, 2) * k, c + Vector2(-4, 5) * k, c + Vector2(-2, 9) * k]), col, w * 1.2, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(0, 2) * k, c + Vector2(4.5, 4) * k, c + Vector2(6, 8.5) * k]), col, w * 1.2, true)
		"hand":
			ci.draw_rect(Rect2(c + Vector2(-5, -1) * k, Vector2(10, 9) * k), col)
			for i in range(4):
				var fx := -4.5 + float(i) * 3.0
				ci.draw_line(c + Vector2(fx + 0.6, 0) * k, c + Vector2(fx + 0.6, -8.0 + absf(float(i) - 1.5) * 1.2) * k, col, 2.4 * k, true)
			ci.draw_line(c + Vector2(-5, 3) * k, c + Vector2(-9, -1) * k, col, 2.4 * k, true)
		"bolt":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(2, -10) * k, c + Vector2(-6, 1) * k, c + Vector2(-0.5, 1) * k, c + Vector2(-2.5, 10) * k, c + Vector2(6, -2) * k, c + Vector2(0.5, -2) * k]), col)
		"plus":
			ci.draw_line(c + Vector2(-6, 0) * k, c + Vector2(6, 0) * k, col, w * 1.3, true)
			ci.draw_line(c + Vector2(0, -6) * k, c + Vector2(0, 6) * k, col, w * 1.3, true)
		"cash":
			var green := Color(0.36, 0.78, 0.36)
			for j in range(2):
				var off := Vector2(float(j) * 2.5, -float(j) * 2.5) * k
				ci.draw_rect(Rect2(c + Vector2(-10, -5) * k + off, Vector2(18, 10) * k), green.darkened(0.25 * float(1 - j)))
				ci.draw_rect(Rect2(c + Vector2(-10, -5) * k + off, Vector2(18, 10) * k), Color(0.1, 0.35, 0.12), false, maxf(1.0, k))
			ci.draw_circle(c + Vector2(1.5, -2.5) * k, 2.6 * k, Color(0.16, 0.45, 0.18))
		"pin":
			ci.draw_circle(c + Vector2(0, -3) * k, 5.5 * k, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-4.6, -0.5) * k, c + Vector2(4.6, -0.5) * k, c + Vector2(0, 9) * k]), col)
			ci.draw_circle(c + Vector2(0, -3) * k, 2.2 * k, dark)
		"diamond":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -8) * k, c + Vector2(8, 0) * k, c + Vector2(0, 8) * k, c + Vector2(-8, 0) * k]), col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -4) * k, c + Vector2(4, 0) * k, c + Vector2(0, 4) * k, c + Vector2(-4, 0) * k]), col.lightened(0.5))
		"close":
			ci.draw_line(c + Vector2(-6, -6) * k, c + Vector2(6, 6) * k, col, w * 1.3, true)
			ci.draw_line(c + Vector2(6, -6) * k, c + Vector2(-6, 6) * k, col, w * 1.3, true)
		_:
			ci.draw_circle(c, 3.0 * k, col)

static func _half_disc(base: Vector2, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(13):
		var a := PI + PI * float(i) / 12.0
		pts.append(base + Vector2(cos(a), sin(a)) * radius)
	return pts
