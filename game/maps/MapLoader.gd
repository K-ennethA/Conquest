extends Node

class_name MapLoader

# MapLoader - Handles dynamic loading and creation of maps from MapResource files
# Replaces the hardcoded map structure in GameWorld.tscn

signal map_loaded(map_resource: MapResource)
signal map_load_failed(error_message: String)

var current_map: MapResource
var map_root: Node3D
var tiles_container: Node3D
var units_container: Node3D

# Tile and unit scene references
var default_tile_scene: PackedScene = preload("res://tile_objects/tiles/tile.tscn")
var warrior_unit_scene: PackedScene = preload("res://game/units/scenes/WarriorUnit.tscn")
var archer_unit_scene: PackedScene = preload("res://game/units/scenes/ArcherUnit.tscn")

# Unit type mapping
var unit_scene_map = {
	"WARRIOR": "res://game/units/scenes/WarriorUnit.tscn",
	"ARCHER": "res://game/units/scenes/ArcherUnit.tscn",
	"MAGE": "res://game/units/scenes/MageUnit.tscn"
}

func _ready():
	print("MapLoader initialized")

func load_map(map_resource: MapResource, target_parent: Node3D) -> bool:
	"""Load a map from MapResource into the scene"""
	if not map_resource:
		_emit_load_failed("Invalid map resource")
		return false
	
	print("Loading map: " + map_resource.map_name)
	
	# Validate map
	var validation = map_resource.validate_map()
	if not validation.valid:
		var error_msg = "Map validation failed: " + str(validation.issues)
		_emit_load_failed(error_msg)
		return false
	
	# Clear existing map if any
	clear_current_map()
	
	# Set up map structure
	current_map = map_resource
	map_root = target_parent
	
	# Create containers
	if not _create_map_containers():
		_emit_load_failed("Failed to create map containers")
		return false
	
	# Load tiles
	if not _load_tiles():
		_emit_load_failed("Failed to load tiles")
		return false
	
	# Load units
	if not _load_units():
		_emit_load_failed("Failed to load units")
		return false
	
	print("Map loaded successfully: " + map_resource.map_name)
	map_loaded.emit(map_resource)
	return true

func load_map_from_file(map_path: String, target_parent: Node3D) -> bool:
	"""Load a map from a .tres file"""
	if not ResourceLoader.exists(map_path):
		_emit_load_failed("Map file not found: " + map_path)
		return false
	
	var map_resource = load(map_path) as MapResource
	if not map_resource:
		_emit_load_failed("Failed to load map resource: " + map_path)
		return false
	
	return load_map(map_resource, target_parent)

func clear_current_map() -> void:
	"""Clear the currently loaded map"""
	if tiles_container:
		tiles_container.queue_free()
		tiles_container = null
	
	if units_container:
		units_container.queue_free()
		units_container = null
	
	current_map = null
	print("Current map cleared")

func get_current_map() -> MapResource:
	"""Get the currently loaded map resource"""
	return current_map

func get_map_info() -> Dictionary:
	"""Get information about the currently loaded map"""
	if not current_map:
		return {}
	
	return current_map.get_display_info()

func _create_map_containers() -> bool:
	"""Create the necessary containers for tiles and units"""
	if not map_root:
		return false
	
	# Create tiles container
	tiles_container = Node3D.new()
	tiles_container.name = "Tiles"
	map_root.add_child(tiles_container)
	
	# Create player containers for units
	for player_id in range(current_map.max_players):
		var player_container = Node3D.new()
		player_container.name = "Player" + str(player_id + 1)
		map_root.add_child(player_container)
	
	return true

func _load_tiles() -> bool:
	"""Load all tiles from the map resource"""
	if not current_map or not tiles_container:
		return false
	
	var map_size = current_map.get_map_size()
	print("Loading tiles for " + str(map_size.x) + "x" + str(map_size.y) + " map")
	
	# Create tiles for each position
	for x in range(map_size.x):
		for y in range(map_size.y):
			var pos = Vector2i(x, y)
			var tile_data = current_map.get_tile_at_position(pos)
			
			if not _create_tile_at_position(pos, tile_data):
				print("Failed to create tile at position: " + str(pos))
				return false
	
	print("Loaded " + str(map_size.x * map_size.y) + " tiles")
	return true

func _create_tile_at_position(grid_pos: Vector2i, tile_data: Dictionary) -> bool:
	"""Create a tile at the specified grid position"""
	var tile_scene = default_tile_scene
	var tile_resource_path = tile_data.get("tile_resource_path", "")
	
	# Load custom tile scene if specified
	if not tile_resource_path.is_empty() and ResourceLoader.exists(tile_resource_path):
		var custom_scene = load(tile_resource_path) as PackedScene
		if custom_scene:
			tile_scene = custom_scene
	
	# Instantiate tile
	var tile_instance = tile_scene.instantiate()
	if not tile_instance:
		return false
	
	# Set tile name and position
	tile_instance.name = "Tile_" + str(grid_pos.x) + "_" + str(grid_pos.y)
	
	# Calculate world position (2x2 tiles with 2 unit spacing)
	var world_pos = Vector3(grid_pos.x * 2, 0, grid_pos.y * 2)
	tile_instance.transform.origin = world_pos
	tile_instance.transform.basis = Basis().scaled(Vector3(2, 1, 2))
	
	# Set tile type if the tile supports it
	var tile_type = tile_data.get("tile_type", "NORMAL")
	if tile_instance.has_method("set_tile_type"):
		tile_instance.set_tile_type(tile_type)
	
	tiles_container.add_child(tile_instance)
	return true

