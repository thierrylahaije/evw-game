extends Control
## Transparent instrument overlay drawn with Godot UI primitives.

const INK := Color("#eff8ff")
const MUTED := Color("#9bb6c9")
const BLUE := Color("#42d5f5")
const GOLD := Color("#ffc75b")

var speed_kmh := 0.0
var engine_rpm := 700.0
var steering_degrees := 0.0
var articulation_degrees := 0.0
var speed_value: Label
var rpm_value: Label
var steering_value: Label
var articulation_value: Label

func _ready() -> void:
	custom_minimum_size = Vector2(500, 150)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -250.0
	offset_top = -168.0
	offset_right = 250.0
	offset_bottom = -18.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_label("SNELHEID", Vector2(46, 9), Vector2(100, 17), 11, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_add_label("TOEREN · SIM.", Vector2(180, 9), Vector2(128, 17), 11, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_add_label("STUURHOEK", Vector2(342, 9), Vector2(116, 17), 11, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	speed_value = _add_label("0", Vector2(64, 63), Vector2(64, 35), 27, INK, HORIZONTAL_ALIGNMENT_CENTER)
	rpm_value = _add_label("700", Vector2(200, 65), Vector2(88, 33), 24, INK, HORIZONTAL_ALIGNMENT_CENTER)
	steering_value = _add_label("0°", Vector2(342, 122), Vector2(116, 25), 20, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_add_label("km/h", Vector2(69, 96), Vector2(54, 21), 13, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_add_label("rpm", Vector2(217, 96), Vector2(54, 21), 13, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	articulation_value = _add_label("KNIKHOEK  0°", Vector2(20, 129), Vector2(200, 18), 11, MUTED)

func _add_label(value: String, at: Vector2, dimensions: Vector2, font_size: int, color: Color, alignment := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = value
	label.position = at
	label.size = dimensions
	label.horizontal_alignment = alignment
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

func set_readings(speed: float, rpm: float, steer: float, articulation: float) -> void:
	speed_kmh = maxf(0.0, speed)
	engine_rpm = clampf(rpm, 0.0, 3000.0)
	steering_degrees = clampf(steer, -35.0, 35.0)
	articulation_degrees = articulation
	speed_value.text = "%d" % roundi(speed_kmh)
	rpm_value.text = "%d" % roundi(engine_rpm)
	steering_value.text = "%s%d°" % ["L " if steering_degrees > 0.5 else ("R " if steering_degrees < -0.5 else ""), roundi(absf(steering_degrees))]
	articulation_value.text = "KNIKHOEK  %d°" % roundi(articulation_degrees)
	queue_redraw()

func _draw() -> void:
	_draw_gauge(Vector2(96, 85), speed_kmh / 60.0, BLUE)
	_draw_gauge(Vector2(244, 85), engine_rpm / 3000.0, GOLD)
	_draw_steering_wheel(Vector2(400, 85))

func _draw_gauge(center: Vector2, fraction: float, accent: Color) -> void:
	var begin := deg_to_rad(135.0)
	var finish := deg_to_rad(405.0)
	draw_arc(center, 43.0, begin, finish, 48, Color(0.27, 0.38, 0.46, 0.85), 7.0, true)
	draw_arc(center, 43.0, begin, lerpf(begin, finish, clampf(fraction, 0.0, 1.0)), 48, accent, 7.0, true)
	for tick in range(11):
		var angle := lerpf(begin, finish, float(tick) / 10.0)
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(center + direction * 51.0, center + direction * (57.0 if tick % 2 == 0 else 54.0), MUTED, 1.3, true)
	var needle_angle := lerpf(begin, finish, clampf(fraction, 0.0, 1.0))
	var needle_direction := Vector2(cos(needle_angle), sin(needle_angle))
	draw_line(center + needle_direction * 36.0, center + needle_direction * 49.0, accent, 2.5, true)

func _draw_steering_wheel(center: Vector2) -> void:
	draw_arc(center, 34.0, 0.0, TAU, 48, Color(0.6, 0.75, 0.83), 5.0, true)
	var angle := deg_to_rad(steering_degrees)
	for spoke in range(3):
		var direction := Vector2(cos(angle + float(spoke) * TAU / 3.0), sin(angle + float(spoke) * TAU / 3.0))
		draw_line(center, center + direction * 31.0, BLUE, 2.5, true)
	draw_circle(center, 6.5, GOLD)
