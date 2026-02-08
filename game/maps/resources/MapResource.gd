extends Resource

class_name MapResource

# Resource for storing map configurations and layouts
# Used by the Map Creator tool and map loading system

@export var map_name: String = ""
@export var description: String = ""
@export var author: String = ""
@export var version: String = "1.0"

# Map Dimensions
@export var width: int = 5
@export var height: int = 5

# Map Layout Data
@export var tile_layout: Array[Dictionary] = []  # Array of {position: Vector2i, tile_type: String, tile_resource_path: String}
@export var unit_spawns: Array[Dictionary] = []  # Array of {position: Vector2i, player_id: int, unit_type: String, unit_resource_path: String}

# Map Properties
@export var max_players: int = 2
@export var recommended_players: int = 2
@export var difficulty: String = "Normal"  # Easy, Normal, Hard, Expert
@export var map_type: String = "Skirmish"  # Skirmish, Campaign, Custom

# Visual Properties
@export var environment_preset: String = "Default"  # Default, Desert, Forest, Snow, Volcanic
@export var lighting_preset: String = "Day"  # Day, Night, Dawn, Dusk
@export var background_color: Color = Color(0.2, 0.2, 0.3, 1.0)

# Gameplay Properties
@export var turn_limit: int = 0  # 0 = no limit
@export var victory_conditions: Array[String] = ["Eliminate All Enemies"]
@export var special_rules: Array[String] = []

# Metadata
@export var creation_date: String = ""
@export var last_modified: String = ""
@export var tags: Array[String] = []
@export var preview_image_path: String = ""

func _init():
	resource_name = "MapResource"
	creation_date = Time.get_datetime_string_from_system()
	last_modified = creation_date

func get_map_size() -> Vector2i:
	"""Get map dimensions as Vector2i"""
	return Vector2i(width, height)

func get_tile_at_position(pos: Vector2i) -> Dictionary:
	"""Get tile data at specific position"""
	for tile_data in tile_layout:
		if tile_data.get("position", Vector2i(-1, -1)) == pos:
			return tile_data
	
	# Return default tile if not found
	return {
		"position": pos,
		"tile_type": "NORMAL",
		"tile_resource_path": ""
	}

func set_tile_at_position(pos: Vector2i, tile_type: String, tile_resource_path: String = "") -> void:
	"""Set tile data at specific position"""
	# Remove existing tile at position
	for i in range(tile_layout.size() - 1, -1, -1):
		if tile_layout[i].get("position", Vector2i(-1, -1)) == pos:
			tile_layout.remove_at(i)
	
	# Add new tile data
	tile_layout.append({
		"position": pos,
		"tile_type": tile_type,
		"tile_resource_path": tile_resource_path
	})

func get_unit_spawn_at_position(pos: Vector2i) -> Dictionary:
	"""Get unit spawn data at specific position"""
	for spawn_data in unit_spawns:
		if spawn_data.get("position", Vector2i(-1, -1)) == pos:
			return spawn_data
	
	return {}

func set_unit_spawn_at_position(pos: Vector2i, player_id: int, unit_type: String, unit_resource_path: String = "") -> void:
	"""Set unit spawn data at specific position"""
	# Remove existing spawn at position
	for i in range(unit_spawns.size() - 1, -1, -1):
		if unit_spawns[i].get("position", Vector2i(-1, -1)) == pos:
			unit_spawns.remove_at(i)
	
	# Add new spawn data
	unit_spawns.append({
		"position": pos,
		"player_id": player_id,
		"unit_type": unit_type,
		"unit_resource_path": unit_resource_path
	})

func remove_unit_spawn_at_position(pos: Vector2i) -> void:
	"""Remove unit spawn at specific position"""
	for i in range(unit_spawns.size() - 1, -1, -1):
		if unit_spawns[i].get("position", Vector2i(-1, -1)) == pos:
			unit_spawns.remove_at(i)

func get_player_spawn_positions(player_id: int) -> Array[Vector2i]:
	"""Get all spawn positions for a specific player"""
	var positions: Array[Vector2i] = []
	for spawn_data in unit_spawns:
		if spawn_data.get("player_id", -1) == player_id:
			positions.append(spawn_data.get("position", Vector2i(-1, -1)))
	return positions

func get_total_units_for_player(player_id: int) -> int:
	"""Get total number of units for a specific player"""
	var count = 0
	for spawn_data in unit_spawns:
		if spawn_data.get("player_id", -1) == player_id:
			count += 1
	return count

func validate_map() -> Dictionary:
	"""Validate map configuration"""
	var issues: Array[String] = []
	var warnings: Array[String] = []
	
	# Check required fields
	if map_name.is_empty():
		issues.append("Map name is required")
	
	# Check dimensions
	if width < 3 or width > 20:
		issues.append("Map width should be between 3 and 20")
	
	if height < 3 or height > 20:
		issues.append("Map height should be between 3 and 20")
	
	# Check player spawns
	var player_counts = {}
	for spawn_data in unit_spawns:
		var player_id = spawn_data.get("player_id", -1)
		if player_id >= 0:
			player_counts[player_id] = player_counts.get(player_id, 0) + 1
	
	if player_counts.size() < 2:
		issues.append("Map needs at least 2 players with unit spawns")
	
	# Check for balanced spawns
	var spawn_counts = player_counts.values()
	if spawn_counts.size() > 1:
		var min_spawns = spawn_counts.min()
		var max_spawns = spawn_counts.max()
		if max_spawns - min_spawns > 2:
			warnings.append("Unbalanced unit spawns between players")
	
	# Check for valid positions
	for tile_data in tile_layout:
		var pos = tile_data.get("position", Vector2i(-1, -1))
		if pos.x < 0 or pos.x >= width or pos.y < 0 or pos.y >= height:
			issues.append("Tile position out of bounds: " + str(pos))
	
	for spawn_data in unit_spawns:
		var pos = spawn_data.get("position", Vector2i(-1, -1))
		if pos.x < 0 or pos.x >= width or pos.y < 0 or pos.y >= height:
			issues.append("Unit spawn position out of bounds: " + str(pos))
	
	return {
		"valid": issues.is_empty(),
		"issues": issues,
		"warnings": warnings
	}

