extends RefCounted
class_name BoardAdapter

## Live bridge between the combat/move model and the running game scene.
##
## The combat module ([MoveExecutor] / [MoveContext] / [MoveEffect]) speaks a
## small, board-agnostic interface in its own [Vector3i]``(col, row, floor)`` cell
## space (see [Cells]). This adapter implements that interface against the real game,
## translating each combat cell to/from the game's [Grid] (grid coords
## ``Vector3(col, floor, row)``; world Y = floor * [constant Cells.FLOOR_HEIGHT]) and
## answering allegiance queries through unit ``owner_player``.
##
## [b]Floors[/b] (see docs/MULTI_FLOOR.md): floor 0 exists at every in-bounds column.
## A cell on floor f > 0 exists only where a tile was registered there (a bridge, a
## rampart); a missing floor-1 cell is AIR (a broken-bridge gap). Explicit [b]links[/b]
## (stairs / ladders, injected via [method set_links]) join cells across floors.
## Occupancy is per [Vector3i], so a unit under a bridge and one on it coexist.
##
## Implemented board interface (see [MoveContext]):
##   cell_of(unit) -> Vector3i
##   units_at(cell: Vector3i) -> Array
##   are_enemies(a, b) -> bool
##   are_allies(a, b) -> bool
##   set_tile(cell: Vector3i, tile_id) -> void
##   move_unit(unit, to_cell: Vector3i) -> void
##
## Also implements the [BotController] board-query superset:
##   all_units() -> Array
##
## Also implements the [MovementResolver] board interface:
##   cells_of(unit) -> Array[Vector3i]
##   can_fit(unit, anchor: Vector3i) -> bool
##   in_bounds(cell: Vector3i) -> bool
##   is_blocked(cell: Vector3i) -> bool
##   is_occupied(cell: Vector3i) -> bool
##   move_cost(cell: Vector3i) -> int
##   tile_id_at(cell: Vector3i) -> StringName
##   tile_tag_at(cell: Vector3i) -> StringName
##   has_tile(cell: Vector3i) -> bool           # floor structure (air = false)
##   links_from(cell: Vector3i) -> Array        # [{to, cost, kind}]
##   floor_count() -> int
##
## Line of sight ([LineOfSight]) reads: has_tile, blocks_los_at, is_solid_ceiling.
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
var _tile_overrides: Dictionary = {}  ## Vector3i -> tile_id, best-effort terrain state.
var _tile_registry: Dictionary = {}   ## Vector3i -> TileResource; injected by CombatServices (empty in mocks).
## Vector3i -> true for every upper-floor cell that has a tile, even one with no
## resolvable TileResource. Injected by CombatServices ([method set_present_cells]).
var _present_cells: Dictionary = {}
## Vector3i -> Array of { "to": Vector3i, "cost": int, "kind": StringName } -- the
## directed adjacency built from [method set_links] (bidirectional links add both).
var _link_adjacency: Dictionary = {}
## The normalized link list last passed to [method set_links].
var _link_list: Array = []
## Cached number of floors (highest floor with any tile or link endpoint + 1).
var _floor_count: int = 1

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
	refresh_floors()


## Inject the set of upper-floor cells that have a tile (Vector3i -> true). Floor-0
## cells always exist; this is what makes a floor-1 bridge cell walkable and a gap
## in it air. Passed by reference, like the registry.
func set_present_cells(cells: Dictionary) -> void:
	_present_cells = cells
	refresh_floors()


## Inject cross-floor links (stairs, ladders...). Each entry is a Dictionary
## { from, to, cost = 1, kind = "stairs", bidirectional = true } where from/to are
## anything [method Cells.from_variant] reads. Replaces any previous links.
func set_links(links: Array) -> void:
	_link_adjacency = {}
	_link_list = []
	for raw in links:
		if not (raw is Dictionary):
			continue
		var l := normalize_link(raw)
		if l.is_empty():
			continue
		_link_list.append(l)
		_add_link_edge(l["from"], l["to"], l["cost"], l["kind"])
		if l["bidirectional"]:
			_add_link_edge(l["to"], l["from"], l["cost"], l["kind"])
	refresh_floors()


