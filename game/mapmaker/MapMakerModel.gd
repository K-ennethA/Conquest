extends RefCounted

class_name MapMakerModel

## Pure, testable editing model for the Map Maker.
##
## Wraps the data of a [MapResource] without any UI or scene dependencies so the
## logic can be unit tested in isolation. Tiles and spawns are stored in
## dictionaries keyed by board cell [Vector3i] (col, row, FLOOR), objective markers
## by [Vector2i] (ground floor), which keeps paint / erase / place operations O(1)
## and free of duplicate positions.
##
## MULTI-FLOOR (see docs/MULTI_FLOOR.md): every tile / spawn call takes an optional
## trailing [code]floor_index[/code] (default 0 = ground, so the classic API is
## unchanged). Floor 0 is implicitly FULL (an unpainted cell is a NORMAL tile);
## floors above only exist where a tile is painted -- anything else is air. A tile
## may carry a "stairs" direction (auto-link to the next floor up), and explicit
## LINKS (ladders, ramps...) join any two cells. [method validate] reports spawns
## standing on air, links / stairs that lead to a missing cell, and similar.
##
## Use [method to_map_resource] / [method from_map_resource] (or the file
## helpers) to convert to and from the reusable [MapResource] type. Objective and
## throne markers are persisted inside the existing [member MapResource.special_rules]
## array so no changes to [MapResource] are required.

## Prefix used to encode objective/throne markers inside MapResource.special_rules.
const OBJECTIVE_PREFIX := "objective"
## Highest floor the editor lets you build on (0-based).
const MAX_FLOOR := 4

## Map metadata mirrored onto the produced MapResource.
var map_name: String = "New Map"
var description: String = ""
var author: String = ""
var max_players: int = 2

## Grid dimensions in cells.
var width: int = 5
var height: int = 5

## Painted tiles: Vector3i -> { "tile_type", "tile_resource_path", "tile_id", ["stairs"] }.
var _tiles: Dictionary = {}
## Spawns: Vector3i -> { "player_id", "unit_type", "unit_resource_path", ... } (any
## extra MapResource spawn keys such as character_id are carried through).
var _spawns: Dictionary = {}
## Objective markers (throne / future win conditions): Vector2i -> { "marker_type": String, "player_id": int }.
var _objectives: Dictionary = {}
## Explicit links: Array of { from: Vector3i, to: Vector3i, cost, kind, bidirectional }.
var _links: Array[Dictionary] = []
## Non-objective special rules carried through untouched on load/save.
var _extra_special_rules: Array[String] = []


func _init(initial_width: int = 5, initial_height: int = 5) -> void:
	width = max(1, initial_width)
	height = max(1, initial_height)


## Returns true if [param pos] lies inside the current grid bounds.
func is_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < width and pos.y >= 0 and pos.y < height


## True if [param cell] (col, row, floor) is inside the grid and on a legal floor.
func is_cell_in_bounds(cell: Vector3i) -> bool:
	return is_in_bounds(Vector2i(cell.x, cell.y)) and cell.z >= 0 and cell.z <= MAX_FLOOR


## Sets the grid dimensions, clamping to a minimum of 1x1 and pruning any tiles,
## spawns, objectives or links that would fall outside the new bounds.
func set_dimensions(new_width: int, new_height: int) -> void:
	width = max(1, new_width)
	height = max(1, new_height)
	_prune_out_of_bounds(_tiles)
	_prune_out_of_bounds(_spawns)
	_prune_out_of_bounds(_objectives)
	for i in range(_links.size() - 1, -1, -1):
		if not is_cell_in_bounds(_links[i]["from"]) or not is_cell_in_bounds(_links[i]["to"]):
			_links.remove_at(i)


func _prune_out_of_bounds(store: Dictionary) -> void:
	for key in store.keys():
		var pos: Vector2i = Vector2i(key.x, key.y)
		if not is_in_bounds(pos):
			store.erase(key)


# --- Tiles --------------------------------------------------------------------------

## Paints a tile at [param pos] on [param floor_index]. Returns false (and does
## nothing) if out of bounds. [param tile_id] is the stable TileResource id.
func paint_tile(pos: Vector2i, tile_type: String = "NORMAL", tile_resource_path: String = "", floor_index: int = 0, tile_id: String = "") -> bool:
	var cell := Vector3i(pos.x, pos.y, floor_index)
	if not is_cell_in_bounds(cell):
		return false
	var entry := {
		"tile_type": tile_type,
		"tile_resource_path": tile_resource_path,
		"tile_id": tile_id,
	}
	# Repainting keeps a stair marker on the cell.
	if _tiles.has(cell) and _tiles[cell].has("stairs"):
		entry["stairs"] = _tiles[cell]["stairs"]
	_tiles[cell] = entry
	return true


