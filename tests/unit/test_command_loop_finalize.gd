extends GutTest

## The command loop's TWO finalize contracts, at the headless data layer the panel's
## golden path is built on:
##
##  1. WAIT finalizes. After a tentative move is committed (mark_moved) the panel calls
##     mark_action_completed("wait"). That must latch the unit as having acted AND emit
##     unit_action_completed exactly once -- the signal the turn systems key off to grey
##     the unit and auto-end the player turn WITHOUT a separate End Turn press (the whole
##     point of the rework).
##
##  2. CANCEL keeps the unit fully available. Backing out of the action menu reverts the
##     tentative move: nothing is committed, so the unit must stay movable AND actable,
##     and the board revert must land it back on its origin cell.
##
## The panel itself is scene-coupled; these assert the underlying Unit + BoardAdapter
## contracts the panel drives, which is where a regression would actually bite.


func _make_stats() -> UnitStatsResource:
	var res := UnitStatsResource.new()
	res.unit_name = "Grunt"
	res.unit_type = "warrior"
	res.max_health = 30
	res.base_attack = 10
	res.base_defense = 0
	res.base_speed = 5
	res.movement_range = 3
	res.attack_range = 1
	return res


func _spawn_unit() -> Unit:
	var unit := Unit.new()
	unit.stats_resource = _make_stats()
	add_child_autofree(unit)  # _ready() wires the UnitStats component
	return unit


# --- 1. WAIT finalizes ------------------------------------------------------

func test_wait_after_committed_move_marks_acted_and_signals_once():
	var unit := _spawn_unit()
	watch_signals(unit)

	# Panel path: _commit_tentative_move() -> mark_moved(), then Wait -> mark_action_completed.
	unit.mark_moved()
	assert_false(unit.can_move(), "a committed move consumes the unit's move for the turn")
	assert_true(unit.can_act(), "but the unit still has its ACTION until Wait finalizes it")

	unit.mark_action_completed("wait")

	assert_true(unit.has_acted_this_turn, "Wait must latch the unit as having acted")
	assert_false(unit.can_act(), "a unit that Waited can no longer act")
	assert_signal_emit_count(unit, "unit_action_completed", 1,
		"Wait must emit unit_action_completed exactly once (the turn systems' hook)")


func test_wait_in_place_without_moving_still_finalizes():
	# Act-in-place: the player clicked the unit's own tile, so no move was committed.
	var unit := _spawn_unit()
	watch_signals(unit)
	assert_true(unit.can_move(), "no move was staged, so the unit could still have moved")

	unit.mark_action_completed("wait")

	assert_true(unit.has_acted_this_turn, "Wait-in-place still ends the unit's turn")
	assert_signal_emit_count(unit, "unit_action_completed", 1,
		"one finalize -> one unit_action_completed")


# --- 2. CANCEL keeps the unit fully available -------------------------------

func test_cancelled_tentative_move_leaves_unit_fully_available():
	# A cancelled tentative move NEVER commits: the panel's _revert_tentative_move calls
	# neither mark_moved nor mark_action_completed. The unit must be untouched.
	var unit := _spawn_unit()

	assert_true(unit.can_move(), "after cancelling a tentative move the unit can still move")
	assert_true(unit.can_act(), "and it still has its action")
	assert_false(unit.has_acted_this_turn, "nothing was consumed by a cancelled move")


func test_revert_lands_the_unit_back_on_its_origin_cell():
	# Mirror _revert_tentative_move at the board layer: move to a destination (the
	# tentative preview), then move back to the origin cell (the revert). cell_of must
	# report the origin again so a re-shown movement range is computed from the right spot.
	var grid := Grid.new()
	var origin := Vector2i(1, 1)
	var dest := Vector2i(3, 2)

	var unit := MockBoardUnit.new()
	var adapter := BoardAdapter.new(grid, [unit])
	unit.position = adapter.cell_to_world(origin)
	assert_eq(adapter.cell_of(unit), origin, "unit starts on its origin cell")

	adapter.move_unit(unit, dest)  # tentative preview
	assert_eq(adapter.cell_of(unit), dest, "tentative move relocates the unit to the destination")

	adapter.move_unit(unit, origin)  # revert
	assert_eq(adapter.cell_of(unit), origin,
		"reverting a cancelled tentative move restores the origin cell")


# Duck-typed board unit (position + owner_player), matching BoardAdapter's expectations
# without pulling in the full Unit/scene setup -- same pattern as test_board_adapter.gd.
class MockBoardUnit extends RefCounted:
	var position: Vector3 = Vector3.ZERO
	var owner_player = null
	var hp = null  # null == alive per BoardAdapter's duck-typed liveness check
