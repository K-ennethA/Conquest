extends Node

# Test script for Unit Gallery functionality

func _ready():
	print("=== UNIT GALLERY TEST ===")
	
	# Test loading unit resources
	test_unit_loading()
	
	# Test unit gallery creation
	test_unit_gallery_creation()
	
	print("=== UNIT GALLERY TEST COMPLETE ===")

func test_unit_loading():
	"""Test loading unit resources from the directory"""
	print("\n--- Testing Unit Loading ---")
	
	var resources_dir = "res://game/units/resources/unit_types/"
	print("Checking directory: " + resources_dir)
	
	if not DirAccess.dir_exists_absolute(resources_dir):
		print("ERROR: Unit resources directory not found")
		return
	
	var dir = DirAccess.open(resources_dir)
	if not dir:
		print("ERROR: Failed to open resources directory")
		return
	
	var units_found = 0
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if file_name.ends_with(".tres"):
			var resource_path = resources_dir + file_name
			print("Found unit file: " + file_name)
			
			if ResourceLoader.exists(resource_path):
				var resource = load(resource_path)
				if resource is UnitStatsResource:
					units_found += 1
					print("  ✓ Loaded unit: " + resource.unit_name)
					print("    Type: " + str(resource.unit_type))
					print("    Health: " + str(resource.base_health if "base_health" in resource else resource.max_health if "max_health" in resource else "Unknown"))
				else:
					print("  ✗ Not a UnitStatsResource: " + str(resource))
			else:
				print("  ✗ Resource doesn't exist: " + resource_path)
		file_name = dir.get_next()
	
	dir.list_dir_end()
	print("Total units loaded: " + str(units_found))

func test_unit_gallery_creation():
	"""Test creating a Unit Gallery instance"""
	print("\n--- Testing Unit Gallery Creation ---")
	
	var unit_gallery = load("res://menus/UnitGallery.gd").new()
	if unit_gallery:
		print("✓ Unit Gallery script loaded successfully")
		
		# Add to scene tree temporarily for testing
		add_child(unit_gallery)
		
		# Wait a frame for _ready to be called
		await get_tree().process_frame
		
		print("✓ Unit Gallery initialized")
		
		# Clean up
		unit_gallery.queue_free()
	else:
		print("✗ Failed to create Unit Gallery instance")