extends GutTest

## "OPEN TO EXPLORE THE WHOLE REGION" once the opening is over: from the burned village, every built
## area of the starting region (the Mossway, River Crossing, Crownhaven and all its buildings, the
## Sparse Forest, Woodland Town and its buildings) is reachable through warps and doors that are
## open given only `opening.complete` -- no later story flag gates any of it. The roads that ARE shut
## lead to places with no area built yet, and each waits on its own `world.*` flag.

const StoryFixture := preload("res://tests/helpers/story_fixture.gd")

## The exits that stay closed after the opening: the roads toward places that are not built yet.
const CLOSED_ROADS: Array[String] = [
	"oakvale_ruins/west_exit",          # Farm Hamlet
	"river_crossing/east_exit",         # Beach Village
	"crownhaven/north_exit",            # Mountain Base
	"crownhaven/east_exit",             # Redrock Village
	"crownhaven/harbour_exit",          # Beach Village
	"woodland_town/north_exit",         # Frostpeak Village
	"woodland_town/west_exit",          # Deepwood Village
	"woodland_town/south_exit",         # the Hidden Thieves Guild
]


func _area(id: String) -> OverworldAreaResource:
	return StoryController.load_area(id)


func test_every_area_of_the_region_is_reachable_with_only_the_opening_behind_you() -> void:
	var s := StoryFixture.past_opening(StoryState.new())
	# Only the flags the opening itself sets: nothing from Act 1, the rival, the arena or the ambush.
	for f in ["act1.met_rowan", "rival.met", "rival.duel1", "mossway.ambush.sprung", "mossway.ambush.cleared"]:
		assert_false(s.has_flag(f), "%s is not needed" % f)
	var seen: Dictionary = {"oakvale_ruins": true}
	var queue: Array[String] = ["oakvale_ruins"]
	while not queue.is_empty():
		var id: String = queue.pop_front()
		var a := _area(id)
		assert_not_null(a, "%s loads" % id)
		if a == null:
			continue
		for e in a.present_entities(s):
			var target: String = ""
			if e is WarpEntity and (e as WarpEntity).is_open(s):
				target = String((e as WarpEntity).target_area)
			elif e is DoorEntity:
				target = String((e as DoorEntity).target_area)
			if not target.is_empty() and not seen.has(target):
				seen[target] = true
				queue.append(target)
	var expected: Array[String] = ["oakvale_ruins", "mossway", "river_crossing", "crownhaven", "sparse_forest",
		"woodland_town"]
	for town in ["river_crossing", "crownhaven", "woodland_town"]:
		expected.append_array(_interiors_of(town))
	for id in expected:
		assert_true(seen.has(id), "%s can be reached once the opening is over" % id)


func _interiors_of(town: String) -> Array[String]:
	var out: Array[String] = []
	for id in StoryController.all_area_ids():
		var a := _area(id)
		if a != null and a.is_interior() and String(a.parent_area) == town:
			out.append(id)
	return out


func test_the_only_shut_exits_are_roads_to_places_that_are_not_built_yet() -> void:
	var s := StoryFixture.past_opening(StoryState.new())
	var atlas := WorldAtlas.load_default()
	var shut: Array[String] = []
	for id in ["oakvale_ruins", "mossway", "river_crossing", "crownhaven", "sparse_forest", "woodland_town"]:
		var a := _area(id)
		for e in a.present_entities(s):
			if e is WarpEntity and not (e as WarpEntity).is_open(s):
				var w := e as WarpEntity
				shut.append("%s/%s" % [id, w.id])
				assert_true(w.requires.contains("world."), "%s/%s waits on its own world flag (%s)" % [id, w.id, w.requires])
	shut.sort()
	var want: Array[String] = CLOSED_ROADS.duplicate()
	want.sort()
	assert_eq(shut, want, "exactly the closed roads are shut")
	# ...and each leads toward a world place that has no area yet.
	for loc in atlas.locations:
		if loc.status == WorldLocation.Status.CLOSED:
			assert_true(loc.area_ids.is_empty(), "%s has no area built" % loc.id)


