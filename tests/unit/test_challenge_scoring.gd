extends GutTest

## Unit tests for [ChallengeScoring] -- the pure points formula behind a challenge run.
##
## The formula is the ONE thing the controller, the browse screen and any future leaderboard
## all read, so every branch of it is pinned here: the on-par baseline, the under-par bonus
## (and its cap), the over-par penalty, the per-unit-lost penalty, the win floor, and the
## flat zero a loss scores. Pure integer maths -- no engine state, no I/O, no autoloads.


# --- Baseline ---------------------------------------------------------------

func test_exact_par_clean_clear_scores_base() -> void:
	assert_eq(ChallengeScoring.score(true, 8, 8, 0), ChallengeScoring.WIN_BASE,
		"an on-par clear with no losses is exactly the base score")


# --- Under par --------------------------------------------------------------

func test_under_par_pays_a_bonus_per_turn() -> void:
	# 2 turns under par -> +50 * 2 on top of the base.
	assert_eq(ChallengeScoring.score(true, 6, 8, 0),
		ChallengeScoring.WIN_BASE + 2 * ChallengeScoring.UNDER_PAR_BONUS)


func test_under_par_bonus_is_capped() -> void:
	# 10 turns under par would pay +500, but the bonus ceiling holds it to +200.
	var far_under: int = ChallengeScoring.score(true, 2, 12, 0)
	assert_eq(far_under, ChallengeScoring.WIN_BASE + ChallengeScoring.UNDER_PAR_BONUS_CAP,
		"the under-par bonus must not exceed its cap")
	# And going even further under pays no more.
	assert_eq(ChallengeScoring.score(true, 1, 20, 0), far_under,
		"once capped, extra turns under par add nothing")


# --- Over par ---------------------------------------------------------------

func test_over_par_costs_per_turn() -> void:
	# 4 turns over par -> -75 * 4.
	assert_eq(ChallengeScoring.score(true, 12, 8, 0),
		ChallengeScoring.WIN_BASE - 4 * ChallengeScoring.OVER_PAR_PENALTY)


# --- Units lost -------------------------------------------------------------

func test_each_unit_lost_costs_points() -> void:
	assert_eq(ChallengeScoring.score(true, 8, 8, 2),
		ChallengeScoring.WIN_BASE - 2 * ChallengeScoring.UNIT_LOSS_PENALTY)


func test_negative_units_lost_never_pays_a_bonus() -> void:
	# Defensive: a miscounted negative tally must not be turned into free points.
	assert_eq(ChallengeScoring.score(true, 8, 8, -3), ChallengeScoring.WIN_BASE)


# --- Floor ------------------------------------------------------------------

func test_a_disastrous_win_still_floors() -> void:
	# 27 turns over par (-2025) and 3 units lost (-300) would go deeply negative.
	var raw: int = ChallengeScoring.WIN_BASE \
		- 27 * ChallengeScoring.OVER_PAR_PENALTY \
		- 3 * ChallengeScoring.UNIT_LOSS_PENALTY
	assert_lt(raw, ChallengeScoring.WIN_FLOOR, "this case must actually be below the floor")
	assert_eq(ChallengeScoring.score(true, 30, 3, 3), ChallengeScoring.WIN_FLOOR,
		"a win never scores below the floor")


# --- Loss -------------------------------------------------------------------

func test_a_loss_scores_zero_however_good_the_run_was() -> void:
	assert_eq(ChallengeScoring.score(false, 1, 20, 0), 0,
		"a fast, clean LOSS is still zero -- only wins score")
	assert_eq(ChallengeScoring.score(false, 8, 8, 4), 0)


# --- Perfect flag -----------------------------------------------------------

func test_perfect_requires_a_win_with_no_losses() -> void:
	assert_true(ChallengeScoring.is_perfect(true, 0), "a win with zero losses is perfect")
	assert_false(ChallengeScoring.is_perfect(true, 1), "losing a unit is not perfect")
	assert_false(ChallengeScoring.is_perfect(false, 0), "a loss is never perfect")


# --- Bundle -----------------------------------------------------------------

func test_evaluate_bundles_score_and_perfect() -> void:
	var clean: Dictionary = ChallengeScoring.evaluate(true, 6, 8, 0)
	assert_eq(int(clean.get("score", -1)), ChallengeScoring.score(true, 6, 8, 0))
	assert_true(bool(clean.get("perfect", false)))

	var costly: Dictionary = ChallengeScoring.evaluate(true, 6, 8, 1)
	assert_eq(int(costly.get("score", -1)), ChallengeScoring.score(true, 6, 8, 1))
	assert_false(bool(costly.get("perfect", true)))

	var lost: Dictionary = ChallengeScoring.evaluate(false, 6, 8, 0)
	assert_eq(int(lost.get("score", -1)), 0)
	assert_false(bool(lost.get("perfect", true)))
