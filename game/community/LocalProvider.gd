class_name LocalProvider
extends CommunityProvider

## Offline / development mock of the community service, backed entirely by user:// files.
## It makes the whole Community UI (browse, sort, vote, download) work with ZERO network,
## and gives the tests a deterministic fixture. It self-seeds on first use from TRUSTED
## res:// content, so a fresh install already has something to browse.
##
## Storage (under [member _root], default user://community_mock/):
##   items.json                    -- the index: { "items": [summary...], "my_votes": { id: dir } }
##   payloads/<id>.json            -- the full map / challenge JSON for each item
##   attempts/<id>.json            -- one base's attempt ledger: { "entries": [newest first] }
##   replays/<attempt_id>.json     -- one attached replay: { "item_id", "replay_b64" }
##
## The ledger is split out of the index ON PURPOSE: a base's history grows with every play,
## and items.json is re-read (and re-written) by every single call. Replay blobs are split
## again, one file per attempt, so paging the ledger never touches half a megabyte of base64.
##
## Each summary carries the SERVER-MAINTAINED fields the live service would own:
## `votes`, the attempt ledger (`attempts` / `clears` -- the defense rate is DERIVED by
## readers, never stored), `owner` (the uploader's device id) and `active`.
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

# --- Recommendation weights (see docs/COMMUNITY_API.md "Recommended feed") ---------------
# The four terms are each normalised to roughly 0..1 (votes to -1..1) and blended. The
# weights are the whole editorial policy: a base that people actually PLAY and sometimes
# beat outranks a base that merely collected up-votes on its screenshot.
const REC_W_VOTES := 0.45
const REC_W_FAIRNESS := 0.35
const REC_W_ENGAGEMENT := 0.12
const REC_W_FRESHNESS := 0.08

## Vote count at which the vote term reaches half its ceiling (soft saturation, so a runaway
## score cannot bury everything else).
const REC_VOTE_SCALE := 25.0
## Same soft saturation for play count -- and the counterweight to a tiny sample: a base with
## two attempts cannot out-rank a well-played one on fairness alone.
const REC_ATTEMPT_SCALE := 25.0
## The clear rate that ranks best. Below it a base is unbeatable, above it a pushover; the
## sweet spot is "beatable, but you have to earn it".
const REC_PEAK_CLEAR_RATE := 0.4
## Age at which the freshness term halves. Small weight -- new content gets a nudge onto the
## page, never a free pass to the top.
const REC_FRESH_HALFLIFE_DAYS := 14.0

var _root: String
var _payload_dir: String
var _attempt_dir: String
var _replay_dir: String


## [param root] lets tests point the mock at a throwaway directory (and clean it up).
func _init(root: String = DEFAULT_ROOT) -> void:
	_root = root if root.ends_with("/") else root + "/"
	_payload_dir = _root + "payloads/"
	_attempt_dir = _root + "attempts/"
	_replay_dir = _root + "replays/"


# --- API --------------------------------------------------------------------

func list_items(sort: String, type: String, page: int, cb: Callable, query: String = "") -> void:
	var index: Dictionary = _load_index()
	var items: Array = index.get("items", [])
	var needle: String = sanitize_query(query)

	# Filters, all applied BEFORE sort + pagination so page 0 is genuinely the top of the
	# filtered set: retired bases are invisible to every feed, then type, then the search.
	var filtered: Array = []
	for it in items:
		if not _is_active(it):
			continue
		if not (type == TYPE_ALL or type == "" or String(it.get("type", "")) == type):
			continue
		if not matches_query(it, needle):
			continue
		filtered.append(it)

	filtered = _sort_items(filtered, sort)

	var start: int = maxi(0, page) * PAGE_SIZE
	var slice: Array = []
	if start < filtered.size():
		slice = filtered.slice(start, mini(start + PAGE_SIZE, filtered.size()))
	_emit(cb, ok(slice))


## Direct fetch by id works for RETIRED bases too: a friend who has the code can always
## play the base, which is what keeps codes the friend-share path.
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
	# Ownership is stamped server-side from the caller's identity -- never taken from the
	# payload, or anyone could upload a base "as" someone else and retire theirs.
	var me: String = device_id()
	summary["owner"] = me
	# Published active by default, but the 3-active cap is an INVARIANT, not just a check on
	# the toggle: a fourth upload lands retired rather than sneaking past the limit. The
	# summary says so, so the uploader's screen can offer to swap one out.
	summary["active"] = String(summary.get("type", "")) != TYPE_CHALLENGE \
		or _active_base_count(index, me) < MAX_ACTIVE_BASES

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

	var found: Dictionary = _find_item(index, id)
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


