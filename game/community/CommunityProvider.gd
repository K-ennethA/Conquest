class_name CommunityProvider
extends RefCounted

## Abstract transport for the community service (browse / search / vote / download / upload
## of player-authored maps + challenges, plus the attempt ledger and a player's own active
## bases). Every call is ASYNC via a result [Callable]: the provider
## invokes [param cb] exactly once with a result dictionary
## [code]{ "ok": bool, "data": Variant }[/code] on success or
## [code]{ "ok": false, "error": String }[/code] on failure. Callers never block.
##
## Two concrete providers implement this:
##   * [LocalProvider] -- an offline sandbox backed by user:// files (calls back
##     synchronously; makes the whole UI + tests work with zero network).
##   * [HttpProvider]  -- the real client, HTTPRequest against a configured base_url.
##
## The contract these implement is documented in docs/COMMUNITY_API.md.

# --- Vocabulary (shared by providers, client and UI) ------------------------
const SORT_TOP := "top"
const SORT_NEW := "new"
const SORT_DAILY := "daily"
## The default feed. SERVER-RANKED: the client sends the sort and RENDERS whatever order
## comes back -- it never re-ranks. [LocalProvider] implements a documented reference
## formula (votes + engagement + challenge fairness + freshness); the live service is free
## to refine it without a client change. See docs/COMMUNITY_API.md.
const SORT_RECOMMENDED := "recommended"

const TYPE_MAP := "map"
const TYPE_CHALLENGE := "challenge"
const TYPE_ALL := "all"

## Summaries returned per list page. Small so a page stays light.
const PAGE_SIZE := 20

## How many of one author's challenges may be ACTIVE (listed in the public feeds) at once.
## Retired bases stay playable by direct id, so a share code never dies.
const MAX_ACTIVE_BASES := 3

## Longest search needle accepted; anything past this is truncated at the boundary rather
## than refused (a search is not an error).
const MAX_QUERY_LENGTH := 64

## Sanity ceilings for a reported attempt. Untrusted numbers from the play flow are clamped
## into these bands, never stored raw.
const MAX_ATTEMPT_SCORE := 1_000_000
const MAX_ATTEMPT_TURNS := 999

# --- Attached replays -------------------------------------------------------
# An attempt may carry the ATTACKER's recorded command log so the defending author can watch
# how their base was played. The blob rides as base64 of the CQRP container
# ([method ReplayLog.encode_container]) under [constant REPLAY_KEY] inside the reported
# outcome. It is ATTACHMENT, never payload: a replay that fails any gate below is DROPPED and
# the attempt still counts -- a ledger entry is the thing that must never be lost.

## The outcome key an attached replay rides on.
const REPLAY_KEY := "replay_b64"

## Cap on ONE decoded replay container. A real battle's container is a few KB gzipped
## (5000 entries of near-identical JSON), so half a megabyte is orders of magnitude above any
## honest replay and still small enough that a base's whole retained set is a few MB.
const MAX_REPLAY_BYTES := 512 * 1024

## The longest base64 text that could possibly decode to [constant MAX_REPLAY_BYTES] --
## checked BEFORE decoding, so an absurd paste is refused without ever being expanded.
const MAX_REPLAY_B64_LENGTH := ((MAX_REPLAY_BYTES + 2) / 3) * 4

## How many replay blobs one base retains. Past this the OLDEST are dropped (their ledger
## entries survive with `has_replay` false) -- the store keeps a rolling window, never an
## unbounded archive.
const MAX_STORED_REPLAYS := 50

## How many attempt-log entries one base retains. Ten pages of history; older entries fall
## off the tail (the `attempts` / `clears` counters are unaffected -- they are the totals).
const MAX_LOGGED_ATTEMPTS := 200

# Machine-readable error codes. These are matched by CALLERS (the bases screen switches on
# them), so unlike the prose messages the older endpoints return they are stable strings.
const ERR_NOT_FOUND := "not_found"
const ERR_NOT_OWNER := "not_owner"
const ERR_BASE_LIMIT := "base_limit"

## Where the anonymous per-device identity is stored by default (see docs: soft identity for
## vote de-duplication and base ownership only).
const DEVICE_PATH := "user://community_device.txt"

## Live device-identity path. Redirected by [method set_device_path] so a test can own an
## identity without touching the player's real one.
static var _device_path: String = DEVICE_PATH


# --- Result helpers ---------------------------------------------------------

## Wrap a successful payload in the uniform result shape.
static func ok(data: Variant) -> Dictionary:
	return {"ok": true, "data": data}


## Wrap a failure reason in the uniform result shape.
static func fail(error: String) -> Dictionary:
	return {"ok": false, "error": error}


## Invoke a result callback if it is still valid (guards freed listeners).
static func _emit(cb: Callable, result: Dictionary) -> void:
	if cb.is_valid():
		cb.call(result)


# --- Device identity --------------------------------------------------------

## Point the identity at another file. Exists for TESTS (a throwaway `user://test_*` path)
## so a suite that uploads or retires a base gets its OWN device id instead of writing the
## player's. An empty path restores [constant DEVICE_PATH].
static func set_device_path(path: String) -> void:
	var trimmed: String = path.strip_edges()
	_device_path = trimmed if not trimmed.is_empty() else DEVICE_PATH


