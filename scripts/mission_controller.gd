extends Node3D
## One warehouse pickup, two ordered deliveries, return to the same dock.
signal mission_finished(route_index: int)

const Routes = preload("res://scripts/mission_routes.gd")
const Session = preload("res://scripts/game_session.gd")
const RouteGuidance = preload("res://scripts/route_guidance.gd")
const PICKUP_DOCK := 2
const UNLOAD_SECONDS := 6.0
const DELIVERY_RADIUS := 3.8 # Must match the visible yellow disc.
const DISTANCE_DETAIL_RADIUS := 25.0
const STOP_SPEED := 0.5

enum Stage { TO_DOCK, LOADING, DELIVERING, RETURNING, COMPLETE }

@export_range(-1, 2) var forced_route_index: int = -1
var stage: Stage = Stage.TO_DOCK
var route_index: int = -1
var route: Dictionary
var stop_index: int = 0
var unload_progress: float = 0.0
var dock: Node
var truck: VehicleBody3D
var trailer: RigidBody3D
var objective: Label
var marker: Node3D
var marker_label: Label3D
var route_guidance: Node3D

func _ready() -> void:
	var scene := get_parent()
	dock = scene.get_node("DockLoading")
	truck = scene.get_node("TruckModel")
	trailer = scene.get_node("TrailerModel")
	var routes := Routes.all()
	var requested_route: int = forced_route_index if forced_route_index >= 0 else Session.next_route_index
	route_index = requested_route if requested_route >= 0 and requested_route < routes.size() else randi_range(0, routes.size() - 1)
	Session.next_route_index = -1
	route = routes[route_index]
	for stop in route.stops:
		if scene.get_node_or_null("MapExpansion/Buildings/" + stop.building) == null:
			push_error("Mission destination missing: " + stop.building)
	dock.configure_mission(PICKUP_DOCK)
	dock.dock_settled.connect(_on_dock_settled)
	dock.load_completed.connect(_on_load_completed)
	_create_hud()
	_create_marker()
	_show_dock_marker()
	route_guidance = RouteGuidance.new()
	route_guidance.name = "RouteGuidance"
	route_guidance.configure(self, truck)
	add_child(route_guidance)
	_refresh_objective()

func _physics_process(delta: float) -> void:
	if stage == Stage.DELIVERING:
		var stop: Dictionary = route.stops[stop_index]
		if _trailer_at_stop(stop):
			unload_progress = minf(UNLOAD_SECONDS, unload_progress + delta)
			if unload_progress >= UNLOAD_SECONDS:
				_finish_delivery()
		else:
			unload_progress = 0.0
	_refresh_objective()

func _trailer_at_stop(stop: Dictionary) -> bool:
	var rear: Vector3 = trailer.to_global(dock.rear_local)
	var displacement: Vector3 = rear - stop.rear
	displacement.y = 0.0
	var rear_velocity := trailer.linear_velocity + trailer.angular_velocity.cross(rear - trailer.to_global(trailer.center_of_mass))
	return displacement.length() <= DELIVERY_RADIUS \
		and rear_velocity.length() < STOP_SPEED \
		and truck.linear_velocity.length() < STOP_SPEED

func _on_dock_settled(number: int) -> void:
	if number != PICKUP_DOCK:
		return
	if stage == Stage.TO_DOCK:
		stage = Stage.LOADING
	elif stage == Stage.RETURNING:
		stage = Stage.COMPLETE
		marker.visible = false
		mission_finished.emit(route_index)
	route_guidance.refresh()
	_refresh_objective()

func _on_load_completed(number: int) -> void:
	if number != PICKUP_DOCK or stage != Stage.LOADING:
		return
	stage = Stage.DELIVERING
	stop_index = 0
	unload_progress = 0.0
	_show_delivery_marker()
	route_guidance.refresh()
	_refresh_objective()

func _finish_delivery() -> void:
	if stage != Stage.DELIVERING:
		return
	unload_progress = 0.0
	stop_index += 1
	if stop_index >= route.stops.size():
		stage = Stage.RETURNING
		dock.configure_mission(PICKUP_DOCK, false)
		_show_dock_marker()
	else:
		_show_delivery_marker()
	route_guidance.refresh()
	_refresh_objective()

