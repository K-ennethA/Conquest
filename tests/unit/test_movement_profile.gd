extends GutTest

# Tests for the data-driven Movement Profiles system: reachability under the
# different shapes and movement kinds, terrain cost overrides, and the board
# interface contract. Uses a lightweight mock board so no scene tree / live grid
# is required. Cells are Vector2i(col, row), matching the combat module.
#
# WHAT THE PROFILE OWNS, AND WHAT IT DOES NOT. Every case above the "Budget" section
# passes NO mover, which is the profile-only path: with nobody to ask for a movement
# stat the resolver falls back to `profile.range`, so those cases read as written.
# For a real unit the budget is `get_stat("movement")` and the profile's range is not
# consulted at all -- pinned in the "Budget" section at the bottom, because that split
# is the whole reason one shared `ground_standard.tres` can serve a roster of eleven
# different strides.

# --- Mock board ------------------------------------------------------------

class MockBoard:
	var w: int
	var h: int
	var walls := {}     # Vector2i -> true (impassable terrain)
	var units := {}     # Vector2i -> true (occupied by a unit)
	var tile_ids := {}  # Vector2i -> StringName (for terrain_cost_overrides)

	func _init(p_w: int = 8, p_h: int = 8) -> void:
		w = p_w
		h = p_h

	func in_bounds(cell: Vector2i) -> bool:
		return cell.x >= 0 and cell.x < w and cell.y >= 0 and cell.y < h

	func move_cost(_cell: Vector2i) -> int:
		return 1

	func is_blocked(cell: Vector2i) -> bool:
		return walls.has(cell)

	func is_occupied(cell: Vector2i) -> bool:
		return units.has(cell)

	# Note: deliberately no tile_tag_at() — exercises graceful degradation.
	func tile_id_at(cell: Vector2i):
		return tile_ids.get(cell, null)

	func wall(cell: Vector2i) -> void:
		walls[cell] = true

	func occupy(cell: Vector2i) -> void:
		units[cell] = true


func _resolver() -> MovementResolver:
	return MovementResolver.new()


func _ground(shape, rng: int, overrides := {}) -> MovementProfile:
	return MovementProfile.create(
		&"test_ground", "Test Ground",
		CombatTypes.MovementKind.GROUND, rng, shape, overrides)


# --- Ground: walls and units block --------------------------------------

func test_ground_cannot_pass_wall():
	# A full vertical wall at x=1 separates the origin from everything to the right.
	var board := MockBoard.new(8, 8)
	for y in range(8):
		board.wall(Vector2i(1, y))
	var r := _resolver()
	var profile := _ground(MovementProfile.Shape.ORTHOGONAL, 4)
	var origin := Vector2i(0, 3)
	assert_true(r.can_reach(origin, Vector2i(0, 5), profile, board),
		"reaches an open cell on its own side")
	assert_false(r.can_reach(origin, Vector2i(1, 3), profile, board),
		"cannot end on the wall")
	assert_false(r.can_reach(origin, Vector2i(2, 3), profile, board),
		"cannot cross the wall to the far side")


func test_ground_blocked_by_occupied_cell():
	# Single-row corridor with a unit two steps away.
	var board := MockBoard.new(6, 1)
	board.occupy(Vector2i(2, 0))
	var r := _resolver()
	var profile := _ground(MovementProfile.Shape.ORTHOGONAL, 3)
	var origin := Vector2i(0, 0)
	assert_true(r.can_reach(origin, Vector2i(1, 0), profile, board),
		"reaches the cell before the occupied one")
	assert_false(r.can_reach(origin, Vector2i(2, 0), profile, board),
		"cannot end on the occupied cell")
	assert_false(r.can_reach(origin, Vector2i(3, 0), profile, board),
		"cannot path through the occupied cell")


# --- Flying: crosses walls -------------------------------------------------

func test_flying_reaches_across_a_wall():
	var board := MockBoard.new(6, 1)
	board.wall(Vector2i(2, 0))
	var r := _resolver()
	var origin := Vector2i(0, 0)
	var flier := MovementLibrary.flier()  # FLYING, ALL8, range 4

	assert_true(r.can_reach(origin, Vector2i(3, 0), flier, board),
		"flier crosses the wall to reach the far side")
	assert_true(r.can_reach(origin, Vector2i(4, 0), flier, board),
		"flier continues past the wall within its range")

	# A ground unit with the same shape/range is stopped by the same wall.
	var walker := _ground(MovementProfile.Shape.ALL8, 4)
	assert_false(r.can_reach(origin, Vector2i(3, 0), walker, board),
		"a ground unit cannot cross the wall")


# --- Teleport: ignores obstacles ------------------------------------------

