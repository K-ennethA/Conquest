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
##   cells_of(unit) -> Array[Vector2i]
##   can_fit(unit, anchor: Vector2i) -> bool
##   in_bounds(cell: Vector2i) -> bool
##   is_blocked(cell: Vector2i) -> bool
##   is_occupied(cell: Vector2i) -> bool
##   move_cost(cell: Vector2i) -> int
##   tile_id_at(cell: Vector2i) -> StringName
##   tile_tag_at(cell: Vector2i) -> StringName
##
## Terrain answers (is_blocked/move_cost/tile_id_at/tile_tag_at) come from a
## shared cell -> [TileResource] registry owned by [CombatServices] and injected
## via [method set_tile_registry]; with no registry (mocks/tests) the board reads
## as flat, passable, cost-1 terrain. [method set_tile] mutates that registry and
## the live tile node so terrain-changing effects update the visible board.
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
##
## A unit may span more than one cell. Its ``cell_of`` anchor is the minimum
## corner and its optional ``get_footprint() -> Vector2i`` gives the span, so it
## covers ``anchor .. anchor + footprint - 1``. Units without that method (mocks)
## read as 1x1. ``units_at`` matches ANY covered cell, which is what makes a large
## boss block, and be attackable from, every tile it stands on.

var _grid                 ## Grid resource (col=X, row=Z); may be null in mocks.
var _units_provider       ## See class docs for accepted shapes.
var _tile_overrides: Dictionary = {}  ## Vector2i -> tile_id, best-effort terrain state.
var _tile_registry: Dictionary = {}   ## Vector2i -> TileResource; injected by CombatServices (empty in mocks).

## Terrain ids ([method set_tile] / [TileTransformEffect]) -> the STABLE
## [member TileResource.id] of the tile to swap a live tile to. Keyed by the
## canonical terrain id (lowercased TileType name) plus friendly aliases, so
## effects can request &"lava", &"water", etc.
##
## The VALUES are tile ids resolved through [TileCatalog], not res:// paths: the
## tile assets are grouped into biome folders and get reorganised, and a path here
## would break silently the next time one moves.
const _TERRAIN_ID_TO_TILE_ID := {
	&"grass": &"grass_plains",
	&"plains": &"grass_plains",
	&"normal": &"grass_plains",
	&"water": &"deep_water",
	&"deep_water": &"deep_water",
	&"wall": &"stone_wall",
	&"stone_wall": &"stone_wall",
	&"lava": &"molten_lava",
	&"molten_lava": &"molten_lava",
}


func _init(grid, units_provider) -> void:
	_grid = grid
	_units_provider = units_provider


## Inject the shared cell -> [TileResource] terrain registry (owned by
## [CombatServices]). Passed by reference so terrain queries and [method set_tile]
## stay consistent with [code]CombatServices.tile_at()[/code]. Left empty in tests
## that construct the adapter directly, which then behave like flat terrain.
func set_tile_registry(registry: Dictionary) -> void:
	_tile_registry = registry


# --- MoveContext board interface -------------------------------------------

## Grid cell the unit currently occupies, derived from its world position.
func cell_of(unit) -> Vector2i:
	if unit == null:
		return Vector2i.ZERO
	return world_to_cell(_unit_position(unit))


## Every cell [param unit] covers: its [method cell_of] anchor plus the rest of its
## footprint span. A normal 1x1 unit returns exactly [code][anchor][/code].
func cells_of(unit) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if unit == null:
		return out
	var anchor := cell_of(unit)
	var fp := _footprint_of(unit)
	for dx in range(fp.x):
		for dy in range(fp.y):
			out.append(Vector2i(anchor.x + dx, anchor.y + dy))
	return out


## Every known unit covering [param cell] -- for a multi-cell unit that is any cell
## of its footprint, not just its anchor, so a large boss is found from all of them.
func units_at(cell: Vector2i) -> Array:
	var result: Array = []
	for u in _all_units():
		if u == null:
			continue
		if _covers(u, cell):
			result.append(u)
	return result


## True when [param unit] could stand with its anchor at [param anchor]: every cell
## it would then cover is in bounds, passable terrain, and free of any OTHER living
## unit. The unit's own current cells never count against it, so a large unit is
## never blocked by itself when shuffling within its own footprint. This is the
## primitive [MovementResolver] uses to place multi-cell units.
func can_fit(unit, anchor: Vector2i) -> bool:
	var fp := _footprint_of(unit)
	for dx in range(fp.x):
		for dy in range(fp.y):
			var c := Vector2i(anchor.x + dx, anchor.y + dy)
			if not in_bounds(c):
				return false
			if is_blocked(c):
				return false
			for other in units_at(c):
				if other != unit and _is_alive(other):
					return false
	return true


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


## Apply a terrain change to [param cell] (used by [TileTransformEffect]).
##
## Records the raw id override, and -- when [param tile_id] resolves to a known
## [TileResource] -- updates the shared terrain registry AND the live tile node's
## bound resource/visual so the change is visible on the board and drives future
## move-cost/blocking/id queries. Resolution and the live-node update are
## best-effort: an unknown id or a mock (non-Node) provider simply leaves the
## override recorded, so tests and headless logic still observe a consistent id.
func set_tile(cell: Vector2i, tile_id) -> void:
	_tile_overrides[cell] = tile_id
	var res := _resolve_tile_resource(tile_id)
	if res != null:
		_tile_registry[cell] = res
		var node = _tile_node_at(cell)
		if node != null and node.has_method("set_tile_resource"):
			node.set_tile_resource(res)


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


