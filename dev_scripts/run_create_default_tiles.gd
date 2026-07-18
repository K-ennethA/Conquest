extends SceneTree

# Script to run the default tile creation

func _init():
	print("Running default tile creation...")
	
	# Ensure directory exists
	if not DirAccess.dir_exists_absolute("res://game/tiles/resources/"):
		var result = DirAccess.open("res://").make_dir_recursive("game/tiles/resources")
		if result == OK:
			print("✓ Created tiles/resources directory")
		else:
			print("✗ Failed to create directory")
			quit()
			return
	
	_create_grass_tile()
	_create_fire_tile()
	_create_water_tile()
	_create_wall_tile()
	_create_ice_tile()
	
	print("✓ All default tiles created successfully!")
	quit()

func _create_grass_tile():
	"""Create a basic grass tile with no effects"""
	var grass_tile = TileResource.new()
	grass_tile.tile_name = "Grass Plains"
	grass_tile.tile_type = Tile.TileType.NORMAL
	grass_tile.description = "Standard grassy terrain that's easy to traverse. No special effects."
	grass_tile.base_movement_cost = 1
	grass_tile.is_passable = true
	grass_tile.blocks_line_of_sight = false
	grass_tile.base_color = Color(0.4, 0.8, 0.3, 1.0)  # Green
	grass_tile.emission_enabled = false
	grass_tile.metallic = 0.0
	grass_tile.roughness = 1.0
	grass_tile.has_default_effects = false
	grass_tile.default_effects = []
	grass_tile.provides_cover = false
	grass_tile.cover_bonus = 0
	grass_tile.elevation = 0
	grass_tile.rarity = "Common"
	grass_tile.generation_weight = 1.0
	
	var result = ResourceSaver.save(grass_tile, "res://game/tiles/resources/grass_plains.tres")
	if result == OK:
		print("✓ Created: Grass Plains tile")
	else:
		print("✗ Failed to create Grass Plains tile")

func _create_fire_tile():
	"""Create a fire tile that deals 10 damage per turn"""
	var fire_tile = TileResource.new()
	fire_tile.tile_name = "Molten Lava"
	fire_tile.tile_type = Tile.TileType.LAVA
	fire_tile.description = "Dangerous molten rock that burns anything that steps on it. Deals 10 fire damage per turn to units standing on it."
	fire_tile.base_movement_cost = 2
	fire_tile.is_passable = true
	fire_tile.blocks_line_of_sight = false
	fire_tile.base_color = Color(1.0, 0.2, 0.0, 1.0)  # Red
	fire_tile.emission_enabled = true
	fire_tile.emission_color = Color(1.0, 0.3, 0.0)  # Orange glow
	fire_tile.metallic = 0.0
	fire_tile.roughness = 0.8
	fire_tile.has_default_effects = true
	fire_tile.provides_cover = false
	fire_tile.cover_bonus = 0
	fire_tile.elevation = 0
	fire_tile.rarity = "Rare"
	fire_tile.generation_weight = 0.3
	
	# Create fire damage effect
	var fire_effect = TileEffect.new()
	fire_effect.effect_name = "Lava Burn"
	fire_effect.effect_type = TileEffect.EffectType.FIRE_DAMAGE
	fire_effect.strength = 10  # 10 damage per turn
	fire_effect.duration = -1  # Permanent effect
	fire_effect.triggers_on_enter = true
	fire_effect.triggers_on_turn_start = true
	fire_effect.triggers_on_turn_end = false
	fire_effect.triggers_on_exit = false
	
	fire_tile.default_effects = [fire_effect]
	
	var result = ResourceSaver.save(fire_tile, "res://game/tiles/resources/molten_lava.tres")
	if result == OK:
		print("✓ Created: Molten Lava tile with 10 fire damage per turn")
	else:
		print("✗ Failed to create Molten Lava tile")

