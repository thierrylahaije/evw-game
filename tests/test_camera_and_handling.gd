extends SceneTree
## Focused checks for the camera's wall avoidance and the truck input ramp.

const Main = preload("res://scenes/main.tscn")
const Truck = preload("res://scripts/truck_controller.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func run_checks() -> void:
	var truck := Truck.new()
	root.add_child(truck)
	Input.action_press("vehicle_accelerate")
	truck._physics_process(1.0 / 60.0)
	var first_force := truck.engine_force
	for i in range(30):
		truck._physics_process(1.0 / 60.0)
	check(first_force > 0.0 and first_force < truck.forward_force * 0.1, "Throttle starts gently")
	check(truck.engine_force > first_force * 4.0, "Throttle increases smoothly")
	Input.action_release("vehicle_accelerate")
	truck._physics_process(1.0 / 60.0)
	check(truck.engine_force == 0.0, "Releasing throttle cuts drive force")
	Input.action_press("vehicle_brake")
	truck._physics_process(1.0 / 60.0)
	check(truck.engine_force < 0.0 and absf(truck.engine_force) < truck.reverse_force * 0.1, "Reverse starts gently")
	Input.action_release("vehicle_brake")
	root.remove_child(truck)
	truck.queue_free()

	var scene := Main.instantiate()
	root.add_child(scene)
	await physics_frame
	var camera: Camera3D = scene.get_node("ChaseCamera")
	var desired_offset: Vector3 = Basis(Vector3.UP, camera.orbit_angle) * camera.follow_offset
	var obstacle := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 4)
	shape.shape = box
	obstacle.add_child(shape)
	scene.add_child(obstacle)
	obstacle.global_position = camera.smoothed_aim + desired_offset.normalized() * 6.0
	await physics_frame
	camera._place_camera(0.5)
	check(camera.camera_distance < 8.0, "Camera moves in front of an obstructing wall")
	check(camera.global_position.distance_to(camera.smoothed_aim) < 8.0, "Camera stays visible-side of the wall")
	root.remove_child(scene)
	scene.queue_free()
	print("CAMERA_HANDLING_RESULT failures=%d" % failures)
	quit(1 if failures else 0)