func test_teleport_reaches_walled_off_cell():
	# (4,4) is fully boxed in by walls (all 8 neighbours); only a teleport can land there.
	var board := MockBoard.new(8, 8)
	for c in [
		Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3),
		Vector2i(3, 4), Vector2i(5, 4),
		Vector2i(3, 5), Vector2i(4, 5), Vector2i(5, 5),
	]:
		board.wall(c)
	var r := _resolver()
	var origin := Vector2i(1, 4)  # Manhattan distance 3 to (4,4)
	var blink := MovementLibrary.blink()  # TELEPORT, range 3

	assert_true(r.can_reach(origin, Vector2i(4, 4), blink, board),
		"teleport lands inside the walled-off cell")
	var walker := _ground(MovementProfile.Shape.ALL8, 3)
	assert_false(r.can_reach(origin, Vector2i(4, 4), walker, board),
		"a walker cannot reach the boxed-in cell")


func test_teleport_range_is_direct_distance():
	var board := MockBoard.new(12, 12)
	var r := _resolver()
	var origin := Vector2i(5, 5)
	var blink := MovementLibrary.blink()  # range 3, Manhattan
	assert_true(r.can_reach(origin, Vector2i(8, 5), blink, board),
		"distance 3 is within range")
	assert_false(r.can_reach(origin, Vector2i(9, 5), blink, board),
		"distance 4 is out of range")


# --- Knight: L-jumps over intervening cells --------------------------------

func test_knight_jumps_over_adjacent_wall():
	var board := MockBoard.new(8, 8)
	# Walls hug the origin; L-jumps clear them entirely.
	for c in [Vector2i(2, 3), Vector2i(3, 2), Vector2i(3, 3)]:
		board.wall(c)
	var r := _resolver()
	var origin := Vector2i(2, 2)
	var knight := MovementLibrary.ranger_knight()  # KNIGHT, range 2

	assert_true(r.can_reach(origin, Vector2i(3, 4), knight, board),
		"lands on an L-jump target despite adjacent walls")
	assert_true(r.can_reach(origin, Vector2i(4, 3), knight, board),
		"another L-jump target is reachable")
	assert_false(r.can_reach(origin, Vector2i(3, 2), knight, board),
		"orthogonal neighbour (a wall) is not a knight destination")
	assert_false(r.can_reach(origin, Vector2i(2, 3), knight, board),
		"cannot land on an adjacent wall")


# --- Terrain cost overrides ------------------------------------------------

func test_terrain_override_reduces_reach():
	var board := MockBoard.new(6, 1)
	board.tile_ids[Vector2i(2, 0)] = &"mud"
	var r := _resolver()
	var origin := Vector2i(0, 0)

	# Without overrides, (3,0) costs 3 and is reachable at range 3.
	var plain := _ground(MovementProfile.Shape.ORTHOGONAL, 3)
	assert_true(r.can_reach(origin, Vector2i(3, 0), plain, board),
		"open corridor: distance 3 reachable")

	# Mud costs 3 to enter, so stepping onto (2,0) alone already blows the budget.
	var muddy := _ground(MovementProfile.Shape.ORTHOGONAL, 3, { &"mud": 3 })
	assert_false(r.can_reach(origin, Vector2i(2, 0), muddy, board),
		"the expensive tile is itself out of reach")
	assert_false(r.can_reach(origin, Vector2i(3, 0), muddy, board),
		"the expensive tile cuts off cells beyond it")
	assert_true(r.can_reach(origin, Vector2i(1, 0), muddy, board),
		"cells before the expensive tile remain reachable")


# --- can_reach true/false + occupancy end rule -----------------------------

func test_can_reach_true_and_false():
	var board := MockBoard.new(8, 8)
	var r := _resolver()
	var origin := Vector2i(0, 0)
	var profile := MovementLibrary.infantry()  # ORTHOGONAL, range 3
	assert_true(r.can_reach(origin, origin, profile, board),
		"origin is trivially reachable")
	assert_true(r.can_reach(origin, Vector2i(3, 0), profile, board),
		"distance 3 within range")
	assert_false(r.can_reach(origin, Vector2i(4, 0), profile, board),
		"distance 4 beyond range")


func test_no_kind_ends_on_an_occupied_cell():
	var board := MockBoard.new(8, 8)
	board.occupy(Vector2i(2, 0))
	var r := _resolver()
	var origin := Vector2i(0, 0)
	var target := Vector2i(2, 0)
	var open := Vector2i(1, 0)

	for profile in [MovementLibrary.infantry(), MovementLibrary.flier(), MovementLibrary.blink()]:
		assert_false(r.can_reach(origin, target, profile, board),
			"%s cannot end on the occupied cell" % profile.id)
		assert_true(r.can_reach(origin, open, profile, board),
			"%s can still reach a nearby open cell" % profile.id)


# --- Budget: the MOVER's movement stat, not the profile's range -------------

## A mover that reports a movement stat, which is what the resolver budgets by.
class StatMover:
	var movement: int
	func _init(p_movement: int) -> void:
		movement = p_movement
	func get_stat(stat_name: String) -> int:
		return movement if stat_name == "movement" else 0


