extends RefCounted
class_name BoardAdapter

## Live bridge between the combat/move model and the running game scene.
##
## The combat module ([MoveExecutor] / [MoveContext] / [MoveEffect]) speaks a
## small, board-agnostic interface in its own [Vector2i]``(col, row)`` cell space.
## This adapter implements that interface against the real game, translating each
## combat cell to/from the game's [Grid] (a Vector3 grid where X = column and
## Z = row, y = 0) and answering allegiance queries through unit ``owner_player``.
##
## Implemented board interface (see [MoveContext]):
##   cell_of(unit) -> Vector2i
##   units_at(cell: Vector2i) -> Array
##   are_enemies(a, b) -> bool
##   are_allies(a, b) -> bool
##   set_tile(cell: Vector2i, tile_id) -> void
##   move_unit(unit, to_cell: Vector2i) -> void
##
## Also implements the [BotController] board-query superset:
##   all_units() -> Array
##
## Also implements the [MovementResolver] board interface:
##   in_bounds(cell: Vector2i) -> bool
##   is_blocked(cell: Vector2i) -> bool
##   is_occupied(cell: Vector2i) -> bool
##   move_cost(cell: Vector2i) -> int
##   tile_id_at(cell: Vector2i) -> StringName
##
## Construct with the grid and a units provider. The provider is flexible so the
## adapter works both in the live game and against a lightweight mock in tests:
##   * Array            - a plain list of units
##   * Dictionary       - cell/position -> Array (like ``board.gd``'s ``units``)
##   * Callable         - returns an Array of units when called
##   * Object.get_units - any object exposing ``get_units() -> Array``
##   * Node             - a container whose [Unit] descendants are gathered
##
## Units are duck-typed: anything exposing ``position`` (Vector3) and
## ``owner_player`` (or ``get_owner_player()``) works. ``units_at`` derives each
## unit's cell live from its world ``position`` every call, so moving a unit only
## needs to reposition it -- there is no separate occupancy index to keep in sync.

var _grid                 ## Grid resource (col=X, row=Z); may be null in mocks.
var _units_provider       ## See class docs for accepted shapes.
var _tile_overrides: Dictionary = {}  ## Vector2i -> tile_id, best-effort terrain state.


func _init(grid, units_provider) -> void:
	_grid = grid
	_units_provider = units_provider


# --- MoveContext board interface -------------------------------------------

## Grid cell the unit currently occupies, derived from its world position.
func cell_of(unit) -> Vector2i:
	if unit == null:
		return Vector2i.ZERO
	return world_to_cell(_unit_position(unit))


## Every known unit whose current cell equals [param cell].
func units_at(cell: Vector2i) -> Array:
	var result: Array = []
	for u in _all_units():
		if u == null:
			continue
		if world_to_cell(_unit_position(u)) == cell:
			result.append(u)
	return result


## True when [param a] and [param b] belong to different (non-null) owners.
func are_enemies(a, b) -> bool:
	var oa = _owner_of(a)
	var ob = _owner_of(b)
	if oa == null or ob == null:
		return false
	return oa != ob


## True when [param a] and [param b] share the same (non-null) owner.
func are_allies(a, b) -> bool:
	var oa = _owner_of(a)
	var ob = _owner_of(b)
	if oa == null or ob == null:
		return false
	return oa == ob


## Record a terrain change for [param cell].
func set_tile(cell: Vector2i, tile_id) -> void:
	_tile_overrides[cell] = tile_id
	# TODO: Wire this to the live terrain system (tile_objects/tiles/tile.gd) so
	#       terrain-changing effects (e.g. TileTransformEffect) update the board
	#       visuals and pathing/occupancy. For now the override is recorded so
	#       logic and tests that query get_tile() observe a consistent result.


## Move [param unit] onto [param to_cell], snapping to the cell's world center
## while preserving the unit's current height.
func move_unit(unit, to_cell: Vector2i) -> void:
	if unit == null:
		return
	var world := cell_to_world(to_cell)
	world.y = _unit_position(unit).y
	unit.set("position", world)
	# TODO: When integrating with the live board, emit GameEvents.unit_moved and
	#       notify any pathing/occupancy subsystem here. No occupancy bookkeeping
	#       is required for correctness because units_at() recomputes cells from
	#       live world positions on every query.


