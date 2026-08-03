extends GutTest

## Unit tests for [LocalProvider] -- the offline community-service mock.
##
## Coverage:
##  - self-seeds a browsable catalogue on first use;
##  - list_items sorts by score (top) and by recency (new);
##  - a vote round-trips and PERSISTS to disk (a fresh provider sees it);
##  - voting is idempotent per device (same dir twice != double count);
##  - daily() is deterministic within a calendar day;
##  - SEARCH: case-insensitive title/author substring, sanitised at the boundary;
##  - RECOMMENDED: the fairness peak and the freshness nudge, on crafted fixtures;
##  - the ATTEMPT ledger: counts every attempt (no idempotency), validates the outcome,
##    and refuses an unknown id;
##  - ATTACHED REPLAYS: a valid CQRP blob persists and round-trips byte-identically, a
##    garbage / oversized one is DROPPED while the attempt still counts, the per-attempt log
##    pages newest-first, both new endpoints are owner-only, and the store keeps only the
##    newest MAX_STORED_REPLAYS blobs per base;
##  - ACTIVE BASES: the 3-active cap, retiring to free a slot, ownership, and the fact that
##    a retired base leaves the feeds but stays fetchable by id.
##
## Each test uses a throwaway user:// root AND a throwaway device identity (uploads stamp
## ownership from it), and cleans both up.

const TMP_ROOT := "user://test_community_local/"
## Own device identity, so an upload never writes the player's real community_device.txt.
const TMP_DEVICE := "user://test_community_local_device.txt"
## A SECOND identity, for proving someone else's base cannot be retired.
const TMP_DEVICE_OTHER := "user://test_community_local_device_other.txt"


func before_each() -> void:
	CommunityProvider.set_device_path(TMP_DEVICE)


func after_each() -> void:
	CommunityProvider.set_device_path("")
	for path in [TMP_DEVICE, TMP_DEVICE_OTHER]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_rm_rf(TMP_ROOT)


# --- Helpers ----------------------------------------------------------------

## Run a synchronous provider call and return its result dict (LocalProvider calls back
## inline, so the holder is populated by the time the call returns).
func _sync(callable_runner: Callable) -> Dictionary:
	var holder: Array = []
	callable_runner.call(func(r: Dictionary): holder.append(r))
	assert_gt(holder.size(), 0, "provider must call back synchronously")
	return holder[0] if holder.size() > 0 else {}


func _list(provider: LocalProvider, sort: String, type: String, page: int = 0, query: String = "") -> Array:
	var result: Dictionary = _sync(func(cb: Callable): provider.list_items(sort, type, page, cb, query))
	assert_true(bool(result.get("ok", false)), "list_items should succeed")
	return result.get("data", [])


## The ids of a listing, in order -- the shape most ordering assertions want.
func _ids(items: Array) -> Array:
	var out: Array = []
	for it in items:
		out.append(String(it.get("id", "")))
	return out


## An ISO stamp [param days] in the past, so a fixture's freshness is relative to the run
## rather than to a date baked into the test (which would rot).
func _days_ago(days: float) -> String:
	var when: int = int(Time.get_unix_time_from_system() - days * 86400.0)
	return Time.get_datetime_string_from_unix_time(when)


## A summary with sane defaults, overridden by [param fields]. Lets each ranking test state
## ONLY the property it is about.
func _fixture(id: String, fields: Dictionary = {}) -> Dictionary:
	var base: Dictionary = {
		"id": id,
		"type": CommunityProvider.TYPE_CHALLENGE,
		"name": id,
		"author": "Fixture Author",
		"votes": 10,
		"attempts": 0,
		"clears": 0,
		"owner": "",
		"active": true,
		"created": _days_ago(30.0),
		"size_bytes": 100,
		"checksum": id,
	}
	for key in fields:
		base[key] = fields[key]
	return base


## Pre-write the mock's index so a test controls the WHOLE catalogue (the provider only
## self-seeds when items.json is absent). Payload files are not written: these fixtures are
## for listing/ranking, which never reads a payload.
func _write_index(items: Array) -> LocalProvider:
	DirAccess.make_dir_recursive_absolute(TMP_ROOT)
	var f: FileAccess = FileAccess.open(TMP_ROOT + "items.json", FileAccess.WRITE)
	assert_not_null(f, "the fixture index should be writable")
	if f != null:
		f.store_string(JSON.stringify({"items": items, "my_votes": {}}))
		f.close()
	return LocalProvider.new(TMP_ROOT)


## A structurally valid challenge payload (distinct names -> distinct content ids).
func _challenge_payload(challenge_name: String) -> Dictionary:
	var ids: Array = CharacterLibrary.all_ids()
	if ids.is_empty():
		return {}
	var cid: String = String(ids[0])
	var res := MapResource.new()
	res.map_name = challenge_name
	res.author = "Local Provider Test"
	res.width = 6
	res.height = 6
	res.max_players = 2
	res.create_default_layout()
	res.set_character_spawn_at_position(Vector2i(0, 0), 0, cid)
	res.set_character_spawn_at_position(Vector2i(5, 5), 1, cid)
	return ChallengeCodec.build_challenge(res, challenge_name, "Local Provider Test",
		"2026-07-30T18:00:00", {"challenger_squad_size": 4, "turn_system": 0, "ai_difficulty": 1})


