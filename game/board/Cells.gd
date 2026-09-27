extends RefCounted
class_name Cells

## The ONE place the game's board-cell convention is spelled out.
##
## [b]Cell[/b] = [Vector3i]([code]col, row, floor[/code]):
##   x = column (world X), y = row (world Z), z = FLOOR (0 = ground).
## Putting the floor in [code]z[/code] means every pre-multi-floor piece of code that
## reads [code]cell.x[/code] / [code]cell.y[/code] as column/row (manhattan distance,
## direction math, footprints) keeps its meaning unchanged.
##
## [b]Grid coord[/b] = [Vector3]([code]col, floor, row[/code]) -- the form the scene
## layer ([Grid], the cursor, [code]GameEvents[/code] signals, visualizers) passes
## around. Its [code]y[/code] is the floor index (not a world height), so legacy code
## that built [code]Vector3(col, 0, row)[/code] is simply "floor 0".
##
## [b]World[/b] = the scene position. A floor-f tile's origin sits at
## [code]y = f * FLOOR_HEIGHT[/code]; a cell's XZ center is [code]col*2+1, row*2+1[/code]
## (see [constant CELL_SIZE]).
##
## Serialization: cells travel as [code][col, row, floor][/code] arrays
## ([method to_array] / [method from_variant]), which survive JSON and the network
## where a raw Vector3i would be stringified.

## World units between two floors. A floor-1 tile sits this far above floor 0.
## 2.5 (vs the 2-wide cells) leaves head-room for a unit standing UNDER a bridge.
## Tunable: everything that converts floor <-> world height reads this constant.
const FLOOR_HEIGHT: float = 2.5

## World size of one cell on X/Z (matches board/Grid.tres cell_size).
const CELL_SIZE: float = 2.0

## Sentinel for "no cell" (off-board). Never a legal board cell.
const INVALID := Vector3i(-9999, -9999, 0)


## Build a cell. [param floor_index] defaults to the ground floor.
static func make(col: int, row: int, floor_index: int = 0) -> Vector3i:
	return Vector3i(col, row, floor_index)


## The floor a cell is on.
static func floor_of(cell: Vector3i) -> int:
	return cell.z


## The (col, row) column of a cell, dropping its floor. Map data ([MapResource]) keys
## tiles by this 2D position plus a separate floor.
static func flat(cell: Vector3i) -> Vector2i:
	return Vector2i(cell.x, cell.y)


## A 2D (col, row) position placed on [param floor_index].
static func lift(pos: Vector2i, floor_index: int = 0) -> Vector3i:
	return Vector3i(pos.x, pos.y, floor_index)


## Same column as [param cell], on [param floor_index].
static func with_floor(cell: Vector3i, floor_index: int) -> Vector3i:
	return Vector3i(cell.x, cell.y, floor_index)


## True when two cells share a column (same x/y), whatever their floors.
static func same_column(a: Vector3i, b: Vector3i) -> bool:
	return a.x == b.x and a.y == b.y


