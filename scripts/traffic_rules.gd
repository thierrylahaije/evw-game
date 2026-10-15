extends Node3D
## Speed zones and visible roadside checkpoints for the player's truck.

const Session = preload("res://scripts/game_session.gd")
const FRONT_LOCAL := Vector3(0, 0, 7.2)
const SPEED_TOLERANCE_KMH := 3.0
const CROSSING_COOLDOWN := 4.0

var truck: VehicleBody3D
var traffic: Node3D
var score: Node
var checkpoints: Array[Dictionary] = []
var previous_front := Vector2.ZERO
var elapsed := 0.0
var speed_limit_label: Label
var displayed_limit := -1
var displayed_over := false

func _ready() -> void:
	truck = get_parent().get_node("TruckModel")
	traffic = get_parent().get_node("AmbientTraffic")
	score = get_parent().get_node("RoundScore")
	var front := truck.to_global(FRONT_LOCAL)
	previous_front = Vector2(front.x, front.z)
	# The southern logistics roads allow 50; streets through the depot allow 30.
	_add_checkpoint("speed", Vector2(-112, -203.35), Vector2(-1, 0), 50)
	_add_checkpoint("speed", Vector2(72, -196.65), Vector2(1, 0), 50)
	_add_checkpoint("speed", Vector2(270, -196.65), Vector2(1, 0), 50)
	_add_checkpoint("speed", Vector2(423.35, -245), Vector2(0, -1), 50)
	_add_checkpoint("speed", Vector2(-316.65, 20), Vector2(0, -1), 30)
	_add_checkpoint("speed", Vector2(-270, 30), Vector2(-1, 0), 30)
	_add_checkpoint("speed", Vector2(137.68, 90), Vector2(0, 1), 30)
	_add_checkpoint("speed", Vector2(-95, 296.65), Vector2(-1, 0), 30)
	_add_checkpoint("stop", Vector2(-32.6, -185), Vector2(0, -1), 0)
	_add_checkpoint("stop", Vector2(-110, 181), Vector2(0, -1), 0)
	_add_checkpoint("stop", Vector2(-250, 321), Vector2(0, -1), 0)
	_add_checkpoint("yield", Vector2(-46.65, 175), Vector2(0, -1), 0)
	_add_checkpoint("yield", Vector2(144.38, 175), Vector2(0, -1), 0)
	_add_zone_signs()
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	speed_limit_label = Label.new()
	if Session.control_mode == "desktop":
		speed_limit_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		speed_limit_label.offset_left = 18
		speed_limit_label.offset_top = -112
		speed_limit_label.offset_right = 210
		speed_limit_label.offset_bottom = -80
	else:
		speed_limit_label.anchor_left = 0.42
		speed_limit_label.anchor_right = 0.58
		speed_limit_label.offset_top = 18
		speed_limit_label.offset_bottom = 48
		speed_limit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speed_limit_label.add_theme_font_size_override("font_size", 20)
	speed_limit_label.add_theme_color_override("font_color", Color("#fff4d4"))
	speed_limit_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	speed_limit_label.add_theme_constant_override("shadow_offset_x", 2)
	speed_limit_label.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(speed_limit_label)
	_refresh_limit()

static func speed_limit_at(point: Vector2) -> int:
	return 50 if point.y < -100.0 else 30

func _physics_process(delta: float) -> void:
	elapsed += delta
	var front_3d := truck.to_global(FRONT_LOCAL)
	var front := Vector2(front_3d.x, front_3d.z)
	var speed_kmh := truck.linear_velocity.length() * 3.6
	for checkpoint in checkpoints:
		var point: Vector2 = checkpoint.point
		if checkpoint.kind == "stop" and front.distance_to(point) < 13.0 and speed_kmh < 1.5:
			checkpoint.stopped = true
		if _crossed(checkpoint, previous_front, front) and elapsed - float(checkpoint.last) > CROSSING_COOLDOWN:
			checkpoint.last = elapsed
			match checkpoint.kind:
				"speed":
					if speed_kmh > float(checkpoint.limit) + SPEED_TOLERANCE_KMH:
						score.add_traffic_fine("Flitspaal: %d in zone %d" % [roundi(speed_kmh), checkpoint.limit])
				"stop":
					if not checkpoint.stopped:
						score.add_traffic_fine("Stopbord genegeerd")
				"yield":
					if _conflicting_traffic(checkpoint.junction):
						score.add_traffic_fine("Geen voorrang verleend")
			checkpoint.stopped = false
		elif checkpoint.kind == "stop" and front.distance_to(point) > 30.0:
			checkpoint.stopped = false
	previous_front = front
	_refresh_limit()

