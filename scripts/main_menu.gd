extends Control

const Session = preload("res://scripts/game_session.gd")
const BACKGROUND := Color("#101c2a")
const CARD := Color("#1b2b3b")
const ACCENT := Color("#f7c843")
const MUTED := Color("#b9c5d1")

var content: VBoxContainer
var name_input: LineEdit
var start_button: Button
var current_view := ""

func _ready() -> void:
	_build_shell()
	var score_api := get_node_or_null("/root/ScoreApi")
	if score_api != null:
		score_api.leaderboard_received.connect(_on_leaderboard_received)
		score_api.round_uploaded.connect(_on_round_uploaded)
	var shared_scores := get_node_or_null("/root/SharedScores")
	if shared_scores != null:
		shared_scores.round_shared.connect(_on_round_shared)
	if Session.pending_result.is_empty():
		_show_home()
	else:
		_show_result()

func _build_shell() -> void:
	var background := ColorRect.new()
	background.color = BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(760, 550)
	var style := StyleBoxFlat.new()
	style.bg_color = CARD
	style.border_color = Color("#526478")
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	card.add_theme_stylebox_override("panel", style)
	center.add_child(card)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	card.add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	margin.add_child(layout)
	var title := Label.new()
	title.text = "EVW LOGISTICS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", ACCENT)
	layout.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "VRACHTRIT  •  DRIE ROUTES  •  ÉÉN DOEL"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 17)
	subtitle.add_theme_color_override("font_color", MUTED)
	layout.add_child(subtitle)
	var separator := HSeparator.new()
	layout.add_child(separator)
	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	layout.add_child(content)

func _clear_content() -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	name_input = null
	start_button = null

func _heading(value: String) -> void:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 29)
	label.add_theme_color_override("font_color", ACCENT)
	content.add_child(label)

func _text(value: String, size: int = 19) -> void:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color.WHITE)
	content.add_child(label)

func _space(height: float = 12.0) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	content.add_child(spacer)

func _button(label: String, callback: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(0, 46)
	button.add_theme_font_size_override("font_size", 20)
	var style := StyleBoxFlat.new()
	style.bg_color = ACCENT if primary else Color("#31485d")
	style.set_corner_radius_all(7)
	style.set_content_margin_all(9)
	button.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate()
	hover.bg_color = Color("#ffda65") if primary else Color("#415e78")
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_color_override("font_color", BACKGROUND if primary else Color.WHITE)
	button.add_theme_color_override("font_hover_color", BACKGROUND if primary else Color.WHITE)
	button.pressed.connect(callback)
	content.add_child(button)
	return button

func _show_home() -> void:
	current_view = "home"
	Session.pending_result = {}
	_clear_content()
	_heading("Welkom bij het warehouse")
	_text("Dock je truck, los de trailer bij twee adressen en keer terug naar het warehouse.")
	_space(18)
	_button("Nieuwe game", _show_new_game, true)
	_button("Topscorers", _show_scores)
	_button("Credits", _show_credits)
	if not OS.has_feature("web"):
		_button("Afsluiten", func() -> void: get_tree().quit())

func _show_new_game() -> void:
	current_view = "new_game"
	_clear_content()
	_heading("Nieuwe game")
	var shared_scores := get_node_or_null("/root/SharedScores")
	var score_api := get_node_or_null("/root/ScoreApi")
	var destination := "."
	if shared_scores != null and shared_scores.enabled():
		destination = " en daarna in de gedeelde scoremap."
	elif score_api != null and score_api.available():
		destination = " en daarna op de online ranglijst."
	_text("Vul je naam in. Je resultaat wordt op dit apparaat bewaard" + destination)
	_space(12)
	name_input = LineEdit.new()
	name_input.placeholder_text = "Naam van de chauffeur"
	name_input.max_length = 24
	name_input.text = Session.player_name
	name_input.custom_minimum_size.y = 50
	name_input.add_theme_font_size_override("font_size", 22)
	content.add_child(name_input)
	start_button = _button("Start rit", _start_game, true)
	start_button.disabled = name_input.text.strip_edges().is_empty()
	name_input.text_changed.connect(func(value: String) -> void:
		start_button.disabled = value.strip_edges().is_empty())
	name_input.text_submitted.connect(func(_value: String) -> void:
		if not start_button.disabled:
			_start_game())
	_button("Terug", _show_home)
	_focus_name_input.call_deferred()

func _focus_name_input() -> void:
	if is_instance_valid(name_input) and name_input.is_inside_tree():
		name_input.grab_focus()

func _start_game() -> void:
	if name_input == null or not Session.set_player_name(name_input.text):
		return
	var score_api := get_node_or_null("/root/ScoreApi")
	if score_api != null:
		score_api.register_player(Session.player_name)
	Session.next_route_index = -1
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _show_scores() -> void:
	current_view = "scores"
	var shared_scores := get_node_or_null("/root/SharedScores")
	if shared_scores != null and shared_scores.enabled():
		shared_scores.sync_pending()
		if shared_scores.has_access():
			_render_scores(shared_scores.load_leaderboard(), "shared")
		else:
			_render_scores(Session.load_scores(), "local")
	else:
		_render_scores(Session.load_scores(), "local")
	var score_api := get_node_or_null("/root/ScoreApi")
	if score_api != null and score_api.available():
		score_api.fetch_leaderboard()

func _on_leaderboard_received(scores: Array) -> void:
	if current_view == "scores":
		_render_scores(scores, "server")

func _render_scores(scores: Array, source: String) -> void:
	_clear_content()
	_heading("Topscorers")
	var score_api := get_node_or_null("/root/ScoreApi")
	var shared_scores := get_node_or_null("/root/SharedScores")
	if source == "shared":
		_text("Gedeelde ranglijst — beste ronde per chauffeur.", 17)
	elif source == "server":
		_text("Online ranglijst — beste ronde per chauffeur.", 17)
	else:
		if score_api != null and score_api.available():
			_text("Lokale resultaten; online ranglijst wordt geladen of is tijdelijk niet bereikbaar.", 17)
		elif shared_scores != null and shared_scores.enabled():
			_text("Resultaten op dit apparaat; gedeelde scoremap niet bereikbaar.", 17)
		else:
			_text("Resultaten op dit apparaat; online ranglijst nog niet ingesteld.", 17)
	if scores.is_empty():
		_space(28)
		_text("Nog geen voltooide ritten. Start een nieuwe game!")
	else:
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 24)
		grid.add_theme_constant_override("v_separation", 7)
		content.add_child(grid)
		for value in ["#", "Chauffeur", "Score", "Tijd"]:
			_grid_cell(grid, value, true)
		for i in range(mini(10, scores.size())):
			var score: Dictionary = scores[i]
			_grid_cell(grid, "%d" % (i + 1))
			_grid_cell(grid, String(score.name))
			_grid_cell(grid, "%d" % int(score.score))
			_grid_cell(grid, Session.format_time(float(score.get("time_seconds", 0.0))))
	var waiting := Session.pending_uploads().size()
	if waiting > 0 and score_api != null and score_api.available():
		_text("%d lokale uitslag(en) wachten op serveropslag." % waiting, 16)
		_button("Online opslag opnieuw proberen", func() -> void:
			score_api.sync_pending())
	var shared_waiting := Session.pending_shared_results().size()
	if shared_waiting > 0 and shared_scores != null and shared_scores.enabled():
		_text("%d uitslag(en) wachten op de gedeelde scoremap." % shared_waiting, 16)
		_button("Gedeelde scoremap opnieuw proberen", func() -> void:
			shared_scores.sync_pending()
			_show_scores())
	_space(10)
	_button("Terug naar start", _show_home)

