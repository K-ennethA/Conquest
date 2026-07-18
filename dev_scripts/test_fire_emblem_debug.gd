extends Node

# Debug script for Fire Emblem movement - press F12 to test

func _ready() -> void:
	print("🔥 Fire Emblem Debug Script Ready - Press F12 to test")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F12:
			print("F12 pressed - running Fire Emblem debug test")
			_debug_fire_emblem_system()

func _debug_fire_emblem_system() -> void:
	"""Debug the Fire Emblem system step by step"""
	
	print("=== Fire Emblem System Debug ===")
	
	# Step 1: Check scene structure
	print("Step 1: Checking scene structure...")
	var scene_root = get_tree().current_scene
	print("Scene root: " + scene_root.name)
	
	var map_node = scene_root.get_node_or_null("Map")
	print("Map node: " + str(map_node != null))
	
	var tiles_node = map_node.get_node_or_null("Tiles") if map_node else null
	print("Tiles node: " + str(tiles_node != null))
	if tiles_node:
		print("Tiles count: " + str(tiles_node.get_child_count()))
	
	var ui_node = scene_root.get_node_or_null("UI")
	print("UI node: " + str(ui_node != null))
	
	var ui_layout = scene_root.get_node_or_null("UI/GameUILayout")
	print("GameUILayout: " + str(ui_layout != null))
	
	var unit_actions_panel = ui_layout.get_node_or_null("UnitActionsPanel") if ui_layout else null
	print("UnitActionsPanel: " + str(unit_actions_panel != null))
	
	var movement_visualizer = scene_root.get_node_or_null("MovementVisualizer")
	print("MovementVisualizer: " + str(movement_visualizer != null))
	
	# Step 2: Find a unit to test with
	print("\nStep 2: Finding test unit...")
	var units = _find_all_units()
	if units.size() == 0:
		print("❌ No units found!")
		return
	
	var test_unit = units[0]
	print("✅ Test unit: " + test_unit.get_display_name())
	print("Unit position: " + str(test_unit.global_position))
	print("Movement range: " + str(test_unit.get_movement_range()))
	
	# Step 3: Test unit selection
	print("\nStep 3: Testing unit selection...")
	print("🔥 Selecting unit - should show blue tiles!")
	
	GameEvents.unit_selected.emit(test_unit, test_unit.global_position)
	
	# Wait for processing
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Step 4: Check results
	print("\nStep 4: Checking results...")
	
	if unit_actions_panel and unit_actions_panel.has_method("is_showing_movement_range"):
		var showing_range = unit_actions_panel.is_showing_movement_range()
		print("UnitActionsPanel showing range: " + str(showing_range))
	
	if movement_visualizer and movement_visualizer.has_method("is_highlighting_movement_range"):
		var highlighting = movement_visualizer.is_highlighting_movement_range()
		print("MovementVisualizer highlighting: " + str(highlighting))
	
	print("=== Debug Complete ===")
	print("Check the console output above for any issues.")
	print("If you see 'DEBUG: Material applied successfully', the system should be working.")

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