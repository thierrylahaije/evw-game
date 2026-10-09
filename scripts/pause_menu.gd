extends CanvasLayer
## Runs while SceneTree.paused so Escape and the buttons remain responsive.

const Session = preload("res://scripts/game_session.gd")
const ACCENT := Color("#f7c843")

var overlay: Control
var resume_button: Button
var standard_controls: VBoxContainer
var mode_options: VBoxContainer
var calibrate_button: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_build_menu()
	overlay.hide()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or event.keycode != KEY_ESCAPE:
		return
	var score: Node = get_parent().get_node("RoundScore")
	if score.finished:
		return
	if overlay.visible:
		_resume()
	else:
		_pause()
	get_viewport().set_input_as_handled()

func open_pause() -> void:
	if get_parent().get_node("RoundScore").finished:
		return
	get_parent().get_node("MobileControls").release_all()
	if calibrate_button != null:
		calibrate_button.visible = Session.control_mode == "tilt"
	standard_controls.show()
	mode_options.hide()
	overlay.show()
	get_tree().paused = true
	get_parent().get_node("MobileControls").surface.queue_redraw()
	resume_button.grab_focus()

func _pause() -> void:
	open_pause()

func _resume() -> void:
	overlay.hide()
	resume_button.release_focus()
	get_parent().get_node("MobileControls").sync_game_pause()
	get_parent().get_node("MobileControls").surface.queue_redraw()

func _choose_mode(mode: String) -> void:
	get_parent().get_node("MobileControls").change_mode(mode)
	_resume()

func _show_modes() -> void:
	standard_controls.hide()
	mode_options.show()

func _recalibrate() -> void:
	get_parent().get_node("MobileControls").calibrate()
	_resume()

func _restart() -> void:
	var mission: Node = get_parent().get_node("MissionController")
	Session.next_route_index = mission.route_index
	Session.pending_result = {}
	Session.pending_saved = false
	_resume()
	get_tree().call_deferred("change_scene_to_file", "res://scenes/main.tscn")

func _main_menu() -> void:
	Session.next_route_index = -1
	Session.pending_result = {}
	Session.pending_saved = false
	_resume()
	get_tree().call_deferred("change_scene_to_file", "res://scenes/menu.tscn")

func _exit_tree() -> void:
	if overlay != null and overlay.visible:
		get_tree().paused = false

func _build_menu() -> void:
	overlay = Control.new()
	overlay.name = "PauseOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.055, 0.085, 0.82)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 0) if Session.control_mode != "desktop" else Vector2(620, 420)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("#1b2b3b")
	panel_style.border_color = Color("#526478")
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18 if Session.control_mode != "desktop" else 32)
	panel.add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8 if Session.control_mode != "desktop" else 16)
	margin.add_child(layout)
	var title := Label.new()
	title.text = "PAUZE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40 if Session.control_mode != "desktop" else 42)
	title.add_theme_color_override("font_color", ACCENT)
	layout.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Je rit en de klok staan stil. Druk nogmaals op Esc om verder te gaan."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 18)
	layout.add_child(subtitle)
	subtitle.visible = Session.control_mode == "desktop"
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 4
	layout.add_child(spacer)
	standard_controls = VBoxContainer.new()
	standard_controls.add_theme_constant_override("separation", 7)
	layout.add_child(standard_controls)
	resume_button = _button(standard_controls, "Hervatten", _resume, true)
	if Session.control_mode != "desktop":
		_button(standard_controls, "Besturing wijzigen", _show_modes)
		calibrate_button = _button(standard_controls, "Stuur recht instellen", _recalibrate)
	_button(standard_controls, "Opnieuw beginnen", _restart)
	_button(standard_controls, "Hoofdmenu", _main_menu)
	mode_options = VBoxContainer.new()
	mode_options.add_theme_constant_override("separation", 7)
	layout.add_child(mode_options)
	_button(mode_options, "Stuurknoppen", func() -> void: _choose_mode("buttons"), true)
	_button(mode_options, "Telefoon kantelen", func() -> void: _choose_mode("tilt"))
	_button(mode_options, "Terug", func() -> void:
		mode_options.hide()
		standard_controls.show())
	mode_options.hide()

func _button(parent: VBoxContainer, label: String, action: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size.y = 65 if Session.control_mode != "desktop" else 50
	button.add_theme_font_size_override("font_size", 24 if Session.control_mode != "desktop" else 21)
	var style := StyleBoxFlat.new()
	style.bg_color = ACCENT if primary else Color("#31485d")
	style.set_corner_radius_all(7)
	style.set_content_margin_all(9)
	button.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate()
	hover.bg_color = Color("#ffda65") if primary else Color("#415e78")
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_color_override("font_color", Color("#101c2a") if primary else Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color("#101c2a") if primary else Color.WHITE)
	button.pressed.connect(action)
	parent.add_child(button)
	return button
