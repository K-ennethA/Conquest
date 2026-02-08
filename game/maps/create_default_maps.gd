@tool
extends EditorScript

# Script to create default maps for the game
# Run this from the editor to generate sample maps

func _run():
	print("Creating default maps...")
	
	# Ensure directory exists
	if not DirAccess.dir_exists_absolute("res://game/maps/resources/"):
		DirAccess.open("res://").make_dir_recursive("game/maps/resources")
	
	_create_default_skirmish()
	_create_small_battlefield()
	_create_large_plains()
	
	print("Default maps created successfully!")

func _create_default_skirmish():
	"""Create a basic 5x5 skirmish map"""
	var map = MapResource.new()
	map.map_name = "Default Skirmish"
	map.description = "A balanced 5x5 map perfect for quick battles between two players."
	map.author = "System"
	map.width = 5
	map.height = 5
	map.max_players = 2
	map.difficulty = "Normal"
	map.map_type = "Skirmish"
	map.tags = ["Balanced", "Quick", "2-Player"]
	
	# Create default layout
	map.create_default_layout()
	
	# Add some varied terrain
	map.set_tile_at_position(Vector2i(2, 2), "DIFFICULT_TERRAIN", "")  # Center obstacle
	map.set_tile_at_position(Vector2i(1, 1), "WATER", "")
	map.set_tile_at_position(Vector2i(3, 3), "WATER", "")
	
	# Create balanced spawns
	# Player 1 (bottom)
	map.set_unit_spawn_at_position(Vector2i(0, 0), 0, "WARRIOR", "")
	map.set_unit_spawn_at_position(Vector2i(2, 0), 0, "WARRIOR", "")
	map.set_unit_spawn_at_position(Vector2i(4, 0), 0, "ARCHER", "")
	
	# Player 2 (top)
	map.set_unit_spawn_at_position(Vector2i(0, 4), 1, "WARRIOR", "")
	map.set_unit_spawn_at_position(Vector2i(2, 4), 1, "WARRIOR", "")
	map.set_unit_spawn_at_position(Vector2i(4, 4), 1, "ARCHER", "")
	
	MapLoader.save_map(map, "default_skirmish")
	print("Created: Default Skirmish")

func _create_small_battlefield():
	"""Create a small 4x4 battlefield"""
	var map = MapResource.new()
	map.map_name = "Small Battlefield"
	map.description = "A compact 4x4 map for fast-paced combat. Close quarters guaranteed!"
	map.author = "System"
	map.width = 4
	map.height = 4
	map.max_players = 2
	map.difficulty = "Easy"
	map.map_type = "Skirmish"
	map.tags = ["Small", "Fast", "Close Combat"]
	
	# Create layout
	for x in range(4):
		for y in range(4):
			map.set_tile_at_position(Vector2i(x, y), "NORMAL", "")
	
	# Add center obstacles
	map.set_tile_at_position(Vector2i(1, 1), "WALL", "")
	map.set_tile_at_position(Vector2i(2, 2), "WALL", "")
	
	# Create spawns
	# Player 1 (left side)
	map.set_unit_spawn_at_position(Vector2i(0, 0), 0, "WARRIOR", "")
	map.set_unit_spawn_at_position(Vector2i(0, 3), 0, "ARCHER", "")
	
	# Player 2 (right side)
	map.set_unit_spawn_at_position(Vector2i(3, 0), 1, "WARRIOR", "")
	map.set_unit_spawn_at_position(Vector2i(3, 3), 1, "ARCHER", "")
	
	MapLoader.save_map(map, "small_battlefield")
	print("Created: Small Battlefield")

func _create_large_plains():
	"""Create a large 7x7 plains map"""
	var map = MapResource.new()
	map.map_name = "Large Plains"
	map.description = "A spacious 7x7 map with open terrain. Perfect for tactical maneuvering and ranged combat."
	map.author = "System"
	map.width = 7
	map.height = 7
	map.max_players = 2
	map.difficulty = "Hard"
	map.map_type = "Skirmish"
	map.tags = ["Large", "Open", "Tactical"]
	
	# Create layout
	for x in range(7):
		for y in range(7):
			map.set_tile_at_position(Vector2i(x, y), "NORMAL", "")
	
	# Add some scattered difficult terrain
	map.set_tile_at_position(Vector2i(2, 2), "DIFFICULT_TERRAIN", "")
	map.set_tile_at_position(Vector2i(4, 4), "DIFFICULT_TERRAIN", "")
	map.set_tile_at_position(Vector2i(1, 5), "WATER", "")
	map.set_tile_at_position(Vector2i(5, 1), "WATER", "")
	map.set_tile_at_position(Vector2i(3, 3), "SACRED_GROUND", "")  # Center healing tile
	
	# Create larger armies
	# Player 1 (bottom)
	map.set_unit_spawn_at_position(Vector2i(0, 0), 0, "WARRIOR", "")
	map.set_unit_spawn_at_position(Vector2i(2, 0), 0, "WARRIOR", "")
	map.set_unit_spawn_at_position(Vector2i(4, 0), 0, "WARRIOR", "")
	map.set_unit_spawn_at_position(Vector2i(6, 0), 0, "ARCHER", "")
	map.set_unit_spawn_at_position(Vector2i(1, 1), 0, "ARCHER", "")
	
	# Player 2 (top)
	map.set_unit_spawn_at_position(Vector2i(0, 6), 1, "WARRIOR", "")
	map.set_unit_spawn_at_position(Vector2i(2, 6), 1, "WARRIOR", "")
	map.set_unit_spawn_at_position(Vector2i(4, 6), 1, "WARRIOR", "")
	map.set_unit_spawn_at_position(Vector2i(6, 6), 1, "ARCHER", "")
	map.set_unit_spawn_at_position(Vector2i(5, 5), 1, "ARCHER", "")
	
	MapLoader.save_map(map, "large_plains")
	print("Created: Large Plains")