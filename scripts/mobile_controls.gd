extends CanvasLayer
## Multitouch driving controls and optional browser orientation steering.

const Session = preload("res://scripts/game_session.gd")
const INK := Color("#eff8ff")
const GOLD := Color("#f7c843")
const PANEL := Color(0.05, 0.10, 0.15, 0.82)
const BUTTONS := ["left", "right", "reverse", "gas"]

var surface: Control
var fingers: Dictionary = {}
var held: Dictionary = {}
var sensor_wait: float = 0.0
var sensor_status := "idle"
var calibrated := false
var pause_menu: CanvasLayer
var truck: VehicleBody3D
var last_touch_at: int = -10000
var auto_paused := false
var shown_speed_kmh := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 5
	pause_menu = get_parent().get_node("PauseMenu")
	truck = get_parent().get_node("TruckModel")
	surface = Control.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.draw.connect(_draw_controls)
	add_child(surface)
	get_viewport().size_changed.connect(func() -> void:
		release_all()
		if Session.control_mode == "tilt":
			_sensor_reset()
		sync_game_pause()
		surface.queue_redraw())
	if Session.control_mode == "tilt":
		_sensor_reset()
	sync_game_pause()
	surface.queue_redraw()

func _process(delta: float) -> void:
	if Session.control_mode == "tilt":
		var status_value: Variant = _sensor_call("status()")
		var current: String = str(status_value) if status_value != null else "unavailable"
		if current == "waiting":
			sensor_wait += delta
			if sensor_wait > 5.0:
				current = "unavailable"
		if current != sensor_status:
			sensor_status = current
			if current in ["lost", "denied", "unavailable"]:
				calibrated = false
			surface.queue_redraw()
	sync_game_pause()
	if Session.control_mode == "tilt" and sensor_status == "ready" and calibrated and not get_tree().paused:
		var raw := clampf(float(_sensor_call("steering()")), -1.0, 1.0)
		Session.tilt_steering = lerpf(Session.tilt_steering, raw, 1.0 - exp(-8.0 * delta))
	else:
		Session.tilt_steering = 0.0
	var speed_kmh := roundi(truck.linear_velocity.length() * 3.6)
	if speed_kmh != shown_speed_kmh:
		shown_speed_kmh = speed_kmh
		surface.queue_redraw()

func sync_game_pause() -> void:
	var needs_pause := Session.control_mode != "desktop" and (surface.size.y > surface.size.x or (Session.control_mode == "tilt" and not calibrated))
	if needs_pause != auto_paused:
		auto_paused = needs_pause
		surface.queue_redraw()
	if not pause_menu.overlay.visible:
		get_tree().paused = auto_paused

func _input(event: InputEvent) -> void:
	if Session.control_mode == "desktop" or pause_menu.overlay.visible:
		return
	if surface.size.y > surface.size.x:
		return
	if event is InputEventScreenTouch:
		last_touch_at = Time.get_ticks_msec()
		if event.pressed:
			var key := _hit(event.position)
			if key != "":
				fingers[event.index] = key
				_activate(key)
				get_viewport().set_input_as_handled()
		else:
			var had_finger := fingers.has(event.index)
			_release_finger(event.index)
			if had_finger:
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and fingers.has(event.index):
		last_touch_at = Time.get_ticks_msec()
		var new_key := _hit(event.position)
		if new_key != fingers[event.index]:
			_release_finger(event.index)
			if new_key in BUTTONS:
				fingers[event.index] = new_key
				_activate(new_key)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and Time.get_ticks_msec() - last_touch_at > 800:
		if event.pressed:
			var key := _hit(event.position)
			if key != "":
				fingers[-1] = key
				_activate(key)
				get_viewport().set_input_as_handled()
		else:
			var had_mouse := fingers.has(-1)
			_release_finger(-1)
			if had_mouse:
				get_viewport().set_input_as_handled()

func _activate(key: String) -> void:
	if key == "pause":
		pause_menu.open_pause()
	elif key == "sensor":
		_sensor_request()
	elif key == "calibrate":
		calibrate()
	elif key == "fallback":
		change_mode("buttons")
	elif key in BUTTONS:
		var action := _action(key)
		if not held.has(key):
			Input.action_press(action)
		held[key] = int(held.get(key, 0)) + 1
	surface.queue_redraw()

func _release_finger(index: int) -> void:
	if not fingers.has(index):
		return
	var key: String = fingers[index]
	fingers.erase(index)
	if key in BUTTONS and held.has(key):
		held[key] = int(held[key]) - 1
		if int(held[key]) <= 0:
			held.erase(key)
			Input.action_release(_action(key))
	surface.queue_redraw()

func release_all() -> void:
	for key in held.keys():
		Input.action_release(_action(key))
	held.clear()
	fingers.clear()
	Session.tilt_steering = 0.0
	surface.queue_redraw()

func change_mode(mode: String) -> void:
	release_all()
	Session.control_mode = mode
	if mode == "tilt":
		_sensor_reset()
	sync_game_pause()
	surface.queue_redraw()

func calibrate() -> void:
	if Session.control_mode != "tilt":
		return
	calibrated = _sensor_call("calibrate()") == true
	Session.tilt_steering = 0.0
	sync_game_pause()
	surface.queue_redraw()

func _sensor_reset() -> void:
	calibrated = false
	sensor_status = "idle"
	sensor_wait = 0.0
	_sensor_call("reset()")

