extends GutTest

# The pause menu's CONTEXT MATRIX.
#
# What this pins: which rows the in-battle pause menu offers, and which of them are
# destructive enough to need a confirm. The rules that matter are the ones about how you
# are allowed to LEAVE a battle:
#
#   * A live NETWORKED match has no save and no quiet "quit to menu" -- walking out is a
#     loss, so FORFEIT (confirmed) is the only exit.
#   * An ARENA run has no save either; the run is ABANDONED (confirmed).
#   * A SOLO battle (skirmish / campaign / challenge) gets SAVE & QUIT plus a no-save
#     QUIT TO MENU fallback, so a missing save contract can never trap the player.
#
# PauseMenu.rows_for_context() is a pure static function precisely so all of that is
# testable with no scene tree, no autoloads and no save manager -- the flags are handed in.

const Row := PauseMenu.Row


# --- helpers -----------------------------------------------------------------

func _ids(rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		out.append(int((r as Dictionary).get("id", -1)))
	return out

## The row dictionary for [param id], or an empty Dictionary when it is not offered.
func _row(rows: Array, id: int) -> Dictionary:
	for r in rows:
		if int((r as Dictionary).get("id", -1)) == id:
			return r
	return {}

func _solo_ctx(save_contract: bool = true, can_save_now: bool = true, challenge: bool = false) -> Dictionary:
	return {
		"networked": false,
		"arena": false,
		"challenge": challenge,
		"save_contract": save_contract,
		"can_save_now": can_save_now,
	}


# --- Solo -------------------------------------------------------------------

func test_solo_battle_offers_save_and_a_no_save_fallback():
	var rows: Array = PauseMenu.rows_for_context(_solo_ctx())
	assert_eq(_ids(rows), [Row.RESUME, Row.SETTINGS, Row.SAVE_AND_QUIT, Row.QUIT_TO_MENU, Row.QUIT_GAME],
		"a solo battle offers resume, settings, save & quit, the no-save quit, and quit game -- in that order")
	assert_true(bool(_row(rows, Row.SAVE_AND_QUIT).get("enabled", false)),
		"with a save contract that says it can save now, SAVE & QUIT is enabled")
	assert_eq(String(_row(rows, Row.SAVE_AND_QUIT).get("confirm", "x")), "",
		"saving is not destructive, so it never asks for a confirm")

func test_missing_save_contract_disables_the_row_but_leaves_a_way_out():
	var rows: Array = PauseMenu.rows_for_context(_solo_ctx(false, false))
	var save_row: Dictionary = _row(rows, Row.SAVE_AND_QUIT)
	assert_false(save_row.is_empty(), "the save row is still SHOWN when no save manager exists")
	assert_false(bool(save_row.get("enabled", true)), "but it is disabled -- there is nothing to call")
	assert_eq(String(save_row.get("tooltip", "")), PauseMenu.TOOLTIP_NO_SAVE,
		"and it says why, rather than failing silently on press")
	assert_true(bool(_row(rows, Row.QUIT_TO_MENU).get("enabled", false)),
		"the no-save QUIT TO MENU still works, so a missing contract never traps the player")

func test_save_contract_that_refuses_right_now_is_disabled_with_its_own_reason():
	var rows: Array = PauseMenu.rows_for_context(_solo_ctx(true, false))
	var save_row: Dictionary = _row(rows, Row.SAVE_AND_QUIT)
	assert_false(bool(save_row.get("enabled", true)),
		"a contract that answers can_save_now() == false disables the row")
	assert_eq(String(save_row.get("tooltip", "")), PauseMenu.TOOLTIP_CANNOT_SAVE_NOW,
		"'not right now' is a different reason from 'not at all', and reads differently")

func test_quitting_without_saving_asks_first():
	var rows: Array = PauseMenu.rows_for_context(_solo_ctx())
	assert_eq(String(_row(rows, Row.QUIT_TO_MENU).get("confirm", "")), PauseMenu.CONFIRM_UNSAVED,
		"leaving a solo battle without saving warns that progress is lost")


# --- Challenge ---------------------------------------------------------------

func test_challenge_battle_carries_the_end_of_day_caption():
	var rows: Array = PauseMenu.rows_for_context(_solo_ctx(true, true, true))
	assert_eq(String(_row(rows, Row.SAVE_AND_QUIT).get("caption", "")), PauseMenu.CHALLENGE_EOD_CAPTION,
		"a paused challenge is still on the clock, so the save row says so before you walk away")

func test_challenge_caption_survives_a_disabled_save_row():
	var rows: Array = PauseMenu.rows_for_context(_solo_ctx(false, false, true))
	assert_eq(String(_row(rows, Row.SAVE_AND_QUIT).get("caption", "")), PauseMenu.CHALLENGE_EOD_CAPTION,
		"the end-of-day rule applies whether or not saving is available")

func test_a_plain_skirmish_has_no_caption():
	var rows: Array = PauseMenu.rows_for_context(_solo_ctx())
	assert_eq(String(_row(rows, Row.SAVE_AND_QUIT).get("caption", "")), "",
		"the challenge deadline caption is challenge-only")


# --- Networked ---------------------------------------------------------------

func test_a_live_match_can_only_be_left_by_forfeiting():
	var ctx: Dictionary = _solo_ctx()
	ctx["networked"] = true
	var rows: Array = PauseMenu.rows_for_context(ctx)
	assert_eq(_ids(rows), [Row.RESUME, Row.SETTINGS, Row.FORFEIT_MATCH, Row.QUIT_GAME],
		"a networked match offers forfeit as the only way out of the battle")
	assert_true(_row(rows, Row.SAVE_AND_QUIT).is_empty(),
		"a live match is never saveable -- the opponent is still playing it")
	assert_true(_row(rows, Row.QUIT_TO_MENU).is_empty(),
		"and there is no quiet quit-to-menu: leaving a live match IS a loss")

func test_forfeit_says_it_loses_the_match_before_it_happens():
	var ctx: Dictionary = _solo_ctx()
	ctx["networked"] = true
	assert_eq(String(_row(PauseMenu.rows_for_context(ctx), Row.FORFEIT_MATCH).get("confirm", "")),
		PauseMenu.CONFIRM_FORFEIT, "forfeiting is confirmed, and the confirm names the consequence")


# --- Arena -------------------------------------------------------------------

func test_an_arena_run_is_abandoned_not_saved():
	var ctx: Dictionary = _solo_ctx()
	ctx["arena"] = true
	var rows: Array = PauseMenu.rows_for_context(ctx)
	assert_eq(_ids(rows), [Row.RESUME, Row.SETTINGS, Row.ABANDON_RUN, Row.QUIT_GAME],
		"an arena run offers abandon instead of a save")
	assert_true(_row(rows, Row.SAVE_AND_QUIT).is_empty(),
		"arena runs are not saveable even when a save contract exists")
	assert_eq(String(_row(rows, Row.ABANDON_RUN).get("confirm", "")), PauseMenu.CONFIRM_ABANDON,
		"abandoning a run is confirmed -- it throws away every round already won")

func test_a_networked_arena_match_forfeits_rather_than_abandons():
	# Both flags true (arena PvP): the networked rule wins, because the opponent's match
	# has to be settled and a local run abort would leave them hanging.
	var ctx: Dictionary = _solo_ctx()
	ctx["arena"] = true
	ctx["networked"] = true
	var rows: Array = PauseMenu.rows_for_context(ctx)
	assert_false(_row(rows, Row.FORFEIT_MATCH).is_empty(), "networked takes precedence: forfeit is offered")
	assert_true(_row(rows, Row.ABANDON_RUN).is_empty(), "and the local run-abort row is not")


# --- Rows that are always there ----------------------------------------------

func test_resume_and_settings_are_always_first_and_never_confirmed():
	for ctx in [_solo_ctx(), {"networked": true}, {"arena": true}, {}]:
		var rows: Array = PauseMenu.rows_for_context(ctx)
		assert_eq(int((rows[0] as Dictionary).get("id", -1)), Row.RESUME,
			"RESUME is always the first row, in every context")
		assert_eq(int((rows[1] as Dictionary).get("id", -1)), Row.SETTINGS,
			"SETTINGS is always the second row, in every context")
		assert_eq(String((rows[0] as Dictionary).get("confirm", "x")), "",
			"resuming is not destructive and never asks")
		assert_eq(String((rows[1] as Dictionary).get("confirm", "x")), "",
			"opening settings is not destructive and never asks")

func test_quit_game_is_always_last_and_always_confirmed():
	for ctx in [_solo_ctx(), {"networked": true}, {"arena": true}, {}]:
		var rows: Array = PauseMenu.rows_for_context(ctx)
		var last: Dictionary = rows[rows.size() - 1]
		assert_eq(int(last.get("id", -1)), Row.QUIT_GAME, "QUIT GAME is always the last row")
		assert_eq(String(last.get("confirm", "")), PauseMenu.CONFIRM_QUIT_GAME,
			"closing the whole game always asks first")

func test_an_empty_context_reads_as_a_solo_battle_with_no_save_manager():
	# The fail-safe default: nothing known -> treat it as solo, show the save row disabled,
	# and keep the no-save exit. Never a state where the player cannot leave.
	var rows: Array = PauseMenu.rows_for_context({})
	assert_eq(_ids(rows), [Row.RESUME, Row.SETTINGS, Row.SAVE_AND_QUIT, Row.QUIT_TO_MENU, Row.QUIT_GAME],
		"an unknown context falls back to the solo row set")
	assert_false(bool(_row(rows, Row.SAVE_AND_QUIT).get("enabled", true)),
		"with no save contract asserted, the save row is disabled rather than optimistically live")

func test_every_row_carries_the_full_shape():
	# The builder consumes these keys unconditionally; a row missing one would crash the
	# menu at open time rather than in a test.
	for ctx in [_solo_ctx(), _solo_ctx(false, false, true), {"networked": true}, {"arena": true}]:
		for r in PauseMenu.rows_for_context(ctx):
			var row: Dictionary = r
			for key in ["id", "label", "enabled", "tooltip", "confirm", "caption"]:
				assert_true(row.has(key), "row %s carries the '%s' key the menu builder reads"
					% [String(row.get("label", "?")), key])
			assert_ne(String(row.get("label", "")), "", "every row has a visible label")