## Record one play. NOT idempotent by design (see [method CommunityProvider.report_attempt]):
## the same device replaying a base counts every time, because the ledger is measuring the
## base's difficulty, not its audience size. Retired bases still count -- a friend playing
## from a code is exactly the traffic an author wants reflected.
func report_attempt(id: String, outcome: Dictionary, cb: Callable) -> void:
	var clean: Dictionary = sanitize_outcome(outcome)
	# The attached replay is gated SEPARATELY from the counters, and before anything is
	# written: a blob that fails the gate is dropped and the attempt is recorded regardless.
	var replay_b64: String = sanitize_replay_b64(outcome.get(REPLAY_KEY, ""))
	var index: Dictionary = _load_index()
	var found: Dictionary = _find_item(index, id)
	if found.is_empty():
		_emit(cb, fail(ERR_NOT_FOUND))
		return

	# maxi() re-floors counters that a hand-edited mock store could have left negative.
	found["attempts"] = maxi(0, int(found.get("attempts", 0))) + 1
	found["clears"] = maxi(0, int(found.get("clears", 0))) + (1 if bool(clean["cleared"]) else 0)
	_save_index(index)

	var attempt_id: String = _new_uuid()
	var has_replay: bool = not replay_b64.is_empty() and _write_replay(attempt_id, id, replay_b64)
	_append_attempt(id, make_attempt_entry(
		attempt_id, clean, Time.get_datetime_string_from_system(), has_replay))

	_emit(cb, ok({
		"id": id,
		"attempts": int(found["attempts"]),
		"clears": int(found["clears"]),
		"outcome": clean,
		"attempt_id": attempt_id,
		"has_replay": has_replay,
	}))


## One page of a base's own attempt ledger, newest first. The OWNER gate is the point of the
## endpoint: an attempt log names how every attacker fared, which is the defender's private
## record -- so a stranger gets [constant ERR_NOT_OWNER], and unowned (seeded) content is
## nobody's to read.
func attempt_log(id: String, page: int, cb: Callable) -> void:
	var found: Dictionary = _find_item(_load_index(), id)
	if found.is_empty():
		_emit(cb, fail(ERR_NOT_FOUND))
		return
	var me: String = device_id()
	if me.is_empty() or String(found.get("owner", "")) != me:
		_emit(cb, fail(ERR_NOT_OWNER))
		return

	var entries: Array = _load_attempts(id)
	var start: int = maxi(0, page) * PAGE_SIZE
	var slice: Array = []
	if start < entries.size():
		slice = entries.slice(start, mini(start + PAGE_SIZE, entries.size()))
	_emit(cb, ok({"entries": slice, "has_more": start + PAGE_SIZE < entries.size()}))


## The blob one attempt carried, exactly as it was stored. Gated on ownership of the BASE the
## attempt was played against (resolved through the blob's own `item_id`), so the same rule
## that guards [method attempt_log] guards the replay it points at.
func fetch_attempt_replay(attempt_id: String, cb: Callable) -> void:
	var record: Dictionary = _load_replay(attempt_id)
	var b64: String = String(record.get(REPLAY_KEY, ""))
	if b64.is_empty():
		_emit(cb, fail(ERR_NOT_FOUND))
		return
	var found: Dictionary = _find_item(_load_index(), String(record.get("item_id", "")))
	if found.is_empty():
		_emit(cb, fail(ERR_NOT_FOUND))
		return
	var me: String = device_id()
	if me.is_empty() or String(found.get("owner", "")) != me:
		_emit(cb, fail(ERR_NOT_OWNER))
		return
	_emit(cb, ok(b64))


## The caller's own uploaded CHALLENGES -- active and retired alike, newest first -- so the
## bases screen can show what is published, what is benched, and how each is performing.
func my_bases(cb: Callable) -> void:
	var me: String = device_id()
	if me.is_empty():
		_emit(cb, ok([]))
		return
	var mine: Array = []
	for it in _load_index().get("items", []):
		if String(it.get("owner", "")) == me and String(it.get("type", "")) == TYPE_CHALLENGE:
			mine.append(it)
	mine.sort_custom(func(a, b): return String(a.get("created", "")) > String(b.get("created", "")))
	_emit(cb, ok(mine))


## Publish or retire one of the caller's own bases. Retiring ALWAYS succeeds (an author can
## always pull a base out of the feeds); publishing is what the cap guards.
func set_base_active(id: String, active: bool, cb: Callable) -> void:
	var index: Dictionary = _load_index()
	var found: Dictionary = _find_item(index, id)
	if found.is_empty():
		_emit(cb, fail(ERR_NOT_FOUND))
		return

	var me: String = device_id()
	if me.is_empty() or String(found.get("owner", "")) != me:
		_emit(cb, fail(ERR_NOT_OWNER))
		return

	# Only a transition INTO active can breach the cap: re-activating something already
	# active is a no-op, and retiring frees the slot for the next call.
	if active and not _is_active(found) and String(found.get("type", "")) == TYPE_CHALLENGE \
			and _active_base_count(index, me) >= MAX_ACTIVE_BASES:
		_emit(cb, fail(ERR_BASE_LIMIT))
		return

	found["active"] = active
	_save_index(index)
	_emit(cb, ok({"id": id, "active": active}))