## Every area reachable from [param from] through warps and doors open under [param s].
func _reachable(s: StoryState, from: String = "oakvale_ruins") -> Dictionary:
	var seen: Dictionary = {from: true}
	var queue: Array[String] = [from]
	while not queue.is_empty():
		var a := _area(queue.pop_front())
		if a == null:
			continue
		for e in a.present_entities(s):
			var target: String = ""
			if e is WarpEntity and (e as WarpEntity).is_open(s):
				target = String((e as WarpEntity).target_area)
			elif e is DoorEntity:
				target = String((e as DoorEntity).target_area)
			if not target.is_empty() and not seen.has(target):
				seen[target] = true
				queue.append(target)
	return seen


func test_the_deep_woods_open_with_the_warden_then_the_chief() -> void:
	# THE DEEP WOODS (DECISIONS.md #40): Woodland Town's west road opens when Warden Hale is asked
	# (world.deepwood_open); the trail north into the Depths once Nyra is beaten
	# (world.depths_of_the_wood_open) -- and nothing else gates either.
	var s := StoryFixture.past_opening(StoryState.new())
	assert_false(_reachable(s).has("deepwood_village"), "Deepwood Village waits on the Wardens' road")
	s.set_flag("world.deepwood_open", 1)
	var reach := _reachable(s)
	assert_true(reach.has("deepwood_village"), "the west road reaches Deepwood Village")
	assert_false(reach.has("depths_of_the_wood"), "the Depths wait on Nyra")
	# In the village, the only shut exit is the trail north, on its own world flag.
	var shut: Array[String] = []
	for e in _area("deepwood_village").present_entities(s):
		if e is WarpEntity and not (e as WarpEntity).is_open(s):
			shut.append(String(e.id))
			assert_eq((e as WarpEntity).requires, "has(\"world.depths_of_the_wood_open\")", "the trail waits on its flag")
	assert_eq(shut, ["north_exit"] as Array[String], "only the trail north is shut")
	s.set_flag("world.depths_of_the_wood_open", 1)
	reach = _reachable(s)
	# The Depths are a MAZE of rooms (#93) ending in the heart of the wood; its warps are never locked
	# (the breakable trees, not the warps, hold the way -- test_deep_woods.gd walks it).
	for id in ["deepwood_village", "depths_of_the_wood", "depths_of_the_wood_2", "depths_of_the_wood_3",
			"depths_of_the_wood_4", "depths_of_the_wood_heart", "woodland_town"]:
		assert_true(reach.has(id), "%s is reachable once Nyra is beaten" % id)
	for id in ["depths_of_the_wood", "depths_of_the_wood_2", "depths_of_the_wood_3", "depths_of_the_wood_4",
			"depths_of_the_wood_heart"]:
		for e in _area(id).present_entities(s):
			if e is WarpEntity:
				assert_true((e as WarpEntity).is_open(s), "%s/%s is open" % [id, e.id])
	# And the way back: the Depths lead to the village, the village to Woodland Town -- from anywhere.
	assert_true(_reachable(s, "depths_of_the_wood").has("oakvale_ruins"), "the road home runs back the same way")
	assert_true(_reachable(s, "depths_of_the_wood_heart").has("oakvale_ruins"), "even from the heart of the wood")


func test_the_edge_exits_between_built_areas_are_open_throughout_the_opening() -> void:
	# Leaving the burned village for the Mossway is never locked, so "Not yet." can mean "go exploring".
	var mid := StoryFixture.sent_off(StoryState.new())
	for f in ["opening.attack", "opening.researcher_taken", "opening.raiders_fled", "opening.chase"]:
		mid.set_flag(f, 1)
	var ruins := _area("oakvale_ruins")
	var open_to_moss: bool = false
	for e in ruins.present_entities(mid):
		if e is WarpEntity and (e as WarpEntity).target_area == &"mossway":
			open_to_moss = (e as WarpEntity).is_open(mid)
	assert_true(open_to_moss, "the burned village's east road is open before the fight too")
