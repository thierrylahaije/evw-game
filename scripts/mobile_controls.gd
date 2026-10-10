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
var sensor_status := "idle"
var sensor_detail := ""
var calibrated := false
var pause_menu: CanvasLayer
var truck: VehicleBody3D
var last_touch_at: int = -10000
var auto_paused := false
var shown_speed_kmh := 0
var sensor_button_visible := false
var sensor_button_status := ""
var sensor_button_size := Vector2.ZERO
var browser_controls_signature := ""

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
		var current: String = str(status_value) if status_value != null else "bridge_missing"
		var detail_value: Variant = _sensor_call("detail()")
		var current_detail: String = str(detail_value) if detail_value != null else ""
		if current != sensor_status:
			sensor_status = current
			if current in ["lost", "denied", "insecure", "unsupported", "activation", "blocked", "permission_error", "permission_timeout", "no_data", "bridge_missing"]:
				calibrated = false
			surface.queue_redraw()
		if current_detail != sensor_detail:
			sensor_detail = current_detail
			surface.queue_redraw()
	_update_sensor_button()
	_update_browser_controls()
	_sync_browser_controls()
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

func _update_browser_controls() -> void:
	if not OS.has_feature("web"):
		return
	var keys: Array[String] = []
	if Session.control_mode != "desktop" and not pause_menu.overlay.visible and surface.size.x >= surface.size.y:
		keys.append("pause")
		if Session.control_mode == "buttons":
			keys.append_array(BUTTONS)
		elif calibrated:
			keys.append_array(["reverse", "gas"])
		elif sensor_status == "ready":
			keys.append("calibrate")
		else:
			keys.append("fallback")
	var signature := "%s|%s|%s" % [",".join(keys), surface.size, sensor_status if Session.control_mode == "tilt" else ""]
	if signature == browser_controls_signature:
		return
	browser_controls_signature = signature
	_browser_input_call("hideAll()")
	if keys.is_empty():
		return
	var rects := _rects()
	for key in keys:
		var rect: Rect2 = rects[key]
		_browser_input_call("setButton('%s',%f,%f,%f,%f)" % [key, rect.position.x / surface.size.x, rect.position.y / surface.size.y, rect.size.x / surface.size.x, rect.size.y / surface.size.y])

func _sync_browser_controls() -> void:
	if not OS.has_feature("web"):
		return
	for key in BUTTONS:
		var pressed: bool = _browser_input_call("pressed('%s')" % key) == 1
		if pressed and not held.has(key):
			held[key] = 1
			Input.action_press(_action(key))
			surface.queue_redraw()
		elif not pressed and held.has(key):
			held.erase(key)
			Input.action_release(_action(key))
			surface.queue_redraw()
	var command: Variant = _browser_input_call("takeCommand()")
	if command != null and str(command) != "":
		_activate(str(command))

func _update_sensor_button() -> void:
	if not OS.has_feature("web"):
		return
	var show_button: bool = Session.control_mode == "tilt" and not calibrated and not pause_menu.overlay.visible and surface.size.x >= surface.size.y and sensor_status in ["idle", "insecure", "unsupported", "denied", "activation", "blocked", "permission_error", "permission_timeout", "no_data", "lost", "bridge_missing"]
	if not show_button:
		if sensor_button_visible:
			_sensor_call("hideRequest()")
			sensor_button_visible = false
		return
	var rect: Rect2 = _rects()["sensor"]
	var size := surface.size
	if sensor_button_visible and sensor_button_status == sensor_status and sensor_button_size == size:
		return
	_sensor_call("showRequest(%f,%f,%f,%f)" % [rect.position.x / size.x, rect.position.y / size.y, rect.size.x / size.x, rect.size.y / size.y])
	sensor_button_visible = true
	sensor_button_status = sensor_status
	sensor_button_size = size

func sync_game_pause() -> void:
	var needs_pause := Session.control_mode != "desktop" and (surface.size.y > surface.size.x or (Session.control_mode == "tilt" and not calibrated))
	if needs_pause != auto_paused:
		auto_paused = needs_pause
		surface.queue_redraw()
	if not pause_menu.overlay.visible:
		get_tree().paused = auto_paused