## True when [param cell] is impassable terrain (its [TileResource] is not
## passable). Cells with no registered terrain (e.g. mocks) are never blocked.
func is_blocked(cell: Vector2i) -> bool:
	var res := _resource_at(cell)
	if res != null:
		return not res.is_tile_passable()
	return false


## Cost to enter [param cell]: the terrain's movement cost (clamped to at least
## 1), or a flat 1 when [param cell] has no registered terrain.
func move_cost(cell: Vector2i) -> int:
	var res := _resource_at(cell)
	if res != null:
		return maxi(1, res.base_movement_cost)
	return 1


## Terrain id for [param cell]. A [method set_tile] override wins (so a just-applied
## transform reads back its id); otherwise the registered [TileResource]'s canonical
## id. Returns [code]&""[/code] when neither is present.
func tile_id_at(cell: Vector2i) -> StringName:
	var t = _tile_overrides.get(cell, null)
	if t != null:
		return t if t is StringName else StringName(str(t))
	var res := _resource_at(cell)
	if res != null:
		return _resource_tile_id(res)
	return &""


## Terrain tag for [param cell]: the registered [TileResource]'s primary tag (its
## first special_property, else its canonical id). Falls back to a [method set_tile]
## override id, then [code]&""[/code]. Used for broad terrain-keyed rules
## ("empowered on water") and movement cost overrides.
func tile_tag_at(cell: Vector2i) -> StringName:
	var res := _resource_at(cell)
	if res != null:
		if res.special_properties != null and not res.special_properties.is_empty():
			return StringName(str(res.special_properties[0]))
		return _resource_tile_id(res)
	var t = _tile_overrides.get(cell, null)
	if t != null:
		return t if t is StringName else StringName(str(t))
	return &""


## EVERY terrain tag on [param cell], not just the primary one.
##
## [method tile_tag_at] returns only the tile's FIRST special property, which is
## fine for "what biome is this" but loses every secondary tag: a volcano tile
## tagged ["volcano", "difficult"] reports only "volcano" through it. Rules that
## ask "does this tile carry tag X" (see [OnTerrainTagCondition]) need the whole
## list, so they read this instead. Never returns null; an unregistered cell, or
## one known only through a [method set_tile] override, yields the override id (or
## the canonical id) as a single-entry list so a tag-less tile can still be named.
func tile_tags_at(cell: Vector2i) -> Array[String]:
	var out: Array[String] = []
	var res := _resource_at(cell)
	if res != null:
		if res.special_properties != null:
			for p in res.special_properties:
				out.append(String(p))
		var canonical := String(_resource_tile_id(res))
		if canonical != "" and not out.has(canonical):
			out.append(canonical)
		return out
	var t = _tile_overrides.get(cell, null)
	if t != null:
		out.append(str(t))
	return out


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

## The [TileResource] registered for [param cell], or null.
func _resource_at(cell: Vector2i) -> TileResource:
	var r = _tile_registry.get(cell, null)
	return r if r is TileResource else null


## Canonical terrain id for a resource: its lowercased [enum Tile.TileType] name
## (e.g. LAVA -> &"lava"), matching the keys in [constant _TERRAIN_ID_TO_TILE_ID].
func _resource_tile_id(res: TileResource) -> StringName:
	var keys := Tile.TileType.keys()
	var idx := int(res.tile_type)
	if idx >= 0 and idx < keys.size():
		return StringName(String(keys[idx]).to_lower())
	return &""


## Resolve a terrain id (StringName/String) to its [TileResource], or null.
##
## Maps the terrain id onto a stable tile id and asks [TileCatalog] for it, so no
## filesystem layout is baked in here. A terrain id that is already a tile id
## (e.g. &"sacred_meadow") resolves directly through the catalog too.
func _resolve_tile_resource(tile_id) -> TileResource:
	var key := StringName(str(tile_id).to_lower())
	var mapped: StringName = _TERRAIN_ID_TO_TILE_ID.get(key, key)
	return TileCatalog.find_by_id(mapped)


## The live tile node at [param cell], found under the map root's "Tiles"
## container (MapLoader names tiles "Tile_<x>_<y>"). Null for non-Node providers
## (mocks) or if the tile is absent.
func _tile_node_at(cell: Vector2i):
	var root = _units_provider
	if root is Node:
		var tiles = root.get_node_or_null("Tiles")
		if tiles != null:
			return tiles.get_node_or_null("Tile_%d_%d" % [cell.x, cell.y])
	return null


## [param unit]'s cell span, read duck-typed. Anything without get_footprint()
## (mock units in tests, legacy units) is a normal 1x1, as is an invalid value.
func _footprint_of(unit) -> Vector2i:
	if unit != null and unit.has_method("get_footprint"):
		var fp = unit.get_footprint()
		if fp is Vector2i:
			return Vector2i(maxi(1, fp.x), maxi(1, fp.y))
	return Vector2i.ONE


## True when [param cell] falls inside [param unit]'s footprint span.
func _covers(unit, cell: Vector2i) -> bool:
	var anchor := world_to_cell(_unit_position(unit))
	var fp := _footprint_of(unit)
	return cell.x >= anchor.x and cell.x < anchor.x + fp.x \
		and cell.y >= anchor.y and cell.y < anchor.y + fp.y


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
