extends GutTest

## KnockbackEffect must never shove a unit off-grid, through a wall, or onto an occupied
## cell -- BoardAdapter.move_unit snaps unconditionally, so the effect itself walks the
## push path cell-by-cell and stops at the last cell the unit can actually stand on.

class MockBoard:
	var bounds := Rect2i(0, 0, 6, 6)
	var blocked: Dictionary = {}   # cell -> true (impassable terrain)
	var occupied: Dictionary = {}  # cell -> some OTHER unit standing there

	func in_bounds(c: Vector3i) -> bool:
		return c.z == 0 and bounds.has_point(Vector2i(c.x, c.y))

	func can_fit(unit, c: Vector3i) -> bool:
		if not in_bounds(c):
			return false
		if blocked.get(c, false):
			return false
		var occ = occupied.get(c, null)
		return occ == null or occ == unit


func _kb(dist: int) -> KnockbackEffect:
	var e := KnockbackEffect.new()
	e.distance = dist
	return e


func test_open_ground_pushes_full_distance():
	var board := MockBoard.new()
	var unit := RefCounted.new()
	var dest: Vector3i = _kb(3)._clamped_dest(board, unit, Vector3i(1, 2, 0), Vector3i(1, 0, 0))
	assert_eq(dest, Vector3i(4, 2, 0), "on open ground a distance-3 knock moves the full 3 cells")


func test_stops_at_board_edge_never_off_grid():
	var board := MockBoard.new()  # width 6 -> valid x is 0..5
	var unit := RefCounted.new()
	# From (4,0) a distance-3 push east would land at (7,0), off-grid; clamp to (5,0).
	var dest: Vector3i = _kb(3)._clamped_dest(board, unit, Vector3i(4, 0, 0), Vector3i(1, 0, 0))
	assert_eq(dest, Vector3i(5, 0, 0), "knock clamps to the last in-bounds cell, never off-grid")


func test_stops_before_a_wall_never_through_it():
	var board := MockBoard.new()
	board.blocked[Vector3i(3, 0, 0)] = true  # wall two cells ahead
	var unit := RefCounted.new()
	# From (1,0) east, cell (2,0) is fine but (3,0) is a wall -> stop at (2,0), don't pass through.
	var dest: Vector3i = _kb(3)._clamped_dest(board, unit, Vector3i(1, 0, 0), Vector3i(1, 0, 0))
	assert_eq(dest, Vector3i(2, 0, 0), "knock stops before a wall and never jumps through it")


func test_stops_before_an_occupied_cell():
	var board := MockBoard.new()
	var pushed := RefCounted.new()
	var blocker := RefCounted.new()
	board.occupied[Vector3i(2, 0, 0)] = blocker  # someone already stands right behind the target
	# The very next cell is occupied -> nowhere to go, dest == from (apply() then skips it).
	var dest: Vector3i = _kb(2)._clamped_dest(board, pushed, Vector3i(1, 0, 0), Vector3i(1, 0, 0))
	assert_eq(dest, Vector3i(1, 0, 0), "knock never stacks the unit onto an occupied cell")
