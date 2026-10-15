extends SceneTree

const Main = preload("res://scenes/main.tscn")
const Session = preload("res://scripts/game_session.gd")
const Prank = preload("res://scripts/charging_pole_prank.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func drive_until_first_pole(prank: Node, mission: Node3D, truck: VehicleBody3D) -> bool:
	var route: Array[Vector2] = mission.route_guidance.current_route.duplicate()
	for index in range(route.size() - 1):
		var segment := route[index + 1] - route[index]
		if segment.length() < 45.0 or not Prank._is_road_lane(route[index], route[index + 1]):
			continue
		var direction := segment.normalized()
		for meters in range(10, int(segment.length()) - 20, 10):
			var point := route[index] + direction * float(meters)
			truck.global_position = Vector3(point.x, 0.0, point.y)
			truck.global_basis = Basis.looking_at(Vector3(direction.x, 0, direction.y), Vector3.UP, true)
			truck.linear_velocity = truck.global_basis.z * 6.0
			prank.next_attempt_at = 0.0
			prank._process(0.1)
			if is_instance_valid(prank.active_pole):
				return true
	return false

func run_checks() -> void:
	for name in ["Ab", "_Ab", "Ab_", "mijn_AB_test", "cab"]:
		check(Session.charging_pole_prank_enabled(name), "Name %s enables the prank" % name)
	for name in ["", "Jan", "Bert", "a b"]:
		check(not Session.charging_pole_prank_enabled(name), "Name %s leaves the prank off" % name)
	var straight: Array[Vector2] = [Vector2(0, 36.70), Vector2(200, 36.70)]
	var windows: Array[Dictionary] = Prank.candidate_windows(straight)
	check(windows.size() == 1, "A long straight lane has a safe spawn window")
	if not windows.is_empty():
		check(float(windows[0].first) >= 18.0 and float(windows[0].last) <= 26.0, "Pole pops up close ahead")
	var junction: Array[Vector2] = [Vector2(0, 36.70), Vector2(24, 36.70), Vector2(24, 80)]
	check(Prank.candidate_windows(junction).is_empty(), "Short junction segments are excluded")
	var off_road: Array[Vector2] = [Vector2(0, 50), Vector2(200, 50)]
	check(Prank.candidate_windows(off_road).is_empty(), "Off-road locations are excluded")
	var vertical: Array[Vector2] = [Vector2(-46.65, 0), Vector2(-46.65, 200)]
	check(Prank.candidate_windows(vertical).size() == 1, "A north-south road also has a spawn window")

	Session.set_player_name("Jan")
	var ordinary := Main.instantiate()
	root.add_child(ordinary)
	await process_frame
	check(not ordinary.get_node("ChargingPolePrank").enabled_for_player, "Other players never spawn poles")
	root.remove_child(ordinary)
	ordinary.queue_free()
	await process_frame

	Session.set_player_name("Ab")
	var scene := Main.instantiate()
	root.add_child(scene)
	await process_frame
	var prank = scene.get_node("ChargingPolePrank")
	var score = scene.get_node("RoundScore")
	check(prank.enabled_for_player, "Ab enables the prank on desktop")
	var mission = scene.get_node("MissionController")
	mission.stage = mission.Stage.DELIVERING
	mission._show_delivery_marker()
	mission.route_guidance.refresh()
	prank.next_attempt_at = 0.0
	prank._process(0.1)
	check(prank.active_pole == null, "A stationary truck never gets a sudden obstacle")
	var truck: VehicleBody3D = scene.get_node("TruckModel")
	check(drive_until_first_pole(prank, mission, truck), "The first pole appears while driving to the first address")
	check(prank.spawned_count == 1 and mission.stop_index == 0, "The first pole arrives before the first delivery")
	if is_instance_valid(prank.active_pole):
		var offset := Vector2(prank.active_pole.global_position.x - truck.global_position.x,
			prank.active_pole.global_position.z - truck.global_position.z)
		var forward := Vector2(truck.global_basis.z.x, truck.global_basis.z.z).normalized()
		check(offset.length() >= 15.0 and offset.length() <= 28.0, "The obstacle appears only a short distance ahead")
		check(offset.normalized().dot(forward) > 0.65, "The obstacle appears in front of the moving truck")
	prank._remove_pole()
	prank.spawned_count = 0
	var before := Session.calculate_score(60.0, score.building_hits, score.car_hits)
	prank._spawn_pole(Vector2(-100, 36.70), Vector2(1, 0))
	check(is_instance_valid(prank.active_pole), "Pole has a physical node")
	check(prank.active_pole.get_child_count() > 10, "Pole includes the charger body and cable")
	prank._on_vehicle_contact(prank.active_pole)
	check(prank.active_pole == null and prank.message_panel.visible, "Truck impact shows the joke and clears the obstacle")
	prank.next_attempt_at = INF
	prank._process(3.1)
	check(not prank.message_panel.visible, "The joke message clears after a short time")
	prank._spawn_pole(Vector2(-90, 36.70), Vector2(1, 0))
	prank._on_vehicle_contact(prank.active_pole)
	check(prank.active_pole == null, "Trailer impact also clears the obstacle")
	for extra in range(3):
		prank._spawn_pole(Vector2(-80 + extra * 10, 36.70), Vector2(1, 0))
		check(is_instance_valid(prank.active_pole), "Pole %d can still spawn" % (extra + 3))
		prank._remove_pole()
		await process_frame
	prank._spawn_pole(Vector2(-40, 36.70), Vector2(1, 0))
	check(prank.spawned_count == 5, "At most five poles may spawn per round")
	check(prank.active_pole == null, "A sixth pole cannot be added")
	check(score.building_hits == 0 and score.car_hits == 0, "Prank impacts do not count as normal damage")
	check(Session.calculate_score(60.0, score.building_hits, score.car_hits) == before, "Prank leaves the leaderboard score alone")
	root.remove_child(scene)
	scene.queue_free()
	await process_frame
	for route_id in range(3):
		var route_scene := Main.instantiate()
		var route_mission = route_scene.get_node("MissionController")
		route_mission.forced_route_index = route_id
		root.add_child(route_scene)
		await process_frame
		route_mission.stage = route_mission.Stage.DELIVERING
		route_mission._show_delivery_marker()
		route_mission.route_guidance.refresh()
		var route_prank = route_scene.get_node("ChargingPolePrank")
		var route_truck: VehicleBody3D = route_scene.get_node("TruckModel")
		check(drive_until_first_pole(route_prank, route_mission, route_truck) and route_mission.stop_index == 0, "Route %d gets its first pole before its first address" % (route_id + 1))
		root.remove_child(route_scene)
		route_scene.queue_free()
		await process_frame
	Session.player_name = ""
	print("CHARGING_POLE_PRANK_RESULT failures=%d" % failures)
	quit(1 if failures else 0)
