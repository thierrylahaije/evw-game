extends AudioStreamPlayer3D

@export var vehicle: VehicleBody3D

var current_pitch: float = 0.75
var gear: int = 1
var display_rpm: float = 700.0 # Simulated reading derived from the engine sound/gear model.

func _process(delta: float) -> void:
	if vehicle == null:
		return

	var speed_kmh: float = float(vehicle.linear_velocity.length()) * 3.6

	# Lees W rechtstreeks uit als gaspedaal
	var throttle: float = 0.0

	if Input.is_key_pressed(KEY_W):
		throttle = 1.0

	# Bepaal versnelling
	if speed_kmh < 6.0:
		gear = 1
	elif speed_kmh < 12.0:
		gear = 2
	elif speed_kmh < 20.0:
		gear = 3
	elif speed_kmh < 29.0:
		gear = 4
	elif speed_kmh < 39.0:
		gear = 5
	else:
		gear = 6

	# Snelheidsbereik van huidige versnelling
	var gear_min_speed: float = 0.0
	var gear_max_speed: float = 6.0

	match gear:
		1:
			gear_min_speed = 0.0
			gear_max_speed = 6.0
		2:
			gear_min_speed = 6.0
			gear_max_speed = 12.0
		3:
			gear_min_speed = 12.0
			gear_max_speed = 20.0
		4:
			gear_min_speed = 20.0
			gear_max_speed = 29.0
		5:
			gear_min_speed = 29.0
			gear_max_speed = 39.0
		6:
			gear_min_speed = 39.0
			gear_max_speed = 50.0

	# Hoe ver zitten we binnen de huidige versnelling?
	var gear_progress: float = (
		(speed_kmh - gear_min_speed)
		/ (gear_max_speed - gear_min_speed)
	)

	if gear_progress < 0.0:
		gear_progress = 0.0

	if gear_progress > 1.0:
		gear_progress = 1.0

	# Pitch loopt binnen iedere versnelling van laag naar hoog
	var target_pitch: float = 0.82 + ((1.35 - 0.82) * gear_progress)

	# Gas geven verhoogt toerental iets
	target_pitch = target_pitch + (throttle * 0.10)

	# Stationair
	if speed_kmh < 1.0 and throttle < 0.1:
		target_pitch = 0.75

	# Pitch begrenzen
	if target_pitch < 0.75:
		target_pitch = 0.75

	if target_pitch > 1.45:
		target_pitch = 1.45

	# Soepele overgang
	var smoothing: float = delta * 6.0

	if smoothing > 1.0:
		smoothing = 1.0

	current_pitch = (
		current_pitch
		+ ((target_pitch - current_pitch) * smoothing)
	)

	pitch_scale = current_pitch
	display_rpm = 700.0 + clampf((current_pitch - 0.75) / 0.70, 0.0, 1.0) * 1800.0
