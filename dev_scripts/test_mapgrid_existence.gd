extends Node

# Test script to check if MapGridVisualizer exists and is working

func _ready() -> void:
	print("=== TESTING MAPGRIDVISUALIZER EXISTENCE ===")
	
	await get_tree().create_timer(2.0).timeout
	
	var scene_root = get_tree().current_scene
	print("Scene root: " + str(scene_root.name))
	
	# Look for MapGridVisualizer node
	var map_grid_visualizer = scene_root.get_node_or_null("MapGridVisualizer")
	if map_grid_visualizer:
		print("✓ MapGridVisualizer node found: " + str(map_grid_visualizer))
		print("✓ Script attached: " + str(map_grid_visualizer.get_script()))
		print("✓ Node name: " + str(map_grid_visualizer.name))
		
		# Check if it has the expected properties
		if map_grid_visualizer.has_method("show_grid"):
			print("✓ show_grid method exists")
		else:
			print("❌ show_grid method missing")
			
		if map_grid_visualizer.has_method("_create_full_map_tile_grid"):
			print("✓ _create_full_map_tile_grid method exists")
		else:
			print("❌ _create_full_map_tile_grid method missing")
			
		# Try to access the map_grid_tiles array
		if "map_grid_tiles" in map_grid_visualizer:
			var tiles = map_grid_visualizer.map_grid_tiles
			print("✓ map_grid_tiles array exists, size: " + str(tiles.size()))
		else:
			print("❌ map_grid_tiles array missing")
			
	else:
		print("❌ MapGridVisualizer node NOT FOUND!")
		print("Available children:")
		for child in scene_root.get_children():
			print("  - " + child.name + " (" + str(child.get_script()) + ")")
	
	print("=== TEST COMPLETE ===")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_G:
				print("G pressed - manually testing MapGridVisualizer")
				var map_grid_visualizer = get_tree().current_scene.get_node_or_null("MapGridVisualizer")
				if map_grid_visualizer:
					print("Calling show_grid() manually...")
					map_grid_visualizer.show_grid()
					print("Grid tiles count: " + str(map_grid_visualizer.map_grid_tiles.size()))
				else:
					print("MapGridVisualizer not found!")
			KEY_H:
				print("H pressed - manually creating grid")
				var map_grid_visualizer = get_tree().current_scene.get_node_or_null("MapGridVisualizer")
				if map_grid_visualizer:
					print("Calling _create_full_map_tile_grid() manually...")
					map_grid_visualizer._create_full_map_tile_grid()
					print("Grid creation complete")
				else:
					print("MapGridVisualizer not found!")