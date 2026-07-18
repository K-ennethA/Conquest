extends Node

# Verification script for Fire Emblem movement system
# This confirms the system is working as expected

func _ready() -> void:
	print("🔥 Fire Emblem Movement System Verification")
	print("==========================================")
	
	await get_tree().process_frame
	await get_tree().process_frame
	
	_verify_system_components()

func _verify_system_components() -> void:
	"""Verify all system components are in place"""
	
	var all_good = true
	
	# Check GameEvents
	if GameEvents:
		print("✅ GameEvents singleton found")
	else:
		print("❌ GameEvents singleton missing")
		all_good = false
	
	# Check MovementVisualizer
	var movement_visualizer = get_tree().current_scene.get_node_or_null("MovementVisualizer")
	if movement_visualizer:
		print("✅ MovementVisualizer found in scene")
	else:
		print("❌ MovementVisualizer missing from scene")
		all_good = false
	
	# Check UnitActionsPanel
	var unit_actions_panel = _get_unit_actions_panel()
	if unit_actions_panel:
		print("✅ UnitActionsPanel found")
	else:
		print("❌ UnitActionsPanel missing")
		all_good = false
	
	# Check for units with movement stats
	var units = _find_all_units()
	if units.size() > 0:
		print("✅ Found " + str(units.size()) + " units in scene")
		
		var test_unit = units[0]
		var movement_range = test_unit.get_movement_range()
		if movement_range > 0:
			print("✅ Unit has movement range: " + str(movement_range))
		else:
			print("❌ Unit has no movement range")
			all_good = false
	else:
		print("❌ No units found in scene")
		all_good = false
	
	# Check Grid resource
	var grid = preload("res://board/Grid.tres")
	if grid:
		print("✅ Grid resource loaded")
	else:
		print("❌ Grid resource missing")
		all_good = false
	
	if all_good:
		print("\n🎉 ALL SYSTEMS READY!")
		print("\n📋 How to use Fire Emblem Movement:")
		print("1. Click on any unit")
		print("2. Blue highlighted tiles should appear immediately")
		print("3. Click on any blue tile to move the unit there")
		print("4. Unit will smoothly animate to the destination")
		print("\n🎮 The system is ready to use!")
	else:
		print("\n❌ Some components are missing - system may not work properly")

func _find_all_units() -> Array[Unit]:
	"""Find all units in the scene"""
	var units: Array[Unit] = []
	var scene_root = get_tree().current_scene
	
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