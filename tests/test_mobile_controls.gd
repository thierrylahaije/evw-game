extends SceneTree

const Main = preload("res://scenes/main.tscn")
const Session = preload("res://scripts/game_session.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func touch(index: int, position: Vector2, pressed: bool) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	return event

func run_checks() -> void:
	Session.control_mode = "buttons"
	var scene := Main.instantiate()
	root.add_child(scene)
	await process_frame
	var controls: CanvasLayer = scene.get_node("MobileControls")
	var rects: Dictionary = controls._rects()
	var left: Vector2 = (rects.left as Rect2).get_center()
	var gas: Vector2 = (rects.gas as Rect2).get_center()
	controls._input(touch(1, left, true))
	controls._input(touch(2, gas, true))
	check(Input.is_action_pressed("vehicle_left") and Input.is_action_pressed("vehicle_accelerate"), "Two fingers can steer and accelerate together")
	controls._input(touch(1, left, false))
	check(not Input.is_action_pressed("vehicle_left") and Input.is_action_pressed("vehicle_accelerate"), "Releasing steering keeps gas pressed")
	controls._input(touch(2, gas, true))
	controls._input(touch(2, gas, false))
	check(not Input.is_action_pressed("vehicle_accelerate"), "A reused touch index cannot leave the pedal pressed")
	controls._input(touch(2, gas, true))
	controls.change_mode("tilt")
	check(not Input.is_action_pressed("vehicle_accelerate"), "Switching controls releases pedals")
	check(Session.control_mode == "tilt", "Control method can change during a round")
	check(paused, "Tilt calibration pauses the whole game")
	var score: Node = scene.get_node("RoundScore")
	var elapsed_before: float = score.elapsed_seconds
	await process_frame
	await process_frame
	check(is_equal_approx(score.elapsed_seconds, elapsed_before), "The score timer stays stopped during calibration")
	controls.change_mode("buttons")
	check(not paused, "Button steering resumes the game")
	controls._input(touch(3, gas, true))
	controls.release_all()
	check(not Input.is_action_pressed("vehicle_accelerate"), "Pausing releases pedals")
	controls.surface.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	controls.surface.size = Vector2(390, 844)
	controls.sync_game_pause()
	check(paused, "Portrait orientation pauses the whole game")
	controls.surface.size = Vector2(844, 390)
	controls.sync_game_pause()
	check(not paused, "Landscape orientation resumes the game")
	controls.truck.linear_velocity = Vector3(0, 0, 10)
	controls._process(1.0 / 60.0)
	check(controls.shown_speed_kmh == 36, "Mobile speed display updates with vehicle speed")
	root.remove_child(scene)
	scene.queue_free()
	Session.control_mode = "desktop"
	print("MOBILE_CONTROLS_RESULT failures=%d" % failures)
	quit(1 if failures else 0)