## The file the anonymous identity currently reads/writes.
static func device_path() -> String:
	return _device_path


## The anonymous device UUID, generated once and cached on disk. Used as the client
## identity for idempotent voting and for BASE OWNERSHIP (who may retire a challenge).
## Real accounts come with the live service.
static func device_id() -> String:
	if FileAccess.file_exists(_device_path):
		var f: FileAccess = FileAccess.open(_device_path, FileAccess.READ)
		if f != null:
			var existing: String = f.get_as_text().strip_edges()
			f.close()
			if not existing.is_empty():
				return existing
	var generated: String = _new_uuid()
	var out: FileAccess = FileAccess.open(_device_path, FileAccess.WRITE)
	if out != null:
		out.store_string(generated)
		out.close()
	return generated


## RFC-4122-ish v4 UUID from the engine RNG. Good enough for a soft, non-secret id.
static func _new_uuid() -> String:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(16)
	for i in 16:
		bytes[i] = randi() % 256
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var hex: String = bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4),
		hex.substr(16, 4), hex.substr(20, 12)]


# --- Boundary sanitisers ----------------------------------------------------
# Everything the UI and the play flow hand us is untrusted (a pasted search string, a
# result dictionary assembled by another system). It is normalised HERE, once, so both
# providers -- and the reference server -- agree on what a request even means.

## Normalise a search needle: trimmed, length-capped, lowercased. "" means NO query
## (an all-whitespace search is not a filter that matches nothing -- it is no filter).
static func sanitize_query(query: String) -> String:
	var trimmed: String = query.strip_edges()
	if trimmed.length() > MAX_QUERY_LENGTH:
		trimmed = trimmed.substr(0, MAX_QUERY_LENGTH)
	return trimmed.to_lower()


## Does [param summary] match an already-sanitised [param needle]? Case-insensitive
## substring over the TITLE and the AUTHOR name. An empty needle matches everything.
static func matches_query(summary: Dictionary, needle: String) -> bool:
	if needle.is_empty():
		return true
	if String(summary.get("name", "")).to_lower().contains(needle):
		return true
	return String(summary.get("author", "")).to_lower().contains(needle)


## Normalise a reported attempt to exactly { cleared: bool, score: int, turns: int }:
## unknown keys are DROPPED, a non-bool `cleared` reads as false, and the numbers are
## clamped to non-negative ints inside the sanity bands. A caller can therefore not widen
## the ledger's shape or poison a counter with a negative / absurd / non-numeric value.
static func sanitize_outcome(outcome: Dictionary) -> Dictionary:
	var cleared: Variant = outcome.get("cleared", false)
	return {
		"cleared": cleared if cleared is bool else false,
		"score": _clamp_counter(outcome.get("score", 0), MAX_ATTEMPT_SCORE),
		"turns": _clamp_counter(outcome.get("turns", 0), MAX_ATTEMPT_TURNS),
	}


## THE REPLAY GATE. Take whatever the play flow attached and return either the accepted
## base64 text or [code]""[/code] -- never a partially trusted blob. Three checks, cheapest
## first, and EVERY failure is silent (convention #1: a dropped attachment is a handled
## outcome, not a fault -- the attempt it rode on still counts):
##   1. it is a String, non-empty, within [constant MAX_REPLAY_B64_LENGTH] and made only of
##      base64 characters -- so [method Marshalls.base64_to_raw] is never handed garbage;
##   2. it decodes to between 1 and [constant MAX_REPLAY_BYTES] bytes;
##   3. [method ReplayLog.decode_container] accepts those bytes -- the SAME strict importer
##      playback uses (magic, container version, sha256 BEFORE inflation, then the full
##      whitelisting validate). Nothing else in this layer ever inspects a replay's insides.
##
## The accepted string is returned verbatim (only edge-trimmed), so what a store keeps is
## byte-identical to what the attacker's machine encoded.
static func sanitize_replay_b64(value: Variant) -> String:
	if not (value is String):
		return ""
	var text: String = (value as String).strip_edges()
	if text.is_empty() or text.length() > MAX_REPLAY_B64_LENGTH:
		return ""
	if not _is_base64_text(text):
		return ""
	var bytes: PackedByteArray = Marshalls.base64_to_raw(text)
	if bytes.is_empty() or bytes.size() > MAX_REPLAY_BYTES:
		return ""
	if ReplayLog.decode_container(bytes).is_empty():
		return ""
	return text


## True when [param text] is nothing but base64 characters and a valid length. A cheap
## pre-filter so the decoder only ever sees well-formed input (a hostile string is EXPECTED
## here, and an engine-level decode complaint would fail a test on sight).
static func _is_base64_text(text: String) -> bool:
	if text.length() % 4 != 0:
		return false
	# Padding is only ever a 1-2 char '=' tail; everything before it must be an alphabet char.
	var body: int = text.length()
	while body > 0 and text.unicode_at(body - 1) == 61:      # '='
		body -= 1
	if text.length() - body > 2:
		return false
	for i in body:
		var c: int = text.unicode_at(i)
		if not ((c >= 65 and c <= 90) or (c >= 97 and c <= 122)
				or (c >= 48 and c <= 57) or c == 43 or c == 47):   # A-Z a-z 0-9 + /
			return false
	return true


