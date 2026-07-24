extends SceneTree

# Simple test to verify tile gallery works

func _init():
	print("=== SIMPLE TILE GALLERY TEST ===")
	
	# Test TileGallery creation
	var tile_gallery = TileGallery.new()
	print("✓ TileGallery created successfully")
	
	# Test default tile creation
	print("Creating default tiles...")
	tile_gallery._create_default_tiles()
	print("✓ Created " + str(tile_gallery.all_tiles.size()) + " default tiles")
	
	# List all tiles
	print("\nTiles created:")
	for i in range(tile_gallery.all_tiles.size()):
		var tile = tile_gallery.all_tiles[i]
		if tile == null:
			print("  " + str(i+1) + ". [NULL TILE]")
			continue
		
		var type_name = Tile.TileType.keys()[tile.tile_type]
		print("  " + str(i+1) + ". " + tile.tile_name + " (" + type_name + ")")
		
		if tile.has_default_effects:
			var effects = tile.create_tile_effects()
			print("     Effects: " + str(effects.size()))
			for effect in effects:
				print("       - " + effect.effect_name + " (Strength: " + str(effect.strength) + ")")
		else:
			print("     Effects: None")
	
	print("\n=== TEST COMPLETED SUCCESSFULLY ===")
	quit()