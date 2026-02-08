extends Node

# Test script for Tile Gallery functionality

func _ready():
	print("=== TILE GALLERY TEST ===")
	
	# Test 1: Check if TileGallery script loads
	var tile_gallery_script = load("res://menus/TileGallery.gd")
	if tile_gallery_script:
		print("✓ TileGallery script loaded successfully")
	else:
		print("✗ Failed to load TileGallery script")
		return
	
	# Test 2: Check if TileResource loads
	var tile_resource_script = load("res://game/tiles/resources/TileResource.gd")
	if tile_resource_script:
		print("✓ TileResource script loaded successfully")
	else:
		print("✗ Failed to load TileResource script")
		return
	
	# Test 3: Check if TileEffect loads
	var tile_effect_script = load("res://game/tiles/TileEffect.gd")
	if tile_effect_script:
		print("✓ TileEffect script loaded successfully")
	else:
		print("✗ Failed to load TileEffect script")
		return
	
	# Test 4: Create a test TileResource
	var test_tile = TileResource.new()
	test_tile.tile_name = "Test Lava Tile"
	test_tile.tile_type = Tile.TileType.LAVA
	test_tile.description = "A test lava tile for demonstration"
	test_tile.base_color = Color.RED
	test_tile.emission_enabled = true
	test_tile.emission_color = Color.ORANGE
	test_tile.has_default_effects = true
	
	if test_tile:
		print("✓ Test TileResource created successfully")
		print("  Name: " + test_tile.tile_name)
		print("  Type: " + Tile.TileType.keys()[test_tile.tile_type])
		print("  Movement Cost: " + str(test_tile.get_movement_cost()))
		print("  Has Effects: " + str(test_tile.has_default_effects))
		
		# Test effect creation
		var effects = test_tile.create_tile_effects()
		print("  Effects Created: " + str(effects.size()))
		for effect in effects:
			print("    - " + effect.effect_name + " (" + TileEffect.EffectType.keys()[effect.effect_type] + ")")
	else:
		print("✗ Failed to create test TileResource")
	
	# Test 5: Test material creation
	var material = test_tile.create_material()
	if material:
		print("✓ Material created successfully")
		print("  Base Color: " + str(material.albedo_color))
		print("  Emission: " + str(material.emission_enabled))
	else:
		print("✗ Failed to create material")
	
	# Test 6: Test validation
	var validation = test_tile.validate_configuration()
	print("✓ Validation test completed")
	print("  Valid: " + str(validation.valid))
	print("  Issues: " + str(validation.issues.size()))
	print("  Warnings: " + str(validation.warnings.size()))
	
	# Test 7: Try to create TileGallery instance
	var tile_gallery = TileGallery.new()
	if tile_gallery:
		print("✓ TileGallery instance created successfully")
		
		# Add to scene tree temporarily for testing
		add_child(tile_gallery)
		
		# Wait a frame for _ready to be called
		await get_tree().process_frame
		
		print("✓ TileGallery initialized")
		print("  Default tiles created: " + str(tile_gallery.all_tiles.size()))
		
		# Clean up
		tile_gallery.queue_free()
	else:
		print("✗ Failed to create TileGallery instance")
	
	print("=== TEST COMPLETE ===")
	
	# Auto-quit after test
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()