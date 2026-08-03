class_name CommunityClient
extends RefCounted

## Front door to the community service for the UI. It:
##   * picks the transport ([LocalProvider] offline, or [HttpProvider] when
##     user://community.cfg supplies a base_url) -- so screens never touch a provider;
##   * forwards the read/write API (list+search / fetch / vote / upload / daily /
##     report_attempt / attempt_log / fetch_attempt_replay / my_bases / set_base_active)
##     unchanged;
##   * adds [method download_to_library], the ONLY safe path from an untrusted downloaded
##     payload to a saved, playable file -- which is also where the item's service id is
##     stamped into the challenge as "community_id", the handle the completion flow later
##     reports attempts against.
##
## SECURITY: a downloaded payload is player-authored, untrusted content. It is turned into
## something on disk ONLY through the two hardened importers:
##   * challenges -> [method ChallengeCodec.validate] then [method ChallengeCodec.save_to_file];
##   * bare maps  -> [method MapResource.import_from_json] (catalog-strict) then a re-EXPORT
##     of the VALIDATED in-memory resource as inert JSON (never the raw bytes, and never a
##     .tres -- a shared .tres is an arbitrary-code-execution vector, so no ResourceLoader
##     ever touches shared input; this matches what the in-game Map Creator writes).
## A payload that fails validation is rejected and NOTHING is written.

const CONFIG_PATH := "user://community.cfg"

## Where downloaded bare maps are saved, as inert JSON. This is the SAME directory and format
## the Map Creator writes (see [constant MapLoader.CUSTOM_MAPS_DIR]), so a downloaded map is
## discovered by [method MapLoader.get_available_map_entries] with origin "custom" and loads
## through [method MapLoader.load_map_from_json_file] like any player-authored map.
const MAPS_DIR := "user://maps/"

var _provider: CommunityProvider


## [param provider] lets tests inject a specific provider (e.g. a temp-dir LocalProvider);
## when omitted the provider is chosen from config presence.
func _init(provider: CommunityProvider = null) -> void:
	_provider = provider if provider != null else _make_provider()


## Choose the transport: an HttpProvider when a base_url is configured, else the offline
## LocalProvider. This single check is the whole switch to a live service.
static func _make_provider() -> CommunityProvider:
	if FileAccess.file_exists(CONFIG_PATH):
		var cfg := ConfigFile.new()
		if cfg.load(CONFIG_PATH) == OK:
			var base_url: String = String(cfg.get_value("service", "base_url", "")).strip_edges()
			if not base_url.is_empty():
				return HttpProvider.new(base_url)
	return LocalProvider.new()


## True when running against the offline sandbox (drives the UI's local-mode banner).
func is_local() -> bool:
	return _provider is LocalProvider


## The live provider (so the UI can read local-only extras like [method LocalProvider.my_vote]).
func provider() -> CommunityProvider:
	return _provider


# --- Forwarded API ----------------------------------------------------------

## [param query] is an optional case-insensitive title/author search; "" is no filter.
func list_items(sort: String, type: String, page: int, cb: Callable, query: String = "") -> void:
	_provider.list_items(sort, type, page, cb, query)


func fetch_item(id: String, cb: Callable) -> void:
	_provider.fetch_item(id, cb)


func upload(payload: Dictionary, cb: Callable) -> void:
	_provider.upload(payload, cb)


func vote(id: String, dir: int, cb: Callable) -> void:
	_provider.vote(id, dir, cb)


func daily(cb: Callable) -> void:
	_provider.daily(cb)


## Record one play of a community item. [param id] is the `community_id` stamped into the
## installed challenge by [method install_payload] -- the challenge-completion flow reads it
## off the challenge it just finished and calls this. [param outcome] is
## { cleared: bool, score: int, turns: int }, optionally plus
## [constant CommunityProvider.REPLAY_KEY] (base64 of the attacker's replay container); it is
## all sanitised at the provider boundary, and a replay that fails the gate is dropped WITHOUT
## costing the attempt.
func report_attempt(id: String, outcome: Dictionary, cb: Callable) -> void:
	if id.strip_edges().is_empty():
		# A locally authored or pre-stamping challenge simply has no ledger to write to.
		# That is an ordinary outcome, not an error the play flow should surface.
		CommunityProvider._emit(cb, CommunityProvider.fail(CommunityProvider.ERR_NOT_FOUND))
		return
	_provider.report_attempt(id, outcome, cb)


