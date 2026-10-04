extends Node3D
## A road-following GPS ribbon for the current mission destination.

const LANE_OFFSET := 3.35
const JUNCTION_RADIUS := 14.0
const RIBBON_WIDTH := 0.95
const RIBBON_HEIGHT := 0.24
const REPLAN_DISTANCE := 18.0
const REPLAN_SECONDS := 1.0
const X_COORDS := [-320.0, -215.0, -50.0, 141.03, 420.0]
const Z_COORDS := [-300.0, -200.0, 33.35, 160.0, 300.0]

var mission: Node3D
var truck: VehicleBody3D
var junctions: Array[Vector2] = []
var neighbors: Array[Dictionary] = []
var ribbon: MeshInstance3D
var elapsed := 0.0
var last_position := Vector2(INF, INF)
var last_target := Vector2(INF, INF)
var last_stage := -1
var last_stop := -1
var current_route: Array[Vector2] = []

func configure(mission_node: Node3D, truck_node: VehicleBody3D) -> void:
	mission = mission_node
	truck = truck_node

func _ready() -> void:
	_build_road_graph()
	ribbon = MeshInstance3D.new()
	ribbon.name = "GPSRouteRibbon"
	ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(0.02, 0.83, 1.0, 0.82)
	material.emission_enabled = true
	material.emission = Color(0.02, 0.7, 1.0)
	material.emission_energy_multiplier = 1.5
	ribbon.material_override = material
	add_child(ribbon)
	_replan()

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < REPLAN_SECONDS:
		return
	elapsed = 0.0
	var position := Vector2(truck.global_position.x, truck.global_position.z)
	var target := Vector2(mission.marker.global_position.x, mission.marker.global_position.z)
	if mission.stage != last_stage or mission.stop_index != last_stop \
		or target.distance_to(last_target) > 0.1 \
		or position.distance_to(last_position) >= REPLAN_DISTANCE:
		_replan()

func refresh() -> void:
	_replan()

func _build_road_graph() -> void:
	for z in Z_COORDS:
		for x in X_COORDS:
			if x == -50.0 and z < 33.0:
				continue
			junctions.append(Vector2(x, z))
			neighbors.append({})
	for a in range(junctions.size()):
		for b in range(a + 1, junctions.size()):
			var first := junctions[a]
			var second := junctions[b]
			if is_equal_approx(first.y, second.y):
				if _no_junction_between(first, second, true):
					_connect(neighbors, a, b, first.distance_to(second))
			elif is_equal_approx(first.x, second.x):
				if _no_junction_between(first, second, false):
					_connect(neighbors, a, b, first.distance_to(second))

func _no_junction_between(a: Vector2, b: Vector2, horizontal: bool) -> bool:
	for point in junctions:
		if point == a or point == b:
			continue
		if horizontal and is_equal_approx(point.y, a.y) and point.x > a.x and point.x < b.x:
			return false
		if not horizontal and is_equal_approx(point.x, a.x) and point.y > a.y and point.y < b.y:
			return false
	return true

func _connect(graph: Array[Dictionary], a: int, b: int, distance: float) -> void:
	graph[a][b] = distance
	graph[b][a] = distance

func _nearest_segment(point: Vector2) -> Dictionary:
	var best := {"a": -1, "b": -1, "point": Vector2.ZERO, "distance": INF}
	for a in range(junctions.size()):
		for b in neighbors[a]:
			if b <= a:
				continue
			var start := junctions[a]
			var finish := junctions[b]
			var fraction := clampf((point - start).dot(finish - start) / start.distance_squared_to(finish), 0.0, 1.0)
			var projected := start.lerp(finish, fraction)
			var distance := point.distance_to(projected)
			if distance < best.distance:
				best = {"a": a, "b": b, "point": projected, "distance": distance}
	return best

func _road_path(start: Vector2, target: Vector2) -> Array[Vector2]:
	var from_edge := _nearest_segment(start)
	var to_edge := _nearest_segment(target)
	var source := junctions.size()
	var destination := source + 1
	var graph: Array[Dictionary] = []
	for linked in neighbors:
		graph.append(linked.duplicate())
	graph.append({})
	graph.append({})
	for endpoint in [from_edge.a, from_edge.b]:
		_connect(graph, source, endpoint, from_edge.point.distance_to(junctions[endpoint]))
	for endpoint in [to_edge.a, to_edge.b]:
		_connect(graph, destination, endpoint, to_edge.point.distance_to(junctions[endpoint]))
	if from_edge.a == to_edge.a and from_edge.b == to_edge.b:
		_connect(graph, source, destination, from_edge.point.distance_to(to_edge.point))
	var distances: Array[float] = []
	var previous: Array[int] = []
	var visited: Dictionary = {}
	for unused in range(graph.size()):
		distances.append(INF)
		previous.append(-1)
	distances[source] = 0.0
	for unused in range(graph.size()):
		var current := -1
		for index in range(graph.size()):
			if not visited.has(index) and (current == -1 or distances[index] < distances[current]):
				current = index
		if current == -1 or is_inf(distances[current]):
			break
		if current == destination:
			break
		visited[current] = true
		for adjacent in graph[current]:
			var option: float = distances[current] + graph[current][adjacent]
			if option < distances[adjacent]:
				distances[adjacent] = option
				previous[adjacent] = current
	var indices: Array[int] = []
	var current := destination
	while current != -1:
		indices.push_front(current)
		current = previous[current]
	var points: Array[Vector2] = []
	for index in indices:
		if index == source:
			points.append(from_edge.point)
		elif index == destination:
			points.append(to_edge.point)
		else:
			points.append(junctions[index])
	return points

