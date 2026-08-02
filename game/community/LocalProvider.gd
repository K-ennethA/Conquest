class_name LocalProvider
extends CommunityProvider

## Offline / development mock of the community service, backed entirely by user:// files.
## It makes the whole Community UI (browse, sort, vote, download) work with ZERO network,
## and gives the tests a deterministic fixture. It self-seeds on first use from TRUSTED
## res:// content, so a fresh install already has something to browse.
##
## Storage (under [member _root], default user://community_mock/):
##   items.json            -- the index: { "items": [summary...], "my_votes": { id: dir } }
##   payloads/<id>.json    -- the full map / challenge JSON for each item
##
## All callbacks fire SYNCHRONOUSLY (there is no I/O to await), which is what lets the
## tests assert on results inline. The on-wire shapes match docs/COMMUNITY_API.md so a
## screen written against this provider works unchanged against [HttpProvider].

const DEFAULT_ROOT := "user://community_mock/"

## res:// maps seeded as downloadable "map" items (trusted builtin content).
const SEED_MAP_PATHS: Array[String] = [
	"res://game/maps/resources/skirmish_arena.tres",
	"res://game/maps/resources/default_skirmish.tres",
]

var _root: String
var _payload_dir: String


## [param root] lets tests point the mock at a throwaway directory (and clean it up).
func _init(root: String = DEFAULT_ROOT) -> void:
	_root = root if root.ends_with("/") else root + "/"
	_payload_dir = _root + "payloads/"


# --- API --------------------------------------------------------------------

func list_items(sort: String, type: String, page: int, cb: Callable) -> void:
	var index: Dictionary = _load_index()
	var items: Array = index.get("items", [])

	# Type filter ("all" keeps everything).
	var filtered: Array = []
	for it in items:
		if type == TYPE_ALL or type == "" or String(it.get("type", "")) == type:
			filtered.append(it)

	filtered = _sort_items(filtered, sort)

	var start: int = maxi(0, page) * PAGE_SIZE
	var slice: Array = []
	if start < filtered.size():
		slice = filtered.slice(start, mini(start + PAGE_SIZE, filtered.size()))
	_emit(cb, ok(slice))


func fetch_item(id: String, cb: Callable) -> void:
	_ensure_seeded()
	var payload: Dictionary = _load_payload(id)
	if payload.is_empty():
		_emit(cb, fail("Item '%s' not found." % id))
		return
	_emit(cb, ok(payload))


func upload(payload: Dictionary, cb: Callable) -> void:
	var index: Dictionary = _load_index()
	var summary: Dictionary = _summary_for_payload(payload, 0, Time.get_datetime_string_from_system())
	if summary.is_empty():
		_emit(cb, fail("Payload is not a recognisable map or challenge."))
		return
	# Ids are content hashes, so re-uploading the same payload is a duplicate. Refuse it the
	# same way the reference server does (409) rather than growing a second index entry --
	# a screen written against this mock then behaves identically online.
	for existing in index.get("items", []):
		if String(existing.get("id", "")) == String(summary["id"]):
			_emit(cb, fail("Item already exists."))
			return
	_write_payload(String(summary["id"]), payload)
	var items: Array = index.get("items", [])
	items.append(summary)
	index["items"] = items
	_save_index(index)
	_emit(cb, ok(summary))


func vote(id: String, dir: int, cb: Callable) -> void:
	var clamped: int = clampi(dir, -1, 1)
	var index: Dictionary = _load_index()
	var my_votes: Dictionary = index.get("my_votes", {})
	var prev: int = int(my_votes.get(id, 0))

	var found: Dictionary = {}
	for it in index.get("items", []):
		if String(it.get("id", "")) == id:
			found = it
			break
	if found.is_empty():
		_emit(cb, fail("Item '%s' not found." % id))
		return

	# Idempotent per device: applying the same dir twice is a no-op; the net change is
	# only the DELTA from this device's previous vote.
	found["votes"] = int(found.get("votes", 0)) + (clamped - prev)
	if clamped == 0:
		my_votes.erase(id)
	else:
		my_votes[id] = clamped
	index["my_votes"] = my_votes
	_save_index(index)
	_emit(cb, ok({"id": id, "votes": int(found["votes"])}))


