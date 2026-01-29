extends Node

# Test script for the movement system
# Run this to verify movement functionality works correctly

func _ready() -> void:
	print("=== Movement System Test ===")
	
	# Wait a frame for everything to initialize
	await get_tree().process_frame
	
	_test_movement_system()

func _test_movement_system() -> void:
	"""Test the movement system functionality"""
	print("Testing movement system components...")
	
	# Test 1: Check if GameEvents has movement signals
	if GameEvents:
		print("✓ GameEvents found")
		
		# Check for required signals
		var required_signals = [
			"movement_range_calculated",
			"movement_range_cleared", 
			"cursor_selected",
			"unit_moved"
		]
		
		for signal_name in required_signals:
			if GameEvents.has_signal(signal_name):
				print("✓ Signal '" + signal_name + "' exists")
			else:
				print("✗ Signal '" + signal_name + "' missing")
	else:
		print("✗ GameEvents not found")
	
	# Test 2: Check if MovementVisualizer exists
	var movement_visualizer = get_tree().current_scene.get_node_or_null("MovementVisualizer")
	if movement_visualizer:
		print("✓ MovementVisualizer found")
	else:
		print("✗ MovementVisualizer not found")
	
	# Test 3: Check if UnitActionsPanel exists and has movement functionality
	var ui_layout = get_tree().current_scene.get_node_or_null("UI/GameUILayout")
	if ui_layout:
		var unit_actions_panel = ui_layout.get_node_or_null("UnitActionsPanel")
		if unit_actions_panel:
			print("✓ UnitActionsPanel found")
			
			# Check if it has movement mode variables
			if "movement_mode" in unit_actions_panel:
				print("✓ Movement mode functionality present")
			else:
				print("✗ Movement mode functionality missing")
		else:
			print("✗ UnitActionsPanel not found")
	else:
		print("✗ UI GameUILayout not found")
	
	# Test 4: Check if units exist and have movement stats
	var units = _find_all_units()
	if units.size() > 0:
		print("✓ Found " + str(units.size()) + " units")
		
		var test_unit = units[0]
		var movement_range = test_unit.get_movement_range()
		print("✓ Test unit movement range: " + str(movement_range))
		
		if movement_range > 0:
			print("✓ Unit has valid movement range")
		else:
			print("✗ Unit has no movement range")
	else:
		print("✗ No units found")
	
	# Test 5: Check grid system
	var grid = preload("res://board/Grid.tres")
	if grid:
		print("✓ Grid resource loaded")
		
		# Test coordinate conversion
		var test_world_pos = Vector3(2, 0, 2)
		var grid_pos = grid.calculate_grid_coordinates(test_world_pos)
		var back_to_world = grid.calculate_map_position(grid_pos)
		
		print("✓ Grid coordinate conversion test:")
		print("  World: " + str(test_world_pos) + " -> Grid: " + str(grid_pos) + " -> World: " + str(back_to_world))
	else:
		print("✗ Grid resource not found")
	
	print("=== Movement System Test Complete ===")

func _find_all_units() -> Array[Unit]:
	"""Find all units in the scene"""
	var units: Array[Unit] = []
	var scene_root = get_tree().current_scene
	
	# Look for units in Player1 and Player2 nodes
	var player_nodes = ["Map/Player1", "Map/Player2"]
	
	for player_path in player_nodes:
		var player_node = scene_root.get_node_or_null(player_path)
		if player_node:
			for child in player_node.get_children():
				if child is Unit:
					units.append(child)
	
	return units

func _input(event: InputEvent) -> void:
	"""Handle test input"""
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F9:
				print("F9 pressed - running movement system test")
				_test_movement_system()
			KEY_F10:
				print("F10 pressed - testing movement range calculation")
				_test_movement_range_calculation()
			KEY_F11:
				print("F11 pressed - testing Fire Emblem style unit selection")
				_test_fire_emblem_selection()
			KEY_F12:
				print("F12 pressed - testing movement range display directly")
				_test_movement_range_display()

