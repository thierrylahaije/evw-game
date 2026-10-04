extends Node3D
## Lightweight ambient cars on the mapped right-hand lanes.

const ASSET_DIR := "res://assets/environment/cars/Models/GLB format/"
const MODELS := ["sedan", "hatchback-sports", "suv", "taxi", "van", "delivery", "sedan-sports"]
const LANE_OFFSET := 3.35
const JUNCTION_RADIUS := 14.0
const STOP_DISTANCE := 20.0
const MAX_SPEED := 8.0
const ACCELERATION := 2.0
const BRAKING := 4.5
const LOOP_CORNERS := [
	[Vector2(-320,-200),Vector2(-215,-200),Vector2(-215,33.35),Vector2(-320,33.35)],
	[Vector2(-215,-200),Vector2(141.03,-200),Vector2(141.03,33.35),Vector2(-50,33.35),Vector2(-215,33.35)],
	[Vector2(141.03,-200),Vector2(420,-200),Vector2(420,33.35),Vector2(141.03,33.35)],
	[Vector2(-320,33.35),Vector2(-215,33.35),Vector2(-215,160),Vector2(-320,160)],
	[Vector2(-215,33.35),Vector2(-50,33.35),Vector2(-50,160),Vector2(-215,160)],
	[Vector2(-50,33.35),Vector2(141.03,33.35),Vector2(141.03,160),Vector2(-50,160)],
	[Vector2(141.03,33.35),Vector2(420,33.35),Vector2(420,160),Vector2(141.03,160)],
	[Vector2(-215,160),Vector2(-50,160),Vector2(-50,300),Vector2(-215,300)],
	[Vector2(-50,160),Vector2(141.03,160),Vector2(141.03,300),Vector2(-50,300)]
]

var routes: Array[Dictionary] = []
var cars: Array[Dictionary] = []
var signals: Array[Node3D] = []
var degree: Dictionary = {}
var truck: VehicleBody3D
var trailer: RigidBody3D

func _ready() -> void:
	truck = get_parent().get_node("TruckModel")
	trailer = get_parent().get_node("TrailerModel")
	for child in get_parent().get_node("MapExpansion/StreetFurniture").get_children():
		if child.name.begins_with("TrafficSignal_"):
			signals.append(child)
	_build_degrees()
	for corners in LOOP_CORNERS:
		routes.append(_make_route(corners))
	for i in range(12):
		var route_id := i % routes.size()
		var phase := fposmod(0.13 + float(i) * 0.173 + (0.43 if i >= routes.size() else 0.0),1.0)
		_spawn_car(i,route_id,phase)

func _build_degrees() -> void:
	var xs := [-320.0,-215.0,141.03,420.0]
	var zs := [-300.0,-200.0,33.35,160.0,300.0]
	for z in zs:
		var row := xs.duplicate()
		if z >= 33.0: row.insert(2,-50.0)
		for i in range(row.size()-1): _edge_degree(Vector2(row[i],z),Vector2(row[i+1],z))
	for x in xs:
		for i in range(zs.size()-1): _edge_degree(Vector2(x,zs[i]),Vector2(x,zs[i+1]))
	_edge_degree(Vector2(-50,33.35),Vector2(-50,160))
	_edge_degree(Vector2(-50,160),Vector2(-50,300))

func _edge_degree(a: Vector2,b: Vector2) -> void:
	degree[a] = degree.get(a,0) + 1
	degree[b] = degree.get(b,0) + 1

func _right(direction: Vector2) -> Vector2:
	return Vector2(-direction.y,direction.x)

func _signal_for(junction: Vector2, incoming: Vector2) -> Node3D:
	var expected := junction - incoming * 12.0 + _right(incoming) * 8.7
	for signal_node in signals:
		var position_2d := Vector2(signal_node.global_position.x,signal_node.global_position.z)
		if position_2d.distance_to(expected) < 2.0:
			return signal_node
	return null

func _append(route: Dictionary, point: Vector2, speed_limit: float) -> void:
	var points: Array = route.points
	if points.is_empty():
		points.append(point)
		route.distances.append(0.0)
		route.limits.append(speed_limit)
		return
	var distance: float = points[-1].distance_to(point)
	if distance < 0.01: return
	points.append(point)
	route.distances.append(route.distances[-1] + distance)
	route.limits.append(speed_limit)

