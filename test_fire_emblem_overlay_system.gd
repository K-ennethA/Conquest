extends Node

# Comprehensive test for Fire Emblem movement system with overlay meshes
# This test verifies that the overlay mesh approach works correctly

func _ready() -> void:
	print("=== Fire Emblem Overlay Movement System Test ===")
	print("Testing the refactored MovementVisualizer with overlay meshes")
	
	# Wait for scene initialization
	await get_tree().create_timer(1.0).timeout
	
	# Run comprehensive test
	await _run_comprehensive_test()

func _run_comprehensive_test() -> void:
	"""Run comprehensive test of the Fire Emblem movement system"""
	print("\n=== COMPREHENSIVE FIRE EMBLEM MOVEMENT TEST ===")
	
	# Step 1: Verify scene structure
	print("\n--- Step 1: Verifying Scene Structure ---")
	if not _verify_scene_structure():
		print("FAILED: Scene structure verification failed")
		return
	print("PASSED: Scene structure verified")
	
	# Step 2: Test MovementVisualizer directly
	print("\n--- Step 2: Testing MovementVisualizer Directly ---")
	if not await _test_movement_visualizer():
		print("FAILED: MovementVisualizer test failed")
		return
	print("PASSED: MovementVisualizer test completed")
	
	# Step 3: Test unit selection and movement range display
	print("\n--- Step 3: Testing Unit Selection and Movement Range ---")
	if not await _test_unit_selection_movement():
		print("FAILED: Unit selection movement test failed")
		return
	print("PASSED: Unit selection movement test completed")
	
	# Step 4: Test Fire Emblem workflow
	print("\n--- Step 4: Testing Complete Fire Emblem Workflow ---")
	if not await _test_fire_emblem_workflow():
		print("FAILED: Fire Emblem workflow test failed")
		return
	print("PASSED: Fire Emblem workflow test completed")
	
	print("\n=== ALL TESTS PASSED ===")
	print("Fire Emblem movement system with overlay meshes is working correctly!")

func _verify_scene_structure() -> bool:
	"""Verify that all required nodes are present in the scene"""
	var scene_root = get_tree().current_scene
	
	# Check for MovementVisualizer
	var movement_visualizer = scene_root.get_node_or_null("MovementVisualizer")
	if not movement_visualizer:
		print("ERROR: MovementVisualizer not found")
		return false
	print("✓ MovementVisualizer found")
	
	# Check for GameEvents
	if not GameEvents:
		print("ERROR: GameEvents singleton not found")
		return false
	print("✓ GameEvents singleton found")
	
	# Check for UnitActionsPanel
	var ui_layout = scene_root.get_node_or_null("UI/GameUILayout")
	if not ui_layout:
		print("ERROR: UI/GameUILayout not found")
		return false
	
	var unit_actions_panel = ui_layout.get_node_or_null("MarginContainer/MainContainer/MiddleArea/RightSidebar/UnitActionsPanel")
	if not unit_actions_panel:
		print("ERROR: UnitActionsPanel not found at correct path")
		return false
	print("✓ UnitActionsPanel found at correct path")
	
	# Check for units
	var player1_node = scene_root.get_node_or_null("Map/Player1")
	if not player1_node or player1_node.get_child_count() == 0:
		print("ERROR: No units found in Map/Player1")
		return false
	print("✓ Units found in Map/Player1")
	
	return true

func _test_movement_visualizer() -> bool:
	"""Test MovementVisualizer overlay mesh creation directly"""
	var scene_root = get_tree().current_scene
	var movement_visualizer = scene_root.get_node_or_null("MovementVisualizer")
	
	print("Testing overlay mesh creation...")
	
	# Test positions (grid coordinates)
	var test_positions: Array[Vector3] = [
		Vector3(1, 0, 1),  # Center-ish position
		Vector3(2, 0, 1),  # Adjacent positions
		Vector3(1, 0, 2),
		Vector3(0, 0, 1),
		Vector3(1, 0, 0)
	]
	
	print("Emitting movement_range_calculated signal with " + str(test_positions.size()) + " positions")
	
	# Count existing children before
	var children_before = scene_root.get_child_count()
	print("Scene children before: " + str(children_before))
	
	# Emit signal to create overlays
	GameEvents.movement_range_calculated.emit(test_positions)
	
	# Wait a frame for processing
	await get_tree().process_frame
	
	# Count children after
	var children_after = scene_root.get_child_count()
	print("Scene children after: " + str(children_after))
	
	# Check if overlay meshes were created
	var overlays_created = children_after > children_before
	if overlays_created:
		print("✓ Overlay meshes created (+" + str(children_after - children_before) + " nodes)")
		
		# Look for overlay meshes by name
		var overlay_count = 0
		for child in scene_root.get_children():
			if child.name.begins_with("MovementOverlay_"):
				overlay_count += 1
				print("  Found overlay: " + child.name + " at position " + str(child.position))
		
		print("✓ Found " + str(overlay_count) + " overlay meshes")
	else:
		print("✗ No overlay meshes created")
		return false
	
	# Wait 2 seconds to see overlays
	print("Waiting 2 seconds to display overlays...")
	await get_tree().create_timer(2.0).timeout
	
	# Clear overlays
	print("Clearing overlays...")
	GameEvents.movement_range_cleared.emit()
	
	# Wait a frame for cleanup
	await get_tree().process_frame
	
	# Verify cleanup
	var children_after_clear = scene_root.get_child_count()
	if children_after_clear <= children_before:
		print("✓ Overlays cleared successfully")
	else:
		print("✗ Overlays not properly cleared")
		return false
	
	return true