## Removes a painted tile at [param pos] on [param floor_index]. Returns true if a
## tile was removed. On floor 0 the cell reverts to the default tile; on an upper
## floor it becomes air (and any spawn standing there is left for [method validate]
## to flag, so the author sees what broke).
func erase_tile(pos: Vector2i, floor_index: int = 0) -> bool:
	var cell := Vector3i(pos.x, pos.y, floor_index)
	if _tiles.has(cell):
		_tiles.erase(cell)
		return true
	return false


## Returns the tile data at [param pos] on [param floor_index]. Floor 0 defaults to
## a NORMAL empty tile; an unpainted upper-floor cell is air and returns {}.
func get_tile(pos: Vector2i, floor_index: int = 0) -> Dictionary:
	var cell := Vector3i(pos.x, pos.y, floor_index)
	if _tiles.has(cell):
		return _tiles[cell].duplicate()
	if floor_index != 0:
		return {}
	return { "tile_type": "NORMAL", "tile_resource_path": "" }


## True when (pos, floor) has a tile: any in-bounds ground cell, or a painted
## upper-floor cell.
func has_tile(pos: Vector2i, floor_index: int = 0) -> bool:
	if not is_in_bounds(pos) or floor_index < 0:
		return false
	if floor_index == 0:
		return true
	return _tiles.has(Vector3i(pos.x, pos.y, floor_index))


## Number of explicitly painted tiles (all floors).
func get_painted_tile_count() -> int:
	return _tiles.size()


## Number of painted tiles on one floor.
func get_floor_tile_count(floor_index: int) -> int:
	var n := 0
	for cell in _tiles:
		if cell.z == floor_index:
			n += 1
	return n


## Number of floors in use (1 for a flat map): the highest floor holding a tile,
## spawn or link endpoint, plus one.
func get_floor_count() -> int:
	var top := 0
	for cell in _tiles:
		top = maxi(top, cell.z)
	for cell in _spawns:
		top = maxi(top, cell.z)
	for l in _links:
		top = maxi(top, maxi(l["from"].z, l["to"].z))
	return top + 1


## Marks the tile at (pos, floor) as a stair climbing toward [param direction]
## ("north" / "south" / "east" / "west"; "" clears). On floor 0 an unpainted cell
## is painted NORMAL first; on an upper floor the cell must already have a tile.
## Returns false for an unknown direction or a missing upper-floor tile.
func set_stairs(pos: Vector2i, direction: String, floor_index: int = 0) -> bool:
	var dir := direction.to_lower()
	if not dir.is_empty() and not MapResource.STAIR_DIRECTIONS.has(dir):
		return false
	var cell := Vector3i(pos.x, pos.y, floor_index)
	if not is_cell_in_bounds(cell):
		return false
	if not _tiles.has(cell):
		if floor_index != 0:
			return false
		paint_tile(pos, "NORMAL", "", 0)
	if dir.is_empty():
		_tiles[cell].erase("stairs")
	else:
		_tiles[cell]["stairs"] = dir
	return true


## The stairs direction of (pos, floor), or "".
func get_stairs(pos: Vector2i, floor_index: int = 0) -> String:
	var cell := Vector3i(pos.x, pos.y, floor_index)
	return str(_tiles[cell].get("stairs", "")) if _tiles.has(cell) else ""


## The cell a stair at (pos, floor) leads to (next floor up), or Cells.INVALID.
func stairs_target(pos: Vector2i, floor_index: int = 0) -> Vector3i:
	var dir := get_stairs(pos, floor_index)
	if dir.is_empty():
		return Cells.INVALID
	var step: Vector2i = MapResource.STAIR_DIRECTIONS[dir]
	return Vector3i(pos.x + step.x, pos.y + step.y, floor_index + 1)


# --- Links ------------------------------------------------------------------------

## Adds an explicit link between two cells (replacing one with the same ends).
## Returns false when an end is out of bounds or both ends are the same cell.
## Missing tiles at the ends are allowed here (so authors can link first, then
## paint) and reported by [method validate].
func add_link(from: Vector3i, to: Vector3i, cost: int = 1, kind: String = "stairs", bidirectional: bool = true) -> bool:
	if from == to or not is_cell_in_bounds(from) or not is_cell_in_bounds(to):
		return false
	remove_link(from, to)
	_links.append({
		"from": from, "to": to, "cost": maxi(1, cost), "kind": kind,
		"bidirectional": bidirectional,
	})
	return true


