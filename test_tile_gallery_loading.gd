extends SceneTree

# Test script to verify TileGallery can load tiles without errors

func _init():
	print("Testing TileGallery tile loading...")
	test_tile_gallery_creation()
	quit()

func test_tile_gallery_creation():
	# Create a TileGallery instance
	var tile_gallery = TileGallery.new()
	print("✓ TileGallery instance created")
	
	# Test the _create_default_tiles method directly
	print("Testing default tile creation...")
	tile_gallery._create_default_tiles()
	print("✓ Default tiles created: " + str(tile_gallery.all_tiles.size()) + " tiles")
	
	# Test each tile
	for i in range(tile_gallery.all_tiles.size()):
		var tile = tile_gallery.all_tiles[i]
		if tile == null:
			print("✗ Tile at index " + str(i) + " is null")
			continue
		
		print("  - " + tile.tile_name + " (" + Tile.TileType.keys()[tile.tile_type] + ")")
		
		# Test effect creation
		if tile.has_default_effects:
			var effects = tile.create_tile_effects()
			print("    Effects: " + str(effects.size()))
			for effect in effects:
				print("      * " + effect.effect_name + " (Strength: " + str(effect.strength) + ")")
	
	print("All tile gallery tests passed!")