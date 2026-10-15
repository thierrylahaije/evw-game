extends Node3D
## Rare charging-pole obstacles for drivers whose name contains "Ab".

const Session = preload("res://scripts/game_session.gd")
const RouteGuidance = preload("res://scripts/route_guidance.gd")
const ChargingPole = preload("res://scripts/charging_pole.gd")
const MIN_AHEAD := 60.0
const MAX_AHEAD := 110.0
const JUNCTION_CLEARANCE := 18.0
const MAX_POLES := 5
const SPAWN_CHANCE := 0.55

var rng := RandomNumberGenerator.new()
var enabled_for_player := false
var elapsed := 0.0
var next_attempt_at := 0.0
var spawned_count := 0
var pole_spawned_at := 0.0
var active_pole: StaticBody3D
var truck: VehicleBody3D
var trailer: RigidBody3D
var mission: Node3D
var traffic: Node3D
var message_panel: PanelContainer
var message_until := 0.0

func _ready() -> void:
	enabled_for_player = Session.charging_pole_prank_enabled(Session.player_name)
	if not enabled_for_player:
		set_process(false)
		return
	rng.randomize()
	next_attempt_at = rng.randf_range(25.0, 35.0)
	truck = get_parent().get_node("TruckModel")
	trailer = get_parent().get_node("TrailerModel")
	mission = get_parent().get_node("MissionController")
	traffic = get_parent().get_node("AmbientTraffic")
	truck.contact_monitor = true
	trailer.contact_monitor = true
	truck.max_contacts_reported = maxi(truck.max_contacts_reported, 24)
	trailer.max_contacts_reported = maxi(trailer.max_contacts_reported, 24)
	truck.body_entered.connect(_on_vehicle_contact)
	trailer.body_entered.connect(_on_vehicle_contact)
	mission.mission_finished.connect(func(_route_index: int) -> void: _remove_pole())
	_create_message()

func _process(delta: float) -> void:
	elapsed += delta
	if message_panel.visible and elapsed >= message_until:
		message_panel.hide()
	if is_instance_valid(active_pole):
		var offset := active_pole.global_position - truck.global_position
		if elapsed - pole_spawned_at > 90.0 or offset.dot(truck.global_basis.z) < -25.0:
			_remove_pole()
	if spawned_count >= MAX_POLES or is_instance_valid(active_pole):
		return
	if mission.stage != mission.Stage.DELIVERING or elapsed < next_attempt_at:
		return
	var windows := candidate_windows(mission.route_guidance.current_route)
	if windows.is_empty():
		next_attempt_at = elapsed + 8.0
		return
	next_attempt_at = elapsed + rng.randf_range(45.0, 75.0)
	if rng.randf() > SPAWN_CHANCE:
		return
	var choices := windows.duplicate()
	while not choices.is_empty():
		var window: Dictionary = choices.pop_at(rng.randi_range(0, choices.size() - 1))
		var ahead := rng.randf_range(float(window.first), float(window.last))
		var position: Vector2 = window.start + window.direction * (ahead - float(window.traveled))
		if _safe_position(position):
			_spawn_pole(position, window.direction)
			return
	# A nearby vehicle can make a segment temporarily unsafe; retry soon.
	next_attempt_at = elapsed + 8.0

static func candidate_windows(path: Array[Vector2]) -> Array[Dictionary]:
	var windows: Array[Dictionary] = []
	var traveled := 0.0
	for index in range(path.size() - 1):
		var start := path[index]
		var finish := path[index + 1]
		var segment := finish - start
		var length := segment.length()
		if length >= 2.0 * JUNCTION_CLEARANCE and _is_road_lane(start, finish):
			var first := maxf(MIN_AHEAD, traveled + JUNCTION_CLEARANCE)
			var last := minf(MAX_AHEAD, traveled + length - JUNCTION_CLEARANCE)
			if first <= last:
				windows.append({"start": start, "direction": segment / length,
					"traveled": traveled, "first": first, "last": last})
		traveled += length
	return windows

static func _is_road_lane(start: Vector2, finish: Vector2) -> bool:
	var segment := finish - start
	if absf(segment.x) > 0.1 and absf(segment.y) > 0.1:
		return false
	var coordinate := start.y if absf(segment.x) > absf(segment.y) else start.x
	var centers: Array = RouteGuidance.Z_COORDS if absf(segment.x) > absf(segment.y) else RouteGuidance.X_COORDS
	for center in centers:
		if absf(absf(coordinate - float(center)) - RouteGuidance.LANE_OFFSET) < 0.35:
			return true
	return false

func _safe_position(point: Vector2) -> bool:
	var truck_point := Vector2(truck.global_position.x, truck.global_position.z)
	var trailer_point := Vector2(trailer.global_position.x, trailer.global_position.z)
	if point.distance_to(truck_point) < 45.0 or point.distance_to(trailer_point) < 45.0:
		return false
	var destination := Vector2(mission.marker.global_position.x, mission.marker.global_position.z)
	if point.distance_to(destination) < 35.0:
		return false
	for car in traffic.cars:
		var body: Node3D = car.body
		if point.distance_to(Vector2(body.global_position.x, body.global_position.z)) < 20.0:
			return false
	return true

func _spawn_pole(point: Vector2, direction: Vector2) -> void:
	if spawned_count >= MAX_POLES or is_instance_valid(active_pole):
		return
	var pole := ChargingPole.new()
	pole.position = Vector3(point.x, 0.0, point.y)
	pole.rotation.y = atan2(-direction.x, -direction.y)
	add_child(pole)
	active_pole = pole
	pole_spawned_at = elapsed
	spawned_count += 1

func _on_vehicle_contact(other: Node) -> void:
	if not is_instance_valid(active_pole) or other != active_pole:
		return
	active_pole.disable_collision()
	_remove_pole()
	message_panel.show()
	message_until = elapsed + 3.0

func _remove_pole() -> void:
	if is_instance_valid(active_pole):
		active_pole.queue_free()
	active_pole = null

func _create_message() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	message_panel = PanelContainer.new()
	message_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	message_panel.offset_left = -230
	message_panel.offset_right = 230
	message_panel.offset_top = 116
	message_panel.offset_bottom = 174
	message_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.1, 0.15, 0.95)
	style.border_color = Color("#f7c843")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	message_panel.add_theme_stylebox_override("panel", style)
	layer.add_child(message_panel)
	var label := Label.new()
	label.text = "Ab… alweer een laadpaal?"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 23)
	label.add_theme_color_override("font_color", Color("#eff8ff"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	message_panel.add_child(label)
	message_panel.hide()
