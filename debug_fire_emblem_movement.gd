extends Node

# Debug script for Fire Emblem movement system
# Add this to your GameWorld scene and press F11 to test

func _ready() -> void:
	print("🔥 Fire Emblem Movement Debug Script Ready")
	print("Press F11 to test Fire Emblem movement")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F11:
			print("F11 pressed - testing Fire Emblem movement system")
			_debug_fire_emblem_movement()

func _debug_fire_emblem_movement() -> void:
	"""Debug the Fire Emblem movement system step by step"""
	
	print("=== Fire Emblem Movement Debug ===")
	
	# Step 1: Check if all components exist
	print("Step 1: Checking components...")
	
	var movement_visualizer = get_tree().current_scene.get_node_or_null("MovementVisualizer")
	if movement_visualizer:
		print("✅ MovementVisualizer found")
	else:
		print("❌ MovementVisualizer NOT found")
		return
	
	var unit_actions_panel = _get_unit_actions_panel()
	if unit_actions_panel:
		print("✅ UnitActionsPanel found")
	else:
		print("❌ UnitActionsPanel NOT found")
		return
	
	# Step 2: Check Grid resource
	print("Step 2: Checking Grid resource...")
	var grid = preload("res://board/Grid.tres")
	if grid:
		print("✅ Grid resource loaded")
		print("  Grid size: " + str(grid.size))
		print("  Cell size: " + str(grid.cell_size))
		
		# Test coordinate conversion
		var test_world = Vector3(2.0, 0.0, 2.0)
		var test_grid = grid.calculate_grid_coordinates(test_world)
		var test_world_back = grid.calculate_map_position(test_grid)
		print("  Coordinate test: World " + str(test_world) + " -> Grid " + str(test_grid) + " -> World " + str(test_world_back))
	else:
		print("❌ Grid resource NOT loaded")
		return
	
	# Step 3: Find and test a unit
	print("Step 3: Finding test unit...")
	var units = _find_all_units()
	if units.size() == 0:
		print("❌ No units found")
		return
	
	var test_unit = units[0]
	print("✅ Test unit: " + test_unit.get_display_name())
	print("  Unit position: " + str(test_unit.global_position))
	print("  Movement range: " + str(test_unit.get_movement_range()))
	
	# Step 4: Test unit selection (should trigger Fire Emblem movement)
	print("Step 4: Testing unit selection...")
	print("🔥 Selecting unit - this should show blue tiles immediately!")
	
	GameEvents.unit_selected.emit(test_unit, test_unit.global_position)
	
	# Wait for processing
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Step 5: Check if movement range is displayed
	print("Step 5: Checking if movement range is displayed...")
	
	if unit_actions_panel.has_method("is_showing_movement_range"):
		if unit_actions_panel.is_showing_movement_range():
			print("✅ UnitActionsPanel reports movement range is showing")
		else:
			print("❌ UnitActionsPanel reports movement range is NOT showing")
	
	if movement_visualizer.has_method("is_highlighting_movement_range"):
		if movement_visualizer.is_highlighting_movement_range():
			print("✅ MovementVisualizer reports highlighting is active")
		else:
			print("❌ MovementVisualizer reports highlighting is NOT active")
	
	print("=== Debug Complete ===")
	print("If you see blue tiles around the unit, Fire Emblem movement is working!")
	print("If not, check the debug output above for issues.")

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