## Build this adapter's terrain + floor structure straight from a [MapResource],
## WITHOUT a scene: a fresh registry (every floor-0 column, plus each upper-floor
## entry, resolved exactly like MapLoader does), the upper-floor present-cell set,
## and the map's links (explicit + stair-generated). For headless tools, AI
## simulations and tests; the live game gets the same data via CombatServices.
## Returns self for chaining.
func configure_from_map(map: MapResource) -> BoardAdapter:
	var registry := {}
	var present := {}
	for x in range(map.width):
		for y in range(map.height):
			var res0 := MapLoader.resolve_tile_resource_for_entry(map.get_tile_at_position(Vector2i(x, y)))
			if res0 != null:
				registry[Vector3i(x, y, 0)] = res0
	for entry in map.tile_layout:
		var f := MapResource.entry_floor(entry)
		if f <= 0:
			continue
		var cell := MapResource.entry_cell(entry)
		present[cell] = true
		var res := MapLoader.resolve_tile_resource_for_entry(entry)
		if res != null:
			registry[cell] = res
	_tile_registry = registry
	_present_cells = present
	set_links(map.get_links())
	return self


## Canonical form of a link entry, or {} when its endpoints are unreadable.
static func normalize_link(raw: Dictionary) -> Dictionary:
	var a := Cells.from_variant(raw.get("from", null))
	var b := Cells.from_variant(raw.get("to", null))
	if a == Cells.INVALID or b == Cells.INVALID or a == b:
		return {}
	return {
		"from": a,
		"to": b,
		"cost": maxi(1, int(raw.get("cost", 1))),
		"kind": StringName(str(raw.get("kind", "stairs"))),
		"bidirectional": bool(raw.get("bidirectional", true)),
	}


func _add_link_edge(a: Vector3i, b: Vector3i, cost: int, kind: StringName) -> void:
	if not _link_adjacency.has(a):
		_link_adjacency[a] = []
	_link_adjacency[a].append({ "to": b, "cost": cost, "kind": kind })


## Recompute the cached floor count from the injected registry / present cells /
## links. Called by every setter; call it yourself after mutating an injected
## dictionary in place.
func refresh_floors() -> void:
	var top := 0
	for c in _tile_registry:
		if c is Vector3i:
			top = maxi(top, c.z)
	for c in _present_cells:
		if c is Vector3i:
			top = maxi(top, c.z)
	for l in _link_list:
		top = maxi(top, maxi(l["from"].z, l["to"].z))
	_floor_count = top + 1


# --- MoveContext board interface -------------------------------------------

## Grid cell the unit currently occupies, derived from its world position.
func cell_of(unit) -> Vector3i:
	if unit == null:
		return Vector3i.ZERO
	return world_to_cell(_unit_position(unit))


## Every cell [param unit] covers: its [method cell_of] anchor plus the rest of its
## footprint span. A normal 1x1 unit returns exactly [code][anchor][/code].
func cells_of(unit) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if unit == null:
		return out
	var anchor := cell_of(unit)
	var fp := _footprint_of(unit)
	for dx in range(fp.x):
		for dy in range(fp.y):
			out.append(Vector3i(anchor.x + dx, anchor.y + dy, anchor.z))
	return out


## Every known unit covering [param cell] -- for a multi-cell unit that is any cell
## of its footprint, not just its anchor, so a large boss is found from all of them.
func units_at(cell: Vector3i) -> Array:
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
func can_fit(unit, anchor: Vector3i) -> bool:
	var fp := _footprint_of(unit)
	for dx in range(fp.x):
		for dy in range(fp.y):
			var c := Vector3i(anchor.x + dx, anchor.y + dy, anchor.z)
			if not in_bounds(c) or not has_tile(c):
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
func set_tile(cell: Vector3i, tile_id) -> void:
	_tile_overrides[cell] = tile_id
	var res := _resolve_tile_resource(tile_id)
	if res != null:
		_tile_registry[cell] = res
		if cell.z >= _floor_count:
			refresh_floors()
		var node = _tile_node_at(cell)
		if node != null and node.has_method("set_tile_resource"):
			node.set_tile_resource(res)


## Move [param unit] onto [param to_cell], snapping to the cell's world center.
## The unit keeps its height ABOVE its floor (e.g. MapLoader's tile-top offset) and
## is lifted/lowered by whole floors when [param to_cell] is on another floor.
func move_unit(unit, to_cell: Vector3i) -> void:
	if unit == null:
		return
	var world := cell_to_world(to_cell)
	var cur := _unit_position(unit)
	var offset := cur.y - Cells.floor_y(Cells.floor_from_world_y(cur.y))
	world.y = Cells.floor_y(to_cell.z) + offset
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

