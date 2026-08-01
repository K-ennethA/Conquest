extends GutTest

## Integrity guards for the campaign definition ([CampaignData]): every chapter points at
## a map that loads and passes its own validator, the difficulty/squad ramp is sane, the
## unlock chain is well-formed, and the finale is the Eldroot DEFEAT-BOSS map. These are
## pure data assertions -- no scene, no autoload -- so they run fast and never flake.

const VALID_DIFFICULTIES := [0, 1, 2, 3]


func test_there_are_at_least_four_chapters() -> void:
	assert_gte(CampaignData.count(), 4, "campaign v1 ships four chapters")


func test_every_chapter_has_the_required_fields() -> void:
	var seen_ids := {}
	for i in range(CampaignData.count()):
		var c: Dictionary = CampaignData.get_chapter(i)
		var where := "chapter %d" % (i + 1)

		var id: String = String(c.get("id", ""))
		assert_false(id.is_empty(), "%s has an id" % where)
		assert_false(seen_ids.has(id), "%s id '%s' is unique" % [where, id])
		seen_ids[id] = true

		assert_eq(int(c.get("number", -1)), i + 1, "%s number is sequential" % where)
		assert_false(String(c.get("title", "")).is_empty(), "%s has a title" % where)
		assert_false(String(c.get("blurb", "")).is_empty(), "%s has a blurb" % where)
		assert_false(String(c.get("map_path", "")).is_empty(), "%s has a map_path" % where)

		var diff: int = int(c.get("ai_difficulty", -1))
		assert_true(diff in VALID_DIFFICULTIES, "%s ai_difficulty %d is 0..3" % [where, diff])
		assert_gte(int(c.get("squad_size", 0)), 1, "%s squad_size is at least 1" % where)


func test_every_chapter_map_loads_and_validates() -> void:
	for i in range(CampaignData.count()):
		var c: Dictionary = CampaignData.get_chapter(i)
		var path: String = String(c.get("map_path", ""))
		assert_true(ResourceLoader.exists(path), "chapter %d map exists: %s" % [i + 1, path])
		var map := load(path) as MapResource
		assert_not_null(map, "chapter %d map loads as a MapResource" % (i + 1))
		if map != null:
			var report: Dictionary = map.validate_map()
			assert_true(bool(report.get("valid", false)),
				"chapter %d map validation issues: %s" % [i + 1, str(report.get("issues", []))])


func test_chapter_squad_size_fits_the_maps_player_slots() -> void:
	# The Character Select cap is the chapter's squad_size; it must never exceed the map's
	# authored player-0 start slots, or some picked units would have nowhere to spawn.
	for i in range(CampaignData.count()):
		var c: Dictionary = CampaignData.get_chapter(i)
		var map := load(String(c.get("map_path", ""))) as MapResource
		if map == null:
			continue
		var p0_slots := 0
		for sd in map.unit_spawns:
			if sd is Dictionary and int(sd.get("player_id", 0)) == 0:
				p0_slots += 1
		assert_lte(int(c.get("squad_size", 0)), p0_slots,
			"chapter %d squad_size fits its %d player-0 slots" % [i + 1, p0_slots])


func test_difficulty_ramps_up_monotonically() -> void:
	var prev := -1
	for i in range(CampaignData.count()):
		var diff: int = int(CampaignData.get_chapter(i).get("ai_difficulty", 1))
		assert_gte(diff, prev, "chapter %d difficulty does not drop below the previous" % (i + 1))
		prev = diff


func test_finale_is_the_eldroot_defeat_boss_map() -> void:
	var last: Dictionary = CampaignData.get_chapter(CampaignData.count() - 1)
	var map := load(String(last.get("map_path", ""))) as MapResource
	assert_not_null(map, "the finale map loads")
	if map != null:
		assert_true("Defeat Boss" in map.victory_conditions,
			"the finale is a Defeat-Boss chapter, got %s" % str(map.victory_conditions))
		var boss_found := false
		for sd in map.unit_spawns:
			var cid: String = str(sd.get("character_id", ""))
			if cid.is_empty():
				continue
			var chr := CharacterLibrary.get_character(cid)
			if chr != null and chr.is_boss:
				boss_found = true
		assert_true(boss_found, "the finale fields a boss (Eldroot)")


func test_unlock_chain_is_well_formed() -> void:
	# next_id walks the chapters in order and terminates at the last one.
	for i in range(CampaignData.count()):
		var id: String = String(CampaignData.get_chapter(i).get("id", ""))
		assert_eq(CampaignData.index_of_id(id), i, "index_of_id round-trips for chapter %d" % (i + 1))
		var nxt: String = CampaignData.next_id(id)
		if i + 1 < CampaignData.count():
			assert_eq(nxt, String(CampaignData.get_chapter(i + 1).get("id", "")),
				"chapter %d links to the next" % (i + 1))
		else:
			assert_eq(nxt, "", "the last chapter links to nothing")


func test_get_by_id_and_bounds() -> void:
	var id0: String = String(CampaignData.get_chapter(0).get("id", ""))
	assert_eq(String(CampaignData.get_by_id(id0).get("id", "")), id0, "get_by_id finds chapter 0")
	assert_true(CampaignData.get_by_id("no_such_chapter").is_empty(), "unknown id yields {}")
	assert_true(CampaignData.get_chapter(-1).is_empty(), "negative index yields {}")
	assert_true(CampaignData.get_chapter(CampaignData.count()).is_empty(), "over-range index yields {}")