## One page of the per-attempt ledger for one of MY OWN bases (newest first,
## [constant CommunityProvider.PAGE_SIZE] per page). data =
## { entries: [{ attempt_id, cleared, score, turns, at, has_replay }], has_more: bool }.
## Someone else's base fails with "not_owner", an unknown id with "not_found".
func attempt_log(id: String, page: int, cb: Callable) -> void:
	if id.strip_edges().is_empty():
		CommunityProvider._emit(cb, CommunityProvider.fail(CommunityProvider.ERR_NOT_FOUND))
		return
	_provider.attempt_log(id, page, cb)


## The replay attached to one attempt, as base64 of its CQRP container (data = String).
## Same owner gate as [method attempt_log]; "not_found" when the attempt carried no blob or
## its blob has aged out of the retention window.
func fetch_attempt_replay(attempt_id: String, cb: Callable) -> void:
	if attempt_id.strip_edges().is_empty():
		CommunityProvider._emit(cb, CommunityProvider.fail(CommunityProvider.ERR_NOT_FOUND))
		return
	_provider.fetch_attempt_replay(attempt_id, cb)


## This device's own uploaded challenges (active and retired), with their counters.
func my_bases(cb: Callable) -> void:
	_provider.my_bases(cb)


## Publish / retire one of this device's own bases. Fails with "base_limit" past
## [constant CommunityProvider.MAX_ACTIVE_BASES] active, "not_owner" for someone else's.
func set_base_active(id: String, active: bool, cb: Callable) -> void:
	_provider.set_base_active(id, active, cb)


# --- Download to library (the guarded write path) ---------------------------

## Fetch an item's payload and install it into the local library. [param cb] receives the
## uniform result: on success data = { status: "downloaded"|"already_owned", path, type }.
func download_to_library(item: Dictionary, cb: Callable) -> void:
	var id: String = String(item.get("id", ""))
	var item_type: String = String(item.get("type", ""))
	if id.is_empty():
		CommunityProvider._emit(cb, CommunityProvider.fail("Item has no id."))
		return
	_provider.fetch_item(id, func(result: Dictionary):
		if not bool(result.get("ok", false)):
			CommunityProvider._emit(cb, result)
			return
		var payload: Variant = result.get("data", {})
		if not (payload is Dictionary):
			CommunityProvider._emit(cb, CommunityProvider.fail("Malformed payload."))
			return
		CommunityProvider._emit(cb, install_payload(item_type, payload, id))
	)


## Validate + save a payload synchronously. This is the hardened core of
## [method download_to_library], exposed so the guard can be unit-tested directly. A
## payload that fails validation returns {ok:false} and writes NOTHING.
##
## [param community_id] is the SERVICE's id for the item. It is stamped into the installed
## challenge as "community_id" so the completion flow can call [method report_attempt] with
## it. Bare maps are not stamped: they have no ledger (nothing attempts a map), and their
## file is written by re-exporting the validated [MapResource], which only knows map fields.
func install_payload(item_type: String, payload: Dictionary, community_id: String = "") -> Dictionary:
	match item_type:
		CommunityProvider.TYPE_CHALLENGE:
			return _install_challenge(payload, community_id)
		CommunityProvider.TYPE_MAP:
			return _install_map(payload)
	# Unknown type: probe the shape rather than trust the label, then route.
	if payload.has("format_version") and payload.has("rules"):
		return _install_challenge(payload, community_id)
	if payload.has("dimensions") and payload.has("layout"):
		return _install_map(payload)
	return CommunityProvider.fail("Unrecognised item type '%s'." % item_type)


