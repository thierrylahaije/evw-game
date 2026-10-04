extends Node
## Counts contact episodes, not physics frames or individual truck/trailer contact points.

const Session = preload("res://scripts/game_session.gd")
const REPEAT_HIT_SECONDS := 1.5
const BUILDING_IMPACT_SPEED := 0.75
const SIGNAL_REPEAT_SECONDS := 3.0
const TRUCK_FRONT_LOCAL := Vector3(0, 0, 7.2)

@export var record_results := true
@export var return_to_menu := true
var elapsed_seconds := 0.0
var building_hits := 0
var car_hits := 0
var red_light_hits := 0
var finished := false
var active_contacts: Dictionary = {}
var last_hit_at: Dictionary = {}
var previous_speed: Dictionary = {}
var hud: HBoxContainer
var kpi_values: Dictionary = {}
var vehicle_bodies: Array[RigidBody3D] = []
var truck: VehicleBody3D
var traffic_signals: Array[Node3D] = []
var previous_front := Vector3.ZERO
var last_red_crossing: Dictionary = {}

func _ready() -> void:
	var scene := get_parent()
	var mission: Node = scene.get_node("MissionController")
	mission.mission_finished.connect(_on_mission_finished)
	for body: RigidBody3D in [scene.get_node("TruckModel"), scene.get_node("TrailerModel")]:
		vehicle_bodies.append(body)
		body.contact_monitor = true
		body.max_contacts_reported = 24
		body.body_entered.connect(_on_body_entered.bind(body))
		body.body_exited.connect(_on_body_exited.bind(body))
	truck = scene.get_node("TruckModel")
	previous_front = truck.to_global(TRUCK_FRONT_LOCAL)
	for signal_node in scene.get_node("MapExpansion/StreetFurniture").signals:
		traffic_signals.append(signal_node)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HBoxContainer.new()
	hud.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hud.offset_left = -726.0
	hud.offset_top = 20.0
	hud.offset_right = -24.0
	hud.offset_bottom = 104.0
	hud.add_theme_constant_override("separation", 8)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	_add_kpi("time", "TIJD", Color("#42d5f5"))
	_add_kpi("building", "GEBOUW/MUUR", Color("#ffab6b"))
	_add_kpi("cars", "AUTO'S", Color("#ffab6b"))
	_add_kpi("red", "ROOD LICHT", Color("#ffab6b"))
	_add_kpi("score", "SCORE", Color("#ffc75b"))
	_refresh_hud()

func _add_kpi(key: String, title: String, accent: Color) -> void:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(134, 82)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.105, 0.16, 0.91)
	style.border_color = accent.darkened(0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	card.add_theme_stylebox_override("panel", style)
	hud.add_child(card)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 7)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 1)
	margin.add_child(column)
	var caption := Label.new()
	caption.text = title
	caption.add_theme_font_size_override("font_size", 12)
	caption.add_theme_color_override("font_color", Color("#9bb6c9"))
	column.add_child(caption)
	var value := Label.new()
	value.text = "0"
	value.add_theme_font_size_override("font_size", 26)
	value.add_theme_color_override("font_color", accent)
	column.add_child(value)
	kpi_values[key] = value

func _physics_process(delta: float) -> void:
	if finished:
		return
	elapsed_seconds += delta
	var front := truck.to_global(TRUCK_FRONT_LOCAL)
	for signal_node in traffic_signals:
		if _crossed_red_signal(signal_node, previous_front, front):
			var key := signal_node.get_instance_id()
			if elapsed_seconds - float(last_red_crossing.get(key, -INF)) >= SIGNAL_REPEAT_SECONDS:
				last_red_crossing[key] = elapsed_seconds
				red_light_hits += 1
	previous_front = front
	for body in vehicle_bodies:
		previous_speed[body.get_instance_id()] = body.linear_velocity.length()
	_refresh_hud()

