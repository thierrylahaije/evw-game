extends VehicleBody3D
## Prototype: +Z forward; +X driver-left. Trailer is a separately jointed passive body.

@export var forward_force: float = 14000.0 # Per driven wheel, in Godot vehicle units.
@export var reverse_force: float = 9000.0
@export var service_brake: float = 180.0
@export var max_forward_kmh: float = 50.0
@export var max_reverse_kmh: float = 15.0
@export var low_speed_steering_degrees: float = 35.0
@export var high_speed_steering_degrees: float = 8.0
@export var max_lateral_acceleration: float = 3.0 # m/s²; loaded-combination steering safety.
@export var wheelbase: float = 3.5
@export var steering_response: float = 3.5 # Exponential response, per second.
@export var throttle_response: float = 2.2 # Avoid a full torque step on key press.
@export var throttle_release_response: float = 5.0

const DIRECTION_CHANGE_SPEED: float = 0.25 # m/s; latch prevents sign chatter.
var drive_direction: int = 1
var signed_speed_mps: float = 0.0
var smoothed_throttle: float = 0.0

func _physics_process(delta: float) -> void:
	signed_speed_mps = linear_velocity.dot(global_basis.z.normalized())
	var accelerate := Input.get_action_strength("vehicle_accelerate")
	var reverse := Input.get_action_strength("vehicle_brake")
	var requested_direction: int = 0
	if accelerate > 0.0:
		requested_direction = 1
	elif reverse > 0.0:
		requested_direction = -1
	var target_throttle := 0.0
	engine_force = 0.0
	brake = 0.0
	if accelerate > 0.0 and reverse > 0.0:
		brake = service_brake
	elif requested_direction == 0:
		# Small rolling resistance and a stationary hold; no artificial velocity lock.
		brake = 60.0 if absf(signed_speed_mps) < 0.1 else 2.0
	elif requested_direction != drive_direction and absf(signed_speed_mps) > DIRECTION_CHANGE_SPEED:
		brake = service_brake
	else:
		var directional_speed := signed_speed_mps * requested_direction
		if directional_speed < -DIRECTION_CHANGE_SPEED:
			brake = service_brake
		else:
			if drive_direction != requested_direction:
				smoothed_throttle = 0.0
			drive_direction = requested_direction
			var limit_mps := (max_forward_kmh if drive_direction == 1 else max_reverse_kmh) / 3.6
			var force := forward_force if drive_direction == 1 else reverse_force
			var throttle := accelerate if drive_direction == 1 else reverse
			# Ease into the speed cap so the engine does not repeatedly cut in and out.
			target_throttle = throttle * clampf((limit_mps - directional_speed) / 1.2, 0.0, 1.0)
			if directional_speed > limit_mps:
				brake = service_brake * clampf((directional_speed - limit_mps) / 1.5, 0.0, 1.0)
			var response := throttle_response if target_throttle > smoothed_throttle else throttle_release_response
			smoothed_throttle = lerpf(smoothed_throttle, target_throttle, 1.0 - exp(-response * delta))
			engine_force = drive_direction * force * smoothed_throttle
	if target_throttle == 0.0:
		smoothed_throttle = lerpf(smoothed_throttle, 0.0, 1.0 - exp(-throttle_release_response * delta))
	var speed_fraction := clampf(absf(signed_speed_mps) / (max_forward_kmh / 3.6), 0.0, 1.0)
	var steering_limit := deg_to_rad(lerpf(low_speed_steering_degrees, high_speed_steering_degrees, speed_fraction))
	# Bicycle-model curvature budget: a_lat = v² * tan(steer) / wheelbase.
	# Preserve docking steering, limit abrupt high-speed jackknifing with the trailer.
	var curve_limit := atan(wheelbase * max_lateral_acceleration / maxf(linear_velocity.length_squared(), 0.01))
	steering_limit = minf(steering_limit, curve_limit)
	var steer_input := Input.get_axis("vehicle_right", "vehicle_left")
	steering = lerpf(steering, steer_input * steering_limit, 1.0 - exp(-steering_response * delta))