func _load_units() -> bool:
	"""Load all unit spawns from the map resource"""
	if not current_map or not map_root:
		return false
	
	print("Loading unit spawns...")
	
	var units_created = 0
	for spawn_data in current_map.unit_spawns:
		if _create_unit_from_spawn(spawn_data, units_created):
			units_created += 1
		else:
			print("Failed to create unit from spawn: " + str(spawn_data))
	
	print("Created " + str(units_created) + " units")
	return true

func _create_unit_from_spawn(spawn_data: Dictionary, units_created: int) -> bool:
	"""Create a unit from spawn data"""
	print("[MapLoader] Creating unit from spawn data: " + str(spawn_data))
	
	var grid_pos = spawn_data.get("position", Vector2i(-1, -1))
	var player_id_raw = spawn_data.get("player_id", 0)
	
	print("[MapLoader] player_id_raw type: " + str(typeof(player_id_raw)) + ", value: " + str(player_id_raw))
	
	var player_id = int(player_id_raw) if player_id_raw is String else player_id_raw  # Ensure int
	
	print("[MapLoader] player_id after conversion: " + str(player_id) + " (type: " + str(typeof(player_id)) + ")")
	
	var unit_type = spawn_data.get("unit_type", "WARRIOR")
	var unit_resource_path = spawn_data.get("unit_resource_path", "")
	
	if grid_pos == Vector2i(-1, -1):
		print("[MapLoader] Invalid grid position, skipping unit")
		return false
	
	# Get unit scene
	var unit_scene = _get_unit_scene(unit_type, unit_resource_path)
	if not unit_scene:
		print("[MapLoader] Failed to get unit scene for type: " + unit_type)
		return false
	
	# Instantiate unit
	var unit_instance = unit_scene.instantiate()
	if not unit_instance:
		print("[MapLoader] Failed to instantiate unit")
		return false
	
	# Set unit name
	unit_instance.name = unit_type + str(units_created + 1)
	print("[MapLoader] Created unit: " + unit_instance.name)
	
	# Calculate world position (units spawn at Y=1.5 above tiles)
	var world_pos = Vector3(grid_pos.x * 2 + 1, 1.5, grid_pos.y * 2 + 1)
	unit_instance.transform.origin = world_pos
	
	# Add to appropriate player container
	print("[MapLoader] Looking for player container: Player" + str(player_id + 1))
	var player_container = map_root.get_node_or_null("Player" + str(player_id + 1))
	if not player_container:
		# Create player container if it doesn't exist
		print("[MapLoader] Creating player container: Player" + str(player_id + 1))
		player_container = Node3D.new()
		player_container.name = "Player" + str(player_id + 1)
		map_root.add_child(player_container)
	
	player_container.add_child(unit_instance)
	print("[MapLoader] Unit added to player container successfully")
	return true

func _get_unit_scene(unit_type: String, unit_resource_path: String) -> PackedScene:
	"""Get the appropriate unit scene for the unit type"""
	# Try custom unit resource path first
	if not unit_resource_path.is_empty() and ResourceLoader.exists(unit_resource_path):
		var custom_scene = load(unit_resource_path) as PackedScene
		if custom_scene:
			return custom_scene
	
	# Fall back to default unit scenes
	var scene_path = unit_scene_map.get(unit_type.to_upper(), "")
	if not scene_path.is_empty() and ResourceLoader.exists(scene_path):
		return load(scene_path) as PackedScene
	
	# Default to warrior if nothing else works
	return warrior_unit_scene

func _emit_load_failed(error_message: String) -> void:
	"""Emit load failed signal with error message"""
	print("Map load failed: " + error_message)
	map_load_failed.emit(error_message)

# Static helper functions for map management
static func get_available_maps() -> Array[String]:
	"""Get list of available map files"""
	var maps: Array[String] = []
	var dir = DirAccess.open("res://game/maps/resources/")
	
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			if file_name.ends_with(".tres") and not file_name.begins_with("."):
				maps.append("res://game/maps/resources/" + file_name)
			file_name = dir.get_next()
		
		dir.list_dir_end()
	
	return maps

static func create_default_map() -> MapResource:
	"""Create a default 5x5 map for testing"""
	var map_resource = MapResource.new()
	map_resource.map_name = "Default Skirmish"
	map_resource.description = "A basic 5x5 map for quick battles"
	map_resource.author = "System"
	map_resource.width = 5
	map_resource.height = 5
	map_resource.max_players = 2
	map_resource.difficulty = "Normal"
	map_resource.map_type = "Skirmish"
	
	# Create default layout
	map_resource.create_default_layout()
	
	# Add sample spawns
	map_resource.create_sample_spawns()
	
	return map_resource

static func save_map(map_resource: MapResource, file_name: String) -> bool:
	"""Save a map resource to file"""
	if not map_resource or file_name.is_empty():
		return false
	
	# Ensure directory exists
	if not DirAccess.dir_exists_absolute("res://game/maps/resources/"):
		DirAccess.open("res://").make_dir_recursive("game/maps/resources")
	
	# Clean filename
	var clean_name = file_name.to_lower().replace(" ", "_")
	if not clean_name.ends_with(".tres"):
		clean_name += ".tres"
	
	var save_path = "res://game/maps/resources/" + clean_name
	
	# Update last modified
	map_resource.last_modified = Time.get_datetime_string_from_system()
	
	# Save resource
	var result = ResourceSaver.save(map_resource, save_path)
	if result == OK:
		print("Map saved: " + save_path)
		return true
	else:
		print("Failed to save map: " + str(result))
		return false