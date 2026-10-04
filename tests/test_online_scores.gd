extends SceneTree

const Session = preload("res://scripts/game_session.gd")
const Menu = preload("res://scenes/menu.tscn")
var failures := 0
var leaderboard: Array = []

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func run_checks() -> void:
	var temp_dir := OS.get_environment("EVW_TEST_TMP_DIR")
	if temp_dir.is_empty():
		temp_dir = OS.get_user_data_dir()
	Session.score_file = temp_dir.path_join("evw-online-test-%d.json" % OS.get_process_id())
	var api = root.get_node("ScoreApi")
	api.base_url = ""
	Session.set_player_name("Online Test")
	var result := Session.finish_round(2, 101.5, 1, 2, 1)
	check(Session.pending_saved, "Round is saved locally before upload")
	check(Session.pending_uploads().size() == 1, "Offline round remains queued")
	Session.pending_result = {} # Mimic leaving the result screen or restarting the game.
	check(Session.pending_uploads().size() == 1, "Retry queue survives session state reset")
	api.sync_pending()
	check(Session.pending_uploads().size() == 1, "Unreachable API does not erase local round")
	api.base_url = OS.get_environment("EVW_TEST_API_URL")
	check(api.available(), "Test API configured")
	api.leaderboard_received.connect(func(scores: Array) -> void: leaderboard = scores)
	api.sync_pending()
	for attempt in range(100):
		if Session.is_uploaded(String(result.id)):
			break
		await create_timer(0.1).timeout
	check(Session.is_uploaded(String(result.id)), "Queued round uploaded")
	check(Session.pending_uploads().is_empty(), "Uploaded round removed from retry queue")
	api.fetch_leaderboard()
	for attempt in range(100):
		if not leaderboard.is_empty():
			break
		await create_timer(0.1).timeout
	check(leaderboard.size() == 1, "Online leaderboard returned the player")
	if leaderboard.size() == 1:
		check(leaderboard[0].score == result.score, "API score matches local score")
	var menu := Menu.instantiate()
	root.add_child(menu)
	await process_frame
	menu._show_scores()
	var online_caption := false
	for attempt in range(100):
		for child in menu.content.get_children():
			if child is Label and child.text.begins_with("Online ranglijst"):
				online_caption = true
		if online_caption:
			break
		await create_timer(0.1).timeout
	check(online_caption, "Menu displays server leaderboard")
	root.remove_child(menu)
	menu.queue_free()
	await process_frame
	DirAccess.remove_absolute(Session.score_file)
	print("ONLINE_SCORE_RESULT failures=%d" % failures)
	quit(1 if failures else 0)