func _grid_cell(grid: GridContainer, value: String, header: bool = false) -> void:
	var label := Label.new()
	label.text = value
	label.custom_minimum_size.x = 68 if grid.get_child_count() % 4 == 0 else 118
	label.add_theme_font_size_override("font_size", 19)
	label.add_theme_color_override("font_color", ACCENT if header else Color.WHITE)
	grid.add_child(label)

func _show_credits() -> void:
	current_view = "credits"
	_clear_content()
	_heading("Credits")
	_space(18)
	_text("EVW GAME — truck- en logistieksimulatie")
	_text("Gemaakt met Godot Engine.")
	_text("Natuur: Kenney Nature Kit. Wegen: Eclair Assets City Roads.")
	_text("Overige modellen en geluidsbestanden: projectassets; licenties staan bij de assets.", 17)
	_space(30)
	_button("Terug naar start", _show_home)

func _show_result() -> void:
	current_view = "result"
	_clear_content()
	var result: Dictionary = Session.pending_result
	_heading("Ronde voltooid")
	_text("Chauffeur %s  •  Route %d" % [result.name, int(result.route)])
	_space(12)
	_text("Basis %d  •  Tijd %s (−%d punten)" % [Session.BASE_SCORE,
		Session.format_time(float(result.time_seconds)),
		ceili(float(result.time_seconds)) * Session.POINTS_PER_SECOND], 22)
	_text("Gebouwen/muren: %d × −%d punten" % [int(result.building_hits), Session.BUILDING_PENALTY])
	_text("Auto's: %d × −%d punten" % [int(result.car_hits), Session.CAR_PENALTY])
	_text("Door rood: %d × −%d punten" % [int(result.get("red_light_hits", 0)), Session.RED_LIGHT_PENALTY])
	_text("Eindscore: %d" % int(result.score), 30)
	if not Session.pending_saved:
		_text("Lokaal opslaan is niet gelukt; probeer opnieuw.", 16)
		_button("Opnieuw opslaan", func() -> void:
			Session.save_pending_result()
			var shared_scores := get_node_or_null("/root/SharedScores")
			if shared_scores != null:
				shared_scores.sync_pending()
			var score_api := get_node_or_null("/root/ScoreApi")
			if score_api != null:
				score_api.sync_pending()
			_show_result())
	elif Session.is_shared(String(result.get("id", ""))):
		_text("Op dit apparaat en in de gedeelde scoremap opgeslagen.", 16)
	elif Session.is_uploaded(String(result.get("id", ""))):
		_text("Op dit apparaat en op de server opgeslagen.", 16)
	else:
		var shared_scores := get_node_or_null("/root/SharedScores")
		var score_api := get_node_or_null("/root/ScoreApi")
		if shared_scores != null and shared_scores.enabled():
			_text("Op dit apparaat bewaard; de gedeelde scoremap is tijdelijk niet bereikbaar.", 16)
			_button("Gedeelde scoremap opnieuw proberen", func() -> void:
				shared_scores.sync_pending()
				_show_result())
		elif score_api != null and score_api.available():
			_text("Op dit apparaat bewaard; verzending volgt zodra de server bereikbaar is.", 16)
			_button("Serveropslag opnieuw proberen", func() -> void:
				score_api.sync_pending())
		else:
			_text("Op dit apparaat opgeslagen.", 16)
	_button("Topscorers", _show_scores)
	_button("Terug naar start", _show_home, true)

func _on_round_uploaded(id: String) -> void:
	if current_view == "result" and Session.pending_result.get("id", "") == id:
		_show_result()
	elif current_view == "scores":
		_show_scores()

func _on_round_shared(id: String) -> void:
	if current_view == "result" and Session.pending_result.get("id", "") == id:
		_show_result()
	elif current_view == "scores":
		_show_scores()
