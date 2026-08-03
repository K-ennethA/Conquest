extends GutTest

# The MY REPLAYS screen: this device's own recordings, watched and deleted.
#
# The screen is built for real and the FILES are real -- written through ReplayLog's own
# codec into a throwaway directory ([constant TEMP_REPLAY_DIR], installed with
# ReplayLog.set_replay_dir), so the player's user://replays/ is never opened. Only PLAYBACK
# is a stand-in: launching for real would change scene out from under the test.
#
# What is pinned here is what a player SEES: that a recording states its mode, map, date and
# outcome; that the newest one is on top; that a recording this build cannot re-simulate is
# still LISTED (with the reason) rather than silently hidden; that watching hands the log to
# the launcher and reports every refusal inline; and that Delete asks twice.
#
# The screen is preloaded by PATH rather than reached through its `class_name`: a brand new
# script is not in the project's global class cache until the project is next imported.
const MyReplaysScript := preload("res://menus/MyReplays.gd")
## The shared replay copy, asserted against directly so a reworded sentence fails ONE place.
const ReplayWatch := preload("res://menus/ReplayWatch.gd")

## A throwaway replay directory. Never the player's.
const TEMP_REPLAY_DIR := "user://test_my_replays/"


## Stand-in for the playback launcher. THE reason no test here changes scene.
class StubPlayback extends RefCounted:
	var result: Dictionary = {"ok": true}
	## The logs it was asked to play, in call order.
	var launched: Array = []

	func launch(log: Dictionary) -> Dictionary:
		launched.append(log)
		return result


var screen: Control
var playback: StubPlayback


func before_each() -> void:
	playback = StubPlayback.new()
	ReplayLog.set_replay_dir(TEMP_REPLAY_DIR)
	_clear_dir()


func after_each() -> void:
	_clear_dir()
	ReplayLog.set_replay_dir(ReplayLog.DEFAULT_REPLAY_DIR)
	screen = null
	playback = null


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_REPLAY_DIR))


func _clear_dir() -> void:
	var dir: DirAccess = DirAccess.open(TEMP_REPLAY_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_REPLAY_DIR + entry))
		entry = dir.get_next()
	dir.list_dir_end()


## Write one real recording into the temp directory and return its full path.
## [param game_version] "" keeps this build's own stamp (the watchable case); anything else
## forges a recording from a different build.
func _write_replay(stem: String, mode: String, map_name: String, at: String,
		result: String, turns: int, game_version: String = "") -> String:
	var log: Dictionary = ReplayLog.make_log({
		"mode": mode,
		"map": {"path": "res://maps/%s.tres" % stem, "name": map_name},
		"recorded_at_utc": at,
	})
	log["outcome"] = ReplayLog.make_outcome(result, 0, turns)
	if not game_version.is_empty():
		log["game_version"] = game_version
	return ReplayLog.save_to_file(log, stem)


func _open() -> void:
	screen = Control.new()
	screen.set_script(MyReplaysScript)
	screen.set_replay_playback(playback)
	add_child_autofree(screen)
	await get_tree().process_frame


# --- Listing -----------------------------------------------------------------

func test_a_recording_states_its_mode_map_date_and_outcome():
	var path: String = _write_replay("alpha", ReplayLog.MODE_CHALLENGE, "Bramble Hollow",
		"2026-08-01T12:03:11", ReplayLog.RESULT_VICTORY, 12)
	assert_false(path.is_empty(), "the fixture recording should be writable")

	await _open()

	var rows: PackedStringArray = screen.replay_rows()
	assert_eq(rows.size(), 1, "the one recording on disk is listed")
	assert_true(rows[0].contains("CHALLENGE"), "the mode it was recorded from")
	assert_true(rows[0].contains("Bramble Hollow"), "the map it was played on")
	assert_true(rows[0].contains("2026-08-01 12:03:11"), "when, readably")
	assert_true(rows[0].contains("Victory in 12 turns"), "and how it ended")

func test_recordings_are_listed_newest_first():
	_write_replay("older", ReplayLog.MODE_SKIRMISH, "Cinder Flats",
		"2026-07-30T09:00:00", ReplayLog.RESULT_DEFEAT, 8)
	_write_replay("newer", ReplayLog.MODE_ARENA, "Bramble Hollow",
		"2026-08-02T09:00:00", ReplayLog.RESULT_VICTORY, 5)

	await _open()

	var rows: PackedStringArray = screen.replay_rows()
	assert_eq(rows.size(), 2, "both recordings are listed")
	assert_true(rows[0].contains("2026-08-02"), "the most recent battle is on top")
	assert_true(rows[1].contains("2026-07-30"), "and the older one below it")

func test_an_empty_replay_directory_says_so_rather_than_showing_a_blank_list():
	await _open()

	assert_eq(screen.replay_rows().size(), 0, "no rows are invented")
	assert_eq(screen.notice_text(), "", "and nothing is reported as an error")

func test_a_recording_from_another_build_is_listed_but_cannot_be_watched():
	_write_replay("foreign", ReplayLog.MODE_SKIRMISH, "Cinder Flats",
		"2026-08-01T09:00:00", ReplayLog.RESULT_VICTORY, 6, "some-other-build")

	await _open()

	assert_eq(screen.replay_rows().size(), 1,
		"a recording this build cannot re-simulate is still SHOWN -- hiding it would read as data loss")
	assert_true(screen.replay_rows()[0].contains(ReplayWatch.VERSION_MISMATCH),
		"with the one shared version-mismatch sentence as its reason")
	assert_false(screen.replay_watch_enabled(0),
		"and its Watch button is closed before it can fail")

