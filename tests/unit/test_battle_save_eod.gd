extends GutTest

## The CHALLENGE END-OF-DAY rule, and the file layer underneath it.
##
## A challenge attempt is a DAILY commitment. Pausing one and coming back the same UTC day is
## fine; letting the date roll over FORFEITS it -- the attempt is recorded as played and
## un-cleared (attempts + 1, no clear) through the same results path a real defeat uses, and
## the save is deleted. Skirmish and campaign saves never expire, however old they are.
##
## This is the rule that is easiest to get subtly wrong, so it is pinned from both ends: the
## expiry decision itself ([method BattleSaveManager.is_expired]), and the consequence
## ([method BattleSaveManager.expire_if_needed] -> the recorded attempt + the deleted file).
##
## HERMETIC BY INJECTION, not by mocking: [method BattleSaveManager.set_save_path] and
## [method ChallengeController.set_results_path] point both files at `user://test_*` for the
## whole suite, so the player's real save and real challenge record are never opened. The
## staging test additionally touches GameSettings and the run's materialised-map directory,
## which the shared guard snapshots and restores from `after_each` (which GUT runs even on a
## failing test).

const SAVE_MANAGER := preload("res://systems/save/BattleSaveManager.gd")
## Preloaded so the script CONSTANTS are read off the script rather than off the autoload
## instance -- the same addressing tests/unit/test_challenge_survive_capture.gd uses.
const CHALLENGE_SCRIPT := preload("res://game/challenge/ChallengeController.gd")
const Guard := preload("res://tests/helpers/global_state_guard.gd")

const TEMP_SAVE_PATH := "user://test_battle_save.json"
const TEMP_RESULTS_PATH := "user://test_battle_save_results.json"

const TODAY := "2026-08-02"
const YESTERDAY := "2026-08-01"

## Untyped on purpose -- see tests/README.md rule 3 (a `: RefCounted` annotation makes the
## static analyser reject the guard's own methods).
var _guard


func before_all() -> void:
	SAVE_MANAGER.set_save_path(TEMP_SAVE_PATH)
	ChallengeController.set_results_path(TEMP_RESULTS_PATH)


func after_all() -> void:
	SAVE_MANAGER.delete_save()
	SAVE_MANAGER.set_save_path(SAVE_MANAGER.DEFAULT_SAVE_PATH)
	if FileAccess.file_exists(TEMP_RESULTS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_RESULTS_PATH))
	ChallengeController.set_results_path(CHALLENGE_SCRIPT.RESULTS_PATH)


func before_each() -> void:
	_guard = Guard.new()
	_guard.watch_setting("selected_map_path")
	_guard.watch_setting("game_mode")
	_guard.watch_setting("selected_turn_system")
	_guard.watch_setting("ai_difficulty")
	_guard.watch_setting("player_count")
	_guard.watch_setting("selected_squad")
	_guard.watch_dir(CHALLENGE_SCRIPT.ACTIVE_MAP_DIR)
	SAVE_MANAGER.delete_save()
	if FileAccess.file_exists(TEMP_RESULTS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_RESULTS_PATH))


func after_each() -> void:
	# Consume any staged resume so it cannot leak into the next suite (the staging slot is
	# process-wide static state, exactly like the save file it points at).
	SAVE_MANAGER.take_pending_resume()
	ChallengeController.cancel()
	_guard.restore()


# --- The expiry decision ----------------------------------------------------

func test_a_challenge_saved_yesterday_has_expired() -> void:
	assert_true(SAVE_MANAGER.is_expired(_challenge_snapshot(YESTERDAY), TODAY),
		"a paused challenge attempt does not survive the UTC date rolling over")


func test_a_challenge_saved_today_is_still_resumable() -> void:
	assert_false(SAVE_MANAGER.is_expired(_challenge_snapshot(TODAY), TODAY),
		"putting an attempt down and picking it up the same day is the whole point")