## This device's current vote on an item (1 / -1 / 0), so the UI can pre-highlight the
## up/down buttons. Local convenience -- not part of the network contract.
func my_vote(id: String) -> int:
	return int(_load_index().get("my_votes", {}).get(id, 0))


# --- Index lookups ----------------------------------------------------------

## The summary dict for [param id] BY REFERENCE (so a caller mutates the index in place),
## or {} when the id is unknown.
func _find_item(index: Dictionary, id: String) -> Dictionary:
	for it in index.get("items", []):
		if String(it.get("id", "")) == id:
			return it
	return {}


## Items written before `active` existed are treated as published -- absence of a retirement
## is not a retirement.
func _is_active(item: Dictionary) -> bool:
	return bool(item.get("active", true))


## How many ACTIVE challenge bases [param owner] currently has published.
func _active_base_count(index: Dictionary, owner: String) -> int:
	if owner.is_empty():
		return 0
	var count: int = 0
	for it in index.get("items", []):
		if String(it.get("owner", "")) == owner and String(it.get("type", "")) == TYPE_CHALLENGE \
				and _is_active(it):
			count += 1
	return count


# --- Sorting / daily --------------------------------------------------------

func _sort_items(items: Array, sort: String) -> Array:
	var out: Array = items.duplicate()
	match sort:
		SORT_RECOMMENDED:
			# Scores are computed ONCE per item (not inside the comparator, which would
			# re-evaluate them O(n log n) times and re-read the clock mid-sort).
			var now: float = Time.get_unix_time_from_system()
			var scores: Dictionary = {}
			for it in out:
				scores[String(it.get("id", ""))] = _recommended_score(it, now)
			out.sort_custom(func(a, b):
				var sa: float = float(scores.get(String(a.get("id", "")), 0.0))
				var sb: float = float(scores.get(String(b.get("id", "")), 0.0))
				if not is_equal_approx(sa, sb):
					return sa > sb
				# Deterministic tie-break, so an equal-scoring pair never shuffles between
				# two calls (which would make pagination lose or repeat an item).
				var va: int = int(a.get("votes", 0))
				var vb: int = int(b.get("votes", 0))
				if va != vb:
					return va > vb
				return String(a.get("id", "")) < String(b.get("id", ""))
			)
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


## The REFERENCE recommendation score. Deterministic given the item and the clock, and
## documented in docs/COMMUNITY_API.md so the live service can be checked against it -- but
## the CONTRACT is only "the server ranks, the client renders", so a live refinement needs
## no client change.
##
## Four terms, blended by the REC_W_* weights:
##   votes      v / (|v| + 25)         -- soft-saturating, signed: the crowd's opinion, but
##                                        a viral score cannot drown out everything else.
##   fairness   1 - ((r - 0.4) / 0.4)^2, floored at 0, where r = clears / attempts
##                                     -- an inverted parabola peaking at a 40% clear rate.
##                                        A base nobody can beat (r=0) and a pushover
##                                        (r>=0.8) both score 0; "sometimes cleared, not
##                                        always" wins. Unplayed (attempts=0) scores 0: an
##                                        unknown base has not EARNED the fairness bonus.
##   engagement a / (a + 25)           -- how much it is actually played, which is also what
##                                        stops a 2-attempt fluke rate from topping the feed.
##   freshness  1 / (1 + age_days/14)  -- a small nudge so new bases surface at all.
func _recommended_score(item: Dictionary, now_unix: float) -> float:
	var votes: float = float(int(item.get("votes", 0)))
	var vote_term: float = votes / (absf(votes) + REC_VOTE_SCALE)

	var attempts: float = float(maxi(0, int(item.get("attempts", 0))))
	var engagement: float = attempts / (attempts + REC_ATTEMPT_SCALE)

	var fairness: float = 0.0
	if attempts > 0.0:
		var rate: float = clampf(float(maxi(0, int(item.get("clears", 0)))) / attempts, 0.0, 1.0)
		var offset: float = (rate - REC_PEAK_CLEAR_RATE) / REC_PEAK_CLEAR_RATE
		fairness = maxf(0.0, 1.0 - offset * offset)

	var freshness: float = 0.0
	var created_unix: float = _created_unix(String(item.get("created", "")))
	if created_unix > 0.0:
		var age_days: float = maxf(0.0, (now_unix - created_unix) / 86400.0)
		freshness = 1.0 / (1.0 + age_days / REC_FRESH_HALFLIFE_DAYS)

	return REC_W_VOTES * vote_term + REC_W_FAIRNESS * fairness \
		+ REC_W_ENGAGEMENT * engagement + REC_W_FRESHNESS * freshness


