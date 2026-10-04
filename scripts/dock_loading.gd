extends Node
## Runtime dock controllers for the imported warehouse doors; GLB stays untouched.
signal dock_settled(dock_number: int)
signal load_completed(dock_number: int)
@export var loading_seconds: float = 12.0
@export var door_seconds: float = 1.6
@export var settle_seconds: float = 0.75
var docks: Array[Dictionary] = []
var trailer: RigidBody3D
var truck: VehicleBody3D
var rear_local := Vector3.ZERO
var status: Label
var mission_dock_number: int = 0
var mission_loading_enabled: bool = true

func configure_mission(dock_number: int, allow_loading: bool = true) -> void:
	mission_dock_number = dock_number
	mission_loading_enabled = allow_loading
	for dock in docks:
		if dock.number != dock_number:
			dock.active = false
			dock.settled = 0.0
			dock.progress = 0.0
			dock.completed = false

func _ready() -> void:
	var scene := get_parent()
	trailer = scene.get_node("TrailerModel")
	truck = scene.get_node("TruckModel")
	var cargo: CollisionShape3D = trailer.get_node("LoadCollision")
	var box: BoxShape3D = cargo.shape
	rear_local = cargo.transform * Vector3(0, 0, -box.size.z * 0.5)
	for warehouse in scene.get_node("Node3D").get_children():
		if warehouse is Node3D:
			_register_warehouse(warehouse)
	var layer := CanvasLayer.new()
	add_child(layer)
	status = Label.new()
	status.position = Vector2(30, 254)
	status.add_theme_font_size_override("font_size", 18)
	status.add_theme_color_override("font_shadow_color", Color.BLACK)
	status.add_theme_constant_override("shadow_offset_x", 2)
	status.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(status)

func _register_warehouse(warehouse: Node3D) -> void:
	var meshes := warehouse.find_children("*", "MeshInstance3D", true, false)
	for mesh in meshes:
		if not _kind(mesh.name).begins_with("sectionaldoor"):
			continue
		var door: MeshInstance3D = mesh
		var local_center := warehouse.to_local(door.global_position)
		var pivot := Node3D.new()
		pivot.name = "AnimatedDockDoor%d" % docks.size()
		warehouse.add_child(pivot)
		# The complete sectional door retracts beneath the shelter header.
		pivot.position = Vector3(local_center.x, 3.72, local_center.z)
		for part in meshes:
			var kind := _kind(part.name)
			var is_door_part := kind.begins_with("sectionaldoor") or kind.begins_with("panelseam") or kind.begins_with("windowframe") or kind.begins_with("inspectionglass")
			if is_door_part and absf(warehouse.to_local(part.global_position).x - local_center.x) < 1.2:
				part.reparent(pivot, true)
		var label := Label3D.new()
		label.name = "DockStatus"
		label.text = "VRIJ"
		label.font_size = 42
		label.pixel_size = 0.006
		label.modulate = Color(0.4, 1.0, 0.5)
		warehouse.add_child(label)
		label.position = Vector3(local_center.x, 4.38, 6.9)
		docks.append({"warehouse":warehouse, "pivot":pivot, "label":label,
			"point":Vector3(local_center.x, 1.0, 6.9), "open":0.0,
			"settled":0.0, "progress":0.0, "active":false, "completed":false,
			"number":docks.size() + 1})

func _kind(value: String) -> String:
	return value.to_lower().replace(" ", "").replace("_", "")

func _geometry_matches(dock: Dictionary, release_margin: float = 0.0) -> bool:
	var warehouse: Node3D = dock.warehouse
	var outward := warehouse.global_basis.z.normalized()
	var sideways := warehouse.global_basis.x.normalized()
	var up := warehouse.global_basis.y.normalized()
	var rear := trailer.to_global(rear_local)
	var delta := rear - warehouse.to_global(dock.point)
	var gap := delta.dot(outward)
	var bottom := trailer.to_global(Vector3(rear_local.x, 0, rear_local.z))
	var floor_point := warehouse.to_global(Vector3(dock.point.x, 0, dock.point.z))
	return absf(delta.dot(sideways)) <= 0.8 + release_margin \
		and gap >= -0.45 - release_margin and gap <= 1.2 + release_margin \
		and absf((bottom - floor_point).dot(up)) < 1.0 \
		and trailer.global_basis.z.normalized().dot(outward) >= cos(deg_to_rad(12.0 + release_margin * 10.0))

func _physics_process(delta: float) -> void:
	status.text = ""
	var rear_velocity := trailer.linear_velocity + trailer.angular_velocity.cross(trailer.to_global(rear_local) - trailer.to_global(trailer.center_of_mass))
	var stopped := rear_velocity.length() < 0.15 and truck.linear_velocity.length() < 0.15 and trailer.angular_velocity.length() < 0.05
	for dock in docks:
		var selected: bool = mission_dock_number == 0 or dock.number == mission_dock_number
		var at_dock: bool = selected and _geometry_matches(dock, 0.25 if dock.active else 0.0)
		if not at_dock:
			dock.active = false
			dock.settled = 0.0
			dock.progress = 0.0
			dock.completed = false
		elif not dock.active:
			dock.settled = dock.settled + delta if stopped else 0.0
			if dock.settled >= settle_seconds:
				dock.active = true
				dock_settled.emit(dock.number)
		var target_open := 1.0 if dock.active else 0.0
		dock.open = move_toward(dock.open, target_open, delta / maxf(door_seconds, 0.01))
		var pivot: Node3D = dock.pivot
		pivot.scale.y = maxf(0.01, 1.0 - dock.open)
		pivot.visible = dock.open < 0.999
		var label: Label3D = dock.label
		if dock.active:
			if not mission_loading_enabled:
				label.text = "GEDOCKT"
				label.modulate = Color(0.4, 1.0, 0.5)
				status.text = "Dock %02d: aangekomen" % dock.number
				continue
			if dock.open >= 0.999 and stopped:
				dock.progress = minf(loading_seconds, dock.progress + delta)
				if dock.progress >= loading_seconds and not dock.completed:
					dock.completed = true
					load_completed.emit(dock.number)
			var percent := int(100.0 * dock.progress / maxf(loading_seconds, 0.01))
			if percent >= 100:
				label.text = "GELADEN"
				label.modulate = Color(0.4, 1.0, 0.5)
				status.text = "Dock %02d: laden voltooid — je kunt vertrekken" % dock.number
			elif dock.open < 0.999:
				label.text = "OPENEN"
				label.modulate = Color(1.0, 0.75, 0.15)
				status.text = "Dock %02d: deur gaat open" % dock.number
			else:
				label.text = "LADEN %d%%" % percent if stopped else "GEPAUZEERD"
				label.modulate = Color(1.0, 0.75, 0.15)
				status.text = "Dock %02d: %s" % [dock.number, label.text]
		else:
			label.text = "SLUITEN" if dock.open > 0.0 else ("DOEL DOCK %02d" % dock.number if mission_dock_number == dock.number else "VRIJ")
			label.modulate = Color(1.0, 0.86, 0.15) if mission_dock_number == dock.number else Color(0.4, 1.0, 0.5)
			if at_dock:
				status.text = "Dock %02d: sta stil om te docken" % dock.number