func _make_route(raw_corners: Array) -> Dictionary:
	var corners := raw_corners.duplicate()
	var route: Dictionary = {"points":[],"distances":[],"limits":[],"stops":[],"length":0.0}
	var count := corners.size()
	for i in range(count):
		var before: Vector2 = corners[(i-1+count)%count]
		var node: Vector2 = corners[i]
		var after: Vector2 = corners[(i+1)%count]
		var incoming := (node-before).normalized()
		var outgoing := (after-node).normalized()
		var arrival := node-incoming*JUNCTION_RADIUS+_right(incoming)*LANE_OFFSET
		var departure := node+outgoing*JUNCTION_RADIUS+_right(outgoing)*LANE_OFFSET
		_append(route,arrival,MAX_SPEED)
		if degree.get(node,0) == 4:
			# Dutch roundabout circulation: around the island, never through it.
			var start_angle := atan2(arrival.y-node.y,arrival.x-node.x)
			var end_angle := atan2(departure.y-node.y,departure.x-node.x)
			var sweep := fposmod(start_angle-end_angle,TAU)
			var steps := maxi(4,ceili(sweep/0.12))
			var radius := arrival.distance_to(node)
			for step in range(1,steps+1):
				var angle := start_angle-sweep*float(step)/float(steps)
				_append(route,node+Vector2(cos(angle),sin(angle))*radius,4.8)
		else:
			var control_a := arrival+incoming*JUNCTION_RADIUS*0.72
			var control_b := departure-outgoing*JUNCTION_RADIUS*0.72
			for step in range(1,9):
				var t := float(step)/8.0
				var s := 1.0-t
				var point := arrival*s*s*s+control_a*3.0*s*s*t+control_b*3.0*s*t*t+departure*t*t*t
				_append(route,point,5.2)
		var next: Vector2 = after
		var next_incoming := outgoing
		var next_arrival := next-next_incoming*JUNCTION_RADIUS+_right(next_incoming)*LANE_OFFSET
		var signal_node := _signal_for(next,next_incoming)
		if signal_node != null:
			var stop_point := next-next_incoming*STOP_DISTANCE+_right(next_incoming)*LANE_OFFSET
			_append(route,stop_point,MAX_SPEED)
			route.stops.append({"distance":route.distances[-1],"signal":signal_node})
		_append(route,next_arrival,MAX_SPEED)
	route.length = route.distances[-1]
	return route

func _pose(route: Dictionary, progress: float) -> Dictionary:
	var distances: Array = route.distances
	var points: Array = route.points
	var s := fposmod(progress,route.length)
	var index := 1
	while index < distances.size()-1 and distances[index] < s:
		index += 1
	var segment: Vector2 = points[index]-points[index-1]
	var fraction: float = (s-distances[index-1])/maxf(distances[index]-distances[index-1],0.001)
	return {"point":points[index-1].lerp(points[index],fraction),"direction":segment.normalized(),"limit":route.limits[index]}

func _spawn_car(index: int,route_index: int,phase: float) -> void:
	var route: Dictionary = routes[route_index]
	var body := AnimatableBody3D.new()
	body.name = "TrafficCar_%02d" % index
	body.collision_layer = 1
	body.collision_mask = 0
	body.sync_to_physics = false
	add_child(body)
	var model: Node3D = load(ASSET_DIR+MODELS[index%MODELS.size()]+".glb").instantiate()
	model.name = "CarVisual"
	model.scale = Vector3.ONE*1.2
	body.add_child(model)
	var shape := CollisionShape3D.new()
	shape.name = "CarCollision"
	var box := BoxShape3D.new()
	box.size = Vector3(1.85,1.65,3.4)
	shape.shape = box
	shape.position = Vector3(0,0.83,-0.05)
	body.add_child(shape)
	var wheels: Array[Node3D] = []
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		if mesh.name.begins_with("wheel-"):
			wheels.append(mesh)
	var car := {"body":body,"route":route,"progress":phase*route.length,"speed":0.0,"cruise":7.0+float(index%4)*0.4,"wheels":wheels}
	cars.append(car)
	_place_car(car)

func _place_car(car: Dictionary) -> void:
	var pose := _pose(car.route,car.progress)
	var p: Vector2 = pose.point
	var direction: Vector2 = pose.direction
	var body: AnimatableBody3D = car.body
	body.position = Vector3(p.x,0.08,p.y)
	body.rotation.y = atan2(direction.x,direction.y)

func _red_distance(car: Dictionary) -> float:
	var route: Dictionary = car.route
	var nearest := INF
	for stop in route.stops:
		var state: String = stop.signal.get_meta("signal_state","red")
		if state == "green": continue
		var distance := fposmod(float(stop.distance)-float(car.progress),float(route.length))
		if distance < nearest: nearest = distance
	return nearest

func _blocked_by_vehicle(car: Dictionary) -> bool:
	var pose := _pose(car.route,car.progress)
	var point: Vector2 = pose.point
	var forward: Vector2 = pose.direction
	var obstacles: Array[Vector2] = [Vector2(truck.global_position.x,truck.global_position.z)]
	var trailer_center: Vector3 = trailer.to_global(Vector3(0,0,-4.0))
	obstacles.append(Vector2(trailer_center.x,trailer_center.z))
	for other in cars:
		if other == car: continue
		var p: Vector3 = other.body.global_position
		obstacles.append(Vector2(p.x,p.z))
	for obstacle in obstacles:
		var offset := obstacle-point
		var ahead := offset.dot(forward)
		if ahead > 0.0 and ahead < 8.0 and absf(offset.cross(forward)) < 3.2:
			return true
	return false

func _physics_process(delta: float) -> void:
	for car in cars:
		var pose := _pose(car.route,car.progress)
		var target_speed: float = minf(car.cruise,pose.limit)
		var red_distance := _red_distance(car)
		if red_distance < 40.0:
			target_speed = minf(target_speed,sqrt(maxf(0.0,2.0*BRAKING*(red_distance-0.5))))
		if _blocked_by_vehicle(car): target_speed = 0.0
		car.speed = move_toward(float(car.speed),target_speed,(ACCELERATION if target_speed > car.speed else BRAKING)*delta)
		var travel: float = car.speed*delta
		if red_distance < INF and travel >= red_distance-0.5:
			travel = maxf(0.0,red_distance-0.5)
			car.speed = 0.0
		car.progress = fposmod(float(car.progress)+travel,float(car.route.length))
		_place_car(car)
		for wheel in car.wheels:
			wheel.rotate_x(-travel/0.36)
