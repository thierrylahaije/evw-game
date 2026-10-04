extends RefCounted
## Each result is saved locally before shared-folder or API synchronization.

const SCORE_FILE := "user://scores.json"
const BASE_SCORE := 10000
const POINTS_PER_SECOND := 2
const BUILDING_PENALTY := 400
const CAR_PENALTY := 700
const RED_LIGHT_PENALTY := 500

static var player_name: String = ""
static var pending_result: Dictionary = {}
static var pending_saved: bool = false
static var score_file: String = SCORE_FILE
static var next_route_index: int = -1

static func set_player_name(value: String) -> bool:
	var cleaned := value.strip_edges().substr(0, 24)
	if cleaned.is_empty():
		return false
	player_name = cleaned
	return true

static func calculate_score(seconds: float, building_hits: int, car_hits: int, red_light_hits: int = 0) -> int:
	return maxi(0, BASE_SCORE - ceili(seconds) * POINTS_PER_SECOND \
		- building_hits * BUILDING_PENALTY - car_hits * CAR_PENALTY \
		- red_light_hits * RED_LIGHT_PENALTY)

static func finish_round(route_index: int, seconds: float, building_hits: int, car_hits: int, red_light_hits: int = 0) -> Dictionary:
	var duration := maxf(0.01, snappedf(seconds, 0.01))
	pending_result = {
		"name": player_name if not player_name.is_empty() else "Speler",
		"id": Crypto.new().generate_random_bytes(16).hex_encode(),
		"route": route_index + 1,
		"time_seconds": duration,
		"building_hits": building_hits,
		"car_hits": car_hits,
		"red_light_hits": red_light_hits,
		"score": calculate_score(duration, building_hits, car_hits, red_light_hits),
		"played_at": Time.get_datetime_string_from_system(),
		"uploaded": false,
		"shared_saved": false,
	}
	pending_saved = false
	save_pending_result()
	return pending_result

static func save_pending_result() -> bool:
	if pending_result.is_empty():
		return false
	if pending_saved:
		return true
	var results := load_scores()
	var already_present := false
	for result in results:
		if result.get("id", "") == pending_result.get("id", ""):
			already_present = true
			break
	if not already_present:
		results.append(pending_result.duplicate())
	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("score", 0)) != int(b.get("score", 0)):
			return int(a.get("score", 0)) > int(b.get("score", 0))
		return float(a.get("time_seconds", 0.0)) < float(b.get("time_seconds", 0.0)))
	pending_saved = _write_scores(results)
	return pending_saved

static func _write_scores(results: Array[Dictionary]) -> bool:
	var file := FileAccess.open(score_file, FileAccess.WRITE)
	if file == null:
		push_error("Could not save local scores: " + error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify({"version": 2, "scores": results}, "\t"))
	file.flush()
	return file.get_error() == OK

static func pending_uploads() -> Array[Dictionary]:
	var pending: Array[Dictionary] = []
	for result in load_scores():
		if result.has("id") and not bool(result.get("uploaded", false)):
			pending.append(result)
	return pending

static func pending_shared_results() -> Array[Dictionary]:
	var pending: Array[Dictionary] = []
	for result in load_scores():
		if result.has("id") and not bool(result.get("shared_saved", false)):
			pending.append(result)
	return pending

static func is_shared(id: String) -> bool:
	for result in load_scores():
		if result.get("id", "") == id:
			return bool(result.get("shared_saved", false))
	return false

static func mark_shared(id: String) -> bool:
	var results := load_scores()
	var found := false
	for result in results:
		if result.get("id", "") == id:
			result["shared_saved"] = true
			found = true
	return _write_scores(results) if found else false

static func is_uploaded(id: String) -> bool:
	for result in load_scores():
		if result.get("id", "") == id:
			return bool(result.get("uploaded", false))
	return false

static func mark_uploaded(id: String) -> bool:
	var results := load_scores()
	var found := false
	for result in results:
		if result.get("id", "") == id:
			result["uploaded"] = true
			found = true
	if not found:
		return false
	return _write_scores(results)

static func load_scores() -> Array[Dictionary]:
	var scores: Array[Dictionary] = []
	if not FileAccess.file_exists(score_file):
		return scores
	var file := FileAccess.open(score_file, FileAccess.READ)
	if file == null:
		return scores
	var document = JSON.parse_string(file.get_as_text())
	if not document is Dictionary or not document.get("scores") is Array:
		return scores
	for item in document.scores:
		if item is Dictionary and item.has("name") and item.has("score"):
			scores.append(item)
	return scores

static func format_time(seconds: float) -> String:
	var whole := ceili(seconds)
	return "%02d:%02d" % [whole / 60, whole % 60]
