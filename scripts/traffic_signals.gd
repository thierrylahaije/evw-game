extends Node3D
## Cycles the three approaches at each T junction without conflicting greens.

@export var main_green_seconds := 14.0
@export var amber_seconds := 3.0
@export var all_red_seconds := 1.0
@export var side_green_seconds := 8.0

var elapsed := 0.0
var signals: Array[Node3D] = []
var on_materials: Dictionary = {}
var off_materials: Dictionary = {}

func _ready() -> void:
	_setup_materials()
	for child in get_children():
		if not child.name.begins_with("TrafficSignal_"):
			continue
		var signal_node: Node3D = child
		signal_node.set_meta("signal_state", "")
		_add_lenses(signal_node)
		signals.append(signal_node)
	_update_signals()

func _process(delta: float) -> void:
	elapsed += delta
	_update_signals()

func _setup_materials() -> void:
	var colors := {
		"red": Color(1.0, 0.07, 0.025),
		"amber": Color(1.0, 0.55, 0.025),
		"green": Color(0.07, 1.0, 0.16)
	}
	for color_name in colors:
		var active := StandardMaterial3D.new()
		active.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		active.albedo_color = colors[color_name]
		active.emission_enabled = true
		active.emission = colors[color_name]
		active.emission_energy_multiplier = 4.0
		on_materials[color_name] = active
		var inactive := StandardMaterial3D.new()
		inactive.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		inactive.albedo_color = colors[color_name] * 0.09
		off_materials[color_name] = inactive

func _add_lenses(signal_node: Node3D) -> void:
	# The imported head faces local -X; these three positions match its lens centers.
	var lens_positions := {"red": 0.478, "amber": 0.437, "green": 0.395}
	for color_name in lens_positions:
		var disc := MeshInstance3D.new()
		disc.name = "Lens_" + color_name
		var sphere := SphereMesh.new()
		sphere.radius = 0.012
		sphere.height = 0.024
		disc.mesh = sphere
		disc.position = Vector3(-0.055, lens_positions[color_name], 0.0)
		disc.material_override = off_materials[color_name]
		signal_node.add_child(disc)

func _cycle_state(main_road: bool, t: float) -> String:
	if t < main_green_seconds:
		return "green" if main_road else "red"
	t -= main_green_seconds
	if t < amber_seconds:
		return "amber" if main_road else "red"
	t -= amber_seconds
	if t < all_red_seconds:
		return "red"
	t -= all_red_seconds
	if t < side_green_seconds:
		return "red" if main_road else "green"
	t -= side_green_seconds
	if t < amber_seconds:
		return "red" if main_road else "amber"
	return "red"

func _update_signals() -> void:
	var cycle := main_green_seconds + amber_seconds * 2.0 + all_red_seconds * 2.0 + side_green_seconds
	for signal_node in signals:
		var junction_id: int = signal_node.get_meta("junction_id", 0)
		var main_road: bool = signal_node.get_meta("main_road", false)
		var time_in_cycle := fposmod(elapsed + float(junction_id) * 4.0, cycle)
		var state := _cycle_state(main_road, time_in_cycle)
		if signal_node.get_meta("signal_state", "") == state:
			continue
		signal_node.set_meta("signal_state", state)
		for color_name in ["red", "amber", "green"]:
			var disc: MeshInstance3D = signal_node.get_node("Lens_" + color_name)
			disc.material_override = on_materials[color_name] if state == color_name else off_materials[color_name]
