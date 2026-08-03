class_name HttpProvider
extends CommunityProvider

## The REAL community client: HTTPRequest against a configured base_url, speaking the
## contract in docs/COMMUNITY_API.md. It is intentionally THIN -- every method is one
## request with a timeout, a status->result mapping, and a JSON parse -- so it stays
## obviously correct until a live service exists to exercise it.
##
## Selection is handled by [CommunityClient]: this provider is used only when
## user://community.cfg supplies a base_url; otherwise the offline [LocalProvider] runs.
##
## HTTPRequest is a Node and must live in the tree, so each call spawns a short-lived
## HTTPRequest under the scene root and frees it on completion.

const TIMEOUT_SEC := 15.0

var _base_url: String


func _init(base_url: String) -> void:
	# Trim a trailing slash so path concatenation is unambiguous.
	_base_url = base_url.strip_edges().trim_suffix("/")


# --- API --------------------------------------------------------------------

func list_items(sort: String, type: String, page: int, cb: Callable, query: String = "") -> void:
	var params: String = "?sort=%s&type=%s&page=%d" % [
		sort.uri_encode(), type.uri_encode(), maxi(0, page)]
	# The needle is sanitised (trimmed + capped) BEFORE it is encoded, so an absurd paste
	# never becomes an absurd URL; an empty search sends no `q` at all.
	var needle: String = sanitize_query(query)
	if not needle.is_empty():
		params += "&q=" + needle.uri_encode()
	_request(HTTPClient.METHOD_GET, "/v1/items" + params, {}, cb, false)


func fetch_item(id: String, cb: Callable) -> void:
	_request(HTTPClient.METHOD_GET, "/v1/items/" + id.uri_encode(), {}, cb, true)


func upload(payload: Dictionary, cb: Callable) -> void:
	_request(HTTPClient.METHOD_POST, "/v1/items", payload, cb, true)


func vote(id: String, dir: int, cb: Callable) -> void:
	_request(HTTPClient.METHOD_POST, "/v1/items/%s/vote" % id.uri_encode(),
		{"dir": clampi(dir, -1, 1)}, cb, true)


func daily(cb: Callable) -> void:
	_request(HTTPClient.METHOD_GET, "/v1/daily", {}, cb, true)


func report_attempt(id: String, outcome: Dictionary, cb: Callable) -> void:
	# Sanitised client-side so the wire body is already the exact 3-key shape; the server
	# MUST re-sanitise anyway (a client is never a validator).
	var body: Dictionary = sanitize_outcome(outcome)
	# The replay rides as a fourth key ONLY when it passes the same gate the store applies --
	# so a blob that would be dropped server-side is never even uploaded.
	var replay_b64: String = sanitize_replay_b64(outcome.get(REPLAY_KEY, ""))
	if not replay_b64.is_empty():
		body[REPLAY_KEY] = replay_b64
	_request(HTTPClient.METHOD_POST, "/v1/items/%s/attempts" % id.uri_encode(), body, cb, true)


## GET the owner-only attempt ledger. The response is normalised to the pinned
## { entries, has_more } shape so a screen never has to guess what a sparse server sent.
func attempt_log(id: String, page: int, cb: Callable) -> void:
	var handler: Callable = func(result: Dictionary) -> void:
		if not bool(result.get("ok", false)):
			_emit(cb, result)
			return
		var data: Variant = result.get("data", {})
		var body: Dictionary = data if data is Dictionary else {}
		var entries: Variant = body.get("entries", [])
		_emit(cb, ok({
			"entries": entries if entries is Array else [],
			"has_more": bool(body.get("has_more", false)),
		}))
	_request(HTTPClient.METHOD_GET,
		"/v1/items/%s/attempts?page=%d" % [id.uri_encode(), maxi(0, page)], {}, handler, false)


## GET one attempt's replay. The service answers { "replay_b64": ... }; the contract here is
## the STRING, so the envelope is unwrapped and an empty/absent blob reads as
## [constant ERR_NOT_FOUND] rather than as a successful empty replay.
func fetch_attempt_replay(attempt_id: String, cb: Callable) -> void:
	var handler: Callable = func(result: Dictionary) -> void:
		if not bool(result.get("ok", false)):
			_emit(cb, result)
			return
		var data: Variant = result.get("data", {})
		var b64: String = String((data as Dictionary).get(REPLAY_KEY, "")) if data is Dictionary else ""
		if b64.is_empty():
			_emit(cb, fail(ERR_NOT_FOUND))
			return
		_emit(cb, ok(b64))
	_request(HTTPClient.METHOD_GET, "/v1/attempts/%s/replay" % attempt_id.uri_encode(),
		{}, handler, false)


## The caller is identified by the X-Community-Device header every request already carries,
## so "me" needs no path parameter.
func my_bases(cb: Callable) -> void:
	_request(HTTPClient.METHOD_GET, "/v1/me/bases", {}, cb, false)


func set_base_active(id: String, active: bool, cb: Callable) -> void:
	_request(HTTPClient.METHOD_POST, "/v1/items/%s/active" % id.uri_encode(),
		{"active": active}, cb, true)


# --- Request plumbing -------------------------------------------------------

## Issue one request. [param has_body] sends [param body] as JSON (POST). [param cb]
## always receives the uniform result shape. Failures (transport, timeout, non-2xx,
## unparseable body) map to {ok:false, error:...}.
func _request(method: int, path: String, body: Dictionary, cb: Callable, has_body: bool) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		_emit(cb, fail("No scene tree available for HTTP."))
		return

	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_SEC
	tree.root.add_child(http)

	var headers: PackedStringArray = PackedStringArray([
		"Accept: application/json",
		"X-Community-Device: " + device_id(),
	])
	var body_text: String = ""
	if has_body:
		headers.append("Content-Type: application/json")
		body_text = JSON.stringify(body)

	http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, resp: PackedByteArray):
		_finish(http, cb, result, code, resp))

	var err: int = http.request(_base_url + path, headers, method, body_text)
	if err != OK:
		http.queue_free()
		_emit(cb, fail("Request could not be started (error %d)." % err))


func _finish(http: HTTPRequest, cb: Callable, result: int, code: int, resp: PackedByteArray) -> void:
	http.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		_emit(cb, fail("Network error (%d)." % result))
		return
	if code < 200 or code >= 300:
		_emit(cb, fail(_error_from_body(resp, code)))
		return

	var text: String = resp.get_string_from_utf8()
	if text.strip_edges().is_empty():
		_emit(cb, ok({}))
		return
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		_emit(cb, fail("Server returned an unreadable response."))
		return
	_emit(cb, ok(parsed))


## Pull the server's {"error": ...} message out of an error body, or fall back to the code.
func _error_from_body(resp: PackedByteArray, code: int) -> String:
	var parsed: Variant = JSON.parse_string(resp.get_string_from_utf8())
	if parsed is Dictionary and (parsed as Dictionary).has("error"):
		return String((parsed as Dictionary)["error"])
	return "Server returned HTTP %d." % code
