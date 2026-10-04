extends Node
## One visual-only controller; no forces, physics-node edits, or extra raycasts.
## Local +X is the verified axle; positive spin rolls toward local +Z.
const RADIUS: float = 0.60
const STOP_EPSILON: float = 0.06 # m/s (0.22 km/h); suppress solver micro-rocking at rest.
var wheels: Array[Dictionary] = []
var initialized: bool = false
var grouping_max_world_error: float = 0.0
var tractor: VehicleBody3D
var trailer: RigidBody3D

func _ready() -> void:
	process_physics_priority = 100
	set_physics_process(false)

func setup(manifest: Array, tractor_body: VehicleBody3D, trailer_body: RigidBody3D) -> void:
	tractor = tractor_body
	trailer = trailer_body
	var seen: Dictionary = {}
	# Resolve the complete exact manifest before changing any parents.
	if manifest.size() != 10:
		push_error("Expected ten visual wheel groups.")
		return
	for spec in manifest:
		var body: RigidBody3D = tractor if spec["assembly"] == "tractor" else trailer
		var visuals: Node3D = body.get_node("VisualModel" if body == tractor else "TrailerVisuals")
		if spec["mesh_paths"].size() != 17 or not body.has_node(spec["physics_node"]):
			push_error("Invalid wheel assembly: " + spec["name"])
			return
		for path in spec["mesh_paths"]:
			if seen.has(path) or not visuals.get_node_or_null(path) is MeshInstance3D:
				push_error("Missing or duplicate wheel mesh: " + path)
				return
			seen[path] = true
	for spec in manifest:
		var body: RigidBody3D = tractor if spec["assembly"] == "tractor" else trailer
		var visuals: Node3D = body.get_node("VisualModel" if body == tractor else "TrailerVisuals")
		var assembly := Node3D.new()
		assembly.name = spec["name"]
		body.add_child(assembly)
		var center: Array = spec["center"]
		# Manifest centers use imported-model coordinates, not the recentered body.
		assembly.position = body.to_local(visuals.to_global(Vector3(center[0], center[1], center[2])))
		var steer := Node3D.new()
		steer.name = "SteeringPivot"
		assembly.add_child(steer)
		var rolling := Node3D.new()
		rolling.name = "RollingPivot"
		steer.add_child(rolling)
		for path in spec["mesh_paths"]:
			var mesh: MeshInstance3D = visuals.get_node(path)
			var before := mesh.global_transform
			mesh.reparent(rolling, true)
			grouping_max_world_error = maxf(grouping_max_world_error, mesh.global_position.distance_to(before.origin))
			assert(mesh.global_transform.is_equal_approx(before), "Wheel reparent changed world transform: " + path)
		wheels.append({"name":str(assembly.name), "body":body, "root":assembly, "steer":steer, "rolling":rolling,
			"physics":body.get_node(spec["physics_node"]), "spin":0.0, "speed":0.0, "spin_delta":0.0,
			"steering":0.0, "contact":false})
	initialized = true
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if trailer.wheel_states.is_empty():
		return # Preserve original pose until both bodies have completed a physics sample.
	for wheel in wheels:
		var body: RigidBody3D = wheel["body"]
		var assembly: Node3D = wheel["root"]
		var speed: float
		var steer_angle: float = 0.0
		if body == tractor:
			var physics_wheel: VehicleWheel3D = wheel["physics"]
			steer_angle = physics_wheel.steering if physics_wheel.use_as_steering else 0.0
			var center := physics_wheel.global_position
			var contact := physics_wheel.is_in_contact()
			var sample_point := center
			var normal := body.global_basis.y.normalized()
			if contact:
				sample_point = physics_wheel.get_contact_point()
				normal = physics_wheel.get_contact_normal().normalized()
				# Use the actual contact surface + radius, not the built-in node's
				# approximate ray-wheel center (~5 cm below the physical tire radius).
				center = sample_point + normal * physics_wheel.wheel_radius
			assembly.position = body.to_local(center)
			var forward := (body.global_basis * Basis(Vector3.UP, steer_angle)).z.slide(normal).normalized()
			var com := body.to_global(body.center_of_mass)
			var point_velocity := body.linear_velocity + body.angular_velocity.cross(sample_point - com)
			speed = point_velocity.dot(forward)
			wheel["contact"] = contact
		else:
			var state: Dictionary = trailer.wheel_states.get(str(wheel["physics"].name), {})
			if state.is_empty():
				continue # Keep original pose until the first suspension sample.
			assembly.position = state["center_local"]
			speed = state["longitudinal_velocity"]
			wheel["contact"] = state["contact"]
		if absf(speed) < STOP_EPSILON:
			speed = 0.0
		var spin_delta := speed * delta / RADIUS
		wheel["spin"] = wrapf(wheel["spin"] + spin_delta, -PI, PI)
		wheel["speed"] = speed
		wheel["spin_delta"] = spin_delta
		wheel["steering"] = steer_angle
		# Independent pivots compose yaw then axle rotation; no Euler overwrites.
		(wheel["steer"] as Node3D).basis = Basis(Vector3.UP, steer_angle)
		(wheel["rolling"] as Node3D).basis = Basis(Vector3.RIGHT, wheel["spin"])
