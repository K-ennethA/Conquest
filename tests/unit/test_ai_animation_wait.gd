extends GutTest

## The AI driver's animations-quiet precondition: BotTurnDriver must NOT start its
## next action while unit animations from the previous action are still playing --
## the reported bug where "the enemy starts moving before my turn is complete".
##
## The turn SYSTEMS advance instantly by design (logic/visuals are decoupled), so the
## fix is a wait on the VISUAL side: the driver polls UnitAnimator's static busy
## registry and defers. These tests drive the pure decision helper
## (_defer_for_animations) against that shared registry -- no Timer, no real
## animations -- asserting it: waits while busy, proceeds when clear, proceeds after
## the cap even if stuck, and skips the wait entirely when animations are off.

const ANIMATOR = preload("res://game/visuals/UnitAnimator.gd")
const Guard := preload("res://tests/helpers/global_state_guard.gd")

## UnitAnimator's busy registry is STATIC (process-wide), and GameSettings is an autoload.
## Both are cleaned in after_each so a failing assertion can never leave a stuck busy flag
## or an animations-off setting behind for the rest of the run.
## Untyped on purpose: a `: RefCounted` annotation would make the static analyser reject
## _guard.set_setting() / .watch_file() as "not found in base RefCounted".
var _guard


func before_each() -> void:
	_guard = Guard.new()
	ANIMATOR._clear_anim_registry()


func after_each() -> void:
	ANIMATOR._clear_anim_registry()
	_guard.restore()


func _make_driver() -> BotTurnDriver:
	var driver := BotTurnDriver.new()
	add_child_autofree(driver)
	# Stop the poll Timer: these tests call the decision helper directly.
	if driver._timer != null:
		driver._timer.stop()
	return driver


# --- defers while busy, proceeds once quiet -----------------------------------

func test_defers_while_animation_busy_then_proceeds_when_clear() -> void:
	var driver := _make_driver()
	# A long-lived entry keeps the registry busy for the whole (sub-millisecond) test.
	ANIMATOR._anim_begin(10.0)
	assert_true(driver._defer_for_animations(),
		"the driver must DEFER (wait) while an animation is still playing")

	# Screen goes quiet -> the very next check must proceed.
	ANIMATOR._clear_anim_registry()
	assert_false(driver._defer_for_animations(),
		"once animations are quiet the driver must PROCEED")


# --- the cap guarantees no deadlock -------------------------------------------

func test_proceeds_after_cap_even_if_still_busy() -> void:
	var driver := _make_driver()
	# Tight budget: two rechecks (0.15 + 0.15 = 0.30) reach the cap, so the 3rd check
	# proceeds ANYWAY even though the registry never clears -- a stuck busy flag can
	# never deadlock the AI.
	driver.anim_recheck = 0.15
	driver.anim_wait_cap = 0.3
	ANIMATOR._anim_begin(10.0)  # stays busy the whole test

	assert_true(driver._defer_for_animations(), "1st check: still under cap -> wait")
	assert_true(driver._defer_for_animations(), "2nd check: still under cap -> wait")
	assert_false(driver._defer_for_animations(),
		"3rd check: cap reached -> proceed anyway despite the animation still 'playing'")


# --- animations off skips the wait entirely -----------------------------------

func test_animations_off_skips_the_wait() -> void:
	var driver := _make_driver()
	ANIMATOR._anim_begin(10.0)  # busy registry...

	# Assign the FIELD, never GameSettings.set_animations_enabled() -- that setter writes
	# user://settings.cfg, so calling it here would edit the player's real settings.
	# The guard restores it from after_each, which runs even when an assertion below fails.
	_guard.set_setting("animations_enabled", false)

	# ...but with animations disabled there is nothing to watch, so no wait.
	assert_false(driver._animations_busy(),
		"animations off -> _animations_busy must be false regardless of the registry")
	assert_false(driver._defer_for_animations(),
		"animations off -> the driver must never defer")