func test_skirmish_and_campaign_saves_never_expire() -> void:
	assert_false(SAVE_MANAGER.is_expired(_snapshot(YESTERDAY, BattleSnapshot.MODE_SKIRMISH), TODAY),
		"a skirmish is not a daily commitment")
	assert_false(SAVE_MANAGER.is_expired(_snapshot("2020-01-01", BattleSnapshot.MODE_CAMPAIGN), TODAY),
		"nor is a campaign chapter, however long it has been sitting")


# --- The consequence: a forfeited attempt -----------------------------------

func test_expiring_records_a_forfeited_attempt_and_deletes_the_save() -> void:
	var challenge: Dictionary = _make_challenge()
	var snapshot: Dictionary = _challenge_snapshot(YESTERDAY, challenge)
	assert_true(SAVE_MANAGER.write_save(snapshot), "the fixture save was written")

	assert_true(SAVE_MANAGER.expire_if_needed(snapshot, TODAY),
		"expiring reports that there is nothing left to resume")

	var record: Dictionary = ChallengeController.result_for(ChallengeCodec.challenge_id(challenge))
	assert_false(record.is_empty(), "the forfeit is written to the challenge record")
	assert_eq(int(record.get("attempts", -1)), 1, "a forfeited attempt still counts as an attempt")
	assert_eq(int(record.get("clears", -1)), 0, "but never as a clear")
	assert_false(bool(record.get("last_won", true)), "the attempt is recorded as lost")

	assert_false(SAVE_MANAGER.has_save(), "and the expired save is deleted, not left to rot")


func test_expiring_a_still_valid_save_changes_nothing() -> void:
	var challenge: Dictionary = _make_challenge()
	var snapshot: Dictionary = _challenge_snapshot(TODAY, challenge)
	SAVE_MANAGER.write_save(snapshot)

	assert_false(SAVE_MANAGER.expire_if_needed(snapshot, TODAY),
		"a same-day attempt is not expired")
	assert_true(ChallengeController.result_for(ChallengeCodec.challenge_id(challenge)).is_empty(),
		"so no attempt is recorded against it")
	assert_true(SAVE_MANAGER.has_save(), "and the save is still there to resume")


# --- Staging a resume -------------------------------------------------------

func test_staging_an_expired_challenge_refuses_and_discards_it() -> void:
	var challenge: Dictionary = _make_challenge()
	var snapshot: Dictionary = _challenge_snapshot(YESTERDAY, challenge)
	SAVE_MANAGER.write_save(snapshot)

	assert_false(SAVE_MANAGER.stage_resume(snapshot, TODAY),
		"an attempt that expired between the menu opening and the click is still refused")
	assert_false(SAVE_MANAGER.has_pending_resume(), "nothing is staged")
	assert_false(SAVE_MANAGER.has_save(), "and the save is gone")
	assert_eq(int(ChallengeController.result_for(ChallengeCodec.challenge_id(challenge))
		.get("attempts", -1)), 1, "the forfeit is recorded on this path too")


func test_staging_a_same_day_challenge_re_arms_the_run() -> void:
	var challenge: Dictionary = _make_challenge()
	var snapshot: Dictionary = _challenge_snapshot(TODAY, challenge)
	SAVE_MANAGER.write_save(snapshot)

	assert_true(SAVE_MANAGER.stage_resume(snapshot, TODAY), "a same-day attempt resumes")
	assert_true(SAVE_MANAGER.has_pending_resume(), "the snapshot is staged for the battle load")
	assert_eq(GameSettings.game_mode, GameSettings.GameMode.SINGLE_PLAYER,
		"a resumed challenge is a solo battle")
	assert_true(String(GameSettings.selected_map_path).begins_with(CHALLENGE_SCRIPT.ACTIVE_MAP_DIR),
		"the map is re-materialised through the codec rather than trusted from the save")
	assert_true(ChallengeController.is_capturing(),
		"and result capture is armed again, so the resumed battle records against this challenge")

	var taken: Dictionary = SAVE_MANAGER.take_pending_resume()
	assert_eq(String(taken.get("saved_at_utc_date", "")), TODAY, "the battle gets the snapshot")
	assert_false(SAVE_MANAGER.has_save(),
		"consuming a resume deletes the slot -- a save is single-use")


