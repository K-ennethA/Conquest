extends Node

# Simple debug script to test movement range display
# This bypasses all complex systems and directly tests the core functionality

func _ready() -> void:
	print("=== Debug Movement Range Script Ready ===")
	
	# Wait for everything to initialize
	await get_tree().process_frame
	await get_tree().process_frame
	
	print("Starting movement range debug test...")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_T:
				print("T pressed - Testing movement range display")
				_test_movement_range_display()
			KEY_Y:
				print("Y pressed - Testing unit selection and movement range")
				_test_unit_selection_and_movement()

func _test_movement_range_display() -> void:
	"""Test movement range display directly"""
	print("=== Testing Movement Range Display ===")
	
	# Check if MovementVisualizer exists
	var movement_visualizer = get_tree().current_scene.get_node_or_null("MovementVisualizer")
	if not movement_visualizer:
		print("✗ MovementVisualizer not found!")
		return
	
	print("✓ MovementVisualizer found: " + movement_visualizer.name)
	
	# Test positions around (1,0,1) - should be near a unit
	var test_positions: Array[Vector3] = [
		Vector3(0, 0, 0),
		Vector3(1, 0, 0),
		Vector3(2, 0, 0),
		Vector3(0, 0, 1),
		Vector3(2, 0, 1),
		Vector3(0, 0, 2),
		Vector3(1, 0, 2),
		Vector3(2, 0, 2)
	]
	
	print("Emitting movement_range_calculated signal with " + str(test_positions.size()) + " positions")
	for pos in test_positions:
		print("  Position: " + str(pos))
	
	# Emit the signal
	GameEvents.movement_range_calculated.emit(test_positions)
	print("Signal emitted - blue tiles should appear")
	
	# Wait 5 seconds then clear
	await get_tree().create_timer(5.0).timeout
	print("Clearing movement range...")
	GameEvents.movement_range_cleared.emit()
	print("Movement range cleared")

func _test_unit_selection_and_movement() -> void:
	"""Test unit selection and automatic movement range display"""
	print("=== Testing Unit Selection and Movement Range ===")
	
	# Find a unit
	var units = _find_all_units()
	if units.size() == 0:
		print("✗ No units found!")
		return
	
	var test_unit = units[0]
	print("✓ Found test unit: " + test_unit.name)
	print("Unit position: " + str(test_unit.global_position))
	
	# Check unit movement range
	var movement_range = test_unit.get_movement_range()
	print("Unit movement range: " + str(movement_range))
	
	if movement_range <= 0:
		print("✗ Unit has no movement range!")
		return
	
	# Simulate unit selection
	print("Simulating unit selection...")
	var world_pos = test_unit.global_position
	GameEvents.unit_selected.emit(test_unit, world_pos)
	print("Unit selection signal emitted - movement range should appear")
	
	# Wait 5 seconds then deselect
	await get_tree().create_timer(5.0).timeout
	print("Deselecting unit...")
	GameEvents.unit_deselected.emit(test_unit)
	print("Unit deselected - movement range should disappear")

func _find_all_units() -> Array[Unit]:
	"""Find all units in the scene"""
	var units: Array[Unit] = []
	var scene_root = get_tree().current_scene
	
	# Look for units in Player1 and Player2 nodes
	var player_nodes = ["Map/Player1", "Map/Player2"]
	
	for player_path in player_nodes:
		var player_node = scene_root.get_node_or_null(player_path)
		if player_node:
			print("Found player node: " + player_path)
			for child in player_node.get_children():
				if child is Unit:
					units.append(child)
					print("  Found unit: " + child.name + " at " + str(child.global_position))
	
	print("Total units found: " + str(units.size()))
	return units