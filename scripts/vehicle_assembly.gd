extends Node3D
## Normalize the runtime physics origin, then split the imported visual assembly.
const PARTS_PATH := "res://assets/vehicle_parts.json"
var visual_split_validated: bool = false

func _enter_tree() -> void:
	# VehicleBody3D computes wheel impulses relative to its origin. Put that
	# origin at the authored COM before its wheels/joint enter the physics world.
	# Counter-translate children to preserve every mesh, collider and hardpoint.
	var truck: VehicleBody3D = $TruckModel
	var offset := truck.center_of_mass
	truck.position += truck.basis * offset
	for child in truck.get_children():
		if child is Node3D:
			child.position -= offset
	truck.center_of_mass = Vector3.ZERO

func _ready() -> void:
	var parts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PARTS_PATH))
	var source: Node3D = $TruckModel/VisualModel
	var destination: Node3D = $TrailerModel/TrailerVisuals
	# Visual roots still coincide after recentering; allow floating-point roundoff.
	if not source.global_transform.is_equal_approx(destination.global_transform):
		push_error("Vehicle visual roots must share the initial transform before physics starts.")
		return
	var meshes := source.find_children("*", "MeshInstance3D", true, false)
	if meshes.size() != 596 or parts["trailer"].size() != 313 or parts["tractor"].size() != 283:
		push_error("Vehicle parts manifest does not match the imported model.")
		return
	# Validate all paths before changing any parent; never silently drop an unknown part.
	var seen: Dictionary = {}
	for category in ["tractor", "trailer"]:
		for path in parts[category]:
			if seen.has(path) or not source.get_node_or_null(path) is MeshInstance3D:
				push_error("Invalid or duplicate vehicle mesh path: " + path)
				return
			seen[path] = true
	for path in parts["trailer"]:
		var mesh: MeshInstance3D = source.get_node(path)
		mesh.reparent(destination, false)
	visual_split_validated = true
	$WheelVisuals.setup(parts["wheels"], $TruckModel, $TrailerModel)
