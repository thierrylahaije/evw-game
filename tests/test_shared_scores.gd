extends SceneTree

const Session = preload("res://scripts/game_session.gd")
var failures := 0

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
	var folder := temp_dir.path_join("evw-shared-test-%d" % OS.get_process_id())
	Session.score_file = temp_dir.path_join("evw-shared-local-%d.json" % OS.get_process_id())
	var shared = root.get_node("SharedScores")
	shared.directory = ""
	Session.set_player_name("Chauffeur A")
	var first := Session.finish_round(0, 120.0, 0, 0)
	check(Session.pending_saved, "First run saved locally")
	check(Session.pending_shared_results().size() == 1, "Offline run waits for shared folder")
	shared.directory = folder
	shared.sync_pending()
	check(FileAccess.file_exists(folder.path_join(String(first.id) + ".json")), "First run has its own JSON file")
	check(Session.is_shared(String(first.id)), "First run is marked shared")
	Session.finish_round(1, 90.0, 0, 0)
	Session.set_player_name("Chauffeur B")
	Session.finish_round(2, 100.0, 1, 0)
	shared.sync_pending()
	check(Session.pending_shared_results().is_empty(), "All pending runs are shared")
	var ranking: Array[Dictionary] = shared.load_leaderboard()
	check(ranking.size() == 2, "Leaderboard contains one best run per driver")
	if ranking.size() == 2:
		check(ranking[0].name == "Chauffeur A" and int(ranking[0].route) == 2,
			"Best run of first driver leads")
	var files := DirAccess.get_files_at(folder)
	check(files.size() == 3, "Three runs occupy three separate files")
	shared.sync_pending()
	check(DirAccess.get_files_at(folder).size() == 3, "Retry never duplicates files")
	for filename in files:
		DirAccess.remove_absolute(folder.path_join(filename))
	DirAccess.remove_absolute(folder)
	DirAccess.remove_absolute(Session.score_file)
	print("SHARED_SCORES_RESULT failures=%d" % failures)
	quit(1 if failures else 0)