## A VALID attached replay: base64 of a real CQRP container. [param tag] makes each blob
## distinct, so a round-trip assertion is about THIS attempt's bytes and not just "some
## replay came back".
func _replay_b64(tag: String) -> String:
	var log_dict: Dictionary = ReplayLog.make_log({
		"mode": ReplayLog.MODE_CHALLENGE,
		"challenge_id": tag,
		"recorded_at_utc": "2026-08-02T14:03:11",
	})
	return Marshalls.raw_to_base64(ReplayLog.encode_container(log_dict))


## Report one attempt and return the result payload (asserting it was accepted).
func _report(provider: LocalProvider, id: String, outcome: Dictionary) -> Dictionary:
	var result: Dictionary = _sync(func(cb: Callable): provider.report_attempt(id, outcome, cb))
	assert_true(bool(result.get("ok", false)), "reporting an attempt should succeed")
	return result.get("data", {})


func _attempt_page(provider: LocalProvider, id: String, page: int) -> Dictionary:
	var result: Dictionary = _sync(func(cb: Callable): provider.attempt_log(id, page, cb))
	assert_true(bool(result.get("ok", false)), "reading my own attempt log should succeed")
	return result.get("data", {})


## Upload [param challenge_name] and return its summary (asserting the upload took).
func _upload_challenge(provider: LocalProvider, challenge_name: String) -> Dictionary:
	var payload: Dictionary = _challenge_payload(challenge_name)
	var result: Dictionary = _sync(func(cb: Callable): provider.upload(payload, cb))
	assert_true(bool(result.get("ok", false)), "uploading '%s' should succeed" % challenge_name)
	return result.get("data", {})


# --- Tests ------------------------------------------------------------------

func test_seeds_on_first_use() -> void:
	var provider := LocalProvider.new(TMP_ROOT)
	var items: Array = _list(provider, CommunityProvider.SORT_TOP, CommunityProvider.TYPE_ALL)
	assert_gt(items.size(), 0, "a fresh LocalProvider must seed a browsable catalogue")
	# The index file was written under the temp root.
	assert_true(FileAccess.file_exists(TMP_ROOT + "items.json"), "seeding writes items.json")


func test_type_filter_splits_maps_and_challenges() -> void:
	var provider := LocalProvider.new(TMP_ROOT)
	var maps: Array = _list(provider, CommunityProvider.SORT_TOP, CommunityProvider.TYPE_MAP)
	var challenges: Array = _list(provider, CommunityProvider.SORT_TOP, CommunityProvider.TYPE_CHALLENGE)
	assert_gt(maps.size(), 0, "seed includes at least one map")
	for it in maps:
		assert_eq(String(it.get("type", "")), CommunityProvider.TYPE_MAP)
	for it in challenges:
		assert_eq(String(it.get("type", "")), CommunityProvider.TYPE_CHALLENGE)


func test_top_sort_is_by_votes_desc() -> void:
	var provider := LocalProvider.new(TMP_ROOT)
	var items: Array = _list(provider, CommunityProvider.SORT_TOP, CommunityProvider.TYPE_ALL)
	assert_gt(items.size(), 1, "need at least two items to check ordering")
	for i in range(items.size() - 1):
		assert_true(int(items[i].get("votes", 0)) >= int(items[i + 1].get("votes", 0)),
			"top sort must be non-increasing by votes")


func test_new_sort_is_by_created_desc() -> void:
	var provider := LocalProvider.new(TMP_ROOT)
	var items: Array = _list(provider, CommunityProvider.SORT_NEW, CommunityProvider.TYPE_ALL)
	assert_gt(items.size(), 1, "need at least two items to check ordering")
	for i in range(items.size() - 1):
		assert_true(String(items[i].get("created", "")) >= String(items[i + 1].get("created", "")),
			"new sort must be non-increasing by created timestamp")


func test_vote_round_trip_persists() -> void:
	var provider := LocalProvider.new(TMP_ROOT)
	var items: Array = _list(provider, CommunityProvider.SORT_TOP, CommunityProvider.TYPE_ALL)
	var id: String = String(items[0].get("id", ""))
	var before: int = int(items[0].get("votes", 0))

	var result: Dictionary = _sync(func(cb: Callable): provider.vote(id, 1, cb))
	assert_true(bool(result.get("ok", false)), "vote should succeed")
	assert_eq(int(result.get("data", {}).get("votes", -999)), before + 1, "an up-vote adds one")

	# A brand-new provider on the SAME root must see the persisted score + my_vote.
	var fresh := LocalProvider.new(TMP_ROOT)
	var reread: Array = _list(fresh, CommunityProvider.SORT_TOP, CommunityProvider.TYPE_ALL)
	var found: Dictionary = {}
	for it in reread:
		if String(it.get("id", "")) == id:
			found = it
			break
	assert_false(found.is_empty(), "the voted item should still be listed")
	assert_eq(int(found.get("votes", 0)), before + 1, "the vote must persist across instances")
	assert_eq(fresh.my_vote(id), 1, "this device's vote must persist")