func _test_unit_selection_movement() -> bool:
	"""Test unit selection triggering movement range display"""
	var scene_root = get_tree().current_scene
	
	# Find a unit to test with
	var player1_node = scene_root.get_node_or_null("Map/Player1")
	if not player1_node:
		print("ERROR: Map/Player1 not found")
		return false
	
	var test_unit: Unit = null
	for child in player1_node.get_children():
		if child is Unit:
			test_unit = child
			break
	
	if not test_unit:
		print("ERROR: No unit found for testing")
		return false
	
	print("Testing unit selection with unit: " + test_unit.name)
	print("Unit position: " + str(test_unit.global_position))
	
	# Get unit's movement range
	var movement_range = test_unit.get_movement_range()
	print("Unit movement range: " + str(movement_range))
	
	# Count scene children before selection
	var children_before = scene_root.get_child_count()
	
	# Emit unit selection signal
	print("Emitting unit_selected signal...")
	GameEvents.unit_selected.emit(test_unit, test_unit.global_position)
	
	# Wait for processing
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	
	# Check if overlays were created
	var children_after = scene_root.get_child_count()
	var overlays_created = children_after > children_before
	
	if overlays_created:
		print("✓ Movement range overlays created on unit selection")
		
		# Count overlay meshes
		var overlay_count = 0
		for child in scene_root.get_children():
			if child.name.begins_with("MovementOverlay_"):
				overlay_count += 1
		
		print("✓ Created " + str(overlay_count) + " movement range overlays")
	else:
		print("✗ No movement range overlays created on unit selection")
		return false
	
	# Wait to see the overlays
	print("Displaying movement range for 3 seconds...")
	await get_tree().create_timer(3.0).timeout
	
	# Deselect unit
	print("Deselecting unit...")
	GameEvents.unit_deselected.emit(test_unit)
	
	# Wait for cleanup
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	
	# Verify cleanup
	var children_after_deselect = scene_root.get_child_count()
	if children_after_deselect <= children_before:
		print("✓ Movement range overlays cleared on unit deselection")
	else:
		print("✗ Movement range overlays not properly cleared")
		return false
	
	return true

func _test_fire_emblem_workflow() -> bool:
	"""Test the complete Fire Emblem workflow"""
	print("Testing complete Fire Emblem workflow...")
	
	var scene_root = get_tree().current_scene
	var cursor = scene_root.get_node_or_null("Map/Cursor")
	
	if not cursor:
		print("ERROR: Cursor not found")
		return false
	
	# Find a unit
	var player1_node = scene_root.get_node_or_null("Map/Player1")
	var test_unit: Unit = null
	for child in player1_node.get_children():
		if child is Unit:
			test_unit = child
			break
	
	if not test_unit:
		print("ERROR: No unit found")
		return false
	
	print("Testing Fire Emblem workflow with unit: " + test_unit.name)
	
	# Step 1: Position cursor on unit
	var grid = preload("res://board/Grid.tres")
	var unit_grid_pos = grid.calculate_grid_coordinates(test_unit.global_position)
	print("Moving cursor to unit at grid position: " + str(unit_grid_pos))
	
	cursor.tile_position = unit_grid_pos
	await get_tree().process_frame
	
	# Step 2: Select unit (Fire Emblem style - immediate movement range display)
	print("Selecting unit (Fire Emblem style)...")
	var children_before = scene_root.get_child_count()
	
	# Simulate cursor selection
	cursor._handle_selection()
	
	# Wait for processing
	await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	
	# Check if movement range is displayed
	var children_after = scene_root.get_child_count()
	var overlays_created = children_after > children_before
	
	if overlays_created:
		print("✓ Fire Emblem style: Movement range displayed immediately on unit selection")
		
		# Count overlays
		var overlay_count = 0
		for child in scene_root.get_children():
			if child.name.begins_with("MovementOverlay_"):
				overlay_count += 1
		
		print("✓ Fire Emblem style: " + str(overlay_count) + " blue tiles showing movement range")
	else:
		print("✗ Fire Emblem style: No movement range displayed on unit selection")
		return false
	
	# Step 3: Test movement destination selection
	print("Testing movement destination selection...")
	
	# Move cursor to a nearby position (simulate clicking a blue tile)
	var destination_pos = unit_grid_pos + Vector3(1, 0, 0)  # Move one tile right
	print("Moving cursor to destination: " + str(destination_pos))
	
	cursor.tile_position = destination_pos
	await get_tree().process_frame
	
	# Simulate clicking the destination
	print("Selecting movement destination...")
	cursor._handle_selection()
	
	# Wait for movement processing
	await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	
	print("✓ Fire Emblem workflow test completed")
	
	# Clean up
	GameEvents.movement_range_cleared.emit()
	await get_tree().process_frame
	
	return true

func _input(event: InputEvent) -> void:
	"""Handle input for manual testing"""
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F6:
				print("F6 pressed - running comprehensive test")
				await _run_comprehensive_test()
			KEY_F7:
				print("F7 pressed - testing MovementVisualizer only")
				await _test_movement_visualizer()
			KEY_F8:
				print("F8 pressed - testing unit selection")
				await _test_unit_selection_movement()
			KEY_F9:
				print("F9 pressed - testing Fire Emblem workflow")
				await _test_fire_emblem_workflow()