## Parse an ISO-ish `created` stamp to unix seconds, or 0 when it is missing / malformed
## (which reads as "very old", i.e. no freshness bonus). The shape is checked first because
## Time's parser is loud about garbage and a bad timestamp is DATA, not an engine error.
func _created_unix(created: String) -> float:
	if created.length() < 10 or not created.substr(0, 4).is_valid_int():
		return 0.0
	return float(Time.get_unix_time_from_datetime_string(created))


## Deterministic daily pick: a hash of today's date modulo the ACTIVE item count, so the
## choice is stable within a calendar day and changes the next. Mirrors the challenge daily
## trick. Retired bases are never featured.
func _daily_id() -> String:
	var index: Dictionary = _load_index()
	var items: Array = []
	for it in index.get("items", []):
		if _is_active(it):
			items.append(it)
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
## map. Returns {} if it is neither. `owner` is left BLANK -- only [method upload] knows the
## caller's identity, and seeded builtin content deliberately belongs to nobody (so nobody
## can retire it).
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
			"owner": "",
			"active": true,
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
			"owner": "",
			"active": true,
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
	for dir in [_root, _payload_dir, _attempt_dir, _replay_dir]:
		if not DirAccess.dir_exists_absolute(dir):
			DirAccess.make_dir_recursive_absolute(dir)


# --- Attempt ledger + attached replays --------------------------------------

## One base's ledger, newest first. Every entry is re-made through
## [method CommunityProvider.make_attempt_entry] on the way out, so a hand-edited store can
## widen neither the shape nor the numbers.
func _load_attempts(id: String) -> Array:
	var raw: Variant = _read_json(_attempt_dir + _safe_id(id) + ".json")
	if not (raw is Dictionary):
		return []
	var out: Array = []
	for item in (raw as Dictionary).get("entries", []):
		if not (item is Dictionary):
			continue
		var e: Dictionary = item
		out.append(make_attempt_entry(
			String(e.get("attempt_id", "")), e, String(e.get("at", "")), bool(e.get("has_replay", false))))
	return out


func _save_attempts(id: String, entries: Array) -> void:
	_ensure_dirs()
	var f: FileAccess = FileAccess.open(_attempt_dir + _safe_id(id) + ".json", FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"entries": entries}, "\t"))
	f.close()


## Push one entry onto the front of [param id]'s ledger and apply BOTH retention rules:
##   * only the newest [constant MAX_STORED_REPLAYS] entries keep their blob -- older ones
##     have the file deleted and their `has_replay` flipped to false, so the ledger stays
##     honest about what is actually watchable;
##   * only the newest [constant MAX_LOGGED_ATTEMPTS] entries are kept at all (their blobs go
##     with them). The `attempts` / `clears` counters are untouched: they are the TOTALS, the
##     ledger is just the recent history.
func _append_attempt(id: String, entry: Dictionary) -> void:
	var entries: Array = _load_attempts(id)
	entries.insert(0, entry)

	var kept_replays: int = 0
	for e in entries:
		if not bool(e.get("has_replay", false)):
			continue
		kept_replays += 1
		if kept_replays > MAX_STORED_REPLAYS:
			_delete_replay(String(e.get("attempt_id", "")))
			e["has_replay"] = false

	while entries.size() > MAX_LOGGED_ATTEMPTS:
		var dropped: Dictionary = entries.pop_back()
		_delete_replay(String(dropped.get("attempt_id", "")))

	_save_attempts(id, entries)


## The stored blob record for [param attempt_id]: { "item_id", "replay_b64" }, or {} when
## there is none (never stored, or aged out of the retention window).
func _load_replay(attempt_id: String) -> Dictionary:
	var raw: Variant = _read_json(_replay_dir + _safe_id(attempt_id) + ".json")
	return raw if raw is Dictionary else {}


## Write one blob. Returns whether it actually landed -- the caller stamps `has_replay` from
## the answer, so an unwritable store degrades to "attempt recorded, no replay" rather than
## advertising a blob that is not there.
func _write_replay(attempt_id: String, item_id: String, b64: String) -> bool:
	_ensure_dirs()
	var path: String = _replay_dir + _safe_id(attempt_id) + ".json"
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"item_id": item_id, REPLAY_KEY: b64}))
	f.close()
	return true


func _delete_replay(attempt_id: String) -> void:
	if attempt_id.is_empty():
		return
	var path: String = _replay_dir + _safe_id(attempt_id) + ".json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Read + parse one store file, or null when it is missing / unreadable / not JSON.
func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text: String = f.get_as_text()
	f.close()
	return JSON.parse_string(text)


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