func _test_fire_emblem_selection() -> void:
	"""Test Fire Emblem style unit selection with immediate movement range display"""
	print("=== Testing Fire Emblem Style Selection ===")
	
	var units = _find_all_units()
	if units.size() == 0:
		print("No units found for testing")
		return
	
	var test_unit = units[0]
	print("Simulating selection of: " + test_unit.get_display_name())
	
	# Simulate unit selection
	var world_pos = test_unit.global_position
	GameEvents.unit_selected.emit(test_unit, world_pos)
	
	print("Unit selected - movement range should now be visible")
	print("Click on blue highlighted tiles to move the unit")
	
	# Wait 5 seconds then deselect
	await get_tree().create_timer(5.0).timeout
	GameEvents.unit_deselected.emit(test_unit)
	print("Unit deselected - movement range should be cleared")

func _test_movement_range_display() -> void:
	"""Test movement range display directly"""
	print("=== Testing Movement Range Display Directly ===")
	
	# Test the MovementVisualizer directly
	var movement_visualizer = get_tree().current_scene.get_node_or_null("MovementVisualizer")
	if not movement_visualizer:
		print("✗ MovementVisualizer not found!")
		return
	
	print("✓ MovementVisualizer found")
	
	# Create some test positions
	var test_positions: Array[Vector3] = [
		Vector3(0, 0, 1),
		Vector3(1, 0, 0),
		Vector3(1, 0, 1),
		Vector3(2, 0, 1),
		Vector3(1, 0, 2)
	]
	
	print("Emitting movement_range_calculated with " + str(test_positions.size()) + " positions")
	GameEvents.movement_range_calculated.emit(test_positions)
	
	# Wait 3 seconds then clear
	await get_tree().create_timer(3.0).timeout
	print("Clearing movement range...")
	GameEvents.movement_range_cleared.emit()

func _test_movement_range_calculation() -> void:
	"""Test movement range calculation"""
	print("=== Testing Movement Range Calculation ===")
	
	var units = _find_all_units()
	if units.size() == 0:
		print("No units found for testing")
		return
	
	var test_unit = units[0]
	print("Testing with unit: " + test_unit.get_display_name())
	
	# Get unit's position and movement range
	var grid = preload("res://board/Grid.tres")
	var unit_world_pos = test_unit.global_position
	var unit_grid_pos = grid.calculate_grid_coordinates(unit_world_pos)
	var movement_range = test_unit.get_movement_range()
	
	print("Unit position: " + str(unit_grid_pos))
	print("Movement range: " + str(movement_range))
	
	# Simulate the movement range calculation from UnitActionsPanel
	var reachable_tiles = _calculate_reachable_tiles(unit_grid_pos, movement_range, grid)
	
	print("Calculated " + str(reachable_tiles.size()) + " reachable tiles:")
	for i in range(min(10, reachable_tiles.size())):  # Show first 10 tiles
		print("  " + str(reachable_tiles[i]))
	
	if reachable_tiles.size() > 10:
		print("  ... and " + str(reachable_tiles.size() - 10) + " more")
	
	# Test the movement visualizer
	print("Testing MovementVisualizer...")
	var movement_visualizer = get_tree().current_scene.get_node_or_null("MovementVisualizer")
	if movement_visualizer:
		print("✓ MovementVisualizer found - testing tile highlighting")
		GameEvents.movement_range_calculated.emit(reachable_tiles)
		
		# Wait a moment then clear
		await get_tree().create_timer(3.0).timeout
		GameEvents.movement_range_cleared.emit()
		print("Movement range test complete")
	else:
		print("✗ MovementVisualizer not found")

func _calculate_reachable_tiles(start_pos: Vector3, max_distance: int, grid: Grid) -> Array[Vector3]:
	"""Calculate reachable tiles (copy of UnitActionsPanel logic for testing)"""
	var reachable: Array[Vector3] = []
	var queue: Array = [{pos = start_pos, distance = 0}]
	var visited: Dictionary = {start_pos: 0}
	
	while not queue.is_empty():
		var current = queue.pop_front()
		var current_pos = current.pos
		var current_distance = current.distance
		
		if current_distance < max_distance:
			var directions = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
			
			for direction in directions:
				var next_pos = current_pos + direction
				
				if grid.is_within_bounds(next_pos) and not visited.has(next_pos):
					visited[next_pos] = current_distance + 1
					queue.append({pos = next_pos, distance = current_distance + 1})
					reachable.append(next_pos)
	
	return reachable