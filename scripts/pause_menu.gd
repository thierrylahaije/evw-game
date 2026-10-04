extends CanvasLayer
## Runs while SceneTree.paused so Escape and the buttons remain responsive.

const Session = preload("res://scripts/game_session.gd")
const ACCENT := Color("#f7c843")

var overlay: Control
var resume_button: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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

func _pause() -> void:
	overlay.show()
	get_tree().paused = true
	resume_button.grab_focus()

func _resume() -> void:
	get_tree().paused = false
	overlay.hide()
	resume_button.release_focus()

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
	panel.custom_minimum_size = Vector2(620, 420)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("#1b2b3b")
	panel_style.border_color = Color("#526478")
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	panel.add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	margin.add_child(layout)
	var title := Label.new()
	title.text = "PAUZE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", ACCENT)
	layout.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Je rit en de klok staan stil. Druk nogmaals op Esc om verder te gaan."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 18)
	layout.add_child(subtitle)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 14
	layout.add_child(spacer)
	resume_button = _button(layout, "Hervatten", _resume, true)
	_button(layout, "Opnieuw beginnen", _restart)
	_button(layout, "Hoofdmenu", _main_menu)

func _button(parent: VBoxContainer, label: String, action: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size.y = 50
	button.add_theme_font_size_override("font_size", 21)
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
