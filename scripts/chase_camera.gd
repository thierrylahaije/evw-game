extends Camera3D

@export var target_path: NodePath
@export var trailer_path: NodePath
@export var follow_offset := Vector3(8.0, 10.0, -24.0)
@export var follow_response: float = 4.0
@export var orbit_speed: float = 2.5
@export var obstacle_margin: float = 0.9
@onready var target: Node3D = get_node(target_path)
@onready var trailer: Node3D = get_node(trailer_path)
var smoothed_aim := Vector3.ZERO
var orbit_angle: float = 0.0
var viewing_reverse: bool = false
var camera_distance: float = 0.0

func _ready() -> void:
	_update_direction()
	orbit_angle = _desired_angle()
	smoothed_aim = _aim_point()
	camera_distance = follow_offset.length()
	_place_camera(0.0)

func _physics_process(delta: float) -> void:
	_update_direction()
	# Orbit around the vehicle instead of interpolating through its body.
	orbit_angle = rotate_toward(orbit_angle, _desired_angle(), orbit_speed * delta)
	var weight := 1.0 - exp(-follow_response * delta)
	smoothed_aim = smoothed_aim.lerp(_aim_point(), weight)
	_place_camera(delta)

func _update_direction() -> void:
	# Actual motion wins while braking. At rest use the controller's latched gear;
	# releasing a pedal or tiny suspension movements must not flip the camera.
	var speed: float = target.linear_velocity.dot(target.global_basis.z.normalized())
	if absf(speed) > 0.3:
		viewing_reverse = speed < 0.0
	else:
		viewing_reverse = target.drive_direction < 0

func _desired_angle() -> float:
	var forward := _heading_basis().z
	return atan2(forward.x, forward.z) + (PI if viewing_reverse else 0.0)

func _aim_point() -> Vector3:
	var center := _combination_center()
	# Keep the trailer's rear and the docking approach in frame when reversing.
	return center - _heading_basis().z * 4.0 if viewing_reverse else center

func _place_camera(delta: float) -> void:
	var desired_offset := Basis(Vector3.UP, orbit_angle) * follow_offset
	var desired_distance := desired_offset.length()
	var ray := PhysicsRayQueryParameters3D.create(smoothed_aim, smoothed_aim + desired_offset)
	ray.exclude = [target.get_rid(), trailer.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		desired_distance = maxf(2.0, smoothed_aim.distance_to(hit.position) - obstacle_margin)
	# Move in quickly at a wall, recover the normal view gently once clear.
	var response := 16.0 if desired_distance < camera_distance else 3.0
	camera_distance = lerpf(camera_distance, desired_distance, 1.0 - exp(-response * delta))
	global_position = smoothed_aim + desired_offset.normalized() * camera_distance
	look_at(smoothed_aim, Vector3.UP)

func _combination_center() -> Vector3:
	return (target.get_node("VisualModel").to_global(Vector3(0, 2.0, 7.2)) + trailer.to_global(Vector3(0, 2.0, -10.14))) * 0.5

func _heading_basis() -> Basis:
	var forward := trailer.global_basis.z.slide(Vector3.UP).normalized()
	if forward.is_zero_approx():
		forward = Vector3.BACK
	return Basis(Vector3.UP.cross(forward), Vector3.UP, forward)