## Removes the explicit link joining [param a] and [param b] (either direction).
## Returns true if one was removed.
func remove_link(a: Vector3i, b: Vector3i) -> bool:
	var removed := false
	for i in range(_links.size() - 1, -1, -1):
		var l: Dictionary = _links[i]
		if (l["from"] == a and l["to"] == b) or (l["from"] == b and l["to"] == a):
			_links.remove_at(i)
			removed = true
	return removed


## Removes every explicit link touching [param cell]. Returns how many were removed.
func remove_links_at(cell: Vector3i) -> int:
	var n := 0
	for i in range(_links.size() - 1, -1, -1):
		if _links[i]["from"] == cell or _links[i]["to"] == cell:
			_links.remove_at(i)
			n += 1
	return n


## Explicit links (copies).
func get_links() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l in _links:
		out.append(l.duplicate())
	return out


## Explicit links touching [param cell].
func get_links_at(cell: Vector3i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l in _links:
		if l["from"] == cell or l["to"] == cell:
			out.append(l.duplicate())
	return out


# --- Spawns -------------------------------------------------------------------------

## Places a unit / player start spawn at [param pos] on [param floor_index].
## Returns false if out of bounds.
func place_spawn(pos: Vector2i, player_id: int, unit_type: String = "WARRIOR", unit_resource_path: String = "", floor_index: int = 0) -> bool:
	var cell := Vector3i(pos.x, pos.y, floor_index)
	if not is_cell_in_bounds(cell):
		return false
	_spawns[cell] = {
		"player_id": player_id,
		"unit_type": unit_type,
		"unit_resource_path": unit_resource_path,
	}
	return true


## Removes a spawn at [param pos] on [param floor_index]. Returns true if removed.
func remove_spawn(pos: Vector2i, floor_index: int = 0) -> bool:
	var cell := Vector3i(pos.x, pos.y, floor_index)
	if _spawns.has(cell):
		_spawns.erase(cell)
		return true
	return false


## Returns spawn data at [param pos] on [param floor_index], or {} if none.
func get_spawn(pos: Vector2i, floor_index: int = 0) -> Dictionary:
	var cell := Vector3i(pos.x, pos.y, floor_index)
	if _spawns.has(cell):
		return _spawns[cell].duplicate()
	return {}


## Number of placed spawns (all floors).
func get_spawn_count() -> int:
	return _spawns.size()


# --- Objectives ---------------------------------------------------------------------

## Places an objective / throne marker at [param pos]. Returns false if out of bounds.
## [param player_id] of -1 marks a neutral objective.
func set_objective(pos: Vector2i, marker_type: String = "THRONE", player_id: int = -1) -> bool:
	if not is_in_bounds(pos):
		return false
	_objectives[pos] = {
		"marker_type": marker_type,
		"player_id": player_id,
	}
	return true


## Removes an objective marker at [param pos]. Returns true if one was removed.
func remove_objective(pos: Vector2i) -> bool:
	if _objectives.has(pos):
		_objectives.erase(pos)
		return true
	return false


## Returns objective data at [param pos], or an empty dictionary if none.
func get_objective(pos: Vector2i) -> Dictionary:
	if _objectives.has(pos):
		return _objectives[pos].duplicate()
	return {}


## Number of objective markers.
func get_objective_count() -> int:
	return _objectives.size()


# --- Validation ---------------------------------------------------------------------

## Author-facing problems with the multi-floor layout, as
## [ { "level": "error"|"warning", "message": String, "cell": Vector3i } ].
## Errors make the map fail MapResource.validate_map / load; warnings are legal but
## probably unintended.
func validate() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for cell in _spawns:
		if not has_tile(Vector2i(cell.x, cell.y), cell.z):
			out.append(_issue("error", "Spawn at (%d, %d) floor %d stands on air" % [cell.x, cell.y, cell.z], cell))
	for l in _links:
		for end in [l["from"], l["to"]]:
			if not has_tile(Vector2i(end.x, end.y), end.z):
				out.append(_issue("error", "Link end (%d, %d) floor %d has no tile" % [end.x, end.y, end.z], end))
		if l["from"].z == l["to"].z and Cells.manhattan_2d(l["from"], l["to"]) <= 1:
			out.append(_issue("warning", "Link %s -> %s joins neighbours on one floor (they already connect)" % [str(l["from"]), str(l["to"])], l["from"]))
	for cell in _tiles:
		var dir := str(_tiles[cell].get("stairs", ""))
		if dir.is_empty():
			continue
		var to := stairs_target(Vector2i(cell.x, cell.y), cell.z)
		if not has_tile(Vector2i(to.x, to.y), to.z):
			out.append(_issue("error", "Stairs at (%d, %d) floor %d lead %s to air" % [cell.x, cell.y, cell.z, dir], cell))
	for cell in _tiles:
		if cell.z <= 0:
			continue
		if not _has_access(cell):
			out.append(_issue("warning", "Floor %d area at (%d, %d) has no stairs or link" % [cell.z, cell.x, cell.y], cell))
	out.sort_custom(func(a, b): return a["level"] < b["level"] or (a["level"] == b["level"] and Cells.less(a["cell"], b["cell"])))
	return out


func _issue(level: String, message: String, cell: Vector3i) -> Dictionary:
	return { "level": level, "message": message, "cell": cell }


## True when the connected same-floor region containing [param start] is reached by
## at least one link or stair. (Flood fill over painted tiles of that floor.)
func _has_access(start: Vector3i) -> bool:
	var ends := {}
	for l in _links:
		ends[l["from"]] = true
		ends[l["to"]] = true
	for cell in _tiles:
		if not str(_tiles[cell].get("stairs", "")).is_empty():
			ends[cell] = true
			ends[stairs_target(Vector2i(cell.x, cell.y), cell.z)] = true
	var seen := { start: true }
	var queue: Array = [start]
	while not queue.is_empty():
		var c: Vector3i = queue.pop_back()
		if ends.has(c):
			return true
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]:
			var n: Vector3i = c + d
			if not seen.has(n) and _tiles.has(n):
				seen[n] = true
				queue.append(n)
	return false


