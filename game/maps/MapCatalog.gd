class_name MapCatalog
extends RefCounted

## The ONE listing API for "which maps may a versus match be played on", across all three
## places a map can come from:
##
##   [code]builtin[/code]    a res:// .tres shipped with the game -- the set
##                           [method MapLoader.get_available_maps] has always returned, which is
##                           what MatchSetup and the networked lobby's gallery offered before
##                           this class existed.
##   [code]custom[/code]     a user://maps/*.json map the player authored in the Map Creator.
##   [code]community[/code]  a user://maps/*.json map installed by
##                           [method CommunityClient.download_to_library]. Community DOWNLOADS
##                           land in the SAME directory and the SAME inert-JSON format as the
##                           creator's own saves (see docs/COMMUNITY_API.md "Payload
##                           validation"), so nothing on disk distinguishes the two -- the
##                           install is recorded in this class's own index instead (see
##                           [method note_community_install]). An unrecorded library map reads
##                           as "custom", which is the truthful default.
##
## Everything here is STATIC and quiet: a corrupt, hostile or simply out-of-date file is
## skipped or reported through a return value, never through the engine log
## (tests/README.md rule 1).
##
## SECURITY. Every user:// map is untrusted, player-authored content: it is only ever turned
## into a resource through [method MapResource.import_from_json], which runs the catalog-strict
## gate ([code]validate_map(strict_catalog = true)[/code]) and returns null on anything it does
## not recognise. No [code]ResourceLoader[/code] ever touches shared bytes, and a file that
## fails the gate is never listed, never transmitted and never installed.


## [code]source[/code] values in a [method versus_maps] entry.
const SOURCE_BUILTIN := "builtin"
const SOURCE_CUSTOM := "custom"
const SOURCE_COMMUNITY := "community"

## The player's map library: Map Creator saves AND community installs.
## Mirrors [constant MapLoader.CUSTOM_MAPS_DIR] / [constant CommunityClient.MAPS_DIR]
## (a literal for the same reason those two are: no load-order dependency between them).
const DEFAULT_MAPS_DIR := "user://maps/"

## Where a map received from a networked HOST is materialised for the duration of that match.
## Deliberately NOT the library: an opponent's map is match content, not something that
## silently joins the player's own collection.
const DEFAULT_SESSION_MAPS_DIR := "user://session_maps/"

## Which library files arrived from the community service. Kept OUTSIDE the maps directory --
## a .json sitting in user://maps/ would be scanned as if it were a map by every lister.
const DEFAULT_COMMUNITY_INDEX_PATH := "user://community_maps.json"

## Hard cap on a map payload carried inside a lobby [code]game_start[/code] message, measured
## on the serialised UTF-8 bytes. A lobby message is delivered over the same channel the match
## itself runs on, so an unbounded blob would stall the start for both peers; over-cap maps are
## simply not offered for networked play ([method network_eligible]).
const MAX_NETWORK_PAYLOAD_BYTES := 256 * 1024

# --- Path injection seams (tests/README.md rule 4) ---------------------------
# Tests point these at a temp directory so a listing test never reads -- or writes -- the
# player's real library. Never set in production.
static var _maps_dir: String = DEFAULT_MAPS_DIR
static var _session_maps_dir: String = DEFAULT_SESSION_MAPS_DIR
static var _community_index_path: String = DEFAULT_COMMUNITY_INDEX_PATH


static func set_maps_dir(dir: String) -> void:
	_maps_dir = _with_trailing_slash(dir) if not dir.is_empty() else DEFAULT_MAPS_DIR


static func maps_dir() -> String:
	return _maps_dir


static func set_session_maps_dir(dir: String) -> void:
	_session_maps_dir = _with_trailing_slash(dir) if not dir.is_empty() else DEFAULT_SESSION_MAPS_DIR


static func session_maps_dir() -> String:
	return _session_maps_dir


static func set_community_index_path(path: String) -> void:
	_community_index_path = path if not path.is_empty() else DEFAULT_COMMUNITY_INDEX_PATH


static func community_index_path() -> String:
	return _community_index_path


static func reset_paths() -> void:
	_maps_dir = DEFAULT_MAPS_DIR
	_session_maps_dir = DEFAULT_SESSION_MAPS_DIR
	_community_index_path = DEFAULT_COMMUNITY_INDEX_PATH


# --- The listing ------------------------------------------------------------

