extends RefCounted

class_name MapMakerModel

## Pure, testable editing model for the Map Maker.
##
## Wraps the data of a [MapResource] without any UI or scene dependencies so the
## logic can be unit tested in isolation. Tiles, spawns and objective markers are
## stored in dictionaries keyed by [Vector2i] cell coordinates, which keeps
## paint / erase / place operations O(1) and free of duplicate positions.
##
## Use [method to_map_resource] / [method from_map_resource] (or the file
## helpers) to convert to and from the reusable [MapResource] type. Objective and
## throne markers are persisted inside the existing [member MapResource.special_rules]
## array so no changes to [MapResource] are required.

## Prefix used to encode objective/throne markers inside MapResource.special_rules.
const OBJECTIVE_PREFIX := "objective"

## Map metadata mirrored onto the produced MapResource.
var map_name: String = "New Map"
var description: String = ""
var author: String = ""
var max_players: int = 2

## Grid dimensions in cells.
var width: int = 5
var height: int = 5

## Painted tile overrides: Vector2i -> { "tile_type": String, "tile_resource_path": String }.
var _tiles: Dictionary = {}
## Unit / player start spawns: Vector2i -> { "player_id": int, "unit_type": String, "unit_resource_path": String }.
var _spawns: Dictionary = {}
## Objective markers (throne / future win conditions): Vector2i -> { "marker_type": String, "player_id": int }.
var _objectives: Dictionary = {}
## Non-objective special rules carried through untouched on load/save.
var _extra_special_rules: Array[String] = []


func _init(initial_width: int = 5, initial_height: int = 5) -> void:
	width = max(1, initial_width)
	height = max(1, initial_height)


## Returns true if [param pos] lies inside the current grid bounds.
func is_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < width and pos.y >= 0 and pos.y < height


## Sets the grid dimensions, clamping to a minimum of 1x1 and pruning any tiles,
## spawns or objectives that would fall outside the new bounds.
func set_dimensions(new_width: int, new_height: int) -> void:
	width = max(1, new_width)
	height = max(1, new_height)
	_prune_out_of_bounds(_tiles)
	_prune_out_of_bounds(_spawns)
	_prune_out_of_bounds(_objectives)


func _prune_out_of_bounds(store: Dictionary) -> void:
	for pos in store.keys():
		if not is_in_bounds(pos):
			store.erase(pos)


## Paints a tile at [param pos]. Returns false (and does nothing) if out of bounds.
func paint_tile(pos: Vector2i, tile_type: String = "NORMAL", tile_resource_path: String = "") -> bool:
	if not is_in_bounds(pos):
		return false
	_tiles[pos] = {
		"tile_type": tile_type,
		"tile_resource_path": tile_resource_path,
	}
	return true


## Removes a painted tile override at [param pos]. Returns true if a tile was removed.
func erase_tile(pos: Vector2i) -> bool:
	if _tiles.has(pos):
		_tiles.erase(pos)
		return true
	return false


## Returns the tile data at [param pos], defaulting to a NORMAL empty tile.
func get_tile(pos: Vector2i) -> Dictionary:
	if _tiles.has(pos):
		return _tiles[pos].duplicate()
	return { "tile_type": "NORMAL", "tile_resource_path": "" }


## Number of explicitly painted tiles.
func get_painted_tile_count() -> int:
	return _tiles.size()


## Places a unit / player start spawn at [param pos]. Returns false if out of bounds.
func place_spawn(pos: Vector2i, player_id: int, unit_type: String = "WARRIOR", unit_resource_path: String = "") -> bool:
	if not is_in_bounds(pos):
		return false
	_spawns[pos] = {
		"player_id": player_id,
		"unit_type": unit_type,
		"unit_resource_path": unit_resource_path,
	}
	return true


## Removes a spawn at [param pos]. Returns true if a spawn was removed.
func remove_spawn(pos: Vector2i) -> bool:
	if _spawns.has(pos):
		_spawns.erase(pos)
		return true
	return false


## Returns spawn data at [param pos], or an empty dictionary if none.
func get_spawn(pos: Vector2i) -> Dictionary:
	if _spawns.has(pos):
		return _spawns[pos].duplicate()
	return {}


## Number of placed spawns.
func get_spawn_count() -> int:
	return _spawns.size()


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


## Builds a fully populated [MapResource] from the current model state.
## Every cell of the grid is written to the tile layout (painted overrides where
## present, NORMAL elsewhere) so the result is directly loadable by MapLoader.
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
			var tile := get_tile(pos)
			tiles.append({
				"position": pos,
				"tile_type": tile.get("tile_type", "NORMAL"),
				"tile_resource_path": tile.get("tile_resource_path", ""),
			})
	res.tile_layout = tiles

	var spawns: Array[Dictionary] = []
	for pos in _spawns.keys():
		var spawn: Dictionary = _spawns[pos]
		spawns.append({
			"position": pos,
			"player_id": spawn.get("player_id", 0),
			"unit_type": spawn.get("unit_type", "WARRIOR"),
			"unit_resource_path": spawn.get("unit_resource_path", ""),
		})
	res.unit_spawns = spawns

	# Persist objective markers inside special_rules alongside any carried-through rules.
	var rules: Array[String] = []
	rules.append_array(_extra_special_rules)
	for pos in _objectives.keys():
		var marker: Dictionary = _objectives[pos]
		rules.append(_encode_objective(pos, marker))
	res.special_rules = rules

	res.last_modified = Time.get_datetime_string_from_system()
	return res


## Populates this model from an existing [MapResource].
func load_from_map_resource(res: MapResource) -> void:
	_tiles.clear()
	_spawns.clear()
	_objectives.clear()
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
		var pos: Vector2i = tile_data.get("position", Vector2i(-1, -1))
		if not is_in_bounds(pos):
			continue
		var tile_type: String = tile_data.get("tile_type", "NORMAL")
		var tile_path: String = tile_data.get("tile_resource_path", "")
		# Only store non-default overrides to keep the model compact.
		if tile_type != "NORMAL" or not tile_path.is_empty():
			_tiles[pos] = { "tile_type": tile_type, "tile_resource_path": tile_path }

	for spawn_data in res.unit_spawns:
		var pos: Vector2i = spawn_data.get("position", Vector2i(-1, -1))
		if not is_in_bounds(pos):
			continue
		_spawns[pos] = {
			"player_id": spawn_data.get("player_id", 0),
			"unit_type": spawn_data.get("unit_type", "WARRIOR"),
			"unit_resource_path": spawn_data.get("unit_resource_path", ""),
		}

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
