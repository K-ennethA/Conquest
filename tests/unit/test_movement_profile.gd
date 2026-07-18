extends GutTest

# Tests for the data-driven Movement Profiles system: reachability under the
# different shapes and movement kinds, terrain cost overrides, and the board
# interface contract. Uses a lightweight mock board so no scene tree / live grid
# is required. Cells are Vector2i(col, row), matching the combat module.

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