## Every map a VERSUS match may be played on, as
## [code]{ "path": String, "name": String, "source": String }[/code] with source one of
## [constant SOURCE_BUILTIN] / [constant SOURCE_CUSTOM] / [constant SOURCE_COMMUNITY].
## Builtins first (stable order), then the library sorted by file name.
##
## [param include_drafts] only affects BUILTINS, and only widens them: false (the default) is
## the player-facing Active set the networked lobby offers; true additionally lists a builtin
## still marked Inactive, which is what the local picker wants so a map can be play-tested.
##
## A library file is listed ONLY when it survives the strict gate AND is versus-shaped
## ([method is_versus_eligible]). So a corrupt download, a map naming an asset this install does
## not have, and a single-player map are all absent rather than offered and then failing to load.
static func versus_maps(include_drafts: bool = false) -> Array:
	var entries: Array = []

	# Builtins: reuse MapLoader's discovery so the active/draft rule and the res:// scan can
	# never drift from the list every other screen has always used.
	for map_path in MapLoader.get_available_maps(include_drafts):
		entries.append({
			"path": map_path,
			"name": map_name_for(map_path),
			"source": SOURCE_BUILTIN,
		})

	var community: Dictionary = _community_index()
	for json_path in library_paths():
		var res: MapResource = _import_library_map(json_path)
		if res == null:
			continue
		if not is_versus_eligible(res):
			continue
		entries.append({
			"path": json_path,
			"name": _resource_display_name(res, json_path),
			"source": SOURCE_COMMUNITY if community.has(json_path) else SOURCE_CUSTOM,
		})

	return entries


