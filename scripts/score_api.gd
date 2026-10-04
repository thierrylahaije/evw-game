extends Node
## Client for our score server. No Turso URL or token is ever used here.

signal round_uploaded(id: String)
signal leaderboard_received(scores: Array)

const Session = preload("res://scripts/game_session.gd")
const RETRY_SECONDS := 30.0

var base_url := ""
var upload_request: HTTPRequest
var leaderboard_request: HTTPRequest
var uploading_id := ""
var leaderboard_busy := false

func _ready() -> void:
	# The public Worker URL is supplied by the HTML shell at deployment time.
	# No database credential is included in the exported game.
	if OS.has_feature("web"):
		base_url = String(JavaScriptBridge.eval("window.EVW_API_BASE_URL || ''")).strip_edges()
	else:
		base_url = OS.get_environment("EVW_SCORE_API_URL").strip_edges()
	if base_url.is_empty():
		var setting := "score_api/web_base_url" if OS.has_feature("web") else "score_api/base_url"
		base_url = String(ProjectSettings.get_setting(setting, "")).strip_edges()
	base_url = base_url.trim_suffix("/")
	upload_request = HTTPRequest.new()
	upload_request.timeout = 8.0
	upload_request.request_completed.connect(_on_upload_completed)
	add_child(upload_request)
	leaderboard_request = HTTPRequest.new()
	leaderboard_request.timeout = 8.0
	leaderboard_request.request_completed.connect(_on_leaderboard_completed)
	add_child(leaderboard_request)
	var retry := Timer.new()
	retry.wait_time = RETRY_SECONDS
	retry.autostart = true
	retry.timeout.connect(sync_pending)
	add_child(retry)
	sync_pending.call_deferred()

func available() -> bool:
	return base_url.begins_with("http://") or base_url.begins_with("https://")

func register_player(name: String) -> void:
	if not available():
		return
	var request := HTTPRequest.new()
	request.timeout = 8.0
	add_child(request)
	request.request_completed.connect(func(_result: int, _code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
		request.queue_free())
	var error := request.request(base_url + "/api/players", ["Content-Type: application/json"],
		HTTPClient.METHOD_POST, JSON.stringify({"name": name}))
	if error != OK:
		request.queue_free()

func sync_pending() -> void:
	if not available() or not uploading_id.is_empty():
		return
	var pending := Session.pending_uploads()
	if pending.is_empty():
		return
	var result: Dictionary = pending[0]
	uploading_id = String(result.id)
	var payload := {
		"id": uploading_id,
		"name": result.name,
		"route": int(result.route),
		"time_seconds": float(result.time_seconds),
		"building_hits": int(result.building_hits),
		"car_hits": int(result.car_hits),
		"red_light_hits": int(result.get("red_light_hits", 0)),
	}
	var error := upload_request.request(base_url + "/api/rounds", ["Content-Type: application/json"],
		HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		uploading_id = ""

func _on_upload_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var completed_id := uploading_id
	uploading_id = ""
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var response = JSON.parse_string(body.get_string_from_utf8())
	if not response is Dictionary or response.get("id", "") != completed_id or not response.get("saved", false):
		return
	if Session.mark_uploaded(completed_id):
		round_uploaded.emit(completed_id)
		sync_pending.call_deferred()

func fetch_leaderboard() -> void:
	if not available() or leaderboard_busy:
		return
	leaderboard_busy = true
	var error := leaderboard_request.request(base_url + "/api/leaderboard?limit=10")
	if error != OK:
		leaderboard_busy = false

func _on_leaderboard_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	leaderboard_busy = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var response = JSON.parse_string(body.get_string_from_utf8())
	if response is Dictionary and response.get("scores") is Array:
		leaderboard_received.emit(response.scores)