func test_an_outcome_reads_in_words_including_the_battle_that_never_finished():
	assert_eq(MyReplaysScript.outcome_label({"result": ReplayLog.RESULT_VICTORY, "turns": 1}),
		"Victory in 1 turn", "a one-turn win is not '1 turns'")
	assert_eq(MyReplaysScript.outcome_label({"result": ReplayLog.RESULT_DEFEAT, "turns": 9}),
		"Defeat in 9 turns", "a loss says how long it took too")
	assert_eq(MyReplaysScript.outcome_label({"result": ReplayLog.RESULT_UNKNOWN, "turns": 0}),
		"Unfinished", "and quitting mid-match is a real outcome, not an error")


# --- Watching ----------------------------------------------------------------

func test_watching_hands_the_recording_to_playback():
	_write_replay("alpha", ReplayLog.MODE_CHALLENGE, "Bramble Hollow",
		"2026-08-01T12:00:00", ReplayLog.RESULT_VICTORY, 12)
	playback.result = {"ok": true}

	await _open()
	assert_true(screen.replay_watch_enabled(0), "a recording from this build is watchable")
	screen.row_watch(0)
	await get_tree().process_frame

	assert_eq(playback.launched.size(), 1, "the log reached the launcher")
	assert_eq(String((playback.launched[0] as Dictionary).get("mode", "")),
		ReplayLog.MODE_CHALLENGE, "as the validated log, not as a path")
	assert_eq(screen.notice_text(), "", "and a successful launch reports nothing")

func test_a_playback_refusal_is_an_inline_sentence():
	_write_replay("alpha", ReplayLog.MODE_SKIRMISH, "Cinder Flats",
		"2026-08-01T12:00:00", ReplayLog.RESULT_DEFEAT, 4)
	playback.result = {"ok": false, "error": "version_mismatch"}

	await _open()
	screen.row_watch(0)
	await get_tree().process_frame

	assert_eq(screen.notice_text(), ReplayWatch.VERSION_MISMATCH,
		"the launcher's refusal becomes the one shared sentence, never a crash")

func test_a_divergence_is_reported_from_the_same_shared_source():
	_write_replay("alpha", ReplayLog.MODE_SKIRMISH, "Cinder Flats",
		"2026-08-01T12:00:00", ReplayLog.RESULT_DEFEAT, 4)
	playback.result = {"ok": false, "error": "diverged"}

	await _open()
	screen.row_watch(0)
	await get_tree().process_frame

	assert_eq(screen.notice_text(), ReplayWatch.DIVERGED,
		"a replay that stopped matching the recording says so in one place")

func test_a_recording_deleted_from_under_the_screen_reports_and_repaints():
	var path: String = _write_replay("alpha", ReplayLog.MODE_SKIRMISH, "Cinder Flats",
		"2026-08-01T12:00:00", ReplayLog.RESULT_DEFEAT, 4)

	await _open()
	# Something else (another device, a file manager) removed it after the list was built.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	screen.row_watch(0)
	await get_tree().process_frame

	assert_eq(screen.notice_text(), ReplayWatch.UNAVAILABLE,
		"a file that vanished is reported, not launched")
	assert_eq(playback.launched.size(), 0, "and nothing empty reaches the launcher")
	assert_eq(screen.replay_rows().size(), 0, "the list repaints to what is actually there")


# --- Deleting ----------------------------------------------------------------

func test_delete_asks_twice_before_removing_anything():
	var path: String = _write_replay("alpha", ReplayLog.MODE_SKIRMISH, "Cinder Flats",
		"2026-08-01T12:00:00", ReplayLog.RESULT_DEFEAT, 4)

	await _open()
	screen.row_delete(0)
	await get_tree().process_frame

	assert_eq(screen.delete_button_text(0), MyReplaysScript.DELETE_ARMED_TEXT,
		"the first press ARMS the row instead of deleting")
	assert_true(FileAccess.file_exists(path), "and the file is still there")
	assert_true(screen.notice_text().contains("Confirm"), "with the page saying what happens next")

func test_the_second_press_deletes_the_file_and_repaints():
	var path: String = _write_replay("alpha", ReplayLog.MODE_SKIRMISH, "Cinder Flats",
		"2026-08-01T12:00:00", ReplayLog.RESULT_DEFEAT, 4)

	await _open()
	screen.row_delete(0)
	screen.row_delete(0)
	await get_tree().process_frame

	assert_false(FileAccess.file_exists(path), "the confirmed delete actually removed the file")
	assert_eq(screen.replay_rows().size(), 0, "and the list repainted without it")
	assert_true(screen.notice_text().contains("Deleted"), "the page confirms what went")

func test_arming_a_different_row_re_aims_rather_than_deleting():
	var keep: String = _write_replay("older", ReplayLog.MODE_SKIRMISH, "Cinder Flats",
		"2026-07-30T09:00:00", ReplayLog.RESULT_DEFEAT, 8)
	var other: String = _write_replay("newer", ReplayLog.MODE_ARENA, "Bramble Hollow",
		"2026-08-02T09:00:00", ReplayLog.RESULT_VICTORY, 5)

	await _open()
	screen.row_delete(0)       # arm the newest
	screen.row_delete(1)       # then aim at the older one instead
	await get_tree().process_frame

	assert_eq(screen.delete_button_text(0), "Delete", "the first row is disarmed again")
	assert_eq(screen.delete_button_text(1), MyReplaysScript.DELETE_ARMED_TEXT,
		"and the second is the one now armed")
	assert_true(FileAccess.file_exists(keep), "nothing was deleted by the re-aim")
	assert_true(FileAccess.file_exists(other), "on either row")
