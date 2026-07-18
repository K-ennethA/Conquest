extends Node

# Test Tactical immediate movement range display

func _ready() -> void:
	print("🔥 Testing Tactical Immediate Movement Range Display")
	
	# Wait for scene initialization
	await get_tree().process_frame
	await get_tree().process_frame
	
	_test_immediate_movement_display()

func _test_immediate_movement_display() -> void:
	"""Test that selecting a unit immediately shows blue tiles"""
	
	# Find a unit to test with
	var units = _find_all_units()
	if units.size() == 0:
		print("❌ No units found!")
		return
	
	var test_unit = units[0]
	print("✅ Testing with unit: " + test_unit.get_display_name())
	
	# Check movement range
	var movement_range = test_unit.get_movement_range()
	print("✅ Unit movement range: " + str(movement_range))
	
	if movement_range <= 0:
		print("❌ Unit has no movement range!")
		return
	
	# Check if MovementVisualizer exists and is connected
	var movement_visualizer = get_tree().current_scene.get_node_or_null("MovementVisualizer")
	if not movement_visualizer:
		print("❌ MovementVisualizer not found in scene!")
		return
	
	print("✅ MovementVisualizer found")
	
	# Test unit selection (should trigger immediate blue tiles)
	print("🔥 Selecting unit - blue tiles should appear immediately...")
	var world_pos = test_unit.global_position
	
	# Emit the unit selection signal
	GameEvents.unit_selected.emit(test_unit, world_pos)
	
	# Wait for processing
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Check if movement range is being displayed
	if movement_visualizer.has_method("is_highlighting_movement_range"):
		if movement_visualizer.is_highlighting_movement_range():
			print("✅ SUCCESS! Blue tiles are being displayed!")
			print("🎯 Tactical movement is working!")
		else:
			print("❌ Movement range not being highlighted")
	else:
		print("❌ MovementVisualizer missing highlighting method")
	
	print("=== Test Complete ===")

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

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F10:
			print("F10 pressed - testing Tactical immediate movement")
			_test_immediate_movement_display()