extends GutTest

## The pure touch-gesture state machine: pointer events in, game intents out.
##
## Every test drives the clock by hand -- GestureClassifier takes `now` as a parameter and
## never reads a wall clock -- so the 0.5s long-press is exercised synchronously. Nothing
## here touches the scene tree; the classifier is a RefCounted with no scene dependencies,
## which is the whole reason it was split out of TouchInputAdapter.

const SLOP := 16.0
const LONG_PRESS := 0.5

var g: GestureClassifier = null

# Signal sinks. Arrays (never ints) because a GDScript lambda captures locals BY VALUE --
# an int counter incremented inside a connected lambda never reaches the test body.
var taps: Array = []
var long_presses: Array = []
var pan_starts: Array = []
var pans: Array = []
var pan_ends: Array = []
var pinches: Array = []


func before_each() -> void:
	taps = []
	long_presses = []
	pan_starts = []
	pans = []
	pan_ends = []
	pinches = []

	g = GestureClassifier.new()
	g.slop_px = SLOP
	g.long_press_sec = LONG_PRESS
	g.tapped.connect(func(p: Vector2) -> void: taps.append(p))
	g.long_pressed.connect(func(p: Vector2) -> void: long_presses.append(p))
	g.pan_started.connect(func(p: Vector2) -> void: pan_starts.append(p))
	g.panned.connect(func(d: Vector2) -> void: pans.append(d))
	g.pan_ended.connect(func() -> void: pan_ends.append(true))
	g.pinched.connect(func(f: float, c: Vector2) -> void: pinches.append([f, c]))


func after_each() -> void:
	g = null


func _assert_v2(actual: Vector2, expected: Vector2, msg: String) -> void:
	assert_true(actual.is_equal_approx(expected),
		"%s (got %s, expected %s)" % [msg, actual, expected])


# --- Tap --------------------------------------------------------------------

func test_press_and_release_in_place_is_a_tap() -> void:
	g.touch_down(0, Vector2(100, 100), 0.0)
	g.touch_up(0, Vector2(100, 100), 0.1)

	assert_eq(taps.size(), 1, "a quick press-and-release is one tap")
	_assert_v2(taps[0], Vector2(100, 100), "the tap reports where the finger landed")
	assert_eq(pans.size(), 0, "a tap never pans the camera")
	assert_eq(long_presses.size(), 0, "a tap released early is not an inspect")


func test_tap_survives_jitter_inside_the_slop_radius() -> void:
	g.touch_down(0, Vector2(100, 100), 0.0)
	g.touch_move(0, Vector2(108, 100), 0.05)
	g.touch_up(0, Vector2(108, 100), 0.1)

	assert_eq(taps.size(), 1, "8px of finger wobble is still a tap, not a drag")
	_assert_v2(taps[0], Vector2(100, 100),
		"the tap targets where the finger LANDED, so wobble can't shift the selected cell")
	assert_eq(pan_starts.size(), 0, "movement inside the slop radius never starts a pan")


func test_state_returns_to_idle_after_a_tap() -> void:
	g.touch_down(0, Vector2(10, 10), 0.0)
	g.touch_up(0, Vector2(10, 10), 0.1)

	assert_eq(g.get_state(), GestureClassifier.State.IDLE,
		"lifting the last finger re-arms the classifier for the next gesture")


# --- Pan --------------------------------------------------------------------

func test_drag_past_slop_becomes_a_pan_and_not_a_tap() -> void:
	g.touch_down(0, Vector2(100, 100), 0.0)
	g.touch_move(0, Vector2(140, 100), 0.05)
	g.touch_up(0, Vector2(140, 100), 0.2)

	assert_eq(pan_starts.size(), 1, "crossing the slop threshold opens exactly one pan")
	_assert_v2(pan_starts[0], Vector2(100, 100), "the pan reports the finger's origin")
	assert_eq(pan_ends.size(), 1, "lifting the finger closes the pan")
	assert_eq(taps.size(), 0, "a drag must never also select the cell it started on")