func test_a_corrupt_save_is_discarded_rather_than_staged() -> void:
	SAVE_MANAGER.write_save(_snapshot(TODAY, BattleSnapshot.MODE_SKIRMISH))
	assert_false(SAVE_MANAGER.stage_resume({"format_version": 99}, TODAY),
		"a save this build cannot read is refused")
	assert_false(SAVE_MANAGER.has_save(), "and deleted, so the menu stops offering it")


# --- File layer -------------------------------------------------------------

func test_the_slot_round_trips_through_disk() -> void:
	var snapshot: Dictionary = _snapshot(TODAY, BattleSnapshot.MODE_SKIRMISH)
	assert_true(SAVE_MANAGER.write_save(snapshot), "the write succeeds")
	var read_back: Dictionary = SAVE_MANAGER.peek_save()
	assert_eq(String(read_back.get("saved_at_utc_date", "")), TODAY, "peek returns what was written")
	assert_true(SAVE_MANAGER.has_save(), "and peeking does NOT consume the save")


func test_peeking_an_empty_slot_is_not_an_error() -> void:
	assert_eq(SAVE_MANAGER.peek_save(), {}, "no file simply means nothing to resume")
	assert_false(SAVE_MANAGER.has_save())


# --- Fixtures ---------------------------------------------------------------

func _a_character_id() -> String:
	var ids: Array = CharacterLibrary.all_ids()
	assert_gt(ids.size(), 0, "the roster must have at least one character for these tests")
	return String(ids[0])


func _make_challenge() -> Dictionary:
	var map := MapResource.new()
	map.map_name = "EOD Test Map"
	map.author = "Tester"
	map.width = 5
	map.height = 5
	map.max_players = 2
	map.create_default_layout()
	var cid: String = _a_character_id()
	map.set_character_spawn_at_position(Vector2i(0, 0), 0, cid)
	map.set_character_spawn_at_position(Vector2i(4, 4), 1, cid)
	return ChallengeCodec.build_challenge(map, "EOD Test", "Tester", "2026-08-01T00:00:00", {
		"challenger_squad_size": 2,
		"turn_system": 0,
		"ai_difficulty": 1,
	})


func _challenge_snapshot(date: String, challenge: Dictionary = {}) -> Dictionary:
	var c: Dictionary = challenge if not challenge.is_empty() else _make_challenge()
	var snapshot: Dictionary = _snapshot(date, BattleSnapshot.MODE_CHALLENGE)
	var context: Dictionary = snapshot["context"]
	context["challenge"] = c
	context["challenge_id"] = ChallengeCodec.challenge_id(c)
	context["challenge_turns"] = 3
	context["challenge_units_lost"] = 1
	return snapshot


func _snapshot(date: String, mode: String) -> Dictionary:
	return {
		"format_version": BattleSnapshot.FORMAT_VERSION,
		"saved_at_utc_date": date,
		"saved_at_utc": date + "T09:30:00",
		"context": {
			"mode": mode,
			"map_path": "res://game/maps/resources/default_skirmish.tres",
			"map_name": "Default Skirmish",
			"campaign_chapter_id": "",
			"campaign_turns": 0,
			"challenge_id": "",
			"challenge": {},
			"challenge_turns": 0,
			"challenge_units_lost": 0,
			"squad": [],
			"turn_system": 0,
			"player_count": 2,
			"difficulty": 1,
		},
		"units": [{
			"index": 0,
			"character_id": _a_character_id(),
			"player_id": 0,
			"cell": [0, 0],
			"hp": 10,
			"shield": 0,
			"facing_yaw": 0.0,
			"has_acted": false,
			"has_moved": false,
			"provoked": false,
			"extra_actions": 0,
			"ai_stance": "defensive",
			"home_cell": [0, 0],
			"aggro_range": -1,
			"leash_radius": -1,
			"statuses": [],
			"moves": {},
		}],
		"turn": {},
		"board": {},
	}