func _sensor_request() -> void:
	if not OS.has_feature("web"):
		sensor_status = "unavailable"
	else:
		_sensor_call("request()")
		sensor_status = "waiting"
		sensor_wait = 0.0
	surface.queue_redraw()

func _sensor_call(method: String) -> Variant:
	if not OS.has_feature("web"):
		return null
	return JavaScriptBridge.eval("window.EVW_TILT ? window.EVW_TILT." + method + " : null")

func _action(key: String) -> String:
	match key:
		"left": return "vehicle_left"
		"right": return "vehicle_right"
		"reverse": return "vehicle_brake"
		_: return "vehicle_accelerate"

func _rects() -> Dictionary:
	var size := surface.size
	var width := clampf(size.x * 0.145, 76.0, 142.0)
	var height := clampf(size.y * 0.23, 64.0, 112.0)
	var gap := 12.0
	var margin := 18.0
	var bottom := size.y - height - margin
	var result := {
		"pause": Rect2(Vector2(margin, margin), Vector2(96, 48)),
		"left": Rect2(Vector2(margin, bottom), Vector2(width, height)),
		"right": Rect2(Vector2(margin + width + gap, bottom), Vector2(width, height)),
		"reverse": Rect2(Vector2(size.x - margin - width * 2.0 - gap, bottom), Vector2(width, height)),
		"gas": Rect2(Vector2(size.x - margin - width, bottom), Vector2(width, height)),
	}
	if Session.control_mode == "tilt" and not calibrated:
		var box_width := minf(420.0, size.x - 40.0)
		var x := (size.x - box_width) * 0.5
		var y := (size.y - 190.0) * 0.5
		if sensor_status == "ready":
			result["calibrate"] = Rect2(Vector2(x + 18, y + 110), Vector2(box_width - 36, 56))
		elif sensor_status in ["denied", "unavailable", "lost"]:
			result["fallback"] = Rect2(Vector2(x + 18, y + 110), Vector2(box_width - 36, 56))
		elif sensor_status == "idle":
			result["sensor"] = Rect2(Vector2(x + 18, y + 110), Vector2(box_width - 36, 56))
	return result

func _hit(position: Vector2) -> String:
	var rects := _rects()
	for key in ["sensor", "calibrate", "fallback", "pause", "left", "right", "reverse", "gas"]:
		if rects.has(key) and (rects[key] as Rect2).has_point(position):
			if Session.control_mode == "tilt" and not calibrated and key in BUTTONS:
				continue
			if key in ["left", "right"] and Session.control_mode != "buttons":
				continue
			return key
	return ""

func _draw_controls() -> void:
	if Session.control_mode == "desktop" or pause_menu.overlay.visible:
		return
	if surface.size.y > surface.size.x:
		surface.draw_rect(Rect2(Vector2.ZERO, surface.size), PANEL, true)
		_draw_centered("Draai je telefoon horizontaal", surface.size * 0.5, 32, INK)
		return
	var rects := _rects()
	_draw_button(rects.pause, "Pauze", false, 19)
	_draw_centered("%d km/u" % shown_speed_kmh, Vector2(225, 48), 21, INK)
	if Session.control_mode == "buttons":
		_draw_button(rects.left, "Links", held.has("left"), 20)
		_draw_button(rects.right, "Rechts", held.has("right"), 20)
	else:
		_draw_centered("KANTEL OM TE STUREN", Vector2(surface.size.x * 0.5, surface.size.y - 40), 16, GOLD)
	_draw_button(rects.reverse, "Rem /\nachteruit", held.has("reverse"), 17)
	_draw_button(rects.gas, "Gas", held.has("gas"), 23)
	if Session.control_mode == "tilt" and not calibrated:
		var box := Rect2(Vector2((surface.size.x - minf(420.0, surface.size.x - 40.0)) * 0.5, (surface.size.y - 190.0) * 0.5), Vector2(minf(420.0, surface.size.x - 40.0), 190.0))
		surface.draw_rect(box, PANEL, true)
		var message := "Houd je telefoon prettig vast"
		if sensor_status == "waiting": message = "Wachten op bewegingssensor…"
		if sensor_status in ["denied", "unavailable", "lost"]: message = "Sensor niet beschikbaar"
		_draw_centered(message, Vector2(surface.size.x * 0.5, box.position.y + 45), 19, INK)
		if rects.has("sensor"): _draw_button(rects.sensor, "Sensor inschakelen", false, 19)
		if rects.has("calibrate"): _draw_button(rects.calibrate, "Stuur recht instellen", false, 19)
		if rects.has("fallback"): _draw_button(rects.fallback, "Gebruik stuurknoppen", false, 19)

func _draw_button(rect: Rect2, label: String, pressed: bool, font_size: int) -> void:
	surface.draw_rect(rect, GOLD if pressed else PANEL, true)
	surface.draw_rect(rect, GOLD, false, 2.0)
	var parts := label.split("\n")
	for i in range(parts.size()):
		_draw_centered(parts[i], Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + rect.size.y * 0.5 + (float(i) - float(parts.size() - 1) * 0.5) * 21.0), font_size, Color("#101c2a") if pressed else INK)

func _draw_centered(label: String, point: Vector2, font_size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	surface.draw_string(font, point - Vector2(text_size.x * 0.5, -text_size.y * 0.32), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _exit_tree() -> void:
	for key in held.keys():
		Input.action_release(_action(key))
	Session.tilt_steering = 0.0
	if auto_paused:
		get_tree().paused = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and surface != null:
		release_all()