# --- MapResource conversion ---------------------------------------------------------

## Builds a fully populated [MapResource] from the current model state.
## Every ground cell is written to the tile layout (painted overrides where
## present, NORMAL elsewhere) so the result is directly loadable by MapLoader;
## upper floors get one entry per painted tile (with "floor"), stairs keep their
## "stairs" key, explicit links go to [member MapResource.links].
func to_map_resource() -> MapResource:
	var res := MapResource.new()
	res.map_name = map_name
	res.description = description
	res.author = author
	res.max_players = max_players
	res.width = width
	res.height = height

	var tiles: Array[Dictionary] = []
	for x in range(width):
		for y in range(height):
			var pos := Vector2i(x, y)
			tiles.append(_tile_entry(pos, 0, get_tile(pos)))
	var upper: Array = _tiles.keys().filter(func(c): return c.z > 0)
	upper.sort_custom(Cells.less)
	for cell in upper:
		tiles.append(_tile_entry(Vector2i(cell.x, cell.y), cell.z, _tiles[cell]))
	res.tile_layout = tiles

	var spawns: Array[Dictionary] = []
	var spawn_cells: Array = _spawns.keys()
	spawn_cells.sort_custom(Cells.less)
	for cell in spawn_cells:
		var spawn: Dictionary = _spawns[cell].duplicate()
		spawn["position"] = Vector2i(cell.x, cell.y)
		spawn["player_id"] = spawn.get("player_id", 0)
		spawn["unit_type"] = spawn.get("unit_type", "WARRIOR")
		spawn["unit_resource_path"] = spawn.get("unit_resource_path", "")
		spawn.erase("floor")
		if cell.z > 0:
			spawn["floor"] = cell.z
		spawns.append(spawn)
	res.unit_spawns = spawns

	var links: Array[Dictionary] = []
	for l in _links:
		links.append(l.duplicate())
	res.links = links

	# Persist objective markers inside special_rules alongside any carried-through rules.
	var rules: Array[String] = []
	rules.append_array(_extra_special_rules)
	for pos in _objectives.keys():
		var marker: Dictionary = _objectives[pos]
		rules.append(_encode_objective(pos, marker))
	res.special_rules = rules

	res.last_modified = Time.get_datetime_string_from_system()
	return res