func _right(direction: Vector2) -> Vector2:
	return Vector2(-direction.y, direction.x)

func _append_unique(points: Array[Vector2], point: Vector2) -> void:
	if points.is_empty() or points[-1].distance_to(point) > 0.05:
		points.append(point)

func _lane_path(road_points: Array[Vector2], start: Vector2, target: Vector2) -> Array[Vector2]:
	var points: Array[Vector2] = []
	if road_points.size() < 2:
		return points
	_append_unique(points, start)
	var first_direction := (road_points[1] - road_points[0]).normalized()
	_append_unique(points, road_points[0] + _right(first_direction) * LANE_OFFSET)
	for index in range(1, road_points.size() - 1):
		var center := road_points[index]
		var incoming := (center - road_points[index - 1]).normalized()
		var outgoing := (road_points[index + 1] - center).normalized()
		if incoming.is_zero_approx() or outgoing.is_zero_approx():
			continue
		var radius_in := minf(JUNCTION_RADIUS, center.distance_to(road_points[index - 1]) * 0.35)
		var radius_out := minf(JUNCTION_RADIUS, center.distance_to(road_points[index + 1]) * 0.35)
		var arrival := center - incoming * radius_in + _right(incoming) * LANE_OFFSET
		var departure := center + outgoing * radius_out + _right(outgoing) * LANE_OFFSET
		_append_unique(points, arrival)
		var junction_id := junctions.find(center)
		if junction_id >= 0 and neighbors[junction_id].size() == 4:
			var start_angle := atan2(arrival.y - center.y, arrival.x - center.x)
			var end_angle := atan2(departure.y - center.y, departure.x - center.x)
			var sweep := fposmod(start_angle - end_angle, TAU)
			var radius := arrival.distance_to(center)
			var steps := maxi(4, ceili(sweep / 0.12))
			for step in range(1, steps + 1):
				var angle := start_angle - sweep * float(step) / float(steps)
				_append_unique(points, center + Vector2(cos(angle), sin(angle)) * radius)
		else:
			var control_a := arrival + incoming * radius_in * 0.72
			var control_b := departure - outgoing * radius_out * 0.72
			for step in range(1, 9):
				var t := float(step) / 8.0
				var s := 1.0 - t
				_append_unique(points, arrival * s * s * s + control_a * 3.0 * s * s * t + control_b * 3.0 * s * t * t + departure * t * t * t)
	var last_direction := (road_points[-1] - road_points[-2]).normalized()
	_append_unique(points, road_points[-1] + _right(last_direction) * LANE_OFFSET)
	_append_unique(points, target)
	return points

func _replan() -> void:
	if mission == null or truck == null or mission.marker == null:
		return
	last_stage = mission.stage
	last_stop = mission.stop_index
	last_position = Vector2(truck.global_position.x, truck.global_position.z)
	last_target = Vector2(mission.marker.global_position.x, mission.marker.global_position.z)
	if mission.stage == mission.Stage.TO_DOCK or mission.stage == mission.Stage.LOADING \
		or mission.stage == mission.Stage.COMPLETE:
		ribbon.visible = false
		current_route.clear()
		return
	current_route = _lane_path(_road_path(last_position, last_target), last_position, last_target)
	ribbon.visible = true
	_draw_ribbon(current_route)

func _draw_ribbon(points: Array[Vector2]) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(points.size() - 1):
		var delta := points[index + 1] - points[index]
		if delta.length() < 0.1:
			continue
		var side := _right(delta.normalized()) * RIBBON_WIDTH * 0.5
		var a := points[index]
		var b := points[index + 1]
		var v0 := Vector3(a.x - side.x, RIBBON_HEIGHT, a.y - side.y)
		var v1 := Vector3(a.x + side.x, RIBBON_HEIGHT, a.y + side.y)
		var v2 := Vector3(b.x - side.x, RIBBON_HEIGHT, b.y - side.y)
		var v3 := Vector3(b.x + side.x, RIBBON_HEIGHT, b.y + side.y)
		for vertex in [v0, v1, v2, v2, v1, v3]:
			surface.add_vertex(vertex)
	ribbon.mesh = surface.commit()