## Horizontal (column/row) Manhattan distance, ignoring floors.
static func manhattan_2d(a: Vector3i, b: Vector3i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## THE range metric: horizontal Manhattan distance plus the floor difference.
## On a single floor this is exactly the old 2D Manhattan distance.
static func distance(a: Vector3i, b: Vector3i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y) + absi(a.z - b.z)


## Deterministic ordering (x, then y, then floor) -- used for stable tie-breaks.
static func less(a: Vector3i, b: Vector3i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	if a.y != b.y:
		return a.y < b.y
	return a.z < b.z


# --- Serialization -----------------------------------------------------------

## [code][col, row, floor][/code] -- JSON/network safe.
static func to_array(cell: Vector3i) -> Array:
	return [cell.x, cell.y, cell.z]


## Parse any reasonable cell representation into a [Vector3i]:
##   Vector3i, Vector2i (lifted to [param default_floor]), Array [c, r] / [c, r, f],
##   Dictionary {x, y[, z|floor]}, or a stringified vector "(c, r)" / "(c, r, f)".
## Returns [constant INVALID] when [param v] cannot be read.
static func from_variant(v, default_floor: int = 0) -> Vector3i:
	if v is Vector3i:
		return v
	if v is Vector2i:
		return Vector3i(v.x, v.y, default_floor)
	if v is Vector2:
		return Vector3i(int(round(v.x)), int(round(v.y)), default_floor)
	if v is Array:
		if v.size() >= 2:
			var f: int = int(v[2]) if v.size() >= 3 else default_floor
			return Vector3i(int(v[0]), int(v[1]), f)
		return INVALID
	if v is Dictionary:
		if v.has("x") and v.has("y"):
			return Vector3i(int(v["x"]), int(v["y"]), int(v.get("z", v.get("floor", default_floor))))
		return INVALID
	if v is String or v is StringName:
		var s := String(v).strip_edges().trim_prefix("(").trim_suffix(")").trim_prefix("[").trim_suffix("]")
		var parts := s.split(",", false)
		if parts.size() >= 2:
			var f2: int = int(parts[2].strip_edges()) if parts.size() >= 3 else default_floor
			return Vector3i(int(parts[0].strip_edges()), int(parts[1].strip_edges()), f2)
	return INVALID


## Parse a 2D (col, row) map position from any representation [method from_variant]
## accepts (the floor, if present, is dropped). [code]Vector2i(-1, -1)[/code] if unreadable.
static func pos2_from_variant(v) -> Vector2i:
	var c := from_variant(v)
	if c == INVALID:
		return Vector2i(-1, -1)
	return Vector2i(c.x, c.y)


# --- Grid coords (Vector3(col, floor, row)) ----------------------------------

## Cell -> scene grid coord [code]Vector3(col, floor, row)[/code].
static func to_grid(cell: Vector3i) -> Vector3:
	return Vector3(cell.x, cell.z, cell.y)


## Scene grid coord [code]Vector3(col, floor, row)[/code] -> cell. Legacy
## [code]Vector3(col, 0, row)[/code] reads as floor 0.
static func from_grid(grid_pos: Vector3) -> Vector3i:
	return Vector3i(int(round(grid_pos.x)), int(round(grid_pos.z)), maxi(0, int(round(grid_pos.y))))


# --- World <-> cell ------------------------------------------------------------

## World Y of floor [param floor_index]'s tile origin (the walkable surface is
## ~0.1 above it -- see MapLoader.UNIT_GROUND_Y).
static func floor_y(floor_index: int) -> float:
	return float(floor_index) * FLOOR_HEIGHT


## How far BELOW a floor's tile origin a height still counts as that floor (a unit
## dipping in an animation). Everything from there up to the next floor's band reads
## as this floor, so a unit (or cursor) held well above its tile -- e.g. the legacy
## y = 1.5 unit height -- still reads as the floor it stands on.
const FLOOR_SNAP_BELOW: float = 0.5


## Floor index a world height belongs to: floor f covers
## [code][f * FLOOR_HEIGHT - FLOOR_SNAP_BELOW, (f + 1) * FLOOR_HEIGHT - FLOOR_SNAP_BELOW)[/code].
## Never negative.
static func floor_from_world_y(y: float) -> int:
	return maxi(0, int(floor((y + FLOOR_SNAP_BELOW) / FLOOR_HEIGHT)))


## World position of a cell's center, on its floor's tile origin height.
static func cell_to_world(cell: Vector3i) -> Vector3:
	return Vector3(cell.x * CELL_SIZE + CELL_SIZE * 0.5, floor_y(cell.z), cell.y * CELL_SIZE + CELL_SIZE * 0.5)


## The cell containing world position [param world] (floor from its height).
static func world_to_cell(world: Vector3) -> Vector3i:
	return Vector3i(int(floor(world.x / CELL_SIZE)), int(floor(world.z / CELL_SIZE)), floor_from_world_y(world.y))