## The .json files in the player's library, sorted, full paths. Dot-files are skipped (a
## hidden bookkeeping file is not a map).
static func library_paths() -> Array:
	var out: Array = []
	var dir: DirAccess = DirAccess.open(_maps_dir)
	if dir == null:
		return out
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json") and not file_name.begins_with("."):
			out.append(_maps_dir + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


## True when [param path] is a map shipped with the game. res:// is the whole test: only the
## build can put a file there, so it is the one map source that needs no validation and never
## has to be transmitted to a peer.
static func is_builtin(path: String) -> bool:
	return path.begins_with("res://")


## Where [param path] came from: [constant SOURCE_BUILTIN] / [constant SOURCE_COMMUNITY] /
## [constant SOURCE_CUSTOM]. A library map with no recorded install is "custom".
static func source_for(path: String) -> String:
	if is_builtin(path):
		return SOURCE_BUILTIN
	return SOURCE_COMMUNITY if _community_index().has(path) else SOURCE_CUSTOM


## Whether a map is shaped for VERSUS: two or more DISTINCT players own a "Start" slot.
##
## A Start point is a squad chair -- the thing a participant's roster fills (see
## [method MapLoader._load_units]). Respawn / Endless / Reinforcement points are map FURNITURE
## (garrisons, portals, waves), so a map whose only second "player" is furniture has nobody for
## the opponent to BE. The catalog-strict gate already demands two players with spawns; this is
## the versus-specific half on top of it.
static func is_versus_eligible(res: MapResource) -> bool:
	if res == null:
		return false
	var start_players: Dictionary = {}
	for spawn_data in res.unit_spawns:
		if not (spawn_data is Dictionary):
			continue
		if res.get_spawn_kind(spawn_data) != MapResource.SPAWN_KIND_START:
			continue
		var player_id: int = int((spawn_data as Dictionary).get("player_id", -1))
		if player_id >= 0:
			start_players[player_id] = true
	return start_players.size() >= 2


## Best-effort display name for [param path], or "" when THIS machine cannot resolve it --
## which is the normal case for an opponent's vote on a map we do not have. Callers fall back
## to whatever name travelled with the vote.
static func map_name_for(path: String) -> String:
	if path.is_empty():
		return ""
	if is_builtin(path):
		if not ResourceLoader.exists(path):
			return ""
		var res = load(path)
		if res is MapResource and not (res as MapResource).map_name.strip_edges().is_empty():
			return (res as MapResource).map_name
		return path.get_file().get_basename()
	# Library / session JSON: read the name WITHOUT the strict gate. Listing rejects an invalid
	# map, but naming one (in a vote line, in a rejection notice) must still work.
	var text: String = _read_text(path)
	if text.is_empty():
		return ""
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		return path.get_file().get_basename()
	var map_info: Variant = (json.data as Dictionary).get("map_info", {})
	if map_info is Dictionary:
		var name_value: String = String((map_info as Dictionary).get("name", "")).strip_edges()
		if not name_value.is_empty():
			return name_value
	return path.get_file().get_basename()


# --- Payloads ---------------------------------------------------------------

## The map at [param path] as a transmissible JSON payload, or [code]{}[/code] on any failure.
##
## The Dictionary is the VALIDATED resource's own export, never the bytes that were on disk:
## round-tripping through [MapResource] normalises the payload to exactly the schema the
## importer accepts and drops anything a file smuggled in, so what a host sends is precisely
## what a client's own gate will accept.
static func load_payload(path: String) -> Dictionary:
	if path.is_empty():
		return {}
	var res: MapResource = null
	if is_builtin(path):
		if not ResourceLoader.exists(path):
			return {}
		res = load(path) as MapResource
	else:
		res = _import_library_map(path)
	if res == null:
		return {}
	var json := JSON.new()
	if json.parse(res.export_to_json()) != OK or not (json.data is Dictionary):
		return {}
	return json.data


## Serialised UTF-8 size of [param payload] -- the figure [constant MAX_NETWORK_PAYLOAD_BYTES]
## caps, so callers measure the same thing the wire carries.
static func payload_size_bytes(payload: Dictionary) -> int:
	if payload.is_empty():
		return 0
	return JSON.stringify(payload).to_utf8_buffer().size()


## Whether [param path] may be offered for a NETWORKED match.
##
## A builtin always may: both peers have it, so nothing is transmitted. Anything else has to
## ride inside the host's game_start message, so it must (a) still pass the strict gate and
## (b) serialise within [constant MAX_NETWORK_PAYLOAD_BYTES]. This is a plain bool the picker
## can read to grey a map out, and the host's last-line check before it broadcasts.
static func network_eligible(path: String) -> bool:
	if path.is_empty():
		return false
	if is_builtin(path):
		return ResourceLoader.exists(path)
	var payload: Dictionary = load_payload(path)
	if payload.is_empty():
		return false
	return payload_size_bytes(payload) <= MAX_NETWORK_PAYLOAD_BYTES


## Materialise a map payload received from a networked HOST, returning the path the battle
## should boot from -- or "" when the payload is over-cap, malformed or fails the strict gate,
## in which case NOTHING is written and the caller must refuse the match.
##
## The file lands in [member _session_maps_dir] as inert JSON, which is exactly the format
## [method MapLoader.load_map_from_json_file] consumes -- so an opponent's map boots through
## the SAME one hardened path as a map the player authored themselves. Overwriting is
## deliberate: a session map is scratch space for the match in progress.
static func install_session_payload(payload: Dictionary) -> String:
	if payload.is_empty():
		return ""
	var text: String = JSON.stringify(payload)
	if text.to_utf8_buffer().size() > MAX_NETWORK_PAYLOAD_BYTES:
		return ""
	# Quiet: a rejected peer payload is an EXPECTED outcome for untrusted input, reported
	# through the "" return rather than the engine log.
	var res: MapResource = MapResource.import_from_json(text, true)
	if res == null:
		return ""

	if not DirAccess.dir_exists_absolute(_session_maps_dir):
		DirAccess.make_dir_recursive_absolute(_session_maps_dir)
	var stem: String = _sanitize_stem(res.map_name)
	if stem.is_empty():
		stem = "session_map_" + str(text.hash())
	var path: String = _session_maps_dir + stem + ".json"

	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	# The VALIDATED resource's own export -- never the bytes that arrived.
	file.store_string(res.export_to_json())
	file.close()
	return path


## Drop every materialised session map. Safe to call when the directory was never created.
static func clear_session_maps() -> int:
	var removed: int = 0
	var dir: DirAccess = DirAccess.open(_session_maps_dir)
	if dir == null:
		return removed
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			if dir.remove(file_name) == OK:
				removed += 1
		file_name = dir.get_next()
	dir.list_dir_end()
	return removed


# --- Community install index ------------------------------------------------

## Record that [param path] was installed from the community service, so
## [method versus_maps] can badge it [constant SOURCE_COMMUNITY] rather than as the player's
## own work. Idempotent, and prunes entries whose file has since been deleted.
##
## Called by whoever completes a download (the community browse screen, off
## [method CommunityClient.download_to_library]'s result path). Not calling it is harmless:
## the map is still listed and still playable, just labelled "custom".
static func note_community_install(path: String) -> bool:
	if path.strip_edges().is_empty() or is_builtin(path):
		return false
	var index: Dictionary = _community_index()
	index[path] = true
	return _write_community_index(index)


## True when [param path] is recorded as a community install.
static func is_community_install(path: String) -> bool:
	return _community_index().has(path)


## path -> true for every recorded community install whose file still exists.
static func _community_index() -> Dictionary:
	var out: Dictionary = {}
	var text: String = _read_text(_community_index_path)
	if text.is_empty():
		return out
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		return out
	var paths: Variant = (json.data as Dictionary).get("paths", [])
	if not (paths is Array):
		return out
	for entry in (paths as Array):
		var p: String = String(entry).strip_edges()
		if p.is_empty() or not FileAccess.file_exists(p):
			continue
		out[p] = true
	return out


static func _write_community_index(index: Dictionary) -> bool:
	var paths: Array = index.keys()
	paths.sort()
	var file: FileAccess = FileAccess.open(_community_index_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"paths": paths}))
	file.close()
	return true


# --- Internals --------------------------------------------------------------

## A library / session map through the HARDENED importer, or null when the file is missing,
## unreadable, malformed or fails the catalog-strict gate. Quiet on purpose: skipping a bad
## file during a LISTING is an expected outcome, not an error worth a log line.
static func _import_library_map(path: String) -> MapResource:
	var text: String = _read_text(path)
	if text.is_empty():
		return null
	return MapResource.import_from_json(text, true)


static func _resource_display_name(res: MapResource, path: String) -> String:
	if res != null and not res.map_name.strip_edges().is_empty():
		return res.map_name
	return path.get_file().get_basename()


static func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


## Lowercase alnum + underscore file stem (mirrors CommunityClient's / ChallengeCodec's).
static func _sanitize_stem(name: String) -> String:
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


static func _with_trailing_slash(dir: String) -> String:
	return dir if dir.ends_with("/") else dir + "/"
