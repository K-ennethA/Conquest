extends GutTest

## Progress persistence + unlock logic for [b]CampaignController[/b]. The controller is
## exercised as a plain instance (never added to the tree, so its _ready signal wiring
## stays dormant) pointed at a TEMP user:// file, so these tests never touch the player's
## real campaign.json. Covers: the unlock chain (clear ch1 -> ch2 unlocks), best-turn
## bookkeeping, and a save/reload file round-trip.

const CONTROLLER := preload("res://game/campaign/CampaignController.gd")
const TEMP_PATH := "user://test_campaign_progress.json"

var _ctrl
var _ch1: String
var _ch2: String


func before_all() -> void:
	_ch1 = String(CampaignData.get_chapter(0).get("id", ""))
	_ch2 = String(CampaignData.get_chapter(1).get("id", ""))


func before_each() -> void:
	_delete_temp()
	_ctrl = _make_controller()


func after_each() -> void:
	_delete_temp()


func _make_controller():
	var c = CONTROLLER.new()
	autofree(c)
	c.set_progress_path(TEMP_PATH)
	return c


func _delete_temp() -> void:
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(TEMP_PATH)


func test_fresh_progress_only_unlocks_the_first_chapter() -> void:
	assert_true(_ctrl.load_progress().is_empty(), "no file yet => empty progress")
	assert_true(_ctrl.is_unlocked(_ch1), "chapter 1 is unlocked from the start")
	assert_false(_ctrl.is_unlocked(_ch2), "chapter 2 is locked until chapter 1 clears")
	assert_false(_ctrl.is_cleared(_ch1), "nothing cleared yet")
	assert_eq(_ctrl.best_turns(_ch1), -1, "no best turns before a clear")


func test_clearing_chapter_one_unlocks_chapter_two() -> void:
	_ctrl.mark_cleared(_ch1, 5)
	assert_true(_ctrl.is_cleared(_ch1), "chapter 1 is now cleared")
	assert_eq(_ctrl.best_turns(_ch1), 5, "best turns recorded")
	assert_true(_ctrl.is_unlocked(_ch2), "chapter 2 unlocks once chapter 1 clears")


func test_best_turns_keeps_the_fewest() -> void:
	_ctrl.mark_cleared(_ch1, 8)
	assert_eq(_ctrl.best_turns(_ch1), 8)
	_ctrl.mark_cleared(_ch1, 3)
	assert_eq(_ctrl.best_turns(_ch1), 3, "a faster clear improves the best")
	_ctrl.mark_cleared(_ch1, 10)
	assert_eq(_ctrl.best_turns(_ch1), 3, "a slower clear does not worsen the best")


func test_progress_survives_a_reload() -> void:
	_ctrl.mark_cleared(_ch1, 4)
	# A brand-new controller reading the SAME file must see the cleared chapter.
	var reloaded = _make_controller()
	assert_true(reloaded.is_cleared(_ch1), "cleared flag persisted to disk")
	assert_eq(reloaded.best_turns(_ch1), 4, "best turns persisted to disk")
	assert_true(reloaded.is_unlocked(_ch2), "unlock chain holds across a reload")


func test_next_playable_advances_after_a_clear() -> void:
	var first: Dictionary = _ctrl.next_playable_chapter()
	assert_eq(String(first.get("id", "")), _ch1, "resume point starts at chapter 1")
	_ctrl.mark_cleared(_ch1, 6)
	var second: Dictionary = _ctrl.next_playable_chapter()
	assert_eq(String(second.get("id", "")), _ch2, "resume point advances to chapter 2")


func test_reset_wipes_progress() -> void:
	_ctrl.mark_cleared(_ch1, 6)
	assert_true(_ctrl.is_cleared(_ch1))
	_ctrl.reset_progress()
	assert_false(_ctrl.is_cleared(_ch1), "reset clears the cleared flag")
	assert_true(_ctrl.load_progress().is_empty(), "reset empties the progress file")


func test_unknown_chapter_is_never_unlocked() -> void:
	assert_false(_ctrl.is_unlocked("no_such_chapter"), "an unknown id is not unlocked")
