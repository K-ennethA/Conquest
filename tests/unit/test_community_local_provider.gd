extends GutTest

## Unit tests for [LocalProvider] -- the offline community-service mock.
##
## Coverage:
##  - self-seeds a browsable catalogue on first use;
##  - list_items sorts by score (top) and by recency (new);
##  - a vote round-trips and PERSISTS to disk (a fresh provider sees it);
##  - voting is idempotent per device (same dir twice != double count);
##  - daily() is deterministic within a calendar day.
##
## Each test uses a throwaway user:// root and cleans it up.

const TMP_ROOT := "user://test_community_local/"


func after_each() -> void:
	_rm_rf(TMP_ROOT)


# --- Helpers ----------------------------------------------------------------

## Run a synchronous provider call and return its result dict (LocalProvider calls back
## inline, so the holder is populated by the time the call returns).
func _sync(callable_runner: Callable) -> Dictionary:
	var holder: Array = []
	callable_runner.call(func(r: Dictionary): holder.append(r))
	assert_gt(holder.size(), 0, "provider must call back synchronously")
	return holder[0] if holder.size() > 0 else {}


func _list(provider: LocalProvider, sort: String, type: String, page: int = 0) -> Array:
	var result: Dictionary = _sync(func(cb: Callable): provider.list_items(sort, type, page, cb))
	assert_true(bool(result.get("ok", false)), "list_items should succeed")
	return result.get("data", [])


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