static func _crossed(checkpoint: Dictionary, from: Vector2, to: Vector2) -> bool:
	var direction: Vector2 = checkpoint.direction
	var travel := to - from
	if travel.length() > 5.0 or travel.dot(direction) < 0.05:
		return false
	var point: Vector2 = checkpoint.point
	var before := (from - point).dot(direction)
	var after := (to - point).dot(direction)
	if before > 0.0 or after < 0.0:
		return false
	var side := Vector2(-direction.y, direction.x)
	return absf((to - point).dot(side)) <= 3.0

func _conflicting_traffic(junction: Vector2) -> bool:
	for car in traffic.cars:
		var body: Node3D = car.body
		var position := Vector2(body.global_position.x, body.global_position.z)
		if position.distance_to(junction) < 18.0 and float(car.speed) > 1.5:
			return true
	return false

func _refresh_limit() -> void:
	var limit := speed_limit_at(Vector2(truck.global_position.x, truck.global_position.z))
	var over := truck.linear_velocity.length() * 3.6 > float(limit) + SPEED_TOLERANCE_KMH
	if limit != displayed_limit:
		displayed_limit = limit
		speed_limit_label.text = "LIMIET %d km/u" % limit
	if over != displayed_over:
		displayed_over = over
		speed_limit_label.add_theme_color_override("font_color", Color("#ff7770") if over else Color("#fff4d4"))

func _add_checkpoint(kind: String, point: Vector2, direction: Vector2, limit: int) -> void:
	checkpoints.append({"kind": kind, "point": point, "direction": direction,
		"limit": limit, "junction": point + direction * 15.0,
		"last": -INF, "stopped": false})
	var right := Vector2(-direction.y, direction.x)
	var verge := point + right * 5.5
	if kind == "speed":
		_make_camera(verge, direction, limit)
	else:
		_make_sign(kind, verge, limit)

func _camera_part(parent: Node3D, name: String, size: Vector3, position: Vector3, color: Color) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = name
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.position = position
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.25
	part.material_override = material
	parent.add_child(part)
	return part

func _make_camera(at: Vector2, direction: Vector2, limit: int) -> void:
	var fixture := Node3D.new()
	fixture.name = "SpeedCamera_%02d" % checkpoints.size()
	fixture.position = Vector3(at.x, 0, at.y)
	# The lenses face approaching traffic. The bright housing is also visible from behind.
	fixture.basis = Basis.looking_at(Vector3(-direction.x, 0, -direction.y), Vector3.UP)
	add_child(fixture)
	_camera_part(fixture, "Mast", Vector3(0.22, 3.3, 0.22), Vector3(0, 1.65, 0), Color("#b5bcc1"))
	_camera_part(fixture, "YellowHousing", Vector3(1.0, 1.25, 0.68), Vector3(0, 3.25, 0), Color("#f6c32f"))
	_camera_part(fixture, "DarkCameraFace", Vector3(0.78, 0.83, 0.045), Vector3(0, 3.36, -0.365), Color("#192632"))
	_camera_part(fixture, "UpperLens", Vector3(0.38, 0.25, 0.05), Vector3(0, 3.58, -0.405), Color("#6bc6e8"))
	_camera_part(fixture, "LowerFlash", Vector3(0.56, 0.15, 0.05), Vector3(0, 3.13, -0.405), Color("#e9f5fb"))
	_camera_part(fixture, "ReflectiveStripe", Vector3(1.03, 0.12, 0.7), Vector3(0, 2.77, 0), Color("#fff5b7"))
	var label := Label3D.new()
	label.name = "CameraSign"
	label.text = "FLITS\n%d" % limit
	label.position = Vector3(0, 4.45, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.012
	label.font_size = 64
	label.outline_size = 16
	label.modulate = Color("#fff1ad")
	fixture.add_child(label)

func _add_zone_signs() -> void:
	# Both directions at each north/south road make the change of zone explicit.
	for x in [-320.0, -215.0, 141.03, 420.0]:
		_make_sign("limit", Vector2(x + 8.5, -104), 50)
		_make_sign("limit", Vector2(x - 8.5, -96), 30)

func _make_sign(kind: String, at: Vector2, limit: int) -> void:
	var fixture := Node3D.new()
	fixture.name = "RoadSign"
	fixture.position = Vector3(at.x, 0, at.y)
	add_child(fixture)
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.055
	pole_mesh.bottom_radius = 0.07
	pole_mesh.height = 3.0
	pole.mesh = pole_mesh
	pole.position.y = 1.5
	fixture.add_child(pole)
	var face := Label3D.new()
	face.position.y = 3.15
	face.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	face.pixel_size = 0.009
	face.font_size = 64
	face.outline_size = 12
	face.modulate = Color.WHITE
	face.text = "%d" % limit if kind == "limit" else ("STOP" if kind == "stop" else "VOORRANG")
	fixture.add_child(face)