# --- BotController board interface ------------------------------------------

## Every live unit in play (used by [BotController] to find targets).
func all_units() -> Array:
	var result: Array = []
	for u in _all_units():
		if u != null and _is_alive(u):
			result.append(u)
	return result


# --- MovementResolver board interface ---------------------------------------

## True when [param cell] lies within the grid's bounds. With no grid attached
## (e.g. lightweight test doubles), every cell is considered in bounds.
func in_bounds(cell: Vector2i) -> bool:
	if _grid == null:
		return true
	if _grid.has_method("is_within_bounds"):
		return bool(_grid.is_within_bounds(Vector3(cell.x, 0, cell.y)))
	return true


## True when a live unit currently occupies [param cell].
func is_occupied(cell: Vector2i) -> bool:
	for u in units_at(cell):
		if _is_alive(u):
			return true
	return false


## True when [param cell] is impassable terrain.
## TODO(P5): wire this to the live terrain/tile system once terrain blocking lands;
##           for now no cell is considered blocked.
func is_blocked(cell: Vector2i) -> bool:
	return false


## Cost to enter [param cell].
## TODO(P5): derive this from terrain once terrain costs are wired in; for now
##           every cell costs a flat 1 to enter.
func move_cost(cell: Vector2i) -> int:
	return 1


## Best-effort terrain id for [param cell], read from the [method set_tile]
## override store. Returns [code]&""[/code] when no override has been recorded.
func tile_id_at(cell: Vector2i) -> StringName:
	var t = _tile_overrides.get(cell, null)
	if t == null:
		return &""
	if t is StringName:
		return t
	return StringName(str(t))


# --- Coordinate mapping helpers --------------------------------------------

## Vector2i(col, row) -> world position of that cell's center.
func cell_to_world(cell: Vector2i) -> Vector3:
	if _grid and _grid.has_method("calculate_map_position"):
		return _grid.calculate_map_position(Vector3(cell.x, 0, cell.y))
	return Vector3(cell.x, 0, cell.y)


## World position -> the Vector2i(col, row) cell containing it.
func world_to_cell(world: Vector3) -> Vector2i:
	if _grid and _grid.has_method("calculate_grid_coordinates"):
		var gc: Vector3 = _grid.calculate_grid_coordinates(world)
		return Vector2i(int(gc.x), int(gc.z))
	return Vector2i(int(round(world.x)), int(round(world.z)))


## Best-effort terrain lookup (see [method set_tile]). Returns null if unset.
func get_tile(cell: Vector2i):
	return _tile_overrides.get(cell, null)


# --- Internal helpers ------------------------------------------------------

func _unit_position(unit) -> Vector3:
	if unit == null:
		return Vector3.ZERO
	var p = unit.get("position")
	if p is Vector3:
		return p
	if p is Vector2:
		return Vector3(p.x, 0, p.y)
	return Vector3.ZERO


func _owner_of(unit):
	if unit == null:
		return null
	if unit.has_method("get_owner_player"):
		return unit.get_owner_player()
	return unit.get("owner_player")


## True while [param unit] is still alive (duck-typed: prefers is_alive(),
## falls back to a readable hp > 0, defaults to true when neither is present).
func _is_alive(unit) -> bool:
	if unit == null:
		return false
	if unit.has_method("is_alive"):
		return bool(unit.is_alive())
	var hp = unit.get("hp")
	if hp != null:
		return int(hp) > 0
	return true


func _all_units() -> Array:
	var p = _units_provider
	if p == null:
		return []
	if p is Array:
		return p
	if p is Callable:
		var r = p.call()
		return r if r is Array else []
	if p is Dictionary:
		var out: Array = []
		for key in p:
			var bucket = p[key]
			if bucket is Array:
				for u in bucket:
					out.append(u)
			elif bucket != null:
				out.append(bucket)
		return out
	if p is Node:
		var nodes: Array = []
		_gather_units_recursive(p, nodes)
		return nodes
	if p is Object and p.has_method("get_units"):
		var r = p.get_units()
		return r if r is Array else []
	return []


func _gather_units_recursive(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is Unit:
			out.append(child)
		_gather_units_recursive(child, out)
