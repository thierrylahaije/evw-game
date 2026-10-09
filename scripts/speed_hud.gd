extends Label

const InstrumentCluster = preload("res://scripts/instrument_cluster.gd")
const Session = preload("res://scripts/game_session.gd")

@export var vehicle_path: NodePath
@export var trailer_path: NodePath
@onready var vehicle: VehicleBody3D = get_node(vehicle_path)
@onready var trailer: RigidBody3D = get_node(trailer_path)
var instruments: InstrumentCluster

func _ready() -> void:
	visible = false
	if Session.control_mode != "desktop":
		return
	instruments = InstrumentCluster.new()
	instruments.name = "InstrumentCluster"
	get_parent().add_child.call_deferred(instruments)

func _process(_delta: float) -> void:
	if instruments == null or not instruments.is_inside_tree():
		return
	var tractor_forward := vehicle.global_basis.z.slide(Vector3.UP).normalized()
	var trailer_forward := trailer.global_basis.z.slide(Vector3.UP).normalized()
	var articulation := rad_to_deg(tractor_forward.signed_angle_to(trailer_forward, Vector3.UP))
	var audio: AudioStreamPlayer3D = vehicle.get_node("AudioStreamPlayer3D")
	instruments.set_readings(vehicle.linear_velocity.length() * 3.6,
		audio.display_rpm, rad_to_deg(vehicle.steering), articulation)
