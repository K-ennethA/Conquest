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