func test_vote_is_idempotent_per_device() -> void:
	var provider := LocalProvider.new(TMP_ROOT)
	var items: Array = _list(provider, CommunityProvider.SORT_TOP, CommunityProvider.TYPE_ALL)
	var id: String = String(items[0].get("id", ""))
	var before: int = int(items[0].get("votes", 0))

	var first: Dictionary = _sync(func(cb: Callable): provider.vote(id, 1, cb))
	var second: Dictionary = _sync(func(cb: Callable): provider.vote(id, 1, cb))
	assert_eq(int(first.get("data", {}).get("votes", 0)), before + 1)
	assert_eq(int(second.get("data", {}).get("votes", 0)), before + 1,
		"re-sending the same vote must NOT double count")

	# Clearing the vote (dir 0) returns to baseline.
	var cleared: Dictionary = _sync(func(cb: Callable): provider.vote(id, 0, cb))
	assert_eq(int(cleared.get("data", {}).get("votes", 0)), before, "clearing a vote returns to baseline")


func test_daily_is_deterministic() -> void:
	var provider := LocalProvider.new(TMP_ROOT)
	# Ensure seeded so the pick has a pool.
	_list(provider, CommunityProvider.SORT_TOP, CommunityProvider.TYPE_ALL)

	var a: Dictionary = _sync(func(cb: Callable): provider.daily(cb))
	var b: Dictionary = _sync(func(cb: Callable): provider.daily(cb))
	var id_a: String = String(a.get("data", {}).get("id", ""))
	var id_b: String = String(b.get("data", {}).get("id", ""))
	assert_eq(id_a, id_b, "daily() must be stable within a day")
	assert_false(id_a.is_empty(), "daily() should pick a real item when the catalogue is non-empty")


# --- Search -----------------------------------------------------------------

func test_search_matches_title_and_author_case_insensitively() -> void:
	var provider: LocalProvider = _write_index([
		_fixture("frozen", {"name": "Frozen Gauntlet", "author": "Ada"}),
		_fixture("sunspire", {"name": "Sunspire Keep", "author": "Frostwarden"}),
		_fixture("ashen", {"name": "Ashen Vale", "author": "Bo"}),
	])

	var by_title: Array = _ids(_list(provider, CommunityProvider.SORT_TOP, CommunityProvider.TYPE_ALL, 0, "FROZEN"))
	assert_eq(by_title, ["frozen"], "a title match is case-insensitive")

	var by_author: Array = _ids(_list(provider, CommunityProvider.SORT_TOP, CommunityProvider.TYPE_ALL, 0, "frostwarden"))
	assert_eq(by_author, ["sunspire"], "the author name is searched too")

	var both: Array = _ids(_list(provider, CommunityProvider.SORT_TOP, CommunityProvider.TYPE_ALL, 0, "fro"))
	assert_eq(both.size(), 2, "a substring may match on either field")
	assert_true(both.has("frozen") and both.has("sunspire"), "both fro* items match")

	assert_eq(_ids(_list(provider, CommunityProvider.SORT_TOP, CommunityProvider.TYPE_ALL, 0, "zzz")).size(), 0,
		"a needle nothing contains matches nothing")


func test_search_is_sanitised_at_the_boundary() -> void:
	var provider: LocalProvider = _write_index([
		_fixture("frozen", {"name": "Frozen Gauntlet", "author": "Ada"}),
		_fixture("ashen", {"name": "Ashen Vale", "author": "Bo"}),
	])

	assert_eq(_ids(_list(provider, CommunityProvider.SORT_TOP, CommunityProvider.TYPE_ALL, 0, "   ")).size(), 2,
		"an all-whitespace search is NO filter, not a filter matching nothing")
	assert_eq(_ids(_list(provider, CommunityProvider.SORT_TOP, CommunityProvider.TYPE_ALL, 0, "  gauntlet  ")),
		["frozen"], "edges are stripped before matching")

	# The cap is a truncation, not a rejection -- a 200-char paste is still a search.
	var long_needle: String = "frozen".lpad(200, "x")
	assert_eq(CommunityProvider.sanitize_query(long_needle).length(), CommunityProvider.MAX_QUERY_LENGTH,
		"a needle is capped at MAX_QUERY_LENGTH characters")
	assert_eq(CommunityProvider.sanitize_query("  MiXeD  "), "mixed", "sanitising trims and lowercases")


func test_search_applies_before_pagination() -> void:
	# One matching item hidden behind a full page of non-matches: if the filter ran AFTER
	# pagination, page 0 would come back empty.
	var items: Array = []
	for i in CommunityProvider.PAGE_SIZE:
		items.append(_fixture("filler_%02d" % i, {"name": "Filler %d" % i, "votes": 100}))
	items.append(_fixture("needle", {"name": "Needle Keep", "votes": 1}))

	var provider: LocalProvider = _write_index(items)
	assert_eq(_ids(_list(provider, CommunityProvider.SORT_TOP, CommunityProvider.TYPE_ALL, 0, "needle")),
		["needle"], "the search filters the catalogue, then page 0 is taken from the matches")


