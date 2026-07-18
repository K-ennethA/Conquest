extends Node

# Simple test to verify Fire Emblem style movement is working
# This script tests the immediate movement range display when selecting units

func _ready() -> void:
	print("=== Fire Emblem Movement Test ===")
	
	# Wait for scene to initialize
	await get_tree().process_frame
	await get_tree().process_frame
	
	_test_fire_emblem_movement()

func _test_fire_emblem_movement() -> void:
	"""Test Fire Emblem style movement system"""
	print("Testing Fire Emblem style movement...")
	
	# Find a unit to test with
	var units = _find_all_units()
	if units.size() == 0:
		print("❌ No units found in scene!")
		return
	
	var test_unit = units[0]
	print("✅ Found test unit: " + test_unit.get_display_name())
	
	# Check if unit has movement range
	var movement_range = test_unit.get_movement_range()
	print("✅ Unit movement range: " + str(movement_range))
	
	if movement_range <= 0:
		print("❌ Unit has no movement range!")
		return
	
	# Check if UnitActionsPanel exists
	var unit_actions_panel = _get_unit_actions_panel()
	if not unit_actions_panel:
		print("❌ UnitActionsPanel not found!")
		return
	
	print("✅ UnitActionsPanel found")
	
	# Check if MovementVisualizer exists
	var movement_visualizer = get_tree().current_scene.get_node_or_null("MovementVisualizer")
	if not movement_visualizer:
		print("❌ MovementVisualizer not found!")
		return
	
	print("✅ MovementVisualizer found")
	
	# Test unit selection (should trigger immediate movement range display)
	print("🔥 Testing Fire Emblem style selection...")
	var world_pos = test_unit.global_position
	
	print("Emitting unit_selected signal...")
	GameEvents.unit_selected.emit(test_unit, world_pos)
	
	# Wait a moment for the system to process
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Check if movement range is displayed
	if unit_actions_panel.has_method("is_showing_movement_range"):
		if unit_actions_panel.is_showing_movement_range():
			print("✅ Movement range is displayed! Fire Emblem style working!")
			print("🎯 You should see blue highlighted tiles around the unit")
			print("🎯 Click on any blue tile to move the unit there")
		else:
			print("❌ Movement range not displayed")
	else:
		print("❌ UnitActionsPanel missing is_showing_movement_range method")
	
	# Test movement destination selection
	print("🔥 Testing movement destination selection...")
	
	# Calculate a valid movement destination
	var grid = preload("res://board/Grid.tres")
	var unit_grid_pos = grid.calculate_grid_coordinates(world_pos)
	var destination = unit_grid_pos + Vector3(1, 0, 0)  # Move one tile to the right
	
	if grid.is_within_bounds(destination):
		print("Testing movement to: " + str(destination))
		
		# Simulate cursor selection of destination
		GameEvents.cursor_selected.emit(destination)
		
		await get_tree().process_frame
		await get_tree().process_frame
		
		print("Movement command sent - unit should move if system is working")
	else:
		print("❌ Destination out of bounds")
	
	# Wait 3 seconds then deselect
	await get_tree().create_timer(3.0).timeout
	print("Deselecting unit...")
	GameEvents.unit_deselected.emit(test_unit)
	
	print("=== Fire Emblem Movement Test Complete ===")

func _find_all_units() -> Array[Unit]:
	"""Find all units in the scene"""
	var units: Array[Unit] = []
	var scene_root = get_tree().current_scene
	
	var player_nodes = ["Map/Player1", "Map/Player2"]
	
	for player_path in player_nodes:
		var player_node = scene_root.get_node_or_null(player_path)
		if player_node:
			for child in player_node.get_children():
				if child is Unit:
					units.append(child)
	
	return units

func _get_unit_actions_panel() -> Node:
	"""Get reference to UnitActionsPanel"""
	var scene_root = get_tree().current_scene
	var ui_layout = scene_root.get_node_or_null("UI/GameUILayout")
	if ui_layout:
		return ui_layout.get_node_or_null("UnitActionsPanel")
	return null

func _input(event: InputEvent) -> void:
	"""Handle test input"""
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F8:
				print("F8 pressed - running Fire Emblem movement test")
				_test_fire_emblem_movement()