func _create_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 20)
	panel.custom_minimum_size = Vector2(380, 0)
	if Session.control_mode != "desktop":
		panel.position = Vector2(18, 76)
		panel.custom_minimum_size = Vector2(300, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.105, 0.16, 0.90)
	style.border_color = Color(0.78, 0.57, 0.23, 0.85)
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 13)
	margin.add_theme_constant_override("margin_bottom", 13)
	panel.add_child(margin)
	objective = Label.new()
	objective.custom_minimum_size.x = 264 if Session.control_mode != "desktop" else 344
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective.add_theme_font_size_override("font_size", 17)
	objective.add_theme_color_override("font_color", Color("#ffe3a3"))
	margin.add_child(objective)

func _create_marker() -> void:
	marker = Node3D.new()
	marker.name = "ActiveObjective"
	add_child(marker)
	var disc := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = DELIVERY_RADIUS
	cylinder.bottom_radius = DELIVERY_RADIUS
	cylinder.height = 0.06
	disc.mesh = cylinder
	disc.position.y = 0.15
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1, 0.78, 0.08, 0.55)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = false
	disc.material_override = material
	marker.add_child(disc)
	marker_label = Label3D.new()
	marker_label.position.y = 5.0
	marker_label.font_size = 64
	marker_label.pixel_size = 0.012
	marker_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker_label.modulate = Color(1, 0.9, 0.24)
	marker_label.outline_modulate = Color.BLACK
	marker.add_child(marker_label)

func _show_dock_marker() -> void:
	var selected: Dictionary = dock.docks[PICKUP_DOCK - 1]
	var world_point: Vector3 = selected.warehouse.to_global(selected.point)
	marker.global_position = Vector3(world_point.x, 0.0, world_point.z)
	marker_label.text = "DOCK %02d" % PICKUP_DOCK
	marker.visible = true

func _show_delivery_marker() -> void:
	var stop: Dictionary = route.stops[stop_index]
	marker.global_position = stop.rear
	marker_label.text = "LOSSEN %d/%d\n%s" % [stop_index + 1, route.stops.size(), stop.title]
	marker.visible = true

func _refresh_objective() -> void:
	if objective == null:
		return
	var heading := "ROUTE %d/3  •  %s" % [route_index + 1, route.name]
	match stage:
		Stage.TO_DOCK:
			objective.text = "%s\nRijd achteruit naar het gele dock %02d en sta stil. %s" % [heading, PICKUP_DOCK, _bearing_text(marker.global_position)]
		Stage.LOADING:
			objective.text = "%s\nLaden bij dock %02d: wacht tot de deur klaar is." % [heading, PICKUP_DOCK]
		Stage.DELIVERING:
			var stop: Dictionary = route.stops[stop_index]
			var rear: Vector3 = trailer.to_global(dock.rear_local)
			var offset: Vector3 = rear - stop.rear
			offset.y = 0.0
			var truck_offset: Vector3 = truck.global_position - stop.rear
			truck_offset.y = 0.0
			var instruction := "Houd de trailerachterkant op de gele plek en sta stil."
			if truck_offset.length() <= DISTANCE_DETAIL_RADIUS:
				instruction = "Trailerachterkant nog %.1f m van de gele plek." % maxf(0.0, offset.length() - DELIVERY_RADIUS)
			if offset.length() <= DELIVERY_RADIUS:
				instruction = "Achterkant op de gele plek: sta stil om te lossen."
			if unload_progress > 0.0:
				instruction = "Lossen: %d%%" % int(100.0 * unload_progress / UNLOAD_SECONDS)
			objective.text = "%s\nStop %d/%d: %s %s\nVolg de blauwe route. %s" % [heading, stop_index + 1, route.stops.size(), stop.title, _bearing_text(stop.rear), instruction]
		Stage.RETURNING:
			objective.text = "%s\nBeide adressen gelost. Volg de blauwe route naar dock %02d. %s" % [heading, PICKUP_DOCK, _bearing_text(marker.global_position)]
		Stage.COMPLETE:
			objective.text = "%s\nRonde voltooid!" % heading

func _bearing_text(point: Vector3) -> String:
	var displacement := point - truck.global_position
	displacement.y = 0.0
	var distance := displacement.length()
	if distance > DISTANCE_DETAIL_RADIUS:
		return ""
	if distance < 1.0:
		return "(bestemming bereikt)"
	var forward := truck.global_basis.z
	var right := truck.global_basis.x
	var longitudinal := displacement.dot(forward)
	var lateral := displacement.dot(right)
	var direction := "voor" if longitudinal >= 0.0 else "achter"
	if absf(lateral) > absf(longitudinal) * 0.4:
		direction = ("schuin " + direction + " rechts") if lateral > 0.0 else ("schuin " + direction + " links")
	return "(%.0f m, %s)" % [distance, direction]
