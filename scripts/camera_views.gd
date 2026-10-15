extends Node
## Driver-selectable chase/cab views; mirror viewports share the main 3D world.

const Session = preload("res://scripts/game_session.gd")
const MIRROR_SIZE := Vector2i(256, 144)
const CAB_EYE := Vector3(0.62, 3.2, 5.35)

var truck: VehicleBody3D
var chase: Camera3D
var cab: Camera3D
var cockpit := false
var layer: CanvasLayer
var cab_frame: Control
var dashboard: PanelContainer
var speed_label: Label
var gear_label: Label
var view_button: Button
var mirrors: Array[Dictionary] = []
var mirror_elapsed := 0.0

func _ready() -> void:
	truck = get_parent().get_node("TruckModel")
	chase = get_parent().get_node("ChaseCamera")
	# The body shell is shown in exterior views and mirrors, but not from inside the cab.
	for visual in truck.get_node("VisualModel").find_children("*", "VisualInstance3D", true, false):
		(visual as VisualInstance3D).layers = 2
	cab = Camera3D.new()
	cab.name = "CabCamera"
	cab.current = false
	cab.fov = 72.0
	cab.near = 0.08
	cab.far = 1000.0
	cab.cull_mask = 1
	truck.add_child(cab)
	cab.position = CAB_EYE
	cab.rotation.y = PI
	layer = CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	cab_frame = Control.new()
	cab_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cab_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cab_frame.draw.connect(_draw_cab_frame)
	layer.add_child(cab_frame)
	get_viewport().size_changed.connect(cab_frame.queue_redraw)
	for side in [1, -1]:
		_make_mirror(side)
	_make_dashboard()
	if Session.control_mode == "desktop":
		view_button = Button.new()
		view_button.text = "Cabine (C)"
		view_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		view_button.offset_left = 18
		view_button.offset_top = -66
		view_button.offset_right = 154
		view_button.offset_bottom = -18
		view_button.custom_minimum_size = Vector2(136, 42)
		view_button.pressed.connect(toggle_view)
		layer.add_child(view_button)
	_set_view(false)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
		toggle_view()
		get_viewport().set_input_as_handled()

func toggle_view() -> void:
	_set_view(not cockpit)

func _set_view(in_cab: bool) -> void:
	cockpit = in_cab
	cab.current = in_cab
	chase.current = not in_cab
	dashboard.visible = in_cab
	cab_frame.visible = in_cab
	for mirror in mirrors:
		(mirror.panel as Control).visible = in_cab
		(mirror.viewport as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE if in_cab else SubViewport.UPDATE_DISABLED
	if view_button != null:
		view_button.text = "Buitencamera (C)" if in_cab else "Cabine (C)"
	var speed_hud: Label = get_parent().get_node("DebugHUD/SpeedLabel")
	if speed_hud.instruments != null:
		speed_hud.instruments.visible = not in_cab

func _physics_process(_delta: float) -> void:
	if not cockpit:
		return
	for mirror in mirrors:
		var camera: Camera3D = mirror.camera
		var side: int = mirror.side
		camera.global_position = truck.to_global(Vector3(float(side) * 3.8, 3.45, 6.8))
		camera.global_basis = truck.global_basis * Basis(Vector3.UP, deg_to_rad(float(side) * 12.0))
	speed_label.text = "%d km/u" % roundi(truck.linear_velocity.length() * 3.6)
	gear_label.text = "R" if truck.drive_direction < 0 else "D"

func _process(delta: float) -> void:
	if not cockpit:
		return
	mirror_elapsed += delta
	if mirror_elapsed >= 0.1:
		mirror_elapsed = 0.0
		for mirror in mirrors:
			(mirror.viewport as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE

func _make_mirror(side: int) -> void:
	var viewport := SubViewport.new()
	viewport.name = "LeftMirrorViewport" if side > 0 else "RightMirrorViewport"
	viewport.size = MIRROR_SIZE
	viewport.world_3d = get_viewport().world_3d
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var camera := Camera3D.new()
	camera.fov = 58.0
	camera.near = 0.1
	camera.far = 450.0
	camera.cull_mask = 3
	viewport.add_child(camera)
	camera.current = true
	var panel := PanelContainer.new()
	panel.anchor_left = 0.02 if side > 0 else 0.78
	panel.anchor_right = 0.22 if side > 0 else 0.98
	panel.anchor_top = 0.2
	panel.anchor_bottom = 0.4
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#101820")
	style.border_color = Color("#c5d1d8")
	style.set_border_width_all(4)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	var image := TextureRect.new()
	image.texture = viewport.get_texture()
	image.flip_h = true
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(image)
	mirrors.append({"side": side, "viewport": viewport, "camera": camera, "panel": panel})

func _make_dashboard() -> void:
	dashboard = PanelContainer.new()
	dashboard.anchor_left = 0.3
	dashboard.anchor_right = 0.7
	dashboard.anchor_top = 0.87
	dashboard.anchor_bottom = 0.99
	dashboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.07, 0.11, 0.93)
	style.border_color = Color("#5d7180")
	style.set_border_width_all(3)
	style.set_corner_radius_all(16)
	dashboard.add_theme_stylebox_override("panel", style)
	layer.add_child(dashboard)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	dashboard.add_child(row)
	gear_label = Label.new()
	gear_label.text = "D"
	gear_label.add_theme_font_size_override("font_size", 24)
	row.add_child(gear_label)
	speed_label = Label.new()
	speed_label.text = "0 km/u"
	speed_label.add_theme_font_size_override("font_size", 27)
	row.add_child(speed_label)

func _draw_cab_frame() -> void:
	var size := cab_frame.size
	var dark := Color(0.025, 0.045, 0.065, 0.96)
	var trim := Color("#65798a")
	cab_frame.draw_colored_polygon(PackedVector2Array([
		Vector2(0, size.y * 0.76), Vector2(size.x * 0.13, size.y * 0.82),
		Vector2(size.x * 0.87, size.y * 0.82), Vector2(size.x, size.y * 0.76),
		Vector2(size.x, size.y), Vector2(0, size.y)]), dark)
	cab_frame.draw_line(Vector2(0, size.y * 0.76), Vector2(size.x * 0.13, size.y * 0.82), trim, 4)
	cab_frame.draw_line(Vector2(size.x * 0.87, size.y * 0.82), Vector2(size.x, size.y * 0.76), trim, 4)
	cab_frame.draw_colored_polygon(PackedVector2Array([
		Vector2(0, 0), Vector2(size.x * 0.055, 0),
		Vector2(size.x * 0.035, size.y * 0.76), Vector2(0, size.y * 0.8)]), dark)
	cab_frame.draw_colored_polygon(PackedVector2Array([
		Vector2(size.x * 0.945, 0), Vector2(size.x, 0),
		Vector2(size.x, size.y * 0.8), Vector2(size.x * 0.965, size.y * 0.76)]), dark)
	var wheel := Vector2(size.x * 0.23, size.y * 0.97)
	cab_frame.draw_arc(wheel, 58.0, PI, TAU, 48, trim, 9.0, true)
	cab_frame.draw_line(wheel, wheel + Vector2(-48, -26), trim, 6.0, true)
	cab_frame.draw_line(wheel, wheel + Vector2(48, -26), trim, 6.0, true)