## True when [param cell] lies within the grid's bounds: its column is on the map
## and its floor is between 0 and the top floor. With no grid attached (e.g.
## lightweight test doubles), every column is considered in bounds.
func in_bounds(cell: Vector3i) -> bool:
	if cell.z < 0 or cell.z >= _floor_count:
		return false
	return _column_in_bounds(cell)


func _column_in_bounds(cell: Vector3i) -> bool:
	if _grid == null:
		return true
	if _grid.has_method("is_within_bounds"):
		return bool(_grid.is_within_bounds(Vector3(cell.x, 0, cell.y)))
	return true


## True when [param cell] has a floor to stand on. Every in-bounds floor-0 cell
## does; an upper-floor cell only where a tile was placed (else it is AIR).
func has_tile(cell: Vector3i) -> bool:
	if cell.z < 0 or not _column_in_bounds(cell):
		return false
	if cell.z == 0:
		return true
	return _tile_registry.has(cell) or _present_cells.has(cell)


# --- Floor / link queries (the multi-floor API; see docs/MULTI_FLOOR.md) ------

## Number of floors on this board (1 for a classic flat map).
func floor_count() -> int:
	return _floor_count


## Every floor with a tile in column [param col] (Vector2i or Vector3i; the floor
## part is ignored), ascending. Floor 0 is always present for an in-bounds column.
func floors_at(col) -> Array[int]:
	var c := Cells.from_variant(col)
	var out: Array[int] = []
	for f in range(_floor_count):
		if has_tile(Vector3i(c.x, c.y, f)):
			out.append(f)
	return out


## Highest floor with a tile in column [param col] (0 when only the ground exists,
## -1 when the column is off the board).
func top_floor_at(col) -> int:
	var fl := floors_at(col)
	return fl[fl.size() - 1] if not fl.is_empty() else -1


