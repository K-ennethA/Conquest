extends GutTest

## CLOSING THE WINDOW MID-BATTLE SAVES THE RUN.
##
## Save & Quit already wrote the slot; killing the window wrote nothing, and the battle was
## simply gone. "I closed the window" is a player leaving, not a player throwing their run away
## -- so [method BattleSaveManager._notification] now handles `NOTIFICATION_WM_CLOSE_REQUEST`
## and writes the SAME snapshot through the SAME [method BattleSaveManager.can_save_now] gate.
##
## WHAT IS PINNED HERE is that gate, from both sides: gate true -> the snapshot lands on disk;
## gate false -> NOTHING is written, not even a partial file. The decision is tested through
## [method BattleSaveManager.write_close_snapshot], the pure gate-and-write step the handler
## delegates to, so the rule can be exercised exhaustively without standing up a live battle,
## a networked session or an Arena run -- exactly the split [method BattleSaveManager.gate]
## already uses for its own exclusions.
##
## HERMETIC BY INJECTION, not by mocking: [method BattleSaveManager.set_save_path] points the
## one save slot at `user://test_*` for the whole suite (tests/README.md rule 4, and the same
## hygiene as tests/unit/test_battle_save_eod.gd), so the player's real save is never opened.

const SAVE_MANAGER := preload("res://systems/save/BattleSaveManager.gd")

const TEMP_SAVE_PATH := "user://test_battle_save_on_close.json"
const TODAY := "2026-08-02"


func before_all() -> void:
	SAVE_MANAGER.set_save_path(TEMP_SAVE_PATH)


func after_all() -> void:
	SAVE_MANAGER.delete_save()
	SAVE_MANAGER.set_save_path(SAVE_MANAGER.DEFAULT_SAVE_PATH)


func before_each() -> void:
	SAVE_MANAGER.delete_save()


func after_each() -> void:
	SAVE_MANAGER.delete_save()


# --- The gate decides, and only the gate ------------------------------------

func test_an_allowed_close_writes_the_snapshot_to_the_slot() -> void:
	assert_true(SAVE_MANAGER.write_close_snapshot(true, _snapshot()),
		"a saveable battle is written when the window is closed")
	assert_true(SAVE_MANAGER.has_save(), "the slot exists afterwards")
	assert_eq(String(SAVE_MANAGER.peek_save().get("saved_at_utc_date", "")), TODAY,
		"and it round-trips as the same snapshot Save & Quit would have written")


func test_a_refused_close_writes_nothing_at_all() -> void:
	assert_false(SAVE_MANAGER.write_close_snapshot(false, _snapshot()),
		"a battle the gate refuses is not saved on close either")
	assert_false(SAVE_MANAGER.has_save(),
		"and NOTHING is written -- not a partial file, not an empty one")


func test_a_refused_close_never_clobbers_an_existing_save() -> void:
	SAVE_MANAGER.write_save(_snapshot("2026-07-01"))
	assert_false(SAVE_MANAGER.write_close_snapshot(false, _snapshot()),
		"the gate still refuses")
	assert_eq(String(SAVE_MANAGER.peek_save().get("saved_at_utc_date", "")), "2026-07-01",
		"and an unrelated saved battle already in the slot is left exactly as it was")


func test_an_empty_snapshot_is_not_written_even_when_allowed() -> void:
	assert_false(SAVE_MANAGER.write_close_snapshot(true, {}),
		"a battle with nothing capturable produces no file rather than an empty one")
	assert_false(SAVE_MANAGER.has_save(), "so the menu is never offered a resume that cannot load")


# --- The close path reuses the SAME exclusions as Save & Quit ----------------

func test_a_networked_match_is_not_saved_on_close() -> void:
	# NetSession already treats the disconnect a closing window causes as a server-side
	# forfeit; writing a local snapshot on top of that would resurrect a match this peer
	# has already lost.
	var allowed: bool = SAVE_MANAGER.gate(true, true, false, true, true, true)
	assert_false(SAVE_MANAGER.write_close_snapshot(allowed, _snapshot()),
		"the networked exclusion reaches the close path unchanged")
	assert_false(SAVE_MANAGER.has_save())


func test_an_arena_run_is_not_saved_on_close() -> void:
	var allowed: bool = SAVE_MANAGER.gate(true, false, true, true, true, true)
	assert_false(SAVE_MANAGER.write_close_snapshot(allowed, _snapshot()),
		"a run's real state lives in ArenaController, so a board-only snapshot is refused here too")
	assert_false(SAVE_MANAGER.has_save())


