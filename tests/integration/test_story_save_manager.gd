extends GutTest

## StorySaveManager (the three slots) against a TEMP dir, and StoryController's session entry
## points (new journey / continue) on top of it. Never touches user://story/.

const Guard := preload("res://tests/helpers/global_state_guard.gd")
const TEMP_DIR := "user://test_story_save_manager/"


func before_each() -> void:
	StorySaveManager.set_save_dir(TEMP_DIR)
	Guard.rm_rf(TEMP_DIR)
	StoryController.end_session()


func after_each() -> void:
	StoryController.end_session()
	Guard.rm_rf(TEMP_DIR)
	StorySaveManager.set_save_dir(StorySaveManager.DEFAULT_SAVE_DIR)


func test_empty_slots() -> void:
	for slot in range(1, 4):
		assert_false(StorySaveManager.has_save(slot), "slot %d starts empty" % slot)
	assert_eq(StorySaveManager.most_recent_slot(), 0, "no journey -> no Continue target")
	assert_false(bool(StorySaveManager.load_state(1)["success"]), "loading an empty slot fails cleanly")
	assert_false(bool(StorySaveManager.save(9, StoryState.new())["success"]), "slot 9 is not a slot")


func test_save_peek_load_delete() -> void:
	var s := StoryState.new()
	s.add_member("vineweave")
	s.gold = 55
	s.set_location("oakvale", Vector3i(10, 11, 0), "north")
	assert_true(bool(StorySaveManager.save(2, s)["success"]), "saves")
	assert_true(StorySaveManager.has_save(2), "slot 2 now has a journey")
	assert_eq(int(StorySaveManager.peek(2)["gold"]), 55, "peek reads the raw data")
	var loaded: Dictionary = StorySaveManager.load_state(2)
	assert_true(bool(loaded["success"]), "loads")
	assert_eq((loaded["state"] as StoryState).gold, 55, "the same journey")
	assert_eq(StorySaveManager.most_recent_slot(), 2, "the only save is the Continue target")
	StorySaveManager.delete(2)
	assert_false(StorySaveManager.has_save(2), "deleted")


func test_an_outdated_journey_is_never_the_continue_target() -> void:
	var s := StoryState.new()
	s.set_location("oakvale", Vector3i(3, 6, 0), "east")
	assert_true(bool(StorySaveManager.save(1, s)["success"]), "saves")
	var data: Dictionary = StorySaveManager.peek(1)
	data["format_version"] = 1
	var f := FileAccess.open(StorySaveManager.slot_path(1), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	assert_true(StorySaveManager.has_save(1), "the old journey still occupies its slot (it can be deleted)")
	assert_eq(StorySaveManager.most_recent_slot(), 0, "but Continue Journey never offers it")
	var r: Dictionary = StoryController.continue_journey(1)
	assert_false(bool(r["success"]), "continuing it is refused cleanly")
	assert_eq(String(r["reason"]), StorySnapshot.REASON_OUTDATED, "because a new journey is required")


func test_corrupt_file_reads_as_empty() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEMP_DIR))
	var f := FileAccess.open(StorySaveManager.slot_path(1), FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	assert_true(StorySaveManager.peek(1).is_empty(), "a corrupt slot reads as empty, never an error")
	assert_false(StorySaveManager.has_save(1), "and does not count as a save")


func test_new_journey_and_continue_through_the_controller() -> void:
	var r: Dictionary = StoryController.new_journey(1)
	assert_true(bool(r["success"]), "a new journey starts")
	var s: StoryState = StoryController.state()
	assert_eq(s.location_area(), "oakvale", "at home in Oakvale")
	assert_eq(s.location_cell(), Vector3i(3, 6, 0), "on the doorstep (the opening's start entry)")
	assert_eq(s.capped_count(), 0, "with no creature yet -- the starter comes from the Crownhaven ceremony")
	assert_true(s.has_hero(), "only the hero himself (docs/design/HUMANS.md)")
	assert_false(s.has_flag("opening.sent_off"), "before the send-off")
	assert_ne(s.rng_seed, 0, "the journey has an encounter seed")
	assert_true(StorySaveManager.has_save(1), "a new journey is saved at once")
	s.gold = 777
	s.set_flag("opening.sent_off", 1)
	assert_true(bool(StoryController.save_game()["success"]), "manual save")
	StoryController.end_session()
	assert_false(StoryController.has_session(), "session ended")
	assert_true(bool(StoryController.continue_journey(1)["success"]), "continue loads it back")
	assert_eq(StoryController.state().gold, 777, "gold survived")
	assert_true(StoryController.state().has_flag("opening.sent_off"), "flags survived")
	assert_eq(StoryController.slot(), 1, "and the session writes back to slot 1")


func test_slotless_journey_never_saves() -> void:
	StoryController.new_journey(0)
	assert_eq(String(StoryController.save_game()["reason"]), "no_slot", "an in-memory journey is not saved")
	assert_eq(StorySaveManager.most_recent_slot(), 0, "and wrote nothing")