## Every cell that has a tile on floor [param floor_index]. Floor 0 enumerates the
## grid (needs a grid; without one, only registered floor-0 cells are known).
func cells_on_floor(floor_index: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if floor_index == 0 and _grid != null and "size" in _grid:
		for x in range(int(_grid.size.x)):
			for y in range(int(_grid.size.z)):
				out.append(Vector3i(x, y, 0))
		return out
	var seen := {}
	for c in _tile_registry.keys() + _present_cells.keys():
		if c is Vector3i and c.z == floor_index and not seen.has(c):
			seen[c] = true
			out.append(c)
	out.sort_custom(Cells.less)
	return out


## Live units standing (anchored) on floor [param floor_index].
func units_on_floor(floor_index: int) -> Array:
	var out: Array = []
	for u in all_units():
		if cell_of(u).z == floor_index:
			out.append(u)
	return out


## Outgoing link edges from [param cell]: Array of { to, cost, kind }.
func links_from(cell: Vector3i) -> Array:
	return _link_adjacency.get(cell, [])


## True when a link leads directly from [param a] to [param b].
func are_linked(a: Vector3i, b: Vector3i) -> bool:
	for e in links_from(a):
		if e["to"] == b:
			return true
	return false


## Every link as normalized { from, to, cost, kind, bidirectional } dictionaries.
func links() -> Array:
	return _link_list.duplicate()


## True when the tile at [param cell] blocks line of sight (walls, trees).
func blocks_los_at(cell: Vector3i) -> bool:
	var res := _resource_at(cell)
	return res != null and res.blocks_line_of_sight


## True when [param cell] is an upper-floor tile that acts as a CEILING for the
## cell below it (blocks line of sight through it). Tiles default to solid; a tile
## resource may opt out ([member TileResource.solid_ceiling] = false, e.g. a grate).
func is_solid_ceiling(cell: Vector3i) -> bool:
	if cell.z <= 0 or not has_tile(cell):
		return false
	var res := _resource_at(cell)
	return res == null or res.solid_ceiling


## True when a live unit currently occupies [param cell].
func is_occupied(cell: Vector3i) -> bool:
	for u in units_at(cell):
		if _is_alive(u):
			return true
	return false


## True when [param cell] is impassable terrain (its [TileResource] is not
## passable). Cells with no registered terrain (e.g. mocks) are never blocked.
func is_blocked(cell: Vector3i) -> bool:
	var res := _resource_at(cell)
	if res != null:
		return not res.is_tile_passable()
	return false


## Cost to enter [param cell]: the terrain's movement cost (clamped to at least
## 1), or a flat 1 when [param cell] has no registered terrain.
func move_cost(cell: Vector3i) -> int:
	var res := _resource_at(cell)
	if res != null:
		return maxi(1, res.base_movement_cost)
	return 1


## Terrain id for [param cell]. A [method set_tile] override wins (so a just-applied
## transform reads back its id); otherwise the registered [TileResource]'s canonical
## id. Returns [code]&""[/code] when neither is present.
func tile_id_at(cell: Vector3i) -> StringName:
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
func tile_tag_at(cell: Vector3i) -> StringName:
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
func tile_tags_at(cell: Vector3i) -> Array[String]:
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

## Vector3i(col, row, floor) -> world position of that cell's center, at the
## floor's height (floor * [constant Cells.FLOOR_HEIGHT]).
func cell_to_world(cell: Vector3i) -> Vector3:
	if _grid and _grid.has_method("calculate_map_position"):
		return _grid.calculate_map_position(Cells.to_grid(cell))
	return Vector3(cell.x, Cells.floor_y(cell.z), cell.y)


## World position -> the Vector3i(col, row, floor) cell containing it (the floor
## is read from the height, rounded to the nearest floor).
func world_to_cell(world: Vector3) -> Vector3i:
	if _grid and _grid.has_method("calculate_grid_coordinates"):
		var gc: Vector3 = _grid.calculate_grid_coordinates(world)
		return Cells.from_grid(gc)
	return Vector3i(int(round(world.x)), int(round(world.z)), Cells.floor_from_world_y(world.y))


## World Y of floor [param floor_index] (tile origin height).
func floor_world_y(floor_index: int) -> float:
	return Cells.floor_y(floor_index)


## Best-effort terrain lookup (see [method set_tile]). Returns null if unset.
func get_tile(cell: Vector3i):
	return _tile_overrides.get(cell, null)


# --- Internal helpers ------------------------------------------------------

## The [TileResource] registered for [param cell], or null.
func _resource_at(cell: Vector3i) -> TileResource:
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


## The live tile node at [param cell], found under the map root's
## "Tiles/Floor_<f>" container (MapLoader names tiles "Tile_<x>_<y>_<f>"; a legacy
## flat "Tiles/Tile_<x>_<y>" is still found for floor 0). Null for non-Node
## providers (mocks) or if the tile is absent.
func _tile_node_at(cell: Vector3i):
	var root = _units_provider
	if root is Node:
		var tiles = root.get_node_or_null("Tiles")
		if tiles != null:
			var n = tiles.get_node_or_null("Floor_%d/Tile_%d_%d_%d" % [cell.z, cell.x, cell.y, cell.z])
			if n == null and cell.z == 0:
				n = tiles.get_node_or_null("Tile_%d_%d" % [cell.x, cell.y])
			return n
	return null


## [param unit]'s cell span, read duck-typed. Anything without get_footprint()
## (mock units in tests, legacy units) is a normal 1x1, as is an invalid value.
func _footprint_of(unit) -> Vector2i:
	if unit != null and unit.has_method("get_footprint"):
		var fp = unit.get_footprint()
		if fp is Vector2i:
			return Vector2i(maxi(1, fp.x), maxi(1, fp.y))
	return Vector2i.ONE


## True when [param cell] falls inside [param unit]'s footprint span (on its floor).
func _covers(unit, cell: Vector3i) -> bool:
	var anchor := world_to_cell(_unit_position(unit))
	if anchor.z != cell.z:
		return false
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


## Collect every [Unit] under [param node]. Hot path (every units_at / is_occupied
## query walks it), so it skips subtrees that can never hold a unit: the map's
## "Tiles" container (hundreds of tile nodes + their meshes) and a unit's own model
## subtree -- which cut a units_at call on a 20x20 map from ~3 ms to a fraction.
func _gather_units_recursive(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is Unit:
			out.append(child)
			continue
		if child.name == &"Tiles":
			continue
		_gather_units_recursive(child, out)