func _create_water_tile():
	"""Create a water tile that slows movement"""
	var water_tile = TileResource.new()
	water_tile.tile_name = "Deep Water"
	water_tile.tile_type = Tile.TileType.WATER
	water_tile.description = "Deep water that slows movement but can be crossed by most units."
	water_tile.base_movement_cost = 3
	water_tile.is_passable = true
	water_tile.blocks_line_of_sight = false
	water_tile.base_color = Color(0.2, 0.4, 0.8, 1.0)  # Blue
	water_tile.emission_enabled = false
	water_tile.metallic = 0.8
	water_tile.roughness = 0.1
	water_tile.has_default_effects = false
	water_tile.default_effects = []
	water_tile.provides_cover = false
	water_tile.cover_bonus = 0
	water_tile.elevation = -1
	water_tile.rarity = "Common"
	water_tile.generation_weight = 0.8
	
	var result = ResourceSaver.save(water_tile, "res://game/tiles/resources/deep_water.tres")
	if result == OK:
		print("✓ Created: Deep Water tile")
	else:
		print("✗ Failed to create Deep Water tile")

func _create_wall_tile():
	"""Create a wall tile that blocks movement"""
	var wall_tile = TileResource.new()
	wall_tile.tile_name = "Stone Wall"
	wall_tile.tile_type = Tile.TileType.WALL
	wall_tile.description = "Solid stone wall that blocks movement and provides cover from attacks."
	wall_tile.base_movement_cost = 999  # Impassable
	wall_tile.is_passable = false
	wall_tile.blocks_line_of_sight = true
	wall_tile.base_color = Color(0.3, 0.3, 0.3, 1.0)  # Gray
	wall_tile.emission_enabled = false
	wall_tile.metallic = 0.2
	wall_tile.roughness = 0.9
	wall_tile.has_default_effects = false
	wall_tile.default_effects = []
	wall_tile.provides_cover = true
	wall_tile.cover_bonus = 3
	wall_tile.elevation = 2
	wall_tile.rarity = "Common"
	wall_tile.generation_weight = 0.5
	
	var result = ResourceSaver.save(wall_tile, "res://game/tiles/resources/stone_wall.tres")
	if result == OK:
		print("✓ Created: Stone Wall tile")
	else:
		print("✗ Failed to create Stone Wall tile")

func _create_ice_tile():
	"""Create an ice tile that can slow units"""
	var ice_tile = TileResource.new()
	ice_tile.tile_name = "Frozen Ice"
	ice_tile.tile_type = Tile.TileType.ICE
	ice_tile.description = "Slippery ice that can slow down movement and cause units to slip."
	ice_tile.base_movement_cost = 1
	ice_tile.is_passable = true
	ice_tile.blocks_line_of_sight = false
	ice_tile.base_color = Color(0.8, 0.9, 1.0, 0.9)  # Light blue
	ice_tile.emission_enabled = false
	ice_tile.metallic = 0.9
	ice_tile.roughness = 0.0
	ice_tile.has_default_effects = true
	ice_tile.provides_cover = false
	ice_tile.cover_bonus = 0
	ice_tile.elevation = 0
	ice_tile.rarity = "Uncommon"
	ice_tile.generation_weight = 0.4
	
	# Create slow effect
	var slow_effect = TileEffect.new()
	slow_effect.effect_name = "Slippery Ice"
	slow_effect.effect_type = TileEffect.EffectType.SLOW
	slow_effect.strength = 1  # Reduce movement by 1
	slow_effect.duration = 2  # Lasts 2 turns after leaving
	slow_effect.triggers_on_enter = true
	slow_effect.triggers_on_turn_start = false
	slow_effect.triggers_on_turn_end = false
	slow_effect.triggers_on_exit = false
	
	ice_tile.default_effects = [slow_effect]
	
	var result = ResourceSaver.save(ice_tile, "res://game/tiles/resources/frozen_ice.tres")
	if result == OK:
		print("✓ Created: Frozen Ice tile with slow effect")
	else:
		print("✗ Failed to create Frozen Ice tile")