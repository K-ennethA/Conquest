extends GutTest

## Command state machine (UnitActionsPanel.CommandState).
##
## The panel itself is heavily scene-coupled (@onready HUD nodes + autoloads), so the
## transition logic is extracted into pure, side-effect-free static helpers
## (forward_state / cancel_target_state) that CAN be exercised headless. These tests pin
## the golden Fire-Emblem progression and its one-step-per-press back-out, which is the
## contract the cursor's cancel routing and the panel's _on_cancel_pressed both rely on.
##
## The enum values are read through the class (UnitActionsPanel.CommandState.X) so the
## compiler resolves them as enum members rather than runtime dictionary access.

# Local int copies of the enum members (resolved at compile time through the class).
var IDLE: int = UnitActionsPanel.CommandState.IDLE
var UNIT_SELECTED: int = UnitActionsPanel.CommandState.UNIT_SELECTED
var ACTION_MENU: int = UnitActionsPanel.CommandState.ACTION_MENU
var TARGETING: int = UnitActionsPanel.CommandState.TARGETING


func test_forward_walks_the_golden_path():
	assert_eq(UnitActionsPanel.forward_state(IDLE), UNIT_SELECTED,
		"selecting a commandable unit enters UNIT_SELECTED")
	assert_eq(UnitActionsPanel.forward_state(UNIT_SELECTED), ACTION_MENU,
		"landing a (tentative) move / act-in-place opens the action menu")
	assert_eq(UnitActionsPanel.forward_state(ACTION_MENU), TARGETING,
		"choosing a move from the menu enters targeting")


func test_targeting_is_the_last_forward_state():
	assert_eq(UnitActionsPanel.forward_state(TARGETING), TARGETING,
		"there is nothing past TARGETING on the forward path")


func test_cancel_backs_out_one_step_per_press():
	assert_eq(UnitActionsPanel.cancel_target_state(TARGETING), ACTION_MENU,
		"first cancel while aiming returns to the action menu, NOT a full deselect")
	assert_eq(UnitActionsPanel.cancel_target_state(ACTION_MENU), UNIT_SELECTED,
		"cancel on the action menu reverts the tentative move back to the selected unit")
	assert_eq(UnitActionsPanel.cancel_target_state(UNIT_SELECTED), IDLE,
		"cancel on a plain selection deselects to IDLE")
	assert_eq(UnitActionsPanel.cancel_target_state(IDLE), IDLE,
		"cancel from IDLE stays IDLE")


func test_forward_then_cancel_are_inverses_each_step():
	# Walking one step forward and immediately cancelling must land back where we started
	# -- this is what makes right-click feel like a clean undo at every level.
	for state in [IDLE, UNIT_SELECTED, ACTION_MENU]:
		var advanced: int = UnitActionsPanel.forward_state(state)
		assert_eq(UnitActionsPanel.cancel_target_state(advanced), state,
			"forward then cancel should return to state %d" % state)


func test_full_golden_path_round_trip():
	# IDLE -> UNIT_SELECTED -> ACTION_MENU -> TARGETING, then all the way back down.
	var s: int = IDLE
	var forward_trail: Array = [s]
	for _i in range(3):
		s = UnitActionsPanel.forward_state(s)
		forward_trail.append(s)
	assert_eq(forward_trail, [IDLE, UNIT_SELECTED, ACTION_MENU, TARGETING],
		"the golden path visits each state in order")

	for _i in range(3):
		s = UnitActionsPanel.cancel_target_state(s)
	assert_eq(s, IDLE, "three cancels from TARGETING unwind all the way to IDLE")
