extends Node

# Test script to verify the overlay mesh system works
# This script simulates the Fire Emblem movement system to test visual display

func _ready() -> void:
	print("=== Testing Overlay Mesh Movement System ===")
	
	# Wait a moment for scene to initialize
	await get_tree().create_timer(1.0).timeout
	
	# Test the movement visualizer directly
	_test_movement_visualizer()

func _test_movement_visualizer() -> void:
	"""Test the MovementVisualizer with overlay meshes"""
	print("=== Testing MovementVisualizer ===")
	
	# Find the MovementVisualizer in the scene
	var scene_root = get_tree().current_scene
	var movement_visualizer = scene_root.get_node_or_null("MovementVisualizer")
	
	if not movement_visualizer:
		print("ERROR: MovementVisualizer not found in scene")
		print("Available nodes in scene:")
		_print_scene_structure(scene_root, 0)
		return
	
	print("MovementVisualizer found: " + movement_visualizer.name)
	
	# Test positions around origin (0,0,0)
	var test_positions: Array[Vector3] = [
		Vector3(0, 0, 0),
		Vector3(1, 0, 0),
		Vector3(-1, 0, 0),
		Vector3(0, 0, 1),
		Vector3(0, 0, -1),
		Vector3(1, 0, 1)
	]
	
	print("Emitting movement_range_calculated signal with " + str(test_positions.size()) + " positions")
	
	# Emit the signal to trigger overlay creation
	GameEvents.movement_range_calculated.emit(test_positions)
	
	print("Signal emitted - overlay meshes should be created")
	
	# Wait 5 seconds then clear
	await get_tree().create_timer(5.0).timeout
	
	print("Clearing movement range...")
	GameEvents.movement_range_cleared.emit()
	
	print("Test complete")

func _print_scene_structure(node: Node, depth: int) -> void:
	"""Print scene structure for debugging"""
	var indent = ""
	for i in range(depth):
		indent += "  "
	
	print(indent + node.name + " (" + node.get_class() + ")")
	
	if depth < 3:  # Limit depth to avoid spam
		for child in node.get_children():
			_print_scene_structure(child, depth + 1)