# --- Recommended feed -------------------------------------------------------

func test_recommended_peaks_at_a_middling_clear_rate() -> void:
	# Identical votes and age: the ONLY difference is play history.
	var provider: LocalProvider = _write_index([
		_fixture("untouched", {"attempts": 0, "clears": 0}),
		_fixture("unbeatable", {"attempts": 20, "clears": 0}),
		_fixture("pushover", {"attempts": 20, "clears": 20}),
		_fixture("fair", {"attempts": 20, "clears": 8}),
	])
	var order: Array = _ids(_list(provider, CommunityProvider.SORT_RECOMMENDED, CommunityProvider.TYPE_ALL))

	assert_eq(order[0], "fair", "a base cleared about 40 percent of the time is the best recommendation")
	assert_lt(order.find("unbeatable"), order.find("untouched"),
		"a base people at least ATTEMPT outranks one nobody has touched")
	assert_lt(order.find("pushover"), order.find("untouched"),
		"engagement still counts for a base that is too easy")
	assert_eq(order[order.size() - 1], "untouched",
		"an unplayed base has earned neither the fairness nor the engagement term")


func test_recommended_prefers_a_healthy_sample_over_a_fluke() -> void:
	# Both sit at a 50% clear rate, so their fairness terms are identical; the engagement
	# term is what separates a proven base from a two-play fluke.
	var provider: LocalProvider = _write_index([
		_fixture("fluke", {"attempts": 2, "clears": 1}),
		_fixture("proven", {"attempts": 60, "clears": 30}),
	])
	assert_eq(_ids(_list(provider, CommunityProvider.SORT_RECOMMENDED, CommunityProvider.TYPE_ALL)),
		["proven", "fluke"], "the same rate over more plays ranks higher")


func test_recommended_boosts_fresh_items_only_slightly() -> void:
	var provider: LocalProvider = _write_index([
		_fixture("stale", {"created": _days_ago(120.0)}),
		_fixture("fresh", {"created": _days_ago(0.0)}),
	])
	assert_eq(_ids(_list(provider, CommunityProvider.SORT_RECOMMENDED, CommunityProvider.TYPE_ALL)),
		["fresh", "stale"], "all else equal, the newer item is boosted")

	# ...but the nudge is small: a well-liked old base still beats a brand-new unknown.
	var provider2: LocalProvider = _write_index([
		_fixture("fresh_unloved", {"votes": 0, "created": _days_ago(0.0)}),
		_fixture("popular_old", {"votes": 200, "created": _days_ago(120.0)}),
	])
	assert_eq(_ids(_list(provider2, CommunityProvider.SORT_RECOMMENDED, CommunityProvider.TYPE_ALL)),
		["popular_old", "fresh_unloved"], "freshness is a nudge onto the page, not a free top slot")


func test_recommended_ordering_is_stable_across_calls() -> void:
	# Two items scoring identically must not shuffle between calls -- a wobbling order makes
	# pagination lose or repeat an item.
	var provider: LocalProvider = _write_index([
		_fixture("beta", {"votes": 5}),
		_fixture("alpha", {"votes": 5}),
	])
	var first: Array = _ids(_list(provider, CommunityProvider.SORT_RECOMMENDED, CommunityProvider.TYPE_ALL))
	var second: Array = _ids(_list(provider, CommunityProvider.SORT_RECOMMENDED, CommunityProvider.TYPE_ALL))
	assert_eq(first, second, "an equal-scoring pair keeps a deterministic tie-break order")


# --- Attempt ledger ---------------------------------------------------------

func test_report_attempt_counts_every_play_including_repeats() -> void:
	var provider: LocalProvider = _write_index([_fixture("base", {"attempts": 0, "clears": 0})])

	var first: Dictionary = _sync(func(cb: Callable): provider.report_attempt("base", {"cleared": false, "score": 10, "turns": 4}, cb))
	assert_true(bool(first.get("ok", false)), "reporting an attempt should succeed")
	assert_eq(int(first.get("data", {}).get("attempts", 0)), 1, "the first play is counted")
	assert_eq(int(first.get("data", {}).get("clears", -1)), 0, "a failed run does not count as a clear")

	var second: Dictionary = _sync(func(cb: Callable): provider.report_attempt("base", {"cleared": true, "score": 900, "turns": 7}, cb))
	assert_eq(int(second.get("data", {}).get("attempts", 0)), 2, "a repeat by the SAME device counts again")
	assert_eq(int(second.get("data", {}).get("clears", 0)), 1, "the clear is counted")

	var third: Dictionary = _sync(func(cb: Callable): provider.report_attempt("base", {"cleared": true, "score": 900, "turns": 7}, cb))
	assert_eq(int(third.get("data", {}).get("attempts", 0)), 3,
		"the ledger is deliberately NOT idempotent -- every attempt counts")
	assert_eq(int(third.get("data", {}).get("clears", 0)), 2, "and so does every clear")

	# The counters are server-maintained state: a fresh provider on the same root sees them.
	var fresh := LocalProvider.new(TMP_ROOT)
	var listed: Array = _list(fresh, CommunityProvider.SORT_TOP, CommunityProvider.TYPE_ALL)
	assert_eq(int(listed[0].get("attempts", 0)), 3, "attempts persist to the store")
	assert_eq(int(listed[0].get("clears", 0)), 2, "clears persist to the store")


