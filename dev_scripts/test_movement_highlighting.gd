extends Node

# Test script to verify movement highlighting is working

func _ready() -> void:
	print("=== Testing Movement Highlighting ===")
	
	# Wait for scene initialization
	await get_tree().process_frame
	await get_tree().process_frame
	
	_test_movement_highlighting()

func _test_movement_highlighting() -> void:
	"""Test if movement highlighting works when selecting a unit"""
	
	# Find the first unit
	var units = _find_all_units()
	if units.size() == 0:
		print("❌ No units found!")
		return
	
	var test_unit = units[0]
	print("✅ Testing with unit: " + test_unit.name)
	
	# Check movement range
	var movement_range = test_unit.get_movement_range()
	print("✅ Unit movement range: " + str(movement_range))
	
	if movement_range <= 0:
		print("❌ Unit has no movement!")
		return
	
	# Check if systems exist
	var unit_actions_panel = _get_unit_actions_panel()
	var movement_visualizer = get_tree().current_scene.get_node_or_null("MovementVisualizer")
	
	if not unit_actions_panel:
		print("❌ UnitActionsPanel not found!")
		return
	
	if not movement_visualizer:
		print("❌ MovementVisualizer not found!")
		return
	
	print("✅ All systems found")
	
	# Test unit selection
	print("🔥 Selecting unit to trigger movement highlighting...")
	var world_pos = test_unit.global_position
	GameEvents.unit_selected.emit(test_unit, world_pos)
	
	# Wait for processing
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Check if highlighting is active
	if movement_visualizer.has_method("is_highlighting_movement_range"):
		if movement_visualizer.is_highlighting_movement_range():
			print("✅ SUCCESS! Movement highlighting is active!")
			print("🎯 Blue tiles should be visible around the unit")
		else:
			print("❌ Movement highlighting not active")
	else:
		print("❌ MovementVisualizer missing highlighting check method")
	
	# Check UnitActionsPanel state
	if unit_actions_panel.has_method("is_showing_movement_range"):
		if unit_actions_panel.is_showing_movement_range():
			print("✅ UnitActionsPanel shows movement range is active")
		else:
			print("❌ UnitActionsPanel says movement range not active")
	
	print("=== Test Complete ===")

func _find_all_units() -> Array[Unit]:
	"""Find all units in the scene"""
	var units: Array[Unit] = []
	var scene_root = get_tree().current_scene
	
	# Look in Map/Player1 and Map/Player2
	var player_paths = ["Map/Player1", "Map/Player2"]
	for path in player_paths:
		var player_node = scene_root.get_node_or_null(path)
		if player_node:
			for child in player_node.get_children():
				if child is Unit:
					units.append(child)
	
	return units

func _get_unit_actions_panel() -> Node:
	"""Get UnitActionsPanel reference"""
	var scene_root = get_tree().current_scene
	var ui_layout = scene_root.get_node_or_null("UI/GameUILayout")
	if ui_layout:
		return ui_layout.get_node_or_null("UnitActionsPanel")
	return null

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F9:
			print("F9 pressed - running movement highlighting test")
			_test_movement_highlighting()