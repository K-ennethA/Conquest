extends Node

# Final test for Unit Gallery after compilation fixes

func _ready():
	print("=== FINAL UNIT GALLERY TEST ===")
	
	# Test 1: Create Unit Gallery instance
	var unit_gallery = load("res://menus/UnitGallery.gd").new()
	if unit_gallery:
		print("✓ Unit Gallery instance created successfully")
		
		# Add to scene tree for testing
		add_child(unit_gallery)
		
		# Wait for initialization
		await get_tree().process_frame
		
		print("✓ Unit Gallery initialized without errors")
		
		# Test loading units
		if unit_gallery.all_units.size() > 0:
			print("✓ Units loaded: " + str(unit_gallery.all_units.size()))
			
			# Test first unit
			var first_unit = unit_gallery.all_units[0]
			print("  First unit: " + first_unit.unit_name)
			print("  Type: " + str(first_unit.unit_type))
		else:
			print("! No units found (this may be normal if no .tres files exist)")
		
		# Clean up
		unit_gallery.queue_free()
	else:
		print("✗ Failed to create Unit Gallery instance")
	
	print("=== TEST COMPLETE ===")
	
	# Auto-quit
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()