func test_report_attempt_validates_the_outcome_at_the_boundary() -> void:
	var provider: LocalProvider = _write_index([_fixture("base")])
	var result: Dictionary = _sync(func(cb: Callable): provider.report_attempt("base", {
		"cleared": "yes",          # not a bool
		"score": -50,              # negative
		"turns": 12.9,             # float
		"admin": true,             # unknown key
		"attempts": 9999,          # trying to write a counter directly
	}, cb))

	assert_true(bool(result.get("ok", false)), "a messy outcome is clamped, not rejected")
	var outcome: Dictionary = result.get("data", {}).get("outcome", {})
	assert_eq(outcome.keys().size(), 3, "the stored outcome has exactly cleared/score/turns")
	assert_false(bool(outcome.get("cleared", true)), "a non-bool 'cleared' reads as false")
	assert_eq(int(outcome.get("score", -1)), 0, "a negative score clamps to zero")
	assert_eq(int(outcome.get("turns", -1)), 12, "a float turn count truncates to an int")
	assert_eq(int(result.get("data", {}).get("attempts", 0)), 1,
		"the caller cannot write a counter directly -- one report is one attempt")

	var over: Dictionary = _sync(func(cb: Callable): provider.report_attempt("base", {"score": 999_999_999, "turns": 100000}, cb))
	var clamped: Dictionary = over.get("data", {}).get("outcome", {})
	assert_eq(int(clamped.get("score", 0)), CommunityProvider.MAX_ATTEMPT_SCORE, "an absurd score clamps to the ceiling")
	assert_eq(int(clamped.get("turns", 0)), CommunityProvider.MAX_ATTEMPT_TURNS, "an absurd turn count clamps to the ceiling")


func test_report_attempt_on_an_unknown_id_fails_with_not_found() -> void:
	var provider: LocalProvider = _write_index([_fixture("base")])
	var result: Dictionary = _sync(func(cb: Callable): provider.report_attempt("no_such_item", {"cleared": true}, cb))
	assert_false(bool(result.get("ok", true)), "an unknown id must not create a ledger entry")
	assert_eq(String(result.get("error", "")), CommunityProvider.ERR_NOT_FOUND,
		"callers switch on the machine-readable code")


# --- Attached replays --------------------------------------------------------

func test_an_attached_replay_persists_and_round_trips_byte_identically() -> void:
	var provider := LocalProvider.new(TMP_ROOT)
	var id: String = String(_upload_challenge(provider, "Replay Base").get("id", ""))
	var blob: String = _replay_b64("attach")

	var reported: Dictionary = _report(provider, id, {
		"cleared": true, "score": 900, "turns": 7, CommunityProvider.REPLAY_KEY: blob})
	assert_true(bool(reported.get("has_replay", false)), "a valid replay is accepted")
	var attempt_id: String = String(reported.get("attempt_id", ""))
	assert_false(attempt_id.is_empty(), "the attempt is named, so its replay can be asked for")
	assert_eq(reported.get("outcome", {}).keys().size(), 3,
		"the replay rides ALONGSIDE the outcome -- it never widens it")

	# The ledger entry carries the pinned shape and flags the blob.
	var page: Dictionary = _attempt_page(provider, id, 0)
	var entries: Array = page.get("entries", [])
	assert_eq(entries.size(), 1, "one attempt, one ledger entry")
	var entry: Dictionary = entries[0]
	assert_eq(String(entry.get("attempt_id", "")), attempt_id, "the entry names the same attempt")
	assert_true(bool(entry.get("has_replay", false)), "and advertises its replay")
	assert_true(bool(entry.get("cleared", false)) and int(entry.get("score", -1)) == 900
		and int(entry.get("turns", -1)) == 7, "the outcome is recorded per attempt, not just counted")
	assert_false(String(entry.get("at", "")).is_empty(), "the store stamps when it happened")
	assert_false(bool(page.get("has_more", true)), "a single entry is the whole log")

	# Byte-identical round trip -- what the attacker's machine encoded is what the defender
	# gets back, or the container's own digest would refuse it.
	var fetched: Dictionary = _sync(func(cb: Callable): provider.fetch_attempt_replay(attempt_id, cb))
	assert_true(bool(fetched.get("ok", false)), "the owner may fetch the replay")
	assert_eq(String(fetched.get("data", "")), blob, "the stored blob comes back unchanged")
	assert_false(ReplayLog.decode_container(Marshalls.base64_to_raw(String(fetched.get("data", "")))).is_empty(),
		"and it is still a decodable replay after the round trip")

	# It survives the process: a fresh provider on the same root serves the same bytes.
	var fresh := LocalProvider.new(TMP_ROOT)
	assert_eq(String(_sync(func(cb: Callable): fresh.fetch_attempt_replay(attempt_id, cb)).get("data", "")),
		blob, "the blob is persisted, not held in memory")