func test_pan_deltas_are_screen_space_steps() -> void:
	g.touch_down(0, Vector2(100, 100), 0.0)
	g.touch_move(0, Vector2(140, 100), 0.05)
	g.touch_move(0, Vector2(160, 110), 0.10)

	assert_eq(pans.size(), 2, "each drag event past the threshold emits one pan step")
	_assert_v2(pans[0], Vector2(40, 0),
		"the opening step carries the whole distance travelled, slop included")
	_assert_v2(pans[1], Vector2(20, 10), "later steps carry the delta since the last event")


func test_pan_does_not_start_before_the_slop_threshold() -> void:
	g.touch_down(0, Vector2(0, 0), 0.0)
	g.touch_move(0, Vector2(SLOP, 0), 0.05)

	assert_eq(pan_starts.size(), 0, "movement of exactly the slop distance is still a tap")
	assert_eq(g.get_state(), GestureClassifier.State.PENDING,
		"the gesture stays undecided until the threshold is actually exceeded")


# --- Long press -------------------------------------------------------------

func test_holding_still_past_the_threshold_is_a_long_press() -> void:
	g.touch_down(0, Vector2(50, 60), 0.0)
	g.tick(0.3)
	assert_eq(long_presses.size(), 0, "the inspect must not fire before 0.5s")

	g.tick(LONG_PRESS)
	assert_eq(long_presses.size(), 1, "holding to 0.5s fires the inspect")
	_assert_v2(long_presses[0], Vector2(50, 60), "inspect targets the held cell")


func test_long_press_fires_exactly_once_however_long_the_hold() -> void:
	g.touch_down(0, Vector2(50, 60), 0.0)
	g.tick(LONG_PRESS)
	g.tick(0.9)
	g.tick(3.0)

	assert_eq(long_presses.size(), 1, "a continued hold never re-fires the inspect")


func test_long_press_does_not_also_tap_on_release() -> void:
	g.touch_down(0, Vector2(50, 60), 0.0)
	g.tick(LONG_PRESS)
	g.touch_up(0, Vector2(50, 60), 0.8)

	assert_eq(taps.size(), 0, "one touch produces one intent -- inspect, not inspect+select")


func test_long_hold_released_without_ticks_is_still_an_inspect() -> void:
	# Covers a caller that never drives tick(): the release itself must classify by
	# elapsed time, so a hold can never silently degrade into a selection.
	g.touch_down(0, Vector2(50, 60), 0.0)
	g.touch_up(0, Vector2(50, 60), 0.7)

	assert_eq(long_presses.size(), 1, "a 0.7s hold is an inspect even with no tick() calls")
	assert_eq(taps.size(), 0, "and it is not also a tap")


func test_dragging_away_cancels_the_pending_long_press() -> void:
	g.touch_down(0, Vector2(0, 0), 0.0)
	g.touch_move(0, Vector2(100, 0), 0.1)
	g.tick(1.0)

	assert_eq(long_presses.size(), 0, "a finger that has left the slop radius is panning")
	assert_eq(pan_starts.size(), 1, "and is still panning after the long-press deadline")


# --- Pinch ------------------------------------------------------------------

func test_two_fingers_spreading_emit_a_zoom_ratio() -> void:
	g.touch_down(0, Vector2(100, 100), 0.0)
	g.touch_down(1, Vector2(200, 100), 0.0)
	g.touch_move(1, Vector2(300, 100), 0.1)

	assert_eq(pinches.size(), 1, "spreading two fingers emits one pinch")
	assert_almost_eq(float(pinches[0][0]), 2.0, 0.001,
		"doubling the finger distance is a factor of 2")
	_assert_v2(pinches[0][1], Vector2(200, 100), "the pinch anchors on the finger midpoint")


func test_pinching_in_emits_a_ratio_below_one() -> void:
	g.touch_down(0, Vector2(0, 0), 0.0)
	g.touch_down(1, Vector2(200, 0), 0.0)
	g.touch_move(1, Vector2(100, 0), 0.1)

	assert_eq(pinches.size(), 1, "closing two fingers emits one pinch")
	assert_almost_eq(float(pinches[0][0]), 0.5, 0.001,
		"halving the finger distance is a factor of 0.5")