## A mover with NO stats at all -- a tool, a mock, a unit with no stat block. It is what
## the profile's `range` fallback exists for.
class StatlessMover extends RefCounted:
	var name: String = "statless"


## Farthest cell reachable straight down the open column from (0,0).
func _column_reach(profile: MovementProfile, unit) -> int:
	var cells := _resolver().reachable_cells(Vector2i(0, 0), profile, MockBoard.new(8, 8), unit)
	var farthest: int = 0
	for c in cells:
		if c.x == 0 and c.y > 0:
			farthest = maxi(farthest, c.y)
	return farthest


func test_the_flood_budget_is_the_movers_movement_stat():
	# ONE profile, three movers, three different strides -- which is exactly how a roster
	# shares a single ground profile without sharing a single reach.
	var shared := _ground(MovementProfile.Shape.ORTHOGONAL, 3)
	for stride in [1, 2, 5, 7]:
		assert_eq(_column_reach(shared, StatMover.new(stride)), stride,
			"a mover with movement %d reaches %d cells, whatever the profile says" % [stride, stride])
	assert_eq(shared.range, 3, "and the shared profile was never mutated to make that true")


func test_a_mover_with_no_stats_falls_back_to_the_profiles_range():
	# The fallback is what keeps profile-only callers -- editor tools, previews with no unit
	# attached, every mock board test above -- working exactly as they always did.
	var profile := _ground(MovementProfile.Shape.ORTHOGONAL, 4)
	assert_eq(_column_reach(profile, StatlessMover.new()), 4,
		"a mover that cannot report a movement stat is budgeted by the profile")
	assert_eq(_column_reach(profile, null), 4,
		"and so is a call that passes no mover at all")


func test_a_mover_debuffed_to_zero_movement_goes_nowhere():
	# The fallback must never rescue a legitimately rooted unit: 0 is a real budget, not a
	# missing one, so nothing clamps it back up to the profile's range.
	var profile := _ground(MovementProfile.Shape.ORTHOGONAL, 4)
	var cells := _resolver().reachable_cells(
		Vector2i(3, 3), profile, MockBoard.new(8, 8), StatMover.new(0))
	assert_true(cells.is_empty(),
		"a unit slowed to 0 movement reaches nothing -- it does not inherit the profile's 4")


func test_the_budget_governs_knight_jumps_and_teleport_distance_too():
	# Not just the stepping flood: the stat is the jump count for KNIGHT and the Manhattan
	# distance for TELEPORT, so no shape has a second source of truth.
	var board := MockBoard.new(12, 12)
	var origin := Vector2i(5, 5)
	var knight := MovementProfile.create(
		&"k", "K", CombatTypes.MovementKind.GROUND, 1, MovementProfile.Shape.KNIGHT)
	var one_jump := _resolver().reachable_cells(origin, knight, board, StatMover.new(1))
	var two_jumps := _resolver().reachable_cells(origin, knight, board, StatMover.new(2))
	assert_gt(two_jumps.size(), one_jump.size(),
		"a movement stat of 2 buys a second L-jump off a range-1 profile")

	var blink := MovementProfile.create(
		&"t", "T", CombatTypes.MovementKind.PHASING, 1, MovementProfile.Shape.TELEPORT)
	assert_true(_resolver().can_reach(origin, Vector2i(8, 5), blink, board, StatMover.new(3)),
		"and a stat of 3 blinks 3 cells off the same range-1 profile")
	assert_false(_resolver().can_reach(origin, Vector2i(9, 5), blink, board, StatMover.new(3)),
		"but no farther -- the stat is the cap")


func test_the_path_derivation_uses_the_same_budget_as_the_reachable_flood():
	# Traps read path_cells and reachability reads the flood; if the two budgets could
	# differ, a cell could be offered with no route (or routed to while unreachable).
	var board := MockBoard.new(8, 8)
	var profile := _ground(MovementProfile.Shape.ORTHOGONAL, 1)
	var mover := StatMover.new(4)
	var dest := Vector2i(0, 4)
	assert_true(_resolver().reachable_cells(Vector2i(0, 0), profile, board, mover).has(dest),
		"the flood offers a cell 4 out for a movement-4 unit")
	assert_eq(_resolver().path_cells(Vector2i(0, 0), dest, profile, board, mover).size(), 4,
		"and path_cells derives a 4-step route to it, off the same budget")


# --- Determinism -----------------------------------------------------------

func test_reachable_cells_are_sorted_and_exclude_origin():
	var board := MockBoard.new(8, 8)
	var r := _resolver()
	var origin := Vector2i(3, 3)
	var cells := r.reachable_cells(origin, MovementLibrary.infantry(), board)

	assert_false(cells.has(origin), "origin is never part of the result")
	var sorted := cells.duplicate()
	sorted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.x != b.x:
			return a.x < b.x
		return a.y < b.y)
	assert_eq(cells, sorted, "output is deterministically sorted")
