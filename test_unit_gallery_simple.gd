extends Node

# Simple test for Unit Gallery functionality

func _ready():
	print("=== SIMPLE UNIT GALLERY TEST ===")
	
	# Test 1: Check if UnitGallery script loads
	var unit_gallery_script = load("res://menus/UnitGallery.gd")
	if unit_gallery_script:
		print("✓ UnitGallery script loaded successfully")
	else:
		print("✗ Failed to load UnitGallery script")
		return
	
	# Test 2: Check if unit resources exist
	var resources_dir = "res://game/units/resources/unit_types/"
	if DirAccess.dir_exists_absolute(resources_dir):
		print("✓ Unit resources directory exists")
		
		var dir = DirAccess.open(resources_dir)
		if dir:
			var unit_count = 0
			dir.list_dir_begin()
			var file_name = dir.get_next()
			
			while file_name != "":
				if file_name.ends_with(".tres"):
					unit_count += 1
					print("  Found unit: " + file_name)
				file_name = dir.get_next()
			
			dir.list_dir_end()
			print("✓ Found " + str(unit_count) + " unit resources")
		else:
			print("✗ Could not open resources directory")
	else:
		print("✗ Unit resources directory not found")
	
	# Test 3: Try to load a unit resource
	var warrior_path = "res://game/units/resources/unit_types/Warrior.tres"
	if ResourceLoader.exists(warrior_path):
		var warrior_resource = load(warrior_path)
		if warrior_resource:
			print("✓ Successfully loaded Warrior unit resource")
			print("  Name: " + str(warrior_resource.unit_name))
			print("  Type: " + str(warrior_resource.unit_type))
		else:
			print("✗ Failed to load Warrior resource")
	else:
		print("✗ Warrior resource file not found")
	
	print("=== TEST COMPLETE ===")
	
	# Auto-quit after test
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()