func daily(cb: Callable) -> void:
	_emit(cb, ok({"id": _daily_id()}))


## This device's current vote on an item (1 / -1 / 0), so the UI can pre-highlight the
## up/down buttons. Local convenience -- not part of the network contract.
func my_vote(id: String) -> int:
	return int(_load_index().get("my_votes", {}).get(id, 0))


# --- Sorting / daily --------------------------------------------------------

func _sort_items(items: Array, sort: String) -> Array:
	var out: Array = items.duplicate()
	match sort:
		SORT_NEW:
			out.sort_custom(func(a, b): return String(a.get("created", "")) > String(b.get("created", "")))
		SORT_DAILY:
			# Featured pick first, then the rest by score -- so the Daily tab leads with
			# the pick but is not a dead end.
			var pick: String = _daily_id()
			out.sort_custom(func(a, b): return int(a.get("votes", 0)) > int(b.get("votes", 0)))
			for i in out.size():
				if String(out[i].get("id", "")) == pick:
					var featured: Variant = out.pop_at(i)
					out.insert(0, featured)
					break
		_:  # SORT_TOP (default): highest score first.
			out.sort_custom(func(a, b): return int(a.get("votes", 0)) > int(b.get("votes", 0)))
	return out


## Deterministic daily pick: a hash of today's date modulo the item count, so the choice
## is stable within a calendar day and changes the next. Mirrors the challenge daily trick.
func _daily_id() -> String:
	var index: Dictionary = _load_index()
	var items: Array = index.get("items", [])
	if items.is_empty():
		return ""
	var seed_str: String = Time.get_date_string_from_system()
	var idx: int = abs(seed_str.hash()) % items.size()
	return String(items[idx].get("id", ""))


# --- Seeding ----------------------------------------------------------------

func _ensure_seeded() -> void:
	if FileAccess.file_exists(_root + "items.json"):
		return
	_seed()


## Build the initial catalogue: a couple of builtin maps plus one demo challenge, so a
## fresh install has content to browse and rank offline.
func _seed() -> void:
	_ensure_dirs()
	var items: Array = []
	# Seeded scores/attempts are arbitrary but fixed so ordering + Held% are demonstrable.
	var seed_votes: Array[int] = [42, 17]
	var seed_created: Array[String] = ["2026-07-20T09:00:00", "2026-07-28T14:30:00"]

	var slot: int = 0
	for path in SEED_MAP_PATHS:
		var res: Resource = load(path)
		if res == null or not (res is MapResource):
			continue
		var payload: Dictionary = _map_to_payload(res)
		if payload.is_empty():
			continue
		var votes: int = seed_votes[slot] if slot < seed_votes.size() else 5
		var created: String = seed_created[slot] if slot < seed_created.size() else Time.get_datetime_string_from_system()
		var summary: Dictionary = _summary_for_payload(payload, votes, created)
		if not summary.is_empty():
			_write_payload(String(summary["id"]), payload)
			items.append(summary)
			slot += 1

	# One demo CHALLENGE (a map with a real AI defender), so the type filter + Held%
	# have something to show.
	var challenge: Dictionary = _make_seed_challenge()
	if not challenge.is_empty():
		var c_summary: Dictionary = _summary_for_payload(challenge, 29, "2026-07-30T18:00:00")
		if not c_summary.is_empty():
			# Give the challenge some play history so Held% renders.
			c_summary["attempts"] = 40
			c_summary["clears"] = 12
			_write_payload(String(c_summary["id"]), challenge)
			items.append(c_summary)

	_save_index({"items": items, "my_votes": {}})


## Export a trusted [MapResource] to the canonical JSON dict the map payload rides as.
func _map_to_payload(res: MapResource) -> Dictionary:
	var parsed: Variant = JSON.parse_string(res.export_to_json())
	return parsed if parsed is Dictionary else {}


