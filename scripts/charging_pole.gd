extends StaticBody3D
## A lightweight charging-station silhouette, based on the supplied reference photo.

var collision: CollisionShape3D

func _ready() -> void:
	name = "SurpriseChargingPole"
	collision_layer = 1
	collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.66, 2.35, 0.62)
	collision = CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = 1.175
	add_child(collision)

	_box("Foot", Vector3(0.8, 0.12, 0.8), Vector3(0, 0.06, 0), Color("#464a4e"))
	_box("Pedestal", Vector3(0.52, 2.02, 0.5), Vector3(0, 1.13, 0), Color("#b9bec2"))
	_box("SidePanel", Vector3(0.04, 1.85, 0.46), Vector3(-0.28, 1.12, 0), Color("#858e95"))
	_box("TopCap", Vector3(0.64, 0.22, 0.6), Vector3(0, 2.25, 0), Color("#202831"))
	_box("FrontPanel", Vector3(0.38, 0.7, 0.035), Vector3(0, 1.48, 0.27), Color("#222a32"))
	_box("Display", Vector3(0.29, 0.22, 0.012), Vector3(0, 1.64, 0.294), Color("#75d9ed"), true)
	_box("CardReader", Vector3(0.2, 0.09, 0.03), Vector3(0, 1.37, 0.294), Color("#424c52"))
	_box("Socket", Vector3(0.15, 0.18, 0.06), Vector3(0.13, 1.04, 0.3), Color("#12191d"))
	_box("Plug", Vector3(0.13, 0.26, 0.13), Vector3(0.24, 1.04, 0.39), Color("#1a2026"))
	_box("PlugGrip", Vector3(0.09, 0.2, 0.1), Vector3(0.27, 0.85, 0.44), Color("#161c22"))
	_box("AccentBand", Vector3(0.53, 0.045, 0.51), Vector3(0, 2.08, 0), Color("#f7c843"))
	_cable()

func disable_collision() -> void:
	if is_instance_valid(collision):
		collision.set_deferred("disabled", true)

func _box(label: String, size: Vector3, offset: Vector3, color: Color, glow := false) -> void:
	var part := MeshInstance3D.new()
	part.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.position = offset
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.22 if color == Color("#b9bec2") else 0.0
	material.roughness = 0.48
	if glow:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.8
	part.material_override = material
	add_child(part)

func _cable() -> void:
	var cable_material := StandardMaterial3D.new()
	cable_material.albedo_color = Color("#13181c")
	cable_material.roughness = 0.95
	var points := [
		Vector3(0.27, 1.82, 0.0), Vector3(0.48, 1.98, 0.0),
		Vector3(0.69, 1.99, 0.0), Vector3(0.85, 1.82, 0.0),
		Vector3(0.9, 1.51, 0.0), Vector3(0.87, 1.12, 0.0),
		Vector3(0.76, 0.68, 0.0), Vector3(0.61, 0.42, 0.0),
		Vector3(0.48, 0.53, 0.1), Vector3(0.31, 0.88, 0.28),
	]
	for index in range(points.size() - 1):
		var start: Vector3 = points[index]
		var finish: Vector3 = points[index + 1]
		var segment := finish - start
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.027
		mesh.bottom_radius = 0.027
		mesh.height = segment.length()
		mesh.radial_segments = 6
		var part := MeshInstance3D.new()
		part.name = "Cable_%02d" % index
		part.mesh = mesh
		part.material_override = cable_material
		part.position = (start + finish) * 0.5
		part.basis = Basis(Quaternion(Vector3.UP, segment.normalized()))
		add_child(part)
