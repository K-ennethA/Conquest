extends GutTest

## StorySnapshot: a lossless round trip through JSON, version gating, unknown ids skipped.


func _state() -> StoryState:
	var s := StoryState.new()
	s.set_flag("quest.blight_road", 1)
	s.set_flag("oakvale.mill_chest.opened", 1)
	var m: StoryPartyMember = s.add_member("vineweave")
	m.current_hp = 41
	m.item_id = "heartwood_charm"
	m.growth = {"growth": 2}
	s.add_member("petalfang")
	s.add_member("petalfang")
	s.add_item("sagebloom_poultice")
	s.gold = 220
	s.set_location("mossway", Vector3i(6, 5, 0), "north")
	s.respawn = {"area_id": "oakvale", "entry": "wayshrine"}
	s.mark_visited("oakvale")
	s.mark_visited("mossway")
	s.light_wayshrine("oakvale.wayshrine")
	s.rng_seed = 918273645
	s.steps = 412
	s.grace_steps = 2
	s.set_actor_position("oakvale", "guard", Vector3i(18, 10, 0), "west", true)
	s.set_actor_position("mossway", "bram", Vector3i(19, 5, 0), "south", false)
	s.play_seconds = 8123.0
	return s


func test_round_trip_through_json() -> void:
	var text: String = JSON.stringify(StorySnapshot.to_dict(_state()))
	var r: Dictionary = StorySnapshot.from_dict(JSON.parse_string(text))
	assert_true(bool(r["success"]), "decodes")
	var s: StoryState = r["state"]
	assert_eq(s.get_flag_int("quest.blight_road"), 1, "flags")
	assert_true(s.get_flag("quest.blight_road") is int, "an int flag is an int again")
	assert_eq(s.party.size(), 3, "party")
	assert_eq(s.member("vineweave").current_hp, 41, "member HP")
	assert_eq(s.member("vineweave").item_id, "heartwood_charm", "member item")
	assert_eq(int(s.member("vineweave").growth.get("growth", 0)), 2,
		"EVOLUTION's opaque growth survives (JSON numbers are EVOLUTION's to coerce)")
	assert_not_null(s.member("petalfang#2"), "the RosterLedger-style uid survives")
	assert_eq(s.item_count("sagebloom_poultice"), 1, "bag")
	assert_eq(s.gold, 220, "gold")
	assert_eq(s.location_area(), "mossway", "location area")
	assert_eq(s.location_cell(), Vector3i(6, 5, 0), "location cell")
	assert_eq(s.location_facing(), "north", "facing")
	assert_eq(s.respawn["entry"], "wayshrine", "respawn")
	assert_eq(s.visited_areas.size(), 2, "visited")
	assert_eq(s.lit_wayshrines, ["oakvale.wayshrine"] as Array[String], "lit shrines")
	assert_eq(s.rng_seed, 918273645, "encounter seed")
	assert_eq(s.steps, 412, "step counter (reloading never re-rolls)")
	assert_eq(s.actor_override("oakvale", "guard")["cell"], Vector3i(18, 10, 0), "a persisted move survives")
	assert_true(s.actor_override("mossway", "bram").is_empty(), "a transient move is not saved")
	assert_eq(int(s.play_seconds), 8123, "play time")


func test_version_gate() -> void:
	var d: Dictionary = StorySnapshot.to_dict(_state())
	d["format_version"] = StorySnapshot.FORMAT_VERSION + 1
	var r: Dictionary = StorySnapshot.from_dict(d)
	assert_false(bool(r["success"]), "a newer format is refused")
	assert_eq(r["reason"], "newer_version", "and says why")
	d.erase("format_version")
	assert_false(bool(StorySnapshot.from_dict(d)["success"]), "a missing version is refused")
	assert_false(bool(StorySnapshot.from_dict([]) ["success"]), "a non-dictionary is refused")


## A version-1 journey predates the story opening: it is not migrated, it is refused as
## OUTDATED (a new journey is required) -- never a crash.
func test_a_pre_opening_journey_is_outdated_not_migrated() -> void:
	var d: Dictionary = StorySnapshot.to_dict(_state())
	assert_false(StorySnapshot.is_outdated(d), "a current save is not outdated")
	d["format_version"] = 1
	assert_true(StorySnapshot.is_outdated(d), "a v1 save is outdated")
	var r: Dictionary = StorySnapshot.from_dict(d)
	assert_false(bool(r["success"]), "and does not load")
	assert_eq(r["reason"], StorySnapshot.REASON_OUTDATED, "it says a new journey is required")
	assert_null(r["state"], "with no half-built state")


func test_unknown_ids_are_skipped_not_raised() -> void:
	var d: Dictionary = StorySnapshot.to_dict(_state())
	d["party"].append({"member_id": "dragon", "character_id": "dragon_that_does_not_exist"})
	d["party"].append({"member_id": "", "character_id": "vineweave"})
	d["bag"]["no_such_item"] = 3
	var s: StoryState = StorySnapshot.from_dict(d)["state"]
	assert_eq(s.party.size(), 3, "an unknown character and a blank uid are dropped")
	assert_eq(s.item_count("no_such_item"), 0, "an unknown item is dropped")


func test_describe_caption() -> void:
	var d: Dictionary = StorySnapshot.to_dict(_state())
	assert_eq(StorySnapshot.describe(d, {"mossway": "The Mossway"}), "The Mossway  ·  2h 15m", "caption")
