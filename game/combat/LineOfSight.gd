extends RefCounted
class_name LineOfSight

## 3D-ish line of sight between two board cells ([Vector3i] col, row, floor).
##
## THE RULES (also in docs/MULTI_FLOOR.md):
##  1. A cell always sees itself.
##  2. SAME COLUMN, different floors (directly above/below): visible only if no solid
##     ceiling lies between them -- i.e. no [code]board.is_solid_ceiling[/code] cell on
##     floors (lower, upper]. The upper unit stands on such a tile, so in practice
##     you cannot shoot straight through the floor you (or your target) stand on.
##  3. Otherwise a segment is traced between the two cells' EYE points (cell center,
##     [constant EYE_HEIGHT] above the floor's tile) in world space and sampled:
##     a. WALLS: a sample inside a column other than the two endpoint columns whose
##        cell at the sample's floor band [code]blocks_los_at[/code] (walls, trees)
##        blocks the shot (only when [param check_walls]).
##     b. CEILINGS: when the line passes from one floor band to another it crosses
##        the floor plane of the upper band; if that column has a solid ceiling tile
##        on that floor the shot is blocked -- EXCEPT the plane the shooter stands on
##        in its own column and the plane the target stands on in its column (you
##        can shoot off the edge you stand on, and hit a unit on the lip of a ledge).
##
## So: a unit under a bridge is protected from archers above (the bridge deck is its
## ceiling), two units on floor 0 shoot freely under a bridge (the line never rises
## to floor 1), and an archer on a rampart can hit the ground beside the wall.
##
## Board queries are duck-typed: has_tile, blocks_los_at, is_solid_ceiling. A board
## missing them never blocks.

## Eye height above a floor's tile origin (world units).
const EYE_HEIGHT: float = 1.0
## Samples per world unit of segment length.
const SAMPLES_PER_UNIT: float = 6.0


static func has_line_of_sight(board, from: Vector3i, to: Vector3i, check_walls: bool = true) -> bool:
	if from == to:
		return true
	if Cells.same_column(from, to):
		var lo := mini(from.z, to.z)
		var hi := maxi(from.z, to.z)
		for k in range(lo + 1, hi + 1):
			if _solid_ceiling(board, Vector3i(from.x, from.y, k)):
				return false
		return true

	var p0 := _eye(from)
	var p1 := _eye(to)
	var length := p0.distance_to(p1)
	var n: int = maxi(8, int(ceil(length * SAMPLES_PER_UNIT)))
	var prev_band := from.z
	for i in range(1, n + 1):
		var t := float(i) / float(n)
		var p := p0.lerp(p1, t)
		var col := Vector2i(int(floor(p.x / Cells.CELL_SIZE)), int(floor(p.z / Cells.CELL_SIZE)))
		var band: int = maxi(0, int(floor(p.y / Cells.FLOOR_HEIGHT)))
		var at_from := col.x == from.x and col.y == from.y
		var at_to := col.x == to.x and col.y == to.y
		# (b) Crossing floor planes between the previous sample and this one.
		if band != prev_band:
			for k in range(mini(band, prev_band) + 1, maxi(band, prev_band) + 1):
				if at_from and k == from.z:
					continue
				if at_to and k == to.z:
					continue
				if _solid_ceiling(board, Vector3i(col.x, col.y, k)):
					return false
			prev_band = band
		# (a) Walls in intermediate columns.
		if check_walls and not at_from and not at_to:
			if _blocks(board, Vector3i(col.x, col.y, band)):
				return false
	return true


static func _eye(cell: Vector3i) -> Vector3:
	var w := Cells.cell_to_world(cell)
	w.y += EYE_HEIGHT
	return w


static func _solid_ceiling(board, cell: Vector3i) -> bool:
	return board != null and board.has_method("is_solid_ceiling") and bool(board.is_solid_ceiling(cell))


static func _blocks(board, cell: Vector3i) -> bool:
	return board != null and board.has_method("blocks_los_at") and bool(board.blocks_los_at(cell))
