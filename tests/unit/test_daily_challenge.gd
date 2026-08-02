extends GutTest

## Unit tests for [DailyChallenge] -- the deterministic daily picker and the built-in pool
## it ships with.
##
## Coverage:
##  - pick_for_date is PURE: the same date + pool always yields the same challenge.
##  - The pick is stable under pool REORDERING (the picker canonicalises the order itself).
##  - Different dates spread across the pool rather than pinning one entry forever.
##  - An empty pool degrades to {} instead of erroring.
##  - Every shipped built-in JSON loads, finalises and passes ChallengeCodec.validate.
##  - BUILTIN_FILES (the exported-build fallback list) matches what is actually on disk.


# --- Helpers ----------------------------------------------------------------

## Three cheap, DISTINCT challenge dicts. The picker only ever reads the checksum and name,
## so a full map is unnecessary here -- these stand in for pool members.
func _fake_pool() -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	pool.append({"name": "Alpha", "checksum": "aaa111"})
	pool.append({"name": "Bravo", "checksum": "bbb222"})
	pool.append({"name": "Cairn", "checksum": "ccc333"})
	return pool


func _names_of(pool: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for entry in pool:
		out.append(String(entry.get("name", "")))
	return out


# --- Determinism ------------------------------------------------------------

func test_same_date_and_pool_always_picks_the_same_challenge() -> void:
	var pool: Array[Dictionary] = _fake_pool()
	var first: Dictionary = DailyChallenge.pick_for_date(pool, "2026-08-01")
	assert_false(first.is_empty(), "a non-empty pool must yield a pick")
	for i in 5:
		assert_eq(String(DailyChallenge.pick_for_date(pool, "2026-08-01").get("name", "")),
			String(first.get("name", "")),
			"repeated picks for one date must be identical")


func test_pick_is_stable_when_the_pool_is_reordered() -> void:
	var pool: Array[Dictionary] = _fake_pool()
	var expected: String = String(DailyChallenge.pick_for_date(pool, "2026-08-01").get("name", ""))

	# Reversed.
	var reversed: Array[Dictionary] = _fake_pool()
	reversed.reverse()
	assert_ne(_names_of(reversed), _names_of(pool), "the reversed pool must really differ")
	assert_eq(String(DailyChallenge.pick_for_date(reversed, "2026-08-01").get("name", "")), expected,
		"reordering the pool must not change the day's pick")

	# Rotated (a different permutation again).
	var rotated: Array[Dictionary] = _fake_pool()
	rotated.push_back(rotated.pop_front())
	assert_eq(String(DailyChallenge.pick_for_date(rotated, "2026-08-01").get("name", "")), expected,
		"any permutation of the pool must give the same pick")


func test_different_dates_spread_across_the_pool() -> void:
	# Not every pair of dates has to differ (3 slots, many dates), but over a month the
	# picker must reach more than one entry -- otherwise it is not really a DAILY.
	var pool: Array[Dictionary] = _fake_pool()
	var seen: Dictionary = {}
	for day in range(1, 29):
		var date: String = "2026-09-%02d" % day
		seen[String(DailyChallenge.pick_for_date(pool, date).get("name", ""))] = true
	assert_gt(seen.size(), 1, "a month of dates must not all land on the same challenge")


func test_each_date_is_independently_reproducible() -> void:
	var pool: Array[Dictionary] = _fake_pool()
	for day in range(1, 15):
		var date: String = "2026-09-%02d" % day
		var a: String = String(DailyChallenge.pick_for_date(pool, date).get("name", ""))
		var b: String = String(DailyChallenge.pick_for_date(_fake_pool(), date).get("name", ""))
		assert_eq(a, b, "date %s must resolve identically from a freshly built pool" % date)


func test_empty_pool_yields_nothing() -> void:
	var empty: Array[Dictionary] = []
	assert_true(DailyChallenge.pick_for_date(empty, "2026-08-01").is_empty(),
		"an empty pool must return {} rather than error")


func test_single_entry_pool_always_picks_it() -> void:
	var one: Array[Dictionary] = []
	one.append({"name": "Only", "checksum": "zzz999"})
	assert_eq(String(DailyChallenge.pick_for_date(one, "2026-01-01").get("name", "")), "Only")
	assert_eq(String(DailyChallenge.pick_for_date(one, "2030-12-31").get("name", "")), "Only")


func test_today_utc_is_a_plain_day_string() -> void:
	var today: String = DailyChallenge.today_utc()
	assert_eq(today.length(), 10, "today_utc must be YYYY-MM-DD (got '%s')" % today)
	assert_eq(today.split("-").size(), 3, "today_utc must be dash-separated (got '%s')" % today)


# --- Built-in pool ----------------------------------------------------------

func test_every_builtin_file_validates() -> void:
	assert_gt(DailyChallenge.BUILTIN_FILES.size(), 0, "the daily needs shipped challenges")
	for file_name in DailyChallenge.BUILTIN_FILES:
		var path: String = DailyChallenge.BUILTIN_DIR + file_name
		assert_true(FileAccess.file_exists(path), "missing built-in challenge: %s" % path)
		var challenge: Dictionary = DailyChallenge.load_builtin_file(path)
		assert_false(challenge.is_empty(), "%s failed to load/parse" % file_name)
		var errors: Array[String] = ChallengeCodec.validate(challenge)
		assert_eq(errors.size(), 0, "%s failed validation: %s" % [file_name, "; ".join(errors)])


func test_builtin_files_list_matches_the_directory() -> void:
	# BUILTIN_FILES is the fallback used when an exported build cannot list res:// dirs, so
	# it has to stay in sync with the files actually shipped.
	var on_disk: Array[String] = []
	var dir: DirAccess = DirAccess.open(DailyChallenge.BUILTIN_DIR)
	assert_not_null(dir, "the built-in challenge directory must exist")
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json") and not file_name.begins_with("."):
			on_disk.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	on_disk.sort()
	var declared: Array[String] = DailyChallenge.BUILTIN_FILES.duplicate()
	declared.sort()
	assert_eq(declared, on_disk, "DailyChallenge.BUILTIN_FILES must match the shipped files")


func test_builtin_pool_loads_every_file() -> void:
	var pool: Array[Dictionary] = DailyChallenge.load_builtin_pool()
	assert_eq(pool.size(), DailyChallenge.BUILTIN_FILES.size(),
		"load_builtin_pool silently skips invalid files -- a short pool means one is broken")
	# Each entry is finalised (checksum stamped), which is what makes it a usable pool id.
	for challenge in pool:
		assert_false(ChallengeCodec.challenge_id(challenge).is_empty(),
			"a pooled built-in must carry a stamped checksum")


func test_builtins_cover_both_modes() -> void:
	# The survive path only ships if a survive challenge actually ships with it.
	var modes: Dictionary = {}
	for challenge in DailyChallenge.load_builtin_pool():
		modes[ChallengeCodec.rules_mode(challenge)] = true
	assert_true(modes.has(ChallengeCodec.MODE_BREACH), "expected at least one breach built-in")
	assert_true(modes.has(ChallengeCodec.MODE_SURVIVE), "expected at least one survive built-in")


func test_picking_from_the_real_builtin_pool_is_deterministic() -> void:
	var pool: Array[Dictionary] = DailyChallenge.load_builtin_pool()
	if pool.is_empty():
		return
	var pick_a: Dictionary = DailyChallenge.pick_for_date(pool, "2026-08-01")
	var pool_b: Array[Dictionary] = DailyChallenge.load_builtin_pool()
	pool_b.reverse()
	var pick_b: Dictionary = DailyChallenge.pick_for_date(pool_b, "2026-08-01")
	assert_eq(ChallengeCodec.challenge_id(pick_a), ChallengeCodec.challenge_id(pick_b),
		"the real pool must pick identically regardless of load order")