func test_a_bad_replay_is_dropped_but_the_attempt_still_counts() -> void:
	var provider := LocalProvider.new(TMP_ROOT)
	var id: String = String(_upload_challenge(provider, "Replay Base").get("id", ""))

	# Three ways to be unacceptable: not base64 at all, well-formed base64 that is not a
	# container, and a blob past the size ceiling (refused on LENGTH, before any decode).
	var junk: Array = [
		"this is not base64!!",
		Marshalls.raw_to_base64("hello, defender".to_utf8_buffer()),
		"A".repeat(CommunityProvider.MAX_REPLAY_B64_LENGTH + 4),
	]
	for i in junk.size():
		var reported: Dictionary = _report(provider, id, {
			"cleared": false, "turns": i, CommunityProvider.REPLAY_KEY: junk[i]})
		assert_false(bool(reported.get("has_replay", true)),
			"an unacceptable replay is dropped (case %d)" % i)
		assert_eq(int(reported.get("attempts", 0)), i + 1,
			"...and the attempt is still counted (case %d)" % i)
		assert_eq(String(_sync(func(cb: Callable):
			provider.fetch_attempt_replay(String(reported.get("attempt_id", "")), cb)).get("error", "")),
			CommunityProvider.ERR_NOT_FOUND, "there is nothing to fetch (case %d)" % i)

	for entry in _attempt_page(provider, id, 0).get("entries", []):
		assert_false(bool(entry.get("has_replay", true)),
			"the ledger never advertises a replay that was dropped")


func test_the_replay_gate_is_the_boundary_sanitiser() -> void:
	# The gate itself, directly -- both providers and the reference server share these rules.
	var blob: String = _replay_b64("gate")
	assert_eq(CommunityProvider.sanitize_replay_b64(blob), blob, "a real container passes verbatim")
	assert_eq(CommunityProvider.sanitize_replay_b64("  %s  " % blob), blob, "edges are trimmed")
	for bad in [null, 42, "", "   ", "***", "AAAA", "A".repeat(CommunityProvider.MAX_REPLAY_B64_LENGTH + 4)]:
		assert_eq(CommunityProvider.sanitize_replay_b64(bad), "",
			"anything that is not a decodable container is refused, quietly")

	# Tampering is caught by the container's own digest, not by us re-parsing it.
	var bytes: PackedByteArray = Marshalls.base64_to_raw(blob)
	bytes[bytes.size() - 1] = bytes[bytes.size() - 1] ^ 0xFF
	assert_eq(CommunityProvider.sanitize_replay_b64(Marshalls.raw_to_base64(bytes)), "",
		"a tampered container is refused before anything would inflate it")


func test_attempt_log_is_newest_first_and_paginated() -> void:
	var provider := LocalProvider.new(TMP_ROOT)
	var id: String = String(_upload_challenge(provider, "Replay Base").get("id", ""))
	var total: int = CommunityProvider.PAGE_SIZE + 3
	for i in total:
		_report(provider, id, {"cleared": false, "turns": i})

	var first: Dictionary = _attempt_page(provider, id, 0)
	var page0: Array = first.get("entries", [])
	assert_eq(page0.size(), CommunityProvider.PAGE_SIZE, "a page holds PAGE_SIZE entries")
	assert_true(bool(first.get("has_more", false)), "and says there is more behind it")
	assert_eq(int(page0[0].get("turns", -1)), total - 1, "newest first: the last attempt leads")
	assert_eq(int(page0[page0.size() - 1].get("turns", -1)), total - CommunityProvider.PAGE_SIZE)

	var second: Dictionary = _attempt_page(provider, id, 1)
	assert_eq(second.get("entries", []).size(), 3, "the tail is the rest")
	assert_eq(int(second.get("entries", [])[2].get("turns", -1)), 0, "ending at the oldest attempt")
	assert_false(bool(second.get("has_more", true)), "the last page says so")

	assert_eq(_attempt_page(provider, id, 9).get("entries", []).size(), 0,
		"a page past the end is empty, not an error")


