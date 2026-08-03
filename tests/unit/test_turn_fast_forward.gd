extends GutTest

## SKIP THE ENEMY TURN: the fast-forward latch ([TurnFastForward]) and the pacing it collapses.
##
## The rule being pinned is that this is a FAST-FORWARD, not a skip. Nothing here shortens the
## AI's decisions or removes an action -- every assertion is about a DELAY. The AI still issues
## each command through the ordinary path, so the battle log and the replay see the turn in full
## either way; all that changes is how long [BotTurnDriver] dwells on each beat.
##
## THE LATCH IS PROCESS-WIDE STATIC STATE, so it is reset from `before_each` AND `after_each`
## (tests/README.md rule 3): a failing assertion must not leave the next suite -- or the
## player's next battle in an editor run -- silently fast-forwarding.
##
## The refusals are tested through the PURE gate ([method TurnFastForward.allows]) rather than by
## standing up a real networked session or a replay, which is the same split
## [method BattleSaveManager.gate] uses for its own exclusions.

const FF := preload("res://game/ai/TurnFastForward.gd")
const DRIVER := preload("res://game/ai/BotTurnDriver.gd")

const EPSILON := 0.0001


## Minimal duck-typed stand-in for a [Player]: the latch only ever reads `is_ai`.
class StubPlayer extends RefCounted:
	var is_ai: bool = false

	func _init(ai: bool) -> void:
		is_ai = ai


func before_each() -> void:
	FF.reset()


func after_each() -> void:
	FF.reset()


# --- The latch ---------------------------------------------------------------

func test_fast_forward_starts_off() -> void:
	assert_false(FF.is_armed(), "a battle never opens already fast-forwarding")


func test_arming_reports_success_and_sets_the_latch() -> void:
	assert_true(FF.arm(), "a solo battle may fast-forward its enemy turn")
	assert_true(FF.is_armed(), "and the latch every reader consults is set")


func test_toggle_flips_the_latch_both_ways() -> void:
	assert_true(FF.toggle(), "the first press arms it")
	assert_true(FF.is_armed(), "which the readers can see")
	assert_false(FF.toggle(), "the second press stands it back down")
	assert_false(FF.is_armed(), "so the player can stop fast-forwarding mid-enemy-turn")


func test_arming_twice_stays_armed() -> void:
	FF.arm()
	FF.arm()
	assert_true(FF.is_armed(), "arm is idempotent -- a double press must not cancel itself")


# --- Who may arm: the pure gate ----------------------------------------------

func test_a_networked_match_may_never_fast_forward() -> void:
	assert_false(FF.allows(true, false),
		"both peers share one clock -- shortening your own AI pacing is a real-time advantage")


func test_a_replay_may_never_fast_forward() -> void:
	assert_false(FF.allows(false, true),
		"a replay already has its own transport speed control; two competing ones is a bug")


func test_an_ordinary_solo_battle_is_allowed() -> void:
	assert_true(FF.allows(false, false), "the case the feature exists for")


# --- Auto-disarm on the player's turn ----------------------------------------

func test_the_players_turn_starting_disarms_the_fast_forward() -> void:
	FF.arm()
	FF.note_turn_started(StubPlayer.new(false))
	assert_false(FF.is_armed(),
		"the player is never handed back a board that is still racing")


func test_a_further_ai_turn_leaves_it_armed() -> void:
	FF.arm()
	FF.note_turn_started(StubPlayer.new(true))
	assert_true(FF.is_armed(),
		"a second enemy player's turn is still an enemy turn -- one press covers the whole AI phase")


func test_a_null_player_changes_nothing() -> void:
	FF.arm()
	FF.note_turn_started(null)
	assert_true(FF.is_armed(), "a turn signal with no player is not evidence the player is up")


func test_is_ai_player_reads_the_flag_null_safely() -> void:
	assert_true(FF.is_ai_player(StubPlayer.new(true)), "an AI player is who the button is offered for")
	assert_false(FF.is_ai_player(StubPlayer.new(false)), "there is nothing to fast-forward on your own turn")
	assert_false(FF.is_ai_player(null), "and no turn system means no enemy turn")


# --- The pacing multiplier ---------------------------------------------------

func test_a_disarmed_delay_is_the_authored_one() -> void:
	assert_almost_eq(FF.scale_delay(1.3), 1.3, EPSILON,
		"ordinary play must be bit-for-bit the pacing the designer authored")


func test_arming_divides_the_delay_by_the_multiplier() -> void:
	FF.arm()
	assert_almost_eq(FF.scale_delay(1.2), 1.2 / FF.SPEED_MULTIPLIER, EPSILON,
		"a beat is DIVIDED, not zeroed -- every action still gets its own beat, just a short one")


func test_a_scaled_delay_never_drops_below_the_minimum_beat() -> void:
	FF.arm()
	assert_eq(FF.scale_delay(0.0001), FF.MIN_BEAT,
		"the driver's one-shot timer always gets a positive wait, so the beats stay ordered")


func test_the_multiplier_is_a_speed_up_not_a_slow_down() -> void:
	assert_gt(FF.SPEED_MULTIPLIER, 1.0,
		"dividing by anything <= 1 would make the skip button slower than not pressing it")


# --- The animation-quiet gate ------------------------------------------------

func test_the_animation_cap_is_untouched_while_disarmed() -> void:
	assert_almost_eq(FF.scale_anim_cap(3.0), 3.0, EPSILON,
		"ordinary play still waits the authored cap for the screen to go quiet")


func test_the_animation_cap_collapses_to_zero_while_armed() -> void:
	FF.arm()
	assert_eq(FF.scale_anim_cap(3.0), 0.0,
		"a zero cap makes the driver's gate proceed on its FIRST check -- the gate is collapsed, not removed")


# --- What the AI driver actually does with it --------------------------------

func test_the_drivers_attack_dwell_collapses_below_its_own_watchability_floor() -> void:
	# Off-tree on purpose: _ready would build and start a Timer, and every value under test is
	# computed from exported fields plus the latch, with no timer involved.
	var driver = autofree(DRIVER.new())
	var authored: float = driver._effective_dwell()
	assert_gte(authored, driver.min_attack_dwell,
		"unpressed, an enemy attack still dwells long enough to be watched")

	FF.arm()
	var fast: float = driver._effective_dwell()
	assert_lt(fast, driver.min_attack_dwell,
		"fast-forward is allowed to undercut the watchability floor -- the player asked not to watch")
	assert_gte(fast, FF.MIN_BEAT, "but never below the minimum beat")
	assert_lt(fast, authored, "and it is unambiguously faster than the authored dwell")


func test_the_drivers_move_dwell_and_interval_collapse_too() -> void:
	var driver = autofree(DRIVER.new())
	var authored_move: float = driver._effective_move_dwell()
	var authored_wait: float = driver._effective_wait()

	FF.arm()
	assert_lt(driver._effective_move_dwell(), authored_move,
		"a visible slide is fast-forwarded on the same latch as a strike")
	assert_lt(driver._effective_wait(), authored_wait,
		"and so is the inter-action interval, so nothing is left pacing at full speed")


func test_the_drivers_animation_gate_stops_deferring_while_armed() -> void:
	var driver = autofree(DRIVER.new())
	# The gate only defers while animations are BUSY; with nothing animating it already
	# proceeds, so what this pins is that arming can never make it defer MORE.
	assert_false(driver._defer_for_animations(),
		"a quiet screen never defers")
	FF.arm()
	assert_false(driver._defer_for_animations(),
		"and a fast-forwarded one never defers either -- its cap is zero, so it proceeds at once")