func _crossed_red_signal(signal_node: Node3D, from: Vector3, to: Vector3) -> bool:
	if signal_node.get_meta("signal_state", "") != "red":
		return false
	var approach := Vector2(signal_node.global_basis.x.x, signal_node.global_basis.x.z).normalized()
	var travel := Vector2(to.x - from.x, to.z - from.z)
	# Ignore teleports, reversing, and traffic from the other direction.
	if travel.length() > 4.0 or travel.dot(approach) <= 0.05:
		return false
	var truck_heading := Vector2(truck.global_basis.z.x, truck.global_basis.z.z).normalized()
	if truck_heading.dot(approach) < 0.5:
		return false
	var origin := Vector2(signal_node.global_position.x, signal_node.global_position.z)
	var before := (Vector2(from.x, from.z) - origin).dot(approach)
	var after := (Vector2(to.x, to.z) - origin).dot(approach)
	if before > 0.0 or after < 0.0:
		return false
	# The light stands on the right verge; accept only the approaching right lane.
	var right := Vector2(-approach.y, approach.x)
	var lateral := (Vector2(to.x, to.z) - origin).dot(right)
	return lateral >= -9.0 and lateral <= -1.0

func _on_body_entered(other: Node, source: RigidBody3D) -> void:
	if finished:
		return
	var identity := _collision_identity(other)
	if identity.is_empty():
		return
	var key: String = identity.key
	var source_id := source.get_instance_id()
	if active_contacts.has(key):
		active_contacts[key][source_id] = true
		return
	active_contacts[key] = {source_id: true}
	if elapsed_seconds - float(last_hit_at.get(key, -INF)) < REPEAT_HIT_SECONDS:
		return
	var impact_speed := maxf(source.linear_velocity.length(), float(previous_speed.get(source_id, 0.0)))
	if identity.kind == "building" and impact_speed < BUILDING_IMPACT_SPEED:
		return
	last_hit_at[key] = elapsed_seconds
	if identity.kind == "car":
		car_hits += 1
	else:
		building_hits += 1
	_refresh_hud()

func _on_body_exited(other: Node, source: RigidBody3D) -> void:
	var identity := _collision_identity(other)
	if identity.is_empty():
		return
	var key: String = identity.key
	if not active_contacts.has(key):
		return
	active_contacts[key].erase(source.get_instance_id())
	if active_contacts[key].is_empty():
		active_contacts.erase(key)

func _collision_identity(other: Node) -> Dictionary:
	if other.name.begins_with("TrafficCar_") and other.get_parent() == get_parent().get_node("AmbientTraffic"):
		return {"kind": "car", "key": "car:" + other.name}
	var parent := other.get_parent()
	if parent == get_parent().get_node("BuildingCollisions"):
		var name_key := String(other.name)
		if name_key.begins_with("Warehouse_"):
			name_key = name_key.get_slice("_loading", 0)
		return {"kind": "building", "key": "building:" + name_key}
	if parent != null and parent.get_parent() == get_parent().get_node("MapExpansion/Buildings"):
		return {"kind": "building", "key": "building:" + String(parent.name)}
	return {}

func _on_mission_finished(route_index: int) -> void:
	if finished:
		return
	finished = true
	_refresh_hud()
	if record_results:
		Session.finish_round(route_index, elapsed_seconds, building_hits, car_hits, red_light_hits)
		var shared_scores := get_node_or_null("/root/SharedScores")
		if shared_scores != null:
			shared_scores.sync_pending()
		var score_api := get_node_or_null("/root/ScoreApi")
		if score_api != null:
			score_api.sync_pending()
	if return_to_menu:
		get_tree().call_deferred("change_scene_to_file", "res://scenes/menu.tscn")

func _refresh_hud() -> void:
	if hud == null:
		return
	(kpi_values["time"] as Label).text = Session.format_time(elapsed_seconds)
	(kpi_values["building"] as Label).text = str(building_hits)
	(kpi_values["cars"] as Label).text = str(car_hits)
	(kpi_values["red"] as Label).text = str(red_light_hits)
	(kpi_values["score"] as Label).text = str(Session.calculate_score(elapsed_seconds, building_hits, car_hits, red_light_hits))