func get_display_info() -> Dictionary:
	"""Get formatted info for UI display"""
	var player_counts = {}
	for spawn_data in unit_spawns:
		var player_id = spawn_data.get("player_id", -1)
		if player_id >= 0:
			player_counts[player_id] = player_counts.get(player_id, 0) + 1
	
	return {
		"name": map_name,
		"description": description,
		"author": author,
		"size": str(width) + "x" + str(height),
		"players": player_counts.size(),
		"max_players": max_players,
		"difficulty": difficulty,
		"map_type": map_type,
		"total_tiles": tile_layout.size(),
		"total_spawns": unit_spawns.size(),
		"creation_date": creation_date,
		"tags": tags
	}

func create_default_layout() -> void:
	"""Create a default tile layout for the map"""
	tile_layout.clear()
	
	# Fill with normal tiles
	for x in range(width):
		for y in range(height):
			set_tile_at_position(Vector2i(x, y), "NORMAL", "")

func create_sample_spawns() -> void:
	"""Create sample unit spawns for testing"""
	unit_spawns.clear()
	
	# Player 1 spawns (bottom)
	if height >= 2:
		for x in range(min(3, width)):
			set_unit_spawn_at_position(Vector2i(x, 0), 0, "WARRIOR", "")
	
	# Player 2 spawns (top)
	if height >= 2:
		for x in range(min(3, width)):
			set_unit_spawn_at_position(Vector2i(x, height - 1), 1, "WARRIOR", "")

func export_to_json() -> String:
	"""Export map data to JSON format"""
	var data = {
		"map_info": {
			"name": map_name,
			"description": description,
			"author": author,
			"version": version,
			"creation_date": creation_date,
			"last_modified": last_modified
		},
		"dimensions": {
			"width": width,
			"height": height
		},
		"gameplay": {
			"max_players": max_players,
			"recommended_players": recommended_players,
			"difficulty": difficulty,
			"map_type": map_type,
			"turn_limit": turn_limit,
			"victory_conditions": victory_conditions,
			"special_rules": special_rules
		},
		"visual": {
			"environment_preset": environment_preset,
			"lighting_preset": lighting_preset,
			"background_color": {
				"r": background_color.r,
				"g": background_color.g,
				"b": background_color.b,
				"a": background_color.a
			}
		},
		"layout": {
			"tiles": tile_layout,
			"unit_spawns": unit_spawns
		},
		"metadata": {
			"tags": tags,
			"preview_image_path": preview_image_path
		}
	}
	
	return JSON.stringify(data, "\t")

static func import_from_json(json_string: String) -> MapResource:
	"""Import map data from JSON format"""
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		print("Failed to parse JSON: " + json.get_error_message())
		return null
	
	var data = json.data
	var resource = MapResource.new()
	
	# Map info
	var map_info = data.get("map_info", {})
	resource.map_name = map_info.get("name", "")
	resource.description = map_info.get("description", "")
	resource.author = map_info.get("author", "")
	resource.version = map_info.get("version", "1.0")
	resource.creation_date = map_info.get("creation_date", "")
	resource.last_modified = map_info.get("last_modified", "")
	
	# Dimensions
	var dimensions = data.get("dimensions", {})
	resource.width = dimensions.get("width", 5)
	resource.height = dimensions.get("height", 5)
	
	# Gameplay
	var gameplay = data.get("gameplay", {})
	resource.max_players = gameplay.get("max_players", 2)
	resource.recommended_players = gameplay.get("recommended_players", 2)
	resource.difficulty = gameplay.get("difficulty", "Normal")
	resource.map_type = gameplay.get("map_type", "Skirmish")
	resource.turn_limit = gameplay.get("turn_limit", 0)
	resource.victory_conditions = gameplay.get("victory_conditions", ["Eliminate All Enemies"])
	resource.special_rules = gameplay.get("special_rules", [])
	
	# Visual
	var visual = data.get("visual", {})
	resource.environment_preset = visual.get("environment_preset", "Default")
	resource.lighting_preset = visual.get("lighting_preset", "Day")
	var bg_color = visual.get("background_color", {"r": 0.2, "g": 0.2, "b": 0.3, "a": 1.0})
	resource.background_color = Color(
		bg_color.get("r", 0.2),
		bg_color.get("g", 0.2),
		bg_color.get("b", 0.3),
		bg_color.get("a", 1.0)
	)
	
	# Layout
	var layout = data.get("layout", {})
	resource.tile_layout = layout.get("tiles", [])
	resource.unit_spawns = layout.get("unit_spawns", [])
	
	# Metadata
	var metadata = data.get("metadata", {})
	resource.tags = metadata.get("tags", [])
	resource.preview_image_path = metadata.get("preview_image_path", "")
	
	return resource