func test_fingers_too_close_together_are_not_a_pinch() -> void:
	g.touch_down(0, Vector2(0, 0), 0.0)
	g.touch_down(1, Vector2(2, 0), 0.0)
	g.touch_move(1, Vector2(4, 0), 0.1)

	assert_eq(pinches.size(), 0,
		"a near-zero finger distance is noise, not a 2x zoom -- the guard rejects it")


func test_second_finger_ends_a_live_pan() -> void:
	g.touch_down(0, Vector2(0, 0), 0.0)
	g.touch_move(0, Vector2(100, 0), 0.05)
	assert_eq(pan_ends.size(), 0, "sanity: the pan is still open before the second finger")

	g.touch_down(1, Vector2(200, 0), 0.1)

	assert_eq(pan_ends.size(), 1, "the second finger closes the pan cleanly")
	assert_eq(g.get_state(), GestureClassifier.State.PINCH,
		"and the gesture becomes a pinch")


func test_lifting_one_pinch_finger_does_not_resume_panning() -> void:
	g.touch_down(0, Vector2(0, 0), 0.0)
	g.touch_down(1, Vector2(200, 0), 0.0)
	g.touch_up(1, Vector2(200, 0), 0.2)
	pans.clear()
	g.touch_move(0, Vector2(300, 0), 0.3)

	assert_eq(pans.size(), 0,
		"the remaining finger must not jerk the camera into a pan mid-pinch-release")
	assert_eq(taps.size(), 0, "and lifting out of a pinch never selects anything")


func test_all_fingers_up_after_a_pinch_re_arms_the_classifier() -> void:
	g.touch_down(0, Vector2(0, 0), 0.0)
	g.touch_down(1, Vector2(200, 0), 0.0)
	g.touch_up(0, Vector2(0, 0), 0.2)
	g.touch_up(1, Vector2(200, 0), 0.25)

	assert_eq(g.get_state(), GestureClassifier.State.IDLE,
		"a finished pinch leaves the classifier ready for the next gesture")


func test_three_fingers_produce_no_intent() -> void:
	g.touch_down(0, Vector2(0, 0), 0.0)
	g.touch_down(1, Vector2(100, 0), 0.0)
	g.touch_down(2, Vector2(200, 0), 0.0)
	g.touch_move(2, Vector2(300, 0), 0.1)
	g.touch_up(2, Vector2(300, 0), 0.2)

	assert_eq(pinches.size(), 0, "three fingers are not a pinch")
	assert_eq(taps.size(), 0, "and never resolve into a selection")
	assert_eq(pans.size(), 0, "and never pan")


# --- Trackpad magnify + teardown -------------------------------------------

func test_magnify_passes_through_as_a_zoom() -> void:
	g.magnify(1.2, Vector2(64, 64))

	assert_eq(pinches.size(), 1, "an OS-level trackpad pinch is forwarded as a zoom")
	assert_almost_eq(float(pinches[0][0]), 1.2, 0.001, "carrying the platform's factor")
	_assert_v2(pinches[0][1], Vector2(64, 64), "and the platform's anchor point")


func test_magnify_rejects_a_non_positive_factor() -> void:
	g.magnify(0.0, Vector2.ZERO)
	g.magnify(-2.0, Vector2.ZERO)

	assert_eq(pinches.size(), 0, "a zero or negative factor would invert the camera")


func test_reset_mid_pan_closes_the_pan_and_clears_state() -> void:
	g.touch_down(0, Vector2(0, 0), 0.0)
	g.touch_move(0, Vector2(100, 0), 0.05)
	g.reset()

	assert_eq(pan_ends.size(), 1,
		"losing focus mid-drag must tell the camera the finger is gone")
	assert_eq(g.get_state(), GestureClassifier.State.IDLE, "and fully re-arm")


func test_events_for_an_untracked_finger_are_ignored() -> void:
	g.touch_move(7, Vector2(10, 10), 0.0)
	g.touch_up(7, Vector2(10, 10), 0.1)

	assert_eq(taps.size(), 0, "a stray release with no matching press selects nothing")
	assert_eq(pans.size(), 0, "and pans nothing")
	assert_eq(g.get_state(), GestureClassifier.State.IDLE, "and leaves the state clean")
