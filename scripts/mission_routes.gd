extends RefCounted
## Three fixed, roughly equal-length two-stop tours. Coordinates are trailer-rear stopping points.

static func all() -> Array[Dictionary]:
	return [
		{
			"name": "Noord–west",
			"estimated_meters": 2000,
			"stops": [
				_stop("building_b_0293", "Noordelijk bedrijf", Vector3(20, 0, 338.43), Vector3(0, 0, -1)),
				_stop("Infill_434", "Centraal magazijn", Vector3(-150, 0, -157.99), Vector3(0, 0, -1)),
			]
		},
		{
			"name": "Zuid–oost",
			"estimated_meters": 2000,
			"stops": [
				_stop("Infill_429", "Noordelijk depot", Vector3(-110, 0, 207.17), Vector3(0, 0, -1)),
				_stop("Infill_432", "Oostelijk magazijn", Vector3(204.21, 0, -100), Vector3(-1, 0, 0)),
			]
		},
		{
			"name": "West–noord",
			"estimated_meters": 2000,
			"stops": [
				_stop("building_s_0284", "Noordwestelijk depot", Vector3(-250, 0, 340.50), Vector3(0, 0, -1)),
				_stop("building_e_0302", "Westelijke fabriek", Vector3(-358.26, 0, -165), Vector3(1, 0, 0)),
			]
		},
	]

static func _stop(building: String, title: String, rear: Vector3, outward: Vector3) -> Dictionary:
	return {"building": building, "title": title, "rear": rear, "outward": outward}