## One attempt-log entry, in the exact pinned shape. Built here so the store, the wire and
## the UI can never drift apart on what an entry IS.
static func make_attempt_entry(attempt_id: String, outcome: Dictionary, at: String, has_replay: bool) -> Dictionary:
	var clean: Dictionary = sanitize_outcome(outcome)
	return {
		"attempt_id": String(attempt_id),
		"cleared": bool(clean["cleared"]),
		"score": int(clean["score"]),
		"turns": int(clean["turns"]),
		"at": String(at),
		"has_replay": bool(has_replay),
	}


## A single untrusted number as an int in 0..[param limit]. Anything that is not a real
## number (a bool, a string, NaN) counts as 0 rather than converting to a surprise.
static func _clamp_counter(value: Variant, limit: int) -> int:
	if value is bool or not (value is int or value is float):
		return 0
	var n: float = float(value)
	if is_nan(n):
		return 0
	if is_inf(n):
		return limit if n > 0.0 else 0
	return clampi(int(n), 0, limit)


# --- API surface (override in subclasses) -----------------------------------

## List item summaries for a sort + type + 0-based page. data = Array[Dictionary].
## [param query] (optional) is a case-insensitive substring filter over title + author,
## applied BEFORE sorting and pagination. INACTIVE (retired) items are never listed.
func list_items(_sort: String, _type: String, _page: int, cb: Callable, _query: String = "") -> void:
	_emit(cb, fail("list_items not implemented"))


## Fetch one item's FULL payload (the map or challenge JSON). data = Dictionary.
func fetch_item(_id: String, cb: Callable) -> void:
	_emit(cb, fail("fetch_item not implemented"))


## Upload a payload. data = the created summary Dictionary.
func upload(_payload: Dictionary, cb: Callable) -> void:
	_emit(cb, fail("upload not implemented"))


## Cast/clear this device's vote (dir in {1, -1, 0}). data = { id, votes } (new score).
func vote(_id: String, _dir: int, cb: Callable) -> void:
	_emit(cb, fail("vote not implemented"))


## The daily featured pick. data = { id }.
func daily(cb: Callable) -> void:
	_emit(cb, fail("daily not implemented"))


## Record ONE play of an item. [param outcome] is { cleared: bool, score: int, turns: int }
## and is sanitised by [method sanitize_outcome] at the boundary. Deliberately NOT
## idempotent: every attempt counts, including repeats from the same device -- the ledger
## measures how a base actually performs, not how many people tried it once.
##
## [param outcome] MAY also carry [constant REPLAY_KEY] -- base64 of the attacker's CQRP
## replay container. It is gated by [method sanitize_replay_b64] and DROPPED on any failure
## while the attempt still counts.
##
## data = { id, attempts, clears, outcome, attempt_id, has_replay }.
## Unknown id = [constant ERR_NOT_FOUND].
func report_attempt(_id: String, _outcome: Dictionary, cb: Callable) -> void:
	_emit(cb, fail("report_attempt not implemented"))


## The per-attempt ledger for one of the CALLER'S OWN bases -- newest first,
## [constant PAGE_SIZE] per 0-based page. data =
## [code]{ "entries": Array[Dictionary], "has_more": bool }[/code], each entry
## [code]{ attempt_id, cleared, score, turns, at, has_replay }[/code]
## ([method make_attempt_entry]).
##
## OWNER-ONLY: this is a defender's private record of who attacked their base. Someone
## else's item = [constant ERR_NOT_OWNER]; an unknown id = [constant ERR_NOT_FOUND].
func attempt_log(_id: String, _page: int, cb: Callable) -> void:
	_emit(cb, fail("attempt_log not implemented"))


## The replay attached to ONE attempt, as the base64 text that was stored (data = String),
## byte-identical to what the attacker's machine encoded. Owner-of-the-BASE only, exactly as
## [method attempt_log] is: [constant ERR_NOT_OWNER] for anyone else, [constant ERR_NOT_FOUND]
## for an unknown attempt, an attempt whose blob was never stored, and one whose blob has
## since aged out of the [constant MAX_STORED_REPLAYS] window.
func fetch_attempt_replay(_attempt_id: String, cb: Callable) -> void:
	_emit(cb, fail("fetch_attempt_replay not implemented"))


## This device's OWN uploaded challenges, active and retired alike, with their counters.
## data = Array[Dictionary] of summaries.
func my_bases(cb: Callable) -> void:
	_emit(cb, fail("my_bases not implemented"))


## Publish ([param active] true) or retire an owned base. Retiring always succeeds;
## activating past [constant MAX_ACTIVE_BASES] fails with [constant ERR_BASE_LIMIT], and
## another author's item fails with [constant ERR_NOT_OWNER]. data = { id, active }.
func set_base_active(_id: String, _active: bool, cb: Callable) -> void:
	_emit(cb, fail("set_base_active not implemented"))