## Construct a valid demo challenge from scratch: a small map with a challenger start slot
## and one AI defender (so it passes [method ChallengeCodec.validate]). Returns {} if the
## roster is unavailable.
func _make_seed_challenge() -> Dictionary:
	var ids: Array = CharacterLibrary.all_ids()
	if ids.is_empty():
		return {}
	var cid: String = String(ids[0])
	var res := MapResource.new()
	res.map_name = "Gauntlet Demo"
	res.author = "Community Seed"
	res.width = 6
	res.height = 6
	res.max_players = 2
	res.create_default_layout()
	res.set_character_spawn_at_position(Vector2i(0, 0), 0, cid)
	res.set_character_spawn_at_position(Vector2i(5, 5), 1, cid)
	return ChallengeCodec.build_challenge(res, "Gauntlet Demo", "Community Seed",
		"2026-07-30T18:00:00", {"challenger_squad_size": 4, "turn_system": 0, "ai_difficulty": 1})


# --- Summary construction ---------------------------------------------------

## Derive an index summary from a payload, detecting whether it is a challenge or a bare
## map. Returns {} if it is neither.
func _summary_for_payload(payload: Dictionary, votes: int, created: String) -> Dictionary:
	var json_text: String = JSON.stringify(payload)
	if payload.has("format_version") and payload.has("map") and payload.has("rules"):
		# Challenge payload.
		var checksum: String = String(payload.get("checksum", str(json_text.hash())))
		return {
			"id": "challenge_" + checksum,
			"type": TYPE_CHALLENGE,
			"name": String(payload.get("name", "Untitled")),
			"author": String(payload.get("author", "")),
			"votes": votes,
			"attempts": 0,
			"clears": 0,
			"created": created,
			"size_bytes": json_text.length(),
			"checksum": checksum,
		}
	if payload.has("dimensions") and payload.has("layout"):
		# Map payload.
		var info: Dictionary = payload.get("map_info", {})
		var checksum2: String = str(json_text.hash())
		return {
			"id": "map_" + checksum2,
			"type": TYPE_MAP,
			"name": String(info.get("name", "Untitled Map")),
			"author": String(info.get("author", "")),
			"votes": votes,
			"attempts": 0,
			"clears": 0,
			"created": created,
			"size_bytes": json_text.length(),
			"checksum": checksum2,
		}
	return {}


# --- Storage ----------------------------------------------------------------

func _load_index() -> Dictionary:
	_ensure_seeded()
	var path: String = _root + "items.json"
	if not FileAccess.file_exists(path):
		return {"items": [], "my_votes": {}}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"items": [], "my_votes": {}}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return {"items": [], "my_votes": {}}
	var d: Dictionary = parsed
	if not d.has("items"):
		d["items"] = []
	if not d.has("my_votes"):
		d["my_votes"] = {}
	return d


func _save_index(index: Dictionary) -> void:
	_ensure_dirs()
	var f: FileAccess = FileAccess.open(_root + "items.json", FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(index, "\t"))
	f.close()


func _load_payload(id: String) -> Dictionary:
	var path: String = _payload_dir + _safe_id(id) + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}


func _write_payload(id: String, payload: Dictionary) -> void:
	_ensure_dirs()
	var f: FileAccess = FileAccess.open(_payload_dir + _safe_id(id) + ".json", FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()


func _ensure_dirs() -> void:
	if not DirAccess.dir_exists_absolute(_root):
		DirAccess.make_dir_recursive_absolute(_root)
	if not DirAccess.dir_exists_absolute(_payload_dir):
		DirAccess.make_dir_recursive_absolute(_payload_dir)


## Reduce an id to a filesystem-safe stem (ids are our own, but stay defensive).
func _safe_id(id: String) -> String:
	var out: String = ""
	for i in id.length():
		var c: String = id[i]
		if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_" or c == "-":
			out += c
		else:
			out += "_"
	return out
