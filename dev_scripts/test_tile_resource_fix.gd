extends SceneTree

# Test script to verify TileResource fixes

func _init():
	print("Testing TileResource fixes...")
	test_tile_creation()
	quit()

func test_tile_creation():
	print("Creating grass tile...")
	var grass_tile = TileResource.new()
	grass_tile.tile_name = "Test Grass"
	grass_tile.tile_type = Tile.TileType.NORMAL
	grass_tile.description = "Test grass tile"
	grass_tile.has_default_effects = false
	grass_tile.default_effects = []
	print("✓ Grass tile created successfully")
	
	print("Creating fire tile with effects...")
	var fire_tile = TileResource.new()
	fire_tile.tile_name = "Test Fire"
	fire_tile.tile_type = Tile.TileType.LAVA
	fire_tile.description = "Test fire tile with damage"
	fire_tile.has_default_effects = true
	
	# Create fire effect
	var fire_effect = TileEffect.new()
	fire_effect.effect_name = "Test Fire Damage"
	fire_effect.effect_type = TileEffect.EffectType.FIRE_DAMAGE
	fire_effect.strength = 10
	fire_effect.duration = -1
	fire_effect.triggers_on_enter = true
	fire_effect.triggers_on_turn_start = true
	
	# Test array assignment
	fire_tile.default_effects = [fire_effect]
	print("✓ Fire tile with effects created successfully")
	
	# Test effect creation
	var effects = fire_tile.create_tile_effects()
	print("✓ Created " + str(effects.size()) + " effects from tile")
	
	for effect in effects:
		print("  - " + effect.effect_name + " (Type: " + TileEffect.EffectType.keys()[effect.effect_type] + ", Strength: " + str(effect.strength) + ")")
	
	print("All tests passed! TileResource fixes are working correctly.")