extends RigidBody3D
## Six passive contact patches: spring/damper, lateral grip and rolling resistance.
## No motor, steering, artificial yaw alignment, or transform/velocity correction.
@export var wheel_radius: float = 0.60
@export var rest_length: float = 0.25
@export var suspension_travel: float = 0.20
@export var spring_stiffness: float = 100000.0 # N/m, per wheel.
@export var damping: float = 10000.0 # N*s/m, per wheel.
@export var max_suspension_force: float = 40000.0
@export var lateral_stiffness: float = 18000.0 # N per m/s of side slip.
@export var tire_friction: float = 0.9
@export var rolling_resistance: float = 0.012

@onready var wheel_points: Array[Node] = $WheelHardpoints.get_children()
## Read-only snapshots for wheel_visuals.gd; populated from the existing six rays.
var wheel_states: Dictionary = {}
var contact_count: int = 0
var axle_contacts := PackedInt32Array([0, 0, 0])
var wheel_loads := PackedFloat32Array([0, 0, 0, 0, 0, 0])

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	contact_count = 0
	axle_contacts.fill(0)
	wheel_loads.fill(0.0)
	var up := state.transform.basis.y.normalized()
	var world_com := state.transform.origin + state.center_of_mass
	for index in range(wheel_points.size()):
		var hardpoint := state.transform * (wheel_points[index] as Node3D).position
		var wheel_name := str(wheel_points[index].name)
		var free_center: Vector3 = (wheel_points[index] as Node3D).position - Vector3.UP * rest_length
		var free_point := state.transform * free_center
		var free_velocity := state.linear_velocity + state.angular_velocity.cross(free_point - world_com)
		wheel_states[wheel_name] = {"contact":false, "ray_hit":false, "suspension_length":rest_length,
			"center_local":free_center, "contact_position":Vector3.ZERO,
			"longitudinal_velocity":free_velocity.dot(state.transform.basis.z.normalized())}
		var ray_end := hardpoint - up * (wheel_radius + rest_length + suspension_travel)
		var query := PhysicsRayQueryParameters3D.create(hardpoint, ray_end, 1, [get_rid()])
		var hit := state.get_space_state().intersect_ray(query)
		if hit.is_empty():
			continue
		var point: Vector3 = hit["position"]
		var normal: Vector3 = hit["normal"]
		if normal.dot(up) < 0.5:
			continue
		var length := clampf(hardpoint.distance_to(point) - wheel_radius, rest_length - suspension_travel, rest_length + suspension_travel)
		var velocity := state.linear_velocity + state.angular_velocity.cross(point - world_com)
		var compression := rest_length - length
		var load := clampf(spring_stiffness * compression - damping * velocity.dot(normal), 0.0, max_suspension_force)
		# Observation only: leave all force calculations and their order unchanged.
		wheel_states[wheel_name] = {"contact":load > 0.0, "ray_hit":true, "suspension_length":length,
			"center_local":(wheel_points[index] as Node3D).position - Vector3.UP * length,
			"contact_position":point, "longitudinal_velocity":velocity.dot(state.transform.basis.z.slide(normal).normalized())}
		if load <= 0.0:
			continue
		contact_count += 1
		axle_contacts[index / 2] += 1
		wheel_loads[index] = load
		var forward := state.transform.basis.z.slide(normal).normalized()
		var lateral := normal.cross(forward).normalized()
		var side_force := -velocity.dot(lateral) * lateral_stiffness
		var rolling_force := -clampf(velocity.dot(forward) / 0.5, -1.0, 1.0) * rolling_resistance * load
		var grip := lateral * side_force + forward * rolling_force
		grip = grip.limit_length(load * tire_friction)
		# Force positions are world-oriented offsets from the BODY ORIGIN, not COM.
		state.apply_force(normal * load + grip, point - state.transform.origin)
