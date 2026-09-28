extends RefCounted
class_name FloorNav

## Pure (static, scene-free) rules for moving the board CURSOR between floors on a
## multi-floor board, plus the "ready unit" ordering used by unit cycling.
## Everything takes a board-like object with the [BoardAdapter] floor API
## (has_tile / floors_at / floor_count) so it is unit-testable headlessly.
##
## The cursor holds a VIEW FLOOR: the highest floor the player currently wants to
## look at / interact with. Floors above it are cut away (see FloorCutaway).
##
##  * Stepping to a column lands on the TOP-MOST floor <= view floor that has a
##    tile there. With the default view floor (the top floor) the cursor rides over
##    bridges and ramparts; walking off a bridge end drops it to the ground below.
##  * floor_up / floor_down cycle the floors of the CURRENT column and move the
##    view floor with them. On a column without another floor they just raise /
##    lower the view floor (so you can "look under" a bridge from beside it).
##  * A cell is COVERED when any higher floor of its column has a tile -- a unit
##    there is hidden by the deck above, so the view auto-cuts to its floor.


## Top-most floor <= [param view_floor] with a tile in column [param col]
## (Vector2i or Vector3i). 0 for a ground-only column, -1 off the board.
static func snap_floor(board, col, view_floor: int) -> int:
	if board == null:
		return 0
	var c := Cells.from_variant(col)
	var best := -1
	for f in board.floors_at(c):
		if f <= view_floor and f > best:
			best = f
	if best < 0 and board.has_tile(Vector3i(c.x, c.y, 0)):
		best = 0
	return best


## The cell a cursor step of [param delta] (col, row) from [param from] lands on,
## honouring [param view_floor]; [constant Cells.INVALID] when it leaves the board.
static func step(board, from: Vector3i, delta: Vector2i, view_floor: int) -> Vector3i:
	var col := Vector3i(from.x + delta.x, from.y + delta.y, 0)
	var f := snap_floor(board, col, view_floor)
	if f < 0:
		return Cells.INVALID
	return Vector3i(col.x, col.y, f)


## floor_up / floor_down. Returns { "cell": Vector3i, "view": int } -- the cursor's
## new cell and the new view floor. [param dir] is +1 (up) or -1 (down).
static func cycle_floor(board, cell: Vector3i, view_floor: int, dir: int) -> Dictionary:
	var top: int = maxi(0, int(board.floor_count()) - 1) if board != null else 0
	var floors: Array = board.floors_at(cell) if board != null else [0]
	var target := -1
	if dir > 0:
		for f in floors:
			if f > cell.z:
				target = f
				break
	else:
		for i in range(floors.size() - 1, -1, -1):
			if floors[i] < cell.z:
				target = floors[i]
				break
	if target >= 0:
		return { "cell": Vector3i(cell.x, cell.y, target), "view": target }
	# No other floor in this column: only the view floor moves (never below the
	# cursor's own floor, never above the top floor).
	var view := clampi(view_floor + dir, cell.z, top)
	return { "cell": cell, "view": view }


## True when a higher floor of [param cell]'s column has a tile (a deck / rampart /
## tower above hides whatever stands here).
static func is_covered(board, cell: Vector3i) -> bool:
	if board == null:
		return false
	for f in board.floors_at(cell):
		if f > cell.z:
			return true
	return false


## Player-facing floor name: "Ground" / "Upper" on two-floor maps, "Ground" /
## "Upper" / "Top" on three-floor ones ("Upper N" in between on taller ones).
static func floor_name(floor_index: int, floor_count: int) -> String:
	if floor_index <= 0:
		return "Ground"
	if floor_count <= 2:
		return "Upper"
	if floor_index >= floor_count - 1:
		return "Top"
	return "Upper" if floor_count == 3 else "Upper %d" % floor_index


## One line per link leaving [param cell], e.g. "Stairs ▲ Upper" / "Ladder ▼ Ground
## (cost 2)". Empty when the cell has no links.
static func describe_links(board, cell: Vector3i) -> PackedStringArray:
	var out := PackedStringArray()
	if board == null or not board.has_method("links_from"):
		return out
	var count: int = int(board.floor_count())
	for e in board.links_from(cell):
		var to: Vector3i = e["to"]
		var kind := String(e.get("kind", "stairs")).capitalize()
		var arrow := "▲" if to.z > cell.z else ("▼" if to.z < cell.z else "▶")
		var line := "%s %s %s" % [kind, arrow, floor_name(to.z, count)]
		if int(e.get("cost", 1)) > 1:
			line += " (cost %d)" % int(e["cost"])
		out.append(line)
	return out


## Stable reading order for unit cycling: row, then column, then floor.
static func cell_order_less(a: Vector3i, b: Vector3i) -> bool:
	if a.y != b.y:
		return a.y < b.y
	if a.x != b.x:
		return a.x < b.x
	return a.z < b.z


## Index of the entry to jump to when cycling [param dir] (+1 next / -1 previous)
## through [param cells] (already sorted with [method cell_order_less]) from the
## cursor at [param current]. When the cursor sits on one of the cells it moves to
## its neighbour (wrapping); otherwise it picks the first cell after (or before) the
## cursor in reading order. -1 when [param cells] is empty.
static func cycle_index(cells: Array, current: Vector3i, dir: int) -> int:
	var n := cells.size()
	if n == 0:
		return -1
	var here := cells.find(current)
	if here >= 0:
		return posmod(here + (1 if dir >= 0 else -1), n)
	if dir >= 0:
		for i in n:
			if cell_order_less(current, cells[i]):
				return i
		return 0
	for i in range(n - 1, -1, -1):
		if cell_order_less(cells[i], current):
			return i
	return n - 1