func _input(event: InputEvent) -> void:
	if OS.has_feature("web"):
		return
	if Session.control_mode == "desktop" or pause_menu.overlay.visible:
		return
	if surface.size.y > surface.size.x:
		return
	if event is InputEventScreenTouch:
		last_touch_at = Time.get_ticks_msec()
		if event.pressed:
			_release_finger(event.index)
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
			_release_finger(-1)
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
	if OS.has_feature("web"):
		_browser_input_call("hideAll()")
		browser_controls_signature = ""
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
	else:
		_sensor_call("hideRequest()")
		sensor_button_visible = false
	sync_game_pause()
	surface.queue_redraw()

func calibrate() -> void:
	if Session.control_mode != "tilt":
		return
	calibrated = _sensor_call("calibrate()") == 1
	Session.tilt_steering = 0.0
	sync_game_pause()
	surface.queue_redraw()

func _sensor_reset() -> void:
	calibrated = false
	sensor_status = "idle"
	sensor_detail = ""
	_sensor_call("reset()")

func _sensor_call(method: String) -> Variant:
	if not OS.has_feature("web"):
		return null
	return JavaScriptBridge.eval("window.EVW_TILT ? window.EVW_TILT." + method + " : null")

func _browser_input_call(method: String) -> Variant:
	if not OS.has_feature("web"):
		return null
	return JavaScriptBridge.eval("window.EVW_INPUT ? window.EVW_INPUT." + method + " : null")

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
		var box_width := minf(480.0, size.x - 40.0)
		var x := (size.x - box_width) * 0.5
		var y := (size.y - 270.0) * 0.5
		if sensor_status == "ready":
			result["calibrate"] = Rect2(Vector2(x + 18, y + 162), Vector2(box_width - 36, 52))
		else:
			result["sensor"] = Rect2(Vector2(x + 18, y + 152), Vector2(box_width - 36, 48))
			result["fallback"] = Rect2(Vector2(x + 18, y + 210), Vector2(box_width - 36, 48))
	return result

func _hit(position: Vector2) -> String:
	var rects := _rects()
	for key in ["calibrate", "fallback", "pause", "left", "right", "reverse", "gas"]:
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
		var box := Rect2(Vector2((surface.size.x - minf(480.0, surface.size.x - 40.0)) * 0.5, (surface.size.y - 270.0) * 0.5), Vector2(minf(480.0, surface.size.x - 40.0), 270.0))
		surface.draw_rect(box, PANEL, true)
		var message := _sensor_message()
		_draw_centered(message, Vector2(surface.size.x * 0.5, box.position.y + 65), 18, INK)
		if not sensor_detail.is_empty():
			_draw_centered("Fout: " + sensor_detail, Vector2(surface.size.x * 0.5, box.position.y + 100), 15, GOLD)
		if rects.has("calibrate"): _draw_button(rects.calibrate, "Stuur recht instellen", false, 19)
		if rects.has("fallback"): _draw_button(rects.fallback, "Gebruik stuurknoppen", false, 19)

func _sensor_message() -> String:
	match sensor_status:
		"idle": return "Houd je telefoon prettig vast"
		"requesting": return "Wachten op toestemming…"
		"waiting": return "Wachten op sensorgegevens…"
		"ready": return "Sensor werkt. Stel het stuur recht in."
		"insecure": return "Sensor vereist een HTTPS-verbinding"
		"unsupported": return "Deze browser biedt geen bewegingssensor"
		"denied": return "Sensortoegang is geweigerd"
		"activation": return "Toestemming vereist een directe tik"
		"blocked": return "Browser blokkeert sensortoegang"
		"permission_error": return "Sensoraanvraag is mislukt"
		"permission_timeout": return "Geen antwoord op toestemmingsvraag"
		"no_data": return "Geen sensorgegevens ontvangen"
		"lost": return "Sensorverbinding onderbroken"
		_: return "Sensorcode is niet geladen"

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
	_sensor_call("hideRequest()")
	_browser_input_call("hideAll()")
	for key in held.keys():
		Input.action_release(_action(key))
	Session.tilt_steering = 0.0
	if auto_paused:
		get_tree().paused = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and surface != null:
		release_all()
