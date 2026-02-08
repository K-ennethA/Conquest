extends SceneTree

# Comprehensive test for the complete tile system

func _init():
	print("=== COMPREHENSIVE TILE SYSTEM TEST ===")
	print()
	
	test_tile_resource_creation()
	test_tile_effect_system()
	test_tile_gallery_integration()
	
	print()
	print("=== ALL TESTS COMPLETED ===")
	quit()

func test_tile_resource_creation():
	print("1. Testing TileResource Creation...")
	
	# Test basic grass tile
	var grass_tile = TileResource.new()
	grass_tile.tile_name = "Test Grass"
	grass_tile.tile_type = Tile.TileType.NORMAL
	grass_tile.description = "Basic grass tile for testing"
	grass_tile.has_default_effects = false
	grass_tile.default_effects = []
	
	test_assert(grass_tile.tile_name == "Test Grass", "Grass tile name not set correctly")
	test_assert(grass_tile.tile_type == Tile.TileType.NORMAL, "Grass tile type not set correctly")
	test_assert(not grass_tile.has_default_effects, "Grass tile should not have effects")
	print("   ✓ Basic grass tile creation successful")
	
	# Test fire tile with effects
	var fire_tile = TileResource.new()
	fire_tile.tile_name = "Test Fire"
	fire_tile.tile_type = Tile.TileType.LAVA
	fire_tile.description = "Fire tile with damage effect"
	fire_tile.has_default_effects = true
	
	var fire_effect = TileEffect.new()
	fire_effect.effect_name = "Test Fire Damage"
	fire_effect.effect_type = TileEffect.EffectType.FIRE_DAMAGE
	fire_effect.strength = 10
	fire_effect.duration = -1
	fire_effect.triggers_on_enter = true
	fire_effect.triggers_on_turn_start = true
	
	# This is the critical test - array assignment
	fire_tile.default_effects = [fire_effect]
	
	test_assert(fire_tile.has_default_effects, "Fire tile should have effects")
	test_assert(fire_tile.default_effects.size() == 1, "Fire tile should have 1 effect")
	print("   ✓ Fire tile with effects creation successful")
	
	# Test effect creation from tile
	var effects = fire_tile.create_tile_effects()
	test_assert(effects.size() > 0, "Fire tile should create effects")
	print("   ✓ Effect creation from tile successful (" + str(effects.size()) + " effects)")
	
	print("   ✓ TileResource creation tests PASSED")
	print()

func test_tile_effect_system():
	print("2. Testing TileEffect System...")
	
	# Test different effect types
	var effect_types = [
		TileEffect.EffectType.FIRE_DAMAGE,
		TileEffect.EffectType.ICE_DAMAGE,
		TileEffect.EffectType.POISON_DAMAGE,
		TileEffect.EffectType.HEALING_SPRING,
		TileEffect.EffectType.SLOW
	]
	
	for effect_type in effect_types:
		var effect = TileEffect.new()
		effect.effect_name = "Test " + TileEffect.EffectType.keys()[effect_type]
		effect.effect_type = effect_type
		effect.strength = 5
		effect.duration = -1
		
		var description = effect._get_effect_description()
		test_assert(not description.is_empty(), "Effect description should not be empty")
		print("   ✓ " + TileEffect.EffectType.keys()[effect_type] + " effect: " + description)
	
	print("   ✓ TileEffect system tests PASSED")
	print()

func test_tile_gallery_integration():
	print("3. Testing TileGallery Integration...")
	
	# Create TileGallery instance
	var tile_gallery = TileGallery.new()
	print("   ✓ TileGallery instance created")
	
	# Test default tile creation
	tile_gallery._create_default_tiles()
	test_assert(tile_gallery.all_tiles.size() > 0, "Should have created default tiles")
	print("   ✓ Default tiles created: " + str(tile_gallery.all_tiles.size()) + " tiles")
	
	# Test each tile
	var grass_found = false
	var fire_found = false
	
	for tile in tile_gallery.all_tiles:
		test_assert(tile != null, "Tile should not be null")
		test_assert(not tile.tile_name.is_empty(), "Tile name should not be empty")
		
		if tile.tile_name == "Grass Plains":
			grass_found = true
			test_assert(not tile.has_default_effects, "Grass should have no effects")
		elif tile.tile_name == "Molten Lava":
			fire_found = true
			test_assert(tile.has_default_effects, "Lava should have effects")
			var effects = tile.create_tile_effects()
			test_assert(effects.size() > 0, "Lava should create effects")
			
			# Find fire damage effect
			var fire_effect_found = false
			for effect in effects:
				if effect.effect_type == TileEffect.EffectType.FIRE_DAMAGE:
					fire_effect_found = true
					test_assert(effect.strength == 10, "Fire effect should have strength 10")
					break
			test_assert(fire_effect_found, "Should find fire damage effect")
		
		print("   ✓ " + tile.tile_name + " (" + Tile.TileType.keys()[tile.tile_type] + ")")
	
	test_assert(grass_found, "Should have found grass tile")
	test_assert(fire_found, "Should have found fire tile")
	
	print("   ✓ TileGallery integration tests PASSED")
	print()

func test_assert(condition: bool, message: String):
	if not condition:
		print("   ✗ ASSERTION FAILED: " + message)
		quit(1)
	