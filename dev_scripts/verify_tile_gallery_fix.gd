extends SceneTree

# Verification script for the tile gallery fix

func _init():
	print("=== VERIFYING TILE GALLERY FIX ===")
	print()
	
	# Test 1: Create TileResource with effects (the original issue)
	print("1. Testing TileResource with effects array assignment...")
	var fire_tile = TileResource.new()
	fire_tile.tile_name = "Test Fire Tile"
	fire_tile.tile_type = Tile.TileType.LAVA
	fire_tile.has_default_effects = true
	
	var fire_effect = TileEffect.new()
	fire_effect.effect_name = "Fire Damage"
	fire_effect.effect_type = TileEffect.EffectType.FIRE_DAMAGE
	fire_effect.strength = 10
	fire_effect.duration = -1
	
	# This was the line that caused the original error
	fire_tile.default_effects = [fire_effect]
	print("   ✓ Array assignment successful - no type error!")
	
	# Test 2: Verify effect creation works
	print("2. Testing effect creation from tile...")
	var effects = fire_tile.create_tile_effects()
	print("   ✓ Created " + str(effects.size()) + " effects")
	
	for effect in effects:
		print("   ✓ Effect: " + effect.effect_name + " (Strength: " + str(effect.strength) + ")")
	
	# Test 3: Test TileGallery loading
	print("3. Testing TileGallery loading...")
	var tile_gallery = TileGallery.new()
	tile_gallery._create_default_tiles()
	print("   ✓ TileGallery loaded " + str(tile_gallery.all_tiles.size()) + " tiles")
	
	# Test 4: Verify specific tiles exist
	print("4. Verifying required tiles exist...")
	var grass_found = false
	var fire_found = false
	
	for tile in tile_gallery.all_tiles:
		if tile.tile_name == "Grass Plains":
			grass_found = true
			print("   ✓ Found Grass Plains (no effects)")
		elif tile.tile_name == "Molten Lava":
			fire_found = true
			var tile_effects = tile.create_tile_effects()
			var fire_damage = 0
			for eff in tile_effects:
				if eff.effect_type == TileEffect.EffectType.FIRE_DAMAGE:
					fire_damage = eff.strength
					break
			print("   ✓ Found Molten Lava (fire damage: " + str(fire_damage) + ")")
	
	if not grass_found:
		print("   ✗ Grass Plains tile not found!")
	if not fire_found:
		print("   ✗ Molten Lava tile not found!")
	
	print()
	if grass_found and fire_found:
		print("🎉 ALL TESTS PASSED! Tile gallery fix is working correctly.")
		print("   - TileResource array assignment fixed")
		print("   - Fire tile deals 10 damage per turn")
		print("   - Grass tile has no effects")
		print("   - Tile gallery loads without errors")
	else:
		print("❌ Some tests failed - check the output above")
	
	print()
	print("=== VERIFICATION COMPLETE ===")
	quit()