func test_the_attempt_log_and_its_replays_are_owner_only() -> void:
	var provider := LocalProvider.new(TMP_ROOT)
	var id: String = String(_upload_challenge(provider, "Replay Base").get("id", ""))
	var attempt_id: String = String(_report(provider, id, {
		"cleared": true, CommunityProvider.REPLAY_KEY: _replay_b64("owner")}).get("attempt_id", ""))

	var unknown: Dictionary = _sync(func(cb: Callable): provider.attempt_log("no_such_item", 0, cb))
	assert_eq(String(unknown.get("error", "")), CommunityProvider.ERR_NOT_FOUND,
		"an unknown id is not_found, not not_owner")
	assert_eq(String(_sync(func(cb: Callable): provider.fetch_attempt_replay("no_such_attempt", cb)).get("error", "")),
		CommunityProvider.ERR_NOT_FOUND, "and so is an unknown attempt")

	# Become someone else: the ledger is the DEFENDER's private record of who attacked them.
	CommunityProvider.set_device_path(TMP_DEVICE_OTHER)
	assert_eq(String(_sync(func(cb: Callable): provider.attempt_log(id, 0, cb)).get("error", "")),
		CommunityProvider.ERR_NOT_OWNER, "someone else's attempt log is not mine to read")
	assert_eq(String(_sync(func(cb: Callable): provider.fetch_attempt_replay(attempt_id, cb)).get("error", "")),
		CommunityProvider.ERR_NOT_OWNER, "nor is the replay it points at")


func test_unowned_seed_content_has_no_readable_attempt_log() -> void:
	# Builtin/seed items belong to nobody (see test_seeded_content_belongs_to_nobody), so
	# there is no owner for the gate to match -- nobody may read their logs.
	var provider: LocalProvider = _write_index([_fixture("base", {"owner": ""})])
	_report(provider, "base", {"cleared": true})
	assert_eq(String(_sync(func(cb: Callable): provider.attempt_log("base", 0, cb)).get("error", "")),
		CommunityProvider.ERR_NOT_OWNER, "an unowned base's log belongs to nobody")


func test_only_the_newest_replays_are_kept() -> void:
	var provider := LocalProvider.new(TMP_ROOT)
	var id: String = String(_upload_challenge(provider, "Replay Base").get("id", ""))

	var first_attempt: String = ""
	var last_attempt: String = ""
	for i in CommunityProvider.MAX_STORED_REPLAYS + 1:
		var reported: Dictionary = _report(provider, id, {
			"cleared": false, "turns": i, CommunityProvider.REPLAY_KEY: _replay_b64("keep_%d" % i)})
		assert_true(bool(reported.get("has_replay", false)), "every valid blob is stored on arrival")
		last_attempt = String(reported.get("attempt_id", ""))
		if i == 0:
			first_attempt = String(reported.get("attempt_id", ""))

	assert_eq(String(_sync(func(cb: Callable): provider.fetch_attempt_replay(first_attempt, cb)).get("error", "")),
		CommunityProvider.ERR_NOT_FOUND,
		"past the retention window the OLDEST blob is dropped")
	assert_true(bool(_sync(func(cb: Callable): provider.fetch_attempt_replay(last_attempt, cb)).get("ok", false)),
		"while the newest is still watchable")

	# The ledger entry survives the blob and stops advertising it -- the log stays honest.
	var oldest: Dictionary = _find_entry(provider, id, first_attempt)
	assert_false(oldest.is_empty(), "the aged-out attempt is still in the ledger")
	assert_false(bool(oldest.get("has_replay", true)), "but no longer claims a replay")

	var kept: int = 0
	for page in 3:
		for entry in _attempt_page(provider, id, page).get("entries", []):
			if bool(entry.get("has_replay", false)):
				kept += 1
	assert_eq(kept, CommunityProvider.MAX_STORED_REPLAYS, "exactly the newest window is retained")


## Walk the paged ledger for one attempt's entry ({} when it is gone).
func _find_entry(provider: LocalProvider, id: String, attempt_id: String) -> Dictionary:
	for page in 20:
		var data: Dictionary = _attempt_page(provider, id, page)
		for entry in data.get("entries", []):
			if String(entry.get("attempt_id", "")) == attempt_id:
				return entry
		if not bool(data.get("has_more", false)):
			break
	return {}


# --- Active bases -----------------------------------------------------------

func test_upload_stamps_ownership_and_publishes_up_to_the_cap() -> void:
	var provider := LocalProvider.new(TMP_ROOT)
	var me: String = CommunityProvider.device_id()

	var first: Dictionary = _upload_challenge(provider, "Base Alpha")
	assert_eq(String(first.get("owner", "")), me, "the uploader's device id is stamped as owner")
	assert_true(bool(first.get("active", false)), "a base is published by default")

	_upload_challenge(provider, "Base Beta")
	_upload_challenge(provider, "Base Gamma")
	var fourth: Dictionary = _upload_challenge(provider, "Base Delta")
	assert_false(bool(fourth.get("active", true)),
		"a fourth upload lands RETIRED rather than sneaking past the 3-active cap")

	var mine: Array = _sync(func(cb: Callable): provider.my_bases(cb)).get("data", [])
	assert_eq(mine.size(), 4, "my_bases lists my bases whether active or retired")
	for it in mine:
		assert_eq(String(it.get("owner", "")), me, "my_bases only returns MY bases")
	assert_true(mine[0].has("attempts") and mine[0].has("clears"),
		"my_bases carries the counters -- that is what the bases screen shows")