func _tile_entry(pos: Vector2i, floor_index: int, tile: Dictionary) -> Dictionary:
	var entry := {
		"position": pos,
		"tile_type": tile.get("tile_type", "NORMAL"),
		"tile_resource_path": tile.get("tile_resource_path", ""),
	}
	if not str(tile.get("tile_id", "")).is_empty():
		entry["tile_id"] = str(tile["tile_id"])
	if floor_index > 0:
		entry["floor"] = floor_index
	if not str(tile.get("stairs", "")).is_empty():
		entry["stairs"] = str(tile["stairs"])
	return entry


## Populates this model from an existing [MapResource].
func load_from_map_resource(res: MapResource) -> void:
	_tiles.clear()
	_spawns.clear()
	_objectives.clear()
	_links.clear()
	_extra_special_rules.clear()

	if res == null:
		return

	map_name = res.map_name
	description = res.description
	author = res.author
	max_players = res.max_players
	width = max(1, res.width)
	height = max(1, res.height)

	for tile_data in res.tile_layout:
		var pos := MapResource.entry_position(tile_data)
		var f := MapResource.entry_floor(tile_data)
		if not is_cell_in_bounds(Vector3i(pos.x, pos.y, f)):
			continue
		var tile_type: String = str(tile_data.get("tile_type", "NORMAL"))
		var tile_path: String = str(tile_data.get("tile_resource_path", ""))
		var tile_id: String = str(tile_data.get("tile_id", ""))
		var stairs: String = str(tile_data.get("stairs", ""))
		# Ground: only store non-default overrides to keep the model compact.
		# Upper floors: every entry IS the floor (absence = air).
		if f > 0 or tile_type != "NORMAL" or not tile_path.is_empty() or not tile_id.is_empty() or not stairs.is_empty():
			var entry := { "tile_type": tile_type, "tile_resource_path": tile_path, "tile_id": tile_id }
			if not stairs.is_empty():
				entry["stairs"] = stairs
			_tiles[Vector3i(pos.x, pos.y, f)] = entry

	for spawn_data in res.unit_spawns:
		var pos := MapResource.entry_position(spawn_data)
		var f := MapResource.entry_floor(spawn_data)
		if not is_cell_in_bounds(Vector3i(pos.x, pos.y, f)):
			continue
		var spawn: Dictionary = spawn_data.duplicate()
		spawn.erase("position")
		spawn.erase("floor")
		spawn["player_id"] = spawn_data.get("player_id", 0)
		spawn["unit_type"] = spawn_data.get("unit_type", "WARRIOR")
		spawn["unit_resource_path"] = spawn_data.get("unit_resource_path", "")
		_spawns[Vector3i(pos.x, pos.y, f)] = spawn

	for raw in res.links:
		var l := MapResource.normalize_link(raw)
		if not l.is_empty():
			add_link(l["from"], l["to"], l["cost"], l["kind"], l["bidirectional"])

	for rule in res.special_rules:
		var decoded := _decode_objective(rule)
		if decoded.is_empty():
			_extra_special_rules.append(rule)
		else:
			var pos: Vector2i = decoded["position"]
			if is_in_bounds(pos):
				_objectives[pos] = {
					"marker_type": decoded["marker_type"],
					"player_id": decoded["player_id"],
				}


## Creates a new model from an existing [MapResource].
static func from_map_resource(res: MapResource) -> MapMakerModel:
	var model := MapMakerModel.new()
	model.load_from_map_resource(res)
	return model


## Saves the current state as a MapResource .tres at [param path].
## Returns true on success.
func save_to_file(path: String) -> bool:
	if path.is_empty():
		return false
	var res := to_map_resource()
	var dir := path.get_base_dir()
	if not dir.is_empty() and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	return ResourceSaver.save(res, path) == OK


## Loads a MapResource .tres from [param path] into a new model.
## Returns null if the file is missing or not a MapResource.
static func load_from_file(path: String) -> MapMakerModel:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var res := load(path) as MapResource
	if res == null:
		return null
	return MapMakerModel.from_map_resource(res)


func _encode_objective(pos: Vector2i, marker: Dictionary) -> String:
	return "%s:%s:%d:%d:%d" % [
		OBJECTIVE_PREFIX,
		marker.get("marker_type", "THRONE"),
		marker.get("player_id", -1),
		pos.x,
		pos.y,
	]


func _decode_objective(rule: String) -> Dictionary:
	if not rule.begins_with(OBJECTIVE_PREFIX + ":"):
		return {}
	var parts := rule.split(":")
	if parts.size() != 5:
		return {}
	return {
		"marker_type": parts[1],
		"player_id": int(parts[2]),
		"position": Vector2i(int(parts[3]), int(parts[4])),
	}
