extends Node
## One immutable JSON file per round in a shared folder; local scores queue retries.

signal round_shared(id: String)

const Session = preload("res://scripts/game_session.gd")
const RETRY_SECONDS := 30.0

var directory := ""

func _ready() -> void:
	directory = _configured_directory()
	var timer := Timer.new()
	timer.wait_time = RETRY_SECONDS
	timer.autostart = true
	timer.timeout.connect(sync_pending)
	add_child(timer)
	sync_pending.call_deferred()

func _configured_directory() -> String:
	var executable_dir := OS.get_executable_path().get_base_dir()
	if OS.has_feature("macos") and executable_dir.ends_with("/Contents/MacOS"):
		executable_dir = executable_dir.get_base_dir().get_base_dir().get_base_dir()
	var path := OS.get_environment("EVW_SHARED_SCORES_DIR").strip_edges()
	if path.is_empty():
		if OS.has_feature("editor") or OS.has_feature("web"):
			return ""
		var config_file := executable_dir.path_join("scoremap.txt")
		if FileAccess.file_exists(config_file):
			var file := FileAccess.open(config_file, FileAccess.READ)
			if file != null:
				path = file.get_as_text().strip_edges()
		if path.is_empty():
			path = "scores"
	if not path.is_absolute_path():
		path = executable_dir.path_join(path)
	return path.simplify_path()

func enabled() -> bool:
	return not directory.is_empty()

func has_access() -> bool:
	return enabled() and DirAccess.open(directory) != null

func sync_pending() -> void:
	if not enabled():
		return
	if not has_access() and DirAccess.make_dir_recursive_absolute(directory) != OK:
		return
	for result in Session.pending_shared_results():
		var id := String(result.get("id", ""))
		if not _valid_id(id) or not _write_round(result):
			continue
		if Session.mark_shared(id):
			round_shared.emit(id)

func _write_round(result: Dictionary) -> bool:
	var id := String(result.get("id", ""))
	var destination := directory.path_join(id + ".json")
	if FileAccess.file_exists(destination):
		return true
	var temporary := directory.path_join(id + ".tmp")
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	var record := result.duplicate()
	record.erase("uploaded")
	record.erase("shared_saved")
	record["version"] = 1
	file.store_string(JSON.stringify(record, "\t"))
	file.flush()
	var written := file.get_error() == OK
	file.close()
	if not written:
		DirAccess.remove_absolute(temporary)
		return false
	if DirAccess.rename_absolute(temporary, destination) != OK:
		DirAccess.remove_absolute(temporary)
		return FileAccess.file_exists(destination)
	return true

func load_leaderboard() -> Array[Dictionary]:
	var scores: Array[Dictionary] = []
	var folder := DirAccess.open(directory) if enabled() else null
	if folder == null:
		return scores
	var best := {}
	for filename in folder.get_files():
		if not filename.ends_with(".json") or not _valid_id(filename.trim_suffix(".json")):
			continue
		var file := FileAccess.open(directory.path_join(filename), FileAccess.READ)
		if file == null:
			continue
		var data = JSON.parse_string(file.get_as_text())
		if not _valid_round(data, filename.trim_suffix(".json")):
			continue
		var name_key := String(data.name).to_lower()
		if not best.has(name_key) or _better(data, best[name_key]):
			best[name_key] = data
	for value in best.values():
		scores.append(value)
	scores.sort_custom(_better)
	return scores

func _valid_id(value: String) -> bool:
	if value.length() != 32:
		return false
	for character in value:
		if not character in "0123456789abcdef":
			return false
	return true

func _valid_round(value: Variant, expected_id: String) -> bool:
	if not value is Dictionary:
		return false
	if value.get("id", "") != expected_id or not value.get("name") is String:
		return false
	if String(value.name).strip_edges().is_empty() or String(value.name).length() > 24:
		return false
	for key in ["route", "building_hits", "car_hits", "red_light_hits", "score"]:
		if not _is_whole_number(value.get(key)):
			return false
	if int(value.route) < 1 or int(value.route) > 3:
		return false
	if not value.get("time_seconds") is float and not value.get("time_seconds") is int:
		return false
	if float(value.time_seconds) <= 0.0:
		return false
	for key in ["building_hits", "car_hits", "red_light_hits"]:
		if int(value[key]) < 0:
			return false
	return int(value.score) == Session.calculate_score(float(value.time_seconds),
		int(value.building_hits), int(value.car_hits), int(value.red_light_hits))

func _is_whole_number(value: Variant) -> bool:
	return (value is int or value is float) and float(value) == float(int(value))

func _better(a: Dictionary, b: Dictionary) -> bool:
	if int(a.score) != int(b.score):
		return int(a.score) > int(b.score)
	return float(a.time_seconds) < float(b.time_seconds)
