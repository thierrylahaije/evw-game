extends Node3D
## The imported building meshes include small overhangs and facade details. Their
## full AABBs make the truck collide before it reaches the visible main wall.

const WALL_INSET_METERS := 0.6

func _ready() -> void:
	for building in $Buildings.get_children():
		var body: StaticBody3D = building.get_node_or_null("BuildingCollision")
		if body == null:
			continue
		for child in body.get_children():
			if not child is CollisionShape3D or not child.shape is BoxShape3D:
				continue
			var shape_node: CollisionShape3D = child
			var fitted: BoxShape3D = shape_node.shape.duplicate()
			var size := fitted.size
			var scale_x := shape_node.global_basis.x.length()
			var scale_z := shape_node.global_basis.z.length()
			size.x = maxf(1.0 / scale_x, size.x - 2.0 * WALL_INSET_METERS / scale_x)
			size.z = maxf(1.0 / scale_z, size.z - 2.0 * WALL_INSET_METERS / scale_z)
			fitted.size = size
			shape_node.shape = fitted