func _install_challenge(payload: Dictionary, community_id: String = "") -> Dictionary:
	var errors: Array[String] = ChallengeCodec.validate(payload)
	if not errors.is_empty():
		return CommunityProvider.fail("Challenge rejected: %s" % errors[0])

	# Already owned? Match by content id so a re-download is idempotent.
	var id: String = ChallengeCodec.challenge_id(payload)
	for entry in ChallengeCodec.list_saved():
		var saved: Dictionary = entry.get("challenge", {})
		if ChallengeCodec.challenge_id(saved) == id and not id.is_empty():
			var owned_path: String = String(entry.get("path", ""))
			# Backfill: a copy saved before we knew its service id (or authored locally and
			# later published) would otherwise never report attempts. The stem is reused so
			# this rewrites the SAME file rather than adding a second copy.
			if not community_id.is_empty() and String(saved.get("community_id", "")) != community_id:
				saved["community_id"] = community_id
				ChallengeCodec.save_to_file(saved, owned_path.get_file().get_basename())
			return CommunityProvider.ok({"status": "already_owned", "path": owned_path,
				"type": CommunityProvider.TYPE_CHALLENGE, "community_id": community_id})

	# Stamp a COPY, and only after validation passed: the id is our metadata, not the
	# author's content. ChallengeCodec.content_hash() hashes a fixed field list, so the extra
	# key leaves the checksum -- and any later re-validation of the saved file -- untouched.
	var to_save: Dictionary = payload.duplicate(true)
	if not community_id.is_empty():
		to_save["community_id"] = community_id

	var path: String = ChallengeCodec.save_to_file(to_save)
	if path.is_empty():
		return CommunityProvider.fail("Could not save the challenge.")
	return CommunityProvider.ok({"status": "downloaded", "path": path,
		"type": CommunityProvider.TYPE_CHALLENGE, "community_id": community_id})


func _install_map(payload: Dictionary) -> Dictionary:
	# import_from_json is ALWAYS catalog-strict (it validates before returning), and returns
	# null on anything invalid -> reject, write nothing. The `true` is its quiet flag: a
	# rejection here is an EXPECTED outcome for untrusted input, reported through our own
	# result rather than push_error.
	var res: MapResource = MapResource.import_from_json(JSON.stringify(payload), true)
	if res == null:
		return CommunityProvider.fail("Map failed validation (unknown assets, bad size, or out-of-bounds cells).")

	if not DirAccess.dir_exists_absolute(MAPS_DIR):
		DirAccess.make_dir_recursive_absolute(MAPS_DIR)
	var stem: String = _sanitize_stem(res.map_name)
	if stem.is_empty():
		stem = "map_" + str(JSON.stringify(payload).hash())
	var path: String = MAPS_DIR + stem + ".json"
	# Never overwrite: a re-download is idempotent, and a same-name map the player authored
	# themselves is left alone (reported as owned) rather than being clobbered by a stranger's.
	if FileAccess.file_exists(path):
		return CommunityProvider.ok({"status": "already_owned", "path": path, "type": CommunityProvider.TYPE_MAP})

	# Write the VALIDATED resource's OWN export -- never the untrusted bytes. Round-tripping
	# through MapResource normalises the file to exactly the schema the importer accepts and
	# drops anything the payload smuggled in, and the result is inert JSON (no .tres, so
	# nothing here is ever handed to ResourceLoader).
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return CommunityProvider.fail("Could not write to the map library.")
	file.store_string(res.export_to_json())
	file.close()
	return CommunityProvider.ok({"status": "downloaded", "path": path, "type": CommunityProvider.TYPE_MAP})


## Lowercase alnum + underscore file stem (mirrors ChallengeCodec's sanitiser).
func _sanitize_stem(name: String) -> String:
	var lowered: String = name.strip_edges().to_lower()
	var out: String = ""
	for i in lowered.length():
		var c: String = lowered[i]
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
		elif c == " " or c == "-" or c == "_":
			out += "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	return out.strip_edges().trim_prefix("_").trim_suffix("_")
