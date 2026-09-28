extends RefCounted
class_name BoardSnapshot

## A read-only, FROZEN-OCCUPANCY view of a board for bulk queries (danger zone,
## threat fringes, walk routes). [BoardAdapter] derives occupancy live -- every
## units_at / is_occupied walks every unit -- which is right for game logic but
## makes a many-unit flood (a whole enemy army's reach) cost seconds. This wraps a
## board, indexes every living unit's covered cells ONCE, and answers the
## occupancy / allegiance queries from that index while forwarding the rest
## (terrain, floors, links, LOS inputs) to the wrapped board.
##
## Only valid while nothing moves: build one, run the batch, drop it. Implements
## exactly the duck-typed surface [MovementResolver], [TargetingPattern],
## [LineOfSight] and [ThreatResolver] read.

var board
var _occ: Dictionary = {}      ## Vector3i -> Array of living units covering it
var _cell_of: Dictionary = {}  ## unit -> anchor cell
var _units: Array = []
## Grid columns / rows when the wrapped board exposes its Grid (-1 = unknown), so
## hot loops can bounds-check floor-0 cells inline.
var cols: int = -1
var rows: int = -1


## Wrap [param p_board]. Returned as-is when it already is a snapshot, or when it
## cannot enumerate its units (lightweight mock boards answer occupancy directly).
static func of(p_board):
	if p_board == null or p_board is BoardSnapshot:
		return p_board
	if not p_board.has_method("all_units") or not p_board.has_method("cell_of"):
		return p_board
	return BoardSnapshot.new(p_board)


func _init(p_board) -> void:
	board = p_board
	var g = board.get("_grid")
	if g != null and "size" in g:
		cols = int(g.size.x)
		rows = int(g.size.z)
	var all: Array = board.all_units() if board.has_method("all_units") else []
	for u in all:
		if u == null:
			continue
		_units.append(u)
		var anchor: Vector3i = board.cell_of(u)
		_cell_of[u] = anchor
		var covered: Array = board.cells_of(u) if board.has_method("cells_of") else [anchor]
		for c in covered:
			if not _occ.has(c):
				_occ[c] = []
			_occ[c].append(u)


# --- indexed ----------------------------------------------------------------------

func all_units() -> Array:
	return _units.duplicate()


func units_at(cell: Vector3i) -> Array:
	return _occ.get(cell, [])


func is_occupied(cell: Vector3i) -> bool:
	return _occ.has(cell)


func cell_of(unit) -> Vector3i:
	if _cell_of.has(unit):
		return _cell_of[unit]
	return board.cell_of(unit)


func cells_of(unit) -> Array:
	return board.cells_of(unit) if board.has_method("cells_of") else [cell_of(unit)]


func can_fit(unit, anchor: Vector3i) -> bool:
	var fp := Vector2i.ONE
	if unit != null and unit.has_method("get_footprint"):
		var f = unit.get_footprint()
		if f is Vector2i:
			fp = Vector2i(maxi(1, f.x), maxi(1, f.y))
	for dx in range(fp.x):
		for dy in range(fp.y):
			var c := Vector3i(anchor.x + dx, anchor.y + dy, anchor.z)
			if not in_bounds(c) or not has_tile(c) or is_blocked(c):
				return false
			for other in units_at(c):
				if other != unit:
					return false
	return true


# --- forwarded --------------------------------------------------------------------

func are_allies(a, b) -> bool:
	return board.are_allies(a, b)

func are_enemies(a, b) -> bool:
	return board.are_enemies(a, b)

func in_bounds(cell: Vector3i) -> bool:
	return board.in_bounds(cell) if board.has_method("in_bounds") else true

func has_tile(cell: Vector3i) -> bool:
	return board.has_tile(cell) if board.has_method("has_tile") else true

func is_blocked(cell: Vector3i) -> bool:
	return board.is_blocked(cell) if board.has_method("is_blocked") else false

func move_cost(cell: Vector3i) -> int:
	return board.move_cost(cell) if board.has_method("move_cost") else 1

func tile_id_at(cell: Vector3i):
	return board.tile_id_at(cell) if board.has_method("tile_id_at") else null

func tile_tag_at(cell: Vector3i):
	return board.tile_tag_at(cell) if board.has_method("tile_tag_at") else null

## Layered tile effects (a rubble slow) -- proxied so a threat flood over the snapshot costs
## cells exactly as the live move does (MovementResolver._tile_effect_cost). [] without one.
func tile_effects_at(cell: Vector3i) -> Array:
	return board.tile_effects_at(cell) if board.has_method("tile_effects_at") else []

func links_from(cell: Vector3i) -> Array:
	return board.links_from(cell) if board.has_method("links_from") else []

func are_linked(a: Vector3i, b: Vector3i) -> bool:
	return board.are_linked(a, b) if board.has_method("are_linked") else false

func floor_count() -> int:
	return board.floor_count() if board.has_method("floor_count") else 1

func blocks_los_at(cell: Vector3i) -> bool:
	return board.blocks_los_at(cell) if board.has_method("blocks_los_at") else false

func is_solid_ceiling(cell: Vector3i) -> bool:
	return board.is_solid_ceiling(cell) if board.has_method("is_solid_ceiling") else false

var _floor_cells: Dictionary = {}

func cells_on_floor(f: int) -> Array:
	if not _floor_cells.has(f):
		_floor_cells[f] = board.cells_on_floor(f) if board.has_method("cells_on_floor") else []
	return _floor_cells[f]

func cell_to_world(cell: Vector3i) -> Vector3:
	return board.cell_to_world(cell)
