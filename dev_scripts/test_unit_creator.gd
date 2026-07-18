extends Node

# Test script for the Unit Creator tool

func _ready() -> void:
	print("=== UNIT CREATOR TOOL TEST ===")
	print("This test demonstrates the new Unit Creator development tool")
	print("")
	print("Features:")
	print("- Visual unit creation interface in Godot editor")
	print("- Complete stat configuration with type presets")
	print("- 3D model and profile image assignment")
	print("- Move selection from available move library")
	print("- Template system for saving/loading unit configurations")
	print("- Automatic resource and scene file generation")
	print("")
	print("How to use:")
	print("1. Enable the 'Unit Creator Tool' plugin in Project Settings")
	print("2. Look for the 'Unit Creator' dock in the editor (usually left side)")
	print("3. Fill in unit information, stats, and select moves")
	print("4. Browse for 3D model and profile image files")
	print("5. Click 'CREATE UNIT' to generate all necessary files")
	print("")
	print("Template System:")
	print("- Save current configuration as template for reuse")
	print("- Load existing templates (includes default Warrior/Archer/Mage)")
	print("- Delete unwanted templates")
	print("")
	print("Generated Files:")
	print("- Unit resource (.tres) in res://game/units/resources/")
	print("- Unit scene (.tscn) in res://game/units/scenes/")
	print("- Automatically includes UnitStats and MoveManager components")
	print("")
	print("Press F11 to test unit creation programmatically")
	print("Press F12 to validate existing unit resources")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F11:
			_test_programmatic_unit_creation()
		elif event.keycode == KEY_F12:
			_validate_existing_units()

func _test_programmatic_unit_creation() -> void:
	"""Test creating a unit programmatically"""
	print("\n=== TESTING PROGRAMMATIC UNIT CREATION ===")
	
	# Create test unit data
	var unit_data = {
		"name": "test_knight",
		"display_name": "Test Knight",
		"description": "A test unit created programmatically",
		"unit_type": "Warrior",
		"stats": {
			"health": 140,
			"attack": 28,
			"defense": 25,
			"magic": 8,
			"speed": 9,
			"movement": 3,
			"range": 1
		},
		"model_path": "",
		"profile_image_path": "",
		"moves": ["Basic Attack", "Power Strike", "Shield Wall"]
	}
	
	# Create unit resource
	var success = _create_test_unit_resource(unit_data)
	if success:
		print("✓ Test unit resource created successfully")
	else:
		print("✗ Failed to create test unit resource")
	
	# Test resource loading
	var resource_path = "res://game/units/resources/" + unit_data.name + ".tres"
	if ResourceLoader.exists(resource_path):
		var loaded_resource = load(resource_path) as UnitStatsResource
		if loaded_resource:
			print("✓ Test unit resource loaded successfully")
			print("  Name: " + loaded_resource.unit_name)
			print("  Type: " + loaded_resource.unit_type)
			print("  Health: " + str(loaded_resource.max_health))
			print("  Attack: " + str(loaded_resource.base_attack))
		else:
			print("✗ Failed to load test unit resource")
	
	print("=== PROGRAMMATIC UNIT CREATION TEST COMPLETE ===")

func _create_test_unit_resource(unit_data: Dictionary) -> bool:
	"""Create a test unit resource"""
	var resource_path = "res://game/units/resources/" + unit_data.name + ".tres"
	
	# Create directory if it doesn't exist
	if not DirAccess.dir_exists_absolute("res://game/units/resources/"):
		DirAccess.open("res://").make_dir_recursive("game/units/resources")
	
	# Create UnitStatsResource
	var unit_stats = UnitStatsResource.new()
	unit_stats.unit_name = unit_data.display_name
	unit_stats.unit_type = unit_data.unit_type
	unit_stats.description = unit_data.description
	unit_stats.max_health = unit_data.stats.health
	unit_stats.base_attack = unit_data.stats.attack
	unit_stats.base_defense = unit_data.stats.defense
	unit_stats.base_magic = unit_data.stats.magic
	unit_stats.base_speed = unit_data.stats.speed
	unit_stats.movement_range = unit_data.stats.movement
	unit_stats.attack_range = unit_data.stats.range
	
	# Save resource
	var result = ResourceSaver.save(unit_stats, resource_path)
	return result == OK

func _validate_existing_units() -> void:
	"""Validate existing unit resources"""
	print("\n=== VALIDATING EXISTING UNIT RESOURCES ===")
	
	var resources_dir = "res://game/units/resources/"
	if not DirAccess.dir_exists_absolute(resources_dir):
		print("No unit resources directory found")
		return
	
	var dir = DirAccess.open(resources_dir)
	if not dir:
		print("Failed to open resources directory")
		return
	
	var unit_count = 0
	var valid_count = 0
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if file_name.ends_with(".tres"):
			unit_count += 1
			var resource_path = resources_dir + file_name
			
			print("\nValidating: " + file_name)
			
			if ResourceLoader.exists(resource_path):
				var resource = load(resource_path)
				if resource is UnitStatsResource:
					var unit_resource = resource as UnitStatsResource
					var validation = unit_resource.validate_stats()
					
					if validation.valid:
						print("✓ Valid unit resource")
						valid_count += 1
					else:
						print("✗ Invalid unit resource:")
						for issue in validation.issues:
							print("  - " + issue)
					
					if not validation.warnings.is_empty():
						print("⚠ Warnings:")
						for warning in validation.warnings:
							print("  - " + warning)
					
					# Display unit info
					var info = unit_resource.get_display_info()
					print("  Name: " + info.name)
					print("  Type: " + info.type)
					print("  Total Stats: " + str(info.total_stats))
				else:
					print("✗ Not a UnitStatsResource")
			else:
				print("✗ Resource file not found")
		
		file_name = dir.get_next()
	
	dir.list_dir_end()
	
	print("\n=== VALIDATION SUMMARY ===")
	print("Total units found: " + str(unit_count))
	print("Valid units: " + str(valid_count))
	print("Invalid units: " + str(unit_count - valid_count))
	print("=== VALIDATION COMPLETE ===")

func _exit_tree() -> void:
	"""Clean up when exiting"""
	pass