func test_a_replay_is_not_saved_on_close() -> void:
	var allowed: bool = SAVE_MANAGER.gate(true, false, false, true, true, true, true)
	assert_false(SAVE_MANAGER.write_close_snapshot(allowed, _snapshot()),
		"a spectated re-simulation is not the player's progress to save")
	assert_false(SAVE_MANAGER.has_save())


func test_a_solo_battle_in_progress_is_exactly_what_the_gate_allows() -> void:
	var allowed: bool = SAVE_MANAGER.gate(true, false, false, true, true, true)
	assert_true(SAVE_MANAGER.write_close_snapshot(allowed, _snapshot()),
		"the case the feature exists for: a live solo battle, saved because the window closed")
	assert_true(SAVE_MANAGER.has_save())


func test_a_challenge_attempt_is_a_legitimate_close_snapshot() -> void:
	# Deliberately NOT excluded: the end-of-day rule already governs a paused attempt, so
	# closing the window parks it until midnight UTC and then forfeits it, exactly as a
	# Save & Quit would have.
	var allowed: bool = SAVE_MANAGER.gate(true, false, false, true, true, true)
	assert_true(SAVE_MANAGER.write_close_snapshot(allowed, _snapshot(TODAY, BattleSnapshot.MODE_CHALLENGE)),
		"a challenge attempt is saveable on close; the EOD rule, not this gate, decides its fate")
	assert_false(SAVE_MANAGER.is_expired(SAVE_MANAGER.peek_save(), TODAY),
		"and on the same UTC day it is still resumable")


# --- The live node ----------------------------------------------------------

func test_a_manager_outside_a_battle_saves_nothing_on_close() -> void:
	var manager: Node = add_child_autofree(SAVE_MANAGER.new())
	if manager.can_save_now():
		# A previous suite left a live battle standing in the shared autoloads. The gate itself
		# is pinned exhaustively above; refusing to assert on a polluted world is honest
		# (tests/README.md rule 8) rather than passing on an accident.
		pending("a battle is somehow in progress in this run; the close gate is pinned above")
		return
	assert_false(manager.save_on_close(),
		"with no battle in progress, closing the window writes nothing -- and reports that as a value, never an error")
	assert_false(SAVE_MANAGER.has_save(), "the slot stays empty")


func test_the_close_notification_is_handled_without_blocking_the_quit() -> void:
	if get_tree().auto_accept_quit == false:
		# The handler finishes the quit itself in that configuration, which would take the test
		# runner down with it. The project ships auto_accept_quit at its default (true).
		pending("auto_accept_quit is off; driving the close notification would quit the runner")
		return
	var manager: Node = add_child_autofree(SAVE_MANAGER.new())
	if manager.can_save_now():
		pending("a battle is somehow in progress in this run; the close gate is pinned above")
		return
	manager._notification(NOTIFICATION_WM_CLOSE_REQUEST)
	assert_false(SAVE_MANAGER.has_save(),
		"no battle means no snapshot, and the handler returns straight away -- no dialog, no await")


func test_an_unrelated_notification_does_nothing() -> void:
	var manager: Node = add_child_autofree(SAVE_MANAGER.new())
	manager._notification(NOTIFICATION_PAUSED)
	assert_false(SAVE_MANAGER.has_save(),
		"only a close REQUEST triggers the close save -- every other notification falls through")


# --- Fixtures ---------------------------------------------------------------

## The smallest snapshot [method BattleSnapshot.is_supported] accepts, so this suite tests the
## close GATE rather than re-testing the capture (which tests/integration/
## test_battle_save_restore.gd covers against a real board).
func _snapshot(date: String = TODAY, mode: String = BattleSnapshot.MODE_SKIRMISH) -> Dictionary:
	return {
		"format_version": BattleSnapshot.FORMAT_VERSION,
		"saved_at_utc_date": date,
		"saved_at_utc": date + "T09:30:00",
		"context": {
			"mode": mode,
			"map_path": "res://game/maps/resources/default_skirmish.tres",
			"map_name": "Default Skirmish",
			"squad": [],
			"turn_system": 0,
			"player_count": 2,
			"difficulty": 1,
		},
		"units": [{
			"index": 0,
			"character_id": "placeholder",
			"player_id": 0,
			"cell": [0, 0],
			"hp": 10,
			"shield": 0,
		}],
		"turn": {},
		"board": {},
	}
