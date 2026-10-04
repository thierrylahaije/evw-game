extends SceneTree
## Automated walkthrough of all mission states, docking, scoring and road distances.

const Main = preload("res://scenes/main.tscn")
const Session = preload("res://scripts/game_session.gd")
var failures := 0
var lengths: Array[float] = []

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func path_length(guidance: Node3D, from: Vector2, to: Vector2) -> float:
	var path: Array[Vector2] = guidance._lane_path(guidance._road_path(from, to), from, to)
	check(path.size() >= 2, "Road path exists")
	var total := 0.0
	for index in range(path.size() - 1):
		total += path[index].distance_to(path[index + 1])
	return total

func run_checks() -> void:
	var temp_dir := OS.get_environment("EVW_TEST_TMP_DIR")
	if temp_dir.is_empty():
		temp_dir = OS.get_user_data_dir()
	Session.score_file = temp_dir.path_join("evw-final-routes-%d.json" % OS.get_process_id())
	for route_id in range(3):
		Session.set_player_name("Route Test %d" % (route_id + 1))
		var scene := Main.instantiate()
		var mission = scene.get_node("MissionController")
		mission.forced_route_index = route_id
		var tracker = scene.get_node("RoundScore")
		tracker.return_to_menu = false
		root.add_child(scene)
		await process_frame
		var dock = scene.get_node("DockLoading")
		var truck: VehicleBody3D = scene.get_node("TruckModel")
		var trailer: RigidBody3D = scene.get_node("TrailerModel")
		var selected: Dictionary = dock.docks[1]
		var target: Vector3 = selected.warehouse.to_global(selected.point)
		target.y = selected.warehouse.to_global(Vector3(selected.point.x, 0, selected.point.z)).y
		var outward: Vector3 = selected.warehouse.global_basis.z.normalized()
		var dock_basis := Basis.looking_at(outward, Vector3.UP, true)
		var dock_origin: Vector3 = target - dock_basis * dock.rear_local
		dock_origin.y = target.y
		var dock_transform := Transform3D(dock_basis, dock_origin)
		var points: Array[Vector2] = [Vector2(target.x, target.z)]
		for stop in mission.route.stops:
			points.append(Vector2(stop.rear.x, stop.rear.z))
		points.append(points[0])
		var distance := 0.0
		check(mission.route.stops.size() == 2, "Route %d has two deliveries" % (route_id + 1))
		for index in range(points.size() - 1):
			distance += path_length(mission.route_guidance, points[index], points[index + 1])
		lengths.append(distance)
		check(absf(distance - 2000.0) < 80.0, "Route %d has comparable road distance" % (route_id + 1))
		trailer.global_transform = dock_transform
		trailer.linear_velocity = Vector3.ZERO
		trailer.angular_velocity = Vector3.ZERO
		truck.linear_velocity = Vector3.ZERO
		check(dock._geometry_matches(selected), "Pickup dock geometry matches route %d" % (route_id + 1))
		dock._physics_process(dock.settle_seconds + 0.1)
		check(mission.stage == mission.Stage.LOADING, "Pickup starts loading")
		dock._physics_process(dock.door_seconds)
		dock._physics_process(dock.loading_seconds)
		check(mission.stage == mission.Stage.DELIVERING, "Pickup completes")
		for stop_id in range(mission.route.stops.size()):
			var stop: Dictionary = mission.route.stops[stop_id]
			var basis := Basis.looking_at(stop.outward, Vector3.UP, true)
			trailer.global_transform = Transform3D(basis, stop.rear - basis * dock.rear_local)
			trailer.linear_velocity = Vector3.ZERO
			trailer.angular_velocity = Vector3.ZERO
			truck.linear_velocity = Vector3.ZERO
			check(mission._trailer_at_stop(stop), "Trailer rear reaches stop %d on route %d" % [stop_id + 1, route_id + 1])
			if stop_id == 0:
				dock._physics_process(0.1) # Release pickup dock before returning.
			mission._physics_process(mission.UNLOAD_SECONDS)
			check(mission.stop_index == stop_id + 1, "Delivery %d recorded" % (stop_id + 1))
		check(mission.stage == mission.Stage.RETURNING, "Two deliveries lead back to warehouse")
		var fitted_shape: BoxShape3D = scene.get_node("MapExpansion/Buildings/" + mission.route.stops[0].building + "/BuildingCollision").get_child(0).shape
		check(fitted_shape.size.x < 2.5 and fitted_shape.size.z < 2.5, "Building collision was fitted")
		tracker.previous_speed[truck.get_instance_id()] = 2.0
		var building: StaticBody3D = scene.get_node("MapExpansion/Buildings/" + mission.route.stops[0].building + "/BuildingCollision")
		tracker._on_body_entered(building, truck)
		tracker._on_body_entered(building, trailer)
		check(tracker.building_hits == 1, "One building impact counted once")
		var car: AnimatableBody3D = scene.get_node("AmbientTraffic").cars[0].body
		tracker._on_body_entered(car, truck)
		check(tracker.car_hits == 1, "Car impact counted")
		tracker.red_light_hits = 1 # Crossing detection has its own geometry test.
		tracker.elapsed_seconds = 180.0 + float(route_id) * 10.0
		trailer.global_transform = dock_transform
		trailer.linear_velocity = Vector3.ZERO
		trailer.angular_velocity = Vector3.ZERO
		truck.linear_velocity = Vector3.ZERO
		check(dock._geometry_matches(selected), "Return dock geometry matches route %d" % (route_id + 1))
		dock._physics_process(dock.settle_seconds + 0.1)
		check(mission.stage == mission.Stage.COMPLETE and tracker.finished, "Route %d ends at return dock" % (route_id + 1))
		var saved := Session.load_scores()
		check(saved.size() == route_id + 1, "Route %d persisted locally" % (route_id + 1))
		check(Session.pending_result.score == Session.calculate_score(tracker.elapsed_seconds, 1, 1, 1), "Route %d score includes all penalties" % (route_id + 1))
		root.remove_child(scene)
		scene.queue_free()
		await process_frame
	var minimum := minf(lengths[0], minf(lengths[1], lengths[2]))
	var maximum := maxf(lengths[0], maxf(lengths[1], lengths[2]))
	check((maximum - minimum) / minimum < 0.02, "Three route distances differ by less than 2%")
	DirAccess.remove_absolute(Session.score_file)
	print("FINAL_ROUTES_RESULT failures=%d lengths=%s" % [failures, str(lengths)])
	quit(1 if failures else 0)
