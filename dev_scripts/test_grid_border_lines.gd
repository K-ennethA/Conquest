extends Node

# Test script to verify grid border line visibility

func _ready() -> void:
	print("=== GRID BORDER LINES TEST ===")
	print("This script tests the MapGridVisualizer border line visibility")
	print("")
	print("CONTROLS:")
	print("- F1: Toggle grid on/off")
	print("- L: Create test lines for visibility check")
	print("- +: Force grid on")
	print("- -: Set grid preference to off")
	print("")
	print("EXPECTED BEHAVIOR:")
	print("1. Transparent white tiles should appear across the 5x5 map")
	print("2. White border lines should be visible around each tile")
	print("3. When unit selected, blue tiles show movement range")
	print("4. Grid should be visible when unit selected even if toggled off")
	print("")
	
	# Wait a moment for the scene to load
	await get_tree().create_timer(2.0).timeout
	
	# Find the MapGridVisualizer
	var map_grid_visualizer = get_tree().current_scene.get_node("MapGridVisualizer")
	if map_grid_visualizer:
		print("✓ MapGridVisualizer found")
		print("Grid visible: " + str(map_grid_visualizer.is_grid_visible()))
		print("Total grid elements: " + str(map_grid_visualizer.map_grid_tiles.size()))
		
		# Count tiles vs lines
		var tile_count = 0
		var line_count = 0
		for element in map_grid_visualizer.map_grid_tiles:
			if element and is_instance_valid(element):
				if element.name.begins_with("GridTile_"):
					tile_count += 1
				elif element.name.begins_with("GridLine_"):
					line_count += 1
		
		print("Tiles created: " + str(tile_count) + " (expected: 25)")
		print("Lines created: " + str(line_count) + " (expected: 100)")
		
		if line_count == 0:
			print("❌ NO BORDER LINES FOUND! This is the issue.")
		elif line_count < 100:
			print("⚠️  INCOMPLETE BORDER LINES: " + str(line_count) + "/100")
		else:
			print("✓ All border lines created")
			
	else:
		print("❌ MapGridVisualizer not found!")
	
	print("")
	print("Press L to create test lines and verify line rendering works")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_SPACE:
				print("=== GRID STATUS CHECK ===")
				var map_grid_visualizer = get_tree().current_scene.get_node("MapGridVisualizer")
				if map_grid_visualizer:
					print("Grid visible: " + str(map_grid_visualizer.is_grid_visible()))
					print("Total elements: " + str(map_grid_visualizer.map_grid_tiles.size()))
					
					# Check visibility of first few elements
					for i in range(min(10, map_grid_visualizer.map_grid_tiles.size())):
						var element = map_grid_visualizer.map_grid_tiles[i]
						if element and is_instance_valid(element):
							print("Element " + str(i) + " (" + element.name + "): visible=" + str(element.visible) + ", pos=" + str(element.position))