extends SceneTree

const Main = preload("res://scenes/main.tscn")
const Session = preload("res://scripts/game_session.gd")
const Rules = preload("res://scripts/traffic_rules.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func run_checks() -> void:
	Session.control_mode = "desktop"
	var scene := Main.instantiate()
	root.add_child(scene)
	await process_frame
	var views = scene.get_node("CameraViews")
	var chase: Camera3D = scene.get_node("ChaseCamera")
	check(chase.current and not views.cockpit, "Exterior camera remains the initial view")
	views.toggle_view()
	check(views.cockpit and views.cab.current and not chase.current, "Driver can switch to the cab")
	var truck: VehicleBody3D = scene.get_node("TruckModel")
	check((-views.cab.global_basis.z).dot(truck.global_basis.z) > 0.9, "Cab camera faces the driving direction")
	check(views.mirrors.size() == 2 and views.dashboard.visible, "Both live mirrors and dashboard appear in cab view")
	for mirror in views.mirrors:
		check(mirror.viewport.world_3d == scene.get_viewport().world_3d, "Mirror renders the game world")
	views.toggle_view()
	check(chase.current and not views.dashboard.visible, "Driver can return to exterior view")
	var rules = scene.get_node("TrafficRules")
	check(Rules.speed_limit_at(Vector2(0, -200)) == 50, "Southern road is a 50 zone")
	check(Rules.speed_limit_at(Vector2(0, 33)) == 30, "Depot road is a 30 zone")
	check(rules.checkpoints.size() >= 8, "Speed, stop and priority checkpoints exist")
	var camera: Dictionary = rules.checkpoints[0]
	var start: Vector2 = camera.point - camera.direction * 2.0
	var finish: Vector2 = camera.point + camera.direction * 2.0
	check(Rules._crossed(camera, start, finish), "Camera detects forward lane crossing")
	check(not Rules._crossed(camera, finish, start), "Camera ignores reverse crossing")
	check(not Rules._crossed(camera, start + Vector2(0, 9), finish + Vector2(0, 9)), "Camera ignores opposite lane")
	var score = scene.get_node("RoundScore")
	var before := Session.calculate_score(100, 0, 0)
	score.add_traffic_fine("Testboete")
	check(score.traffic_fines == 1 and score.fine_label.visible, "Traffic fine is visible once")
	check(Session.calculate_score(100, 0, 0, 0, score.traffic_fines) == before - Session.TRAFFIC_FINE_PENALTY,
		"Traffic fine reduces the final score")
	truck.global_basis = Basis.looking_at(Vector3(camera.direction.x, 0, camera.direction.y), Vector3.UP, true)
	var front_target: Vector2 = camera.point + camera.direction * 1.0
	truck.global_position = Vector3(front_target.x, 0, front_target.y) - truck.global_basis * Rules.FRONT_LOCAL
	truck.linear_velocity = truck.global_basis.z * 17.0
	rules.previous_front = camera.point - camera.direction * 1.0
	rules._physics_process(0.02)
	check(score.traffic_fines == 2, "Speed camera fines a truck above its posted limit")
	var stop: Dictionary = rules.checkpoints[3]
	truck.global_basis = Basis.looking_at(Vector3(stop.direction.x, 0, stop.direction.y), Vector3.UP, true)
	front_target = stop.point + stop.direction * 1.0
	truck.global_position = Vector3(front_target.x, 0, front_target.y) - truck.global_basis * Rules.FRONT_LOCAL
	truck.linear_velocity = truck.global_basis.z * 4.0
	rules.previous_front = stop.point - stop.direction * 1.0
	rules._physics_process(0.02)
	check(score.traffic_fines == 3, "Rolling through a stop sign adds a fine")
	var priority: Dictionary = rules.checkpoints[6]
	var car: Dictionary = scene.get_node("AmbientTraffic").cars[0]
	car.body.global_position = Vector3(priority.junction.x, 0, priority.junction.y)
	car.speed = 4.0
	truck.global_basis = Basis.looking_at(Vector3(priority.direction.x, 0, priority.direction.y), Vector3.UP, true)
	front_target = priority.point + priority.direction * 1.0
	truck.global_position = Vector3(front_target.x, 0, front_target.y) - truck.global_basis * Rules.FRONT_LOCAL
	truck.linear_velocity = truck.global_basis.z * 4.0
	rules.previous_front = priority.point - priority.direction * 1.0
	rules._physics_process(0.02)
	check(score.traffic_fines == 4, "Entering a roundabout in front of traffic adds a fine")
	check(scene.get_node("TruckModel").max_forward_kmh > 50.0, "Truck can exceed road limits")
	root.remove_child(scene)
	scene.queue_free()
	await process_frame
	print("CAMERA_TRAFFIC_RULES_RESULT failures=%d" % failures)
	quit(1 if failures else 0)