func test_activating_a_fourth_base_fails_until_one_is_retired() -> void:
	var provider := LocalProvider.new(TMP_ROOT)
	var alpha: String = String(_upload_challenge(provider, "Base Alpha").get("id", ""))
	_upload_challenge(provider, "Base Beta")
	_upload_challenge(provider, "Base Gamma")
	var delta: String = String(_upload_challenge(provider, "Base Delta").get("id", ""))

	var refused: Dictionary = _sync(func(cb: Callable): provider.set_base_active(delta, true, cb))
	assert_false(bool(refused.get("ok", true)), "a fourth ACTIVE base must be refused")
	assert_eq(String(refused.get("error", "")), CommunityProvider.ERR_BASE_LIMIT,
		"the refusal names the base limit")

	var retired: Dictionary = _sync(func(cb: Callable): provider.set_base_active(alpha, false, cb))
	assert_true(bool(retired.get("ok", false)), "retiring an own base always succeeds")

	var accepted: Dictionary = _sync(func(cb: Callable): provider.set_base_active(delta, true, cb))
	assert_true(bool(accepted.get("ok", false)), "retiring one frees the slot immediately")
	assert_true(bool(accepted.get("data", {}).get("active", false)), "and the base is now published")


func test_retired_base_leaves_the_feeds_but_stays_fetchable_by_id() -> void:
	var provider := LocalProvider.new(TMP_ROOT)
	var summary: Dictionary = _upload_challenge(provider, "Base Alpha")
	var id: String = String(summary.get("id", ""))

	assert_true(_ids(_list(provider, CommunityProvider.SORT_NEW, CommunityProvider.TYPE_CHALLENGE)).has(id),
		"an active base is listed")

	assert_true(bool(_sync(func(cb: Callable): provider.set_base_active(id, false, cb)).get("ok", false)),
		"retiring should succeed")

	for sort in [CommunityProvider.SORT_TOP, CommunityProvider.SORT_NEW,
			CommunityProvider.SORT_DAILY, CommunityProvider.SORT_RECOMMENDED]:
		assert_false(_ids(_list(provider, sort, CommunityProvider.TYPE_ALL)).has(id),
			"a retired base is excluded from the '%s' feed" % sort)
	assert_false(_ids(_list(provider, CommunityProvider.SORT_TOP, CommunityProvider.TYPE_ALL, 0, "Base Alpha")).has(id),
		"and from search results")

	# The share code must keep working: a friend with the id can still play it.
	var fetched: Dictionary = _sync(func(cb: Callable): provider.fetch_item(id, cb))
	assert_true(bool(fetched.get("ok", false)), "a retired base is still fetchable by direct id")
	assert_eq(String(fetched.get("data", {}).get("name", "")), "Base Alpha", "and it is the right payload")

	# It also still accepts attempts -- a friend playing from a code is real traffic.
	var reported: Dictionary = _sync(func(cb: Callable): provider.report_attempt(id, {"cleared": true}, cb))
	assert_true(bool(reported.get("ok", false)), "a retired base still records attempts")


func test_another_devices_base_cannot_be_retired() -> void:
	var provider := LocalProvider.new(TMP_ROOT)
	var id: String = String(_upload_challenge(provider, "Base Alpha").get("id", ""))

	# Become a different device (a fresh identity file -> a fresh uuid).
	CommunityProvider.set_device_path(TMP_DEVICE_OTHER)

	var refused: Dictionary = _sync(func(cb: Callable): provider.set_base_active(id, false, cb))
	assert_false(bool(refused.get("ok", true)), "someone else's base is not mine to retire")
	assert_eq(String(refused.get("error", "")), CommunityProvider.ERR_NOT_OWNER, "the refusal says why")

	var mine: Array = _sync(func(cb: Callable): provider.my_bases(cb)).get("data", [])
	assert_eq(mine.size(), 0, "another device's uploads are not my bases")

	var unknown: Dictionary = _sync(func(cb: Callable): provider.set_base_active("no_such_item", false, cb))
	assert_eq(String(unknown.get("error", "")), CommunityProvider.ERR_NOT_FOUND,
		"an unknown id is not_found, not not_owner")


func test_seeded_content_belongs_to_nobody() -> void:
	var provider := LocalProvider.new(TMP_ROOT)
	var items: Array = _list(provider, CommunityProvider.SORT_TOP, CommunityProvider.TYPE_ALL)
	assert_gt(items.size(), 0, "the seed catalogue should exist")
	for it in items:
		assert_eq(String(it.get("owner", "")), "", "builtin seed content has no owner...")
	var refused: Dictionary = _sync(func(cb: Callable): provider.set_base_active(String(items[0].get("id", "")), false, cb))
	assert_eq(String(refused.get("error", "")), CommunityProvider.ERR_NOT_OWNER,
		"...so nobody can retire it")


# --- Cleanup ----------------------------------------------------------------

func _rm_rf(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		var child: String = path + name
		if dir.current_is_dir():
			_rm_rf(child + "/")
		else:
			DirAccess.remove_absolute(child)
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
