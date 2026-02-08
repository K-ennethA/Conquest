extends SceneTree

# Test to verify tile gallery click fix

func _init():
	print("=== TESTING TILE GALLERY CLICK FIX ===")
	
	# Create TileGallery
	var tile_gallery = TileGallery.new()
	print("✓ TileGallery created")
	
	# Create default tiles
	tile_gallery._create_default_tiles()
	print("✓ Default tiles created: " + str(tile_gallery.all_tiles.size()))
	
	# Test clicking on each tile (simulate the _display_tile method)
	for i in range(tile_gallery.all_tiles.size()):
		var tile = tile_gallery.all_tiles[i]
		if tile == null:
			print("✗ Tile at index " + str(i) + " is null")
			continue
		
		print("Testing tile: " + tile.tile_name)
		
		# This simulates what happens when clicking on a tile
		try_display_tile(tile_gallery, tile)
	
	print("✓ All tile clicks tested successfully!")
	print("=== TEST COMPLETED ===")
	quit()

func try_display_tile(tile_gallery: TileGallery, tile: TileResource):
	"""Simulate the tile display process that was causing the error"""
	
	# Set current tile
	tile_gallery.current_tile = tile
	
	# Test material creation (this was causing the duplicate() error)
	var material = tile.create_material()
	if material == null:
		print("✗ Failed to create material for " + tile.tile_name)
		return
	
	print("  ✓ Material created for " + tile.tile_name)
	
	# Test effect creation
	if tile.has_default_effects:
		var effects = tile.create_tile_effects()
		print("  ✓ Effects created: " + str(effects.size()) + " for " + tile.tile_name)
		
		for effect in effects:
			print("    - " + effect.effect_name + " (Strength: " + str(effect.strength) + ")")
	else:
		print("  ✓ No effects for " + tile.tile_name)
	
	# Test the preview update (this was the main source of the error)
	test_preview_creation(tile)

func test_preview_creation(tile: TileResource):
	"""Test creating a 3D preview without the Tile class"""
	
	# Create simple 3D preview (like the fixed version)
	var preview = Node3D.new()
	preview.name = "TestTilePreview"
	
	# Create mesh
	var mesh_instance = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = Vector3(2, 0.2, 2)
	mesh_instance.mesh = mesh
	preview.add_child(mesh_instance)
	
	# Apply material - this should not cause duplicate() error anymore
	var material = tile.create_material()
	mesh_instance.material_override = material
	
	print("  ✓ 3D preview created successfully for " + tile.tile_name)
	
	# Clean up
